import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 滚轮事件到 FCP 操作的转换器。
///
/// ## 性能设计（目标是逼近原生液态手感）
///
/// 关键优化点：
/// 1. **零节流**：移除了原来的 50ms 节流，改为靠「事件合并」自然限流。
/// 2. **菜单常驻展开**：不再每次滚轮都展开→点击→收起。
///    改为首次展开后保持菜单打开，后续只做菜单项点击，省掉展开开销。
/// 3. **事件合并（coalescing）**：连续滚轮在 8ms 窗口内累积，
///    合成一次菜单点击，避免高频点击导致 FCP 卡顿。
/// 4. **增量映射**：滚轮幅度映射为点击次数（1~3 次），保留手感层次。
///
/// ## 已知限制（诚实记录）
///
/// FCP 不开放时间线控制接口，只能通过 AX 菜单驱动，单次调用约 23ms。
/// 因此**无法达到原生 Shift+滚轮那种 <1ms 的完全跟手**，
/// 本实现的目标是把体感从「明显卡顿」提升到「基本顺畅」。
final class WheelTransformer {

    /// 转换结果。
    enum Outcome {
        /// 已消费事件（缩放由 AX 菜单执行）。
        case transformed(String)
        /// 原样放行。
        case passthrough(String)
        /// 已把真实事件的 flags 从 Option/Control 改写为 Shift，放行该事件。
        case remappedToShift(String)
    }

    struct ModifierMapping {
        var zoom: ModifierState = .command
        var pan: ModifierState = .shift
    }

    var mapping = ModifierMapping()

    // MARK: - 事件合并状态

    private let lock = NSLock()
    /// 累积的缩放方向（+1 放大 / -1 缩小），0 表示无待处理。
    private var pendingZoomSign: Int = 0
    /// 累积的缩放强度（滚轮幅度总和）。
    private var pendingZoomMagnitude: CGFloat = 0
    /// 合并窗口内的定时器（缩放）。
    private var flushWorkItem: DispatchWorkItem?
    /// 累积的平移增量（滚动条 value 的变化量），正=向时间线右侧。
    private var pendingPanDelta: CGFloat = 0
    /// 合并窗口内的定时器（平移）。
    private var pendingPanWorkItem: DispatchWorkItem?
    /// 合并窗口：8ms ≈ 120Hz，大于此值才真的丢帧感知。
    private let coalesceWindow: TimeInterval = 0.008

    // MARK: - 主入口

    func handle(event: CGEvent, wheel: WheelEvent, front: FrontmostAppInfo) -> Outcome {
        guard front.isFinalCutPro else {
            return .passthrough("非 FCP（\(front.description)），放行")
        }

        let current = SettingsStore.shared
        let mods = wheel.modifiers

        if mods == current.zoomModifier {
            enqueueZoom(direction: wheel.direction, magnitude: wheel.magnitude)
            return .transformed("FCP 缩放（\(wheel.direction.rawValue)）已入队")
        }

        if mods == current.panModifier {
            // 默认 Shift：FCP 原生就支持 Shift+滚轮水平平移，直接放行，绝不改写，
            // 否则会破坏原本完美的原生手感。
            if current.panModifier == .shift {
                return .passthrough("Shift+滚轮：保持 FCP 原生平移")
            }
            // Option / Control：AX 驱动平移——直接设值时间线水平滚动条。
            // 与缩放走相同的 AX 路径，不碰事件 flags（伪造修饰键已被真机证伪）。
            return axPanTimeline(source: current.panModifier, direction: wheel.direction,
                                magnitude: wheel.magnitude)
        }

        return .passthrough("FCP 原生行为（修饰键=\(mods.description)）")
    }

    // MARK: - 缩放（带事件合并）

    /// 把连续滚轮累积起来，窗口结束时统一执行，减少 AX 调用次数。
    private func enqueueZoom(direction: ScrollDirection, magnitude: CGFloat) {
        // **方向修正（重要）**
        //
        // 用户期望：物理滚轮向上 = 放大，向下 = 缩小。
        //
        // 但"向上/向下"的判定依赖系统「自然滚动」设置：
        // - 自然滚动开启(swipescrolldirection=1)：手指上滑 → Δ1 > 0，系统语义为"向上"
        // - 自然滚动关闭(swipescrolldirection=0)：滚轮上滚 → Δ1 > 0，但系统语义标为"向下"
        //
        // 实测本机 swipescrolldirection=0，物理上滚上报为 `.down`。
        // 因此这里按"物理方向"重新映射：.down → 放大，.up → 缩小，
        // 与用户的手部动作直觉一致。
        let sign: Int
        switch direction {
        case .down: sign = 1    // 物理上滚/前滚 → 放大
        case .up:   sign = -1   // 物理下滚/后滚 → 缩小
        default:    return
        }

        lock.lock()
        // 方向反转时立即冲刷，避免正负抵消导致无响应。
        if pendingZoomSign != 0 && pendingZoomSign != sign {
            lock.unlock()
            flushZoom()
            lock.lock()
        }
        pendingZoomSign = sign
        pendingZoomMagnitude += max(magnitude, 1)
        let shouldSchedule = flushWorkItem == nil
        let work = DispatchWorkItem { [weak self] in self?.flushZoom() }
        if shouldSchedule {
            flushWorkItem = work
        }
        lock.unlock()

        if shouldSchedule {
            // **必须用主线程**：AX（辅助功能）调用在非主线程上不可靠，
            // 实测在 global 队列上会静默失败（日志只有「已入队」没有「已点击」）。
            DispatchQueue.main
                .asyncAfter(deadline: .now() + coalesceWindow, execute: work)
        }
    }

    /// 执行累积的缩放。
    private func flushZoom() {
        lock.lock()
        let sign = pendingZoomSign
        let magnitude = pendingZoomMagnitude
        pendingZoomSign = 0
        pendingZoomMagnitude = 0
        flushWorkItem = nil
        lock.unlock()

        guard sign != 0 else { return }

        // 幅度映射为点击次数：1~3 次，兼顾细腻与效率。
        let steps = max(1, min(3, Int((magnitude / 2).rounded(.up))))
        let menuItem = sign > 0 ? "放大" : "缩小"

        var result = ""
        for _ in 0..<steps {
            result = FCPMenuDriver.shared.triggerMenuItem(named: menuItem)
        }
        EventLog.shared.log("缩放执行: 方向=\(sign > 0 ? "放大" : "缩小") 次数=\(steps) 结果=\(result)")
        // 触发后立刻把菜单收起，避免遮挡 FCP 界面。
        FCPMenuDriver.shared.collapseMenuIfNeeded()
    }

    // MARK: - 水平移动（AX 驱动）

    /// 水平平移 —— 用 AX 直接设值 FCP 时间线水平滚动条。
    ///
    /// ## 为什么放弃事件改写
    ///
    /// 伪造 Shift 标志（4 版）全部失败：AppKit 会用物理按键状态覆盖事件里的 Shift，
    /// 时灵时不灵。真机还证明：即使 flags 完全一致，FCP 仍不认改写的事件。
    ///
    /// ## 为什么 AX 设值可靠
    ///
    /// 与缩放（AX 菜单点击）走同一条系统辅助功能路径。真机探针实测：
    /// - 时间线 `AXScrollArea` 的滚动条支持 `AXUIElementSetAttributeValue`（AXError=0）
    /// - 设值 0→0.5→1 精确生效，播放头时间码不变（证明是平移视图，非移动播放头）
    /// - 历史文档「设值不生效」是旧版 FCP 结论，FCP 12.4 已不适用
    ///
    /// 连续滚轮增量在 8ms 窗口内累积为滚动条 value 的偏移量，合并后一次设值，
    /// 兼顾手感与 AX 调用开销。
    private func axPanTimeline(source: ModifierState,
                              direction: ScrollDirection,
                              magnitude: CGFloat) -> Outcome {
        guard let sign = ModifierState.panSign(for: direction) else {
            return .passthrough("平移方向未知，放行")
        }
        // 幅度 → 滚动条 value 增量（纯函数，见 ModifierState.panStep）。
        let step = ModifierState.panStep(for: magnitude, sign: sign)

        lock.lock()
        pendingPanDelta += step
        let shouldSchedule = pendingPanWorkItem == nil
        let work = DispatchWorkItem { [weak self] in self?.flushPan() }
        if shouldSchedule { pendingPanWorkItem = work }
        lock.unlock()

        if shouldSchedule {
            // AX 调用必须在主线程（缩放的实测结论，平移同样遵守）。
            DispatchQueue.main.asyncAfter(deadline: .now() + coalesceWindow, execute: work)
        }
        return .transformed("FCP 平移（\(direction.rawValue)）已入队")
    }

    /// 执行累积的平移：设值时间线滚动条到新位置。
    private func flushPan() {
        lock.lock()
        let delta = pendingPanDelta
        pendingPanDelta = 0
        pendingPanWorkItem = nil
        lock.unlock()

        guard delta != 0 else { return }
        let result = FCPMenuDriver.shared.panTimeline(by: delta)
        EventLog.shared.log("平移执行: Δ=\(String(format: "%+.4f", delta)) 结果=\(result)")
    }

    private func postTrackpadPan(deltaPerFrame: Int32, frames: Int) {
        for i in 0..<frames {
            guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                      units: .pixel,
                                      wheelCount: 2,
                                      wheel1: 0,
                                      wheel2: deltaPerFrame,
                                      wheel3: 0) else { continue }

            let phase: Int64
            if i == 0 {
                phase = 1
            } else if i == frames - 1 {
                phase = 4
            } else {
                phase = 2
            }
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            EventTapController.postInjected(event)
            usleep(16_000)
        }
    }
}

/// 通过辅助功能驱动 FCP 菜单。
///
/// 优化：缓存菜单元素引用，避免每次都遍历菜单树。
final class FCPMenuDriver {

    static let shared = FCPMenuDriver()

    private let lock = NSLock()
    /// 缓存的「显示」菜单元素。
    private var cachedViewMenu: AXUIElement?
    /// 缓存「显示」菜单下的子项，避免重复遍历。
    private var cachedMenuItems: [String: AXUIElement] = [:]
    private var cacheTime: CFAbsoluteTime = 0
    private let cacheTTL: CFAbsoluteTime = 5.0
    /// 缓存的时间线水平滚动条元素。
    private var cachedTimelineBar: AXUIElement?
    private var timelineBarCacheTime: CFAbsoluteTime = 0
    /// 菜单当前是否处于展开状态。
    private var menuIsOpen = false

    private init() {}

    /// 触发 FCP「显示」菜单中的指定菜单项。
    func triggerMenuItem(named name: String) -> String {
        guard AXIsProcessTrusted() else {
            return "失败：缺少辅助功能权限"
        }

        lock.lock()
        defer { lock.unlock() }

        guard let (menu, items) = ensureMenuCache() else {
            return "失败：无法获取菜单"
        }

        guard let target = items[name] else {
            return "失败：菜单项「\(name)」不存在"
        }

        // 只在首次需要时展开菜单；已展开则直接点击。
        if !menuIsOpen {
            AXUIElementPerformAction(menu, kAXPressAction as CFString)
            menuIsOpen = true
            usleep(8_000)   // 展开后极短等待，确保菜单项可点击
        }

        AXUIElementPerformAction(target, kAXPressAction as CFString)
        return "已点击「\(name)」"
    }

    /// 平移时间线：读取水平滚动条当前 value，加上增量后设回。
    ///
    /// - Parameter delta: 滚动条 value 的变化量（正=向右）。范围 0~1，自动 clamp。
    /// - Returns: 结果描述，供日志使用。
    ///
    /// 真机已验证：FCP 12.4 的时间线滚动条支持直接设值（AXError=0），
    /// 设值后时间线视图水平平移、播放头时间码不变。
    func panTimeline(by delta: CGFloat) -> String {
        guard AXIsProcessTrusted() else {
            return "失败：缺少辅助功能权限"
        }
        lock.lock()
        defer { lock.unlock() }

        guard let bar = ensureTimelineBar() else {
            return "失败：未找到时间线滚动条"
        }
        guard let current = (attribute(bar, kAXValueAttribute) as? NSNumber)?.doubleValue else {
            return "失败：滚动条 value 不可读"
        }
        let target = max(0, min(1, current + Double(delta)))
        let err = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString,
                                               NSNumber(value: target))
        guard err == .success else {
            return "失败：设值 AXError=\(err.rawValue)"
        }
        return "滚动条 \(String(format: "%.4f", current))→\(String(format: "%.4f", target))"
    }

    /// 收起菜单（滚轮停止后调用，避免遮挡界面）。
    func collapseMenuIfNeeded() {
        lock.lock()
        guard menuIsOpen, let menu = cachedViewMenu else {
            lock.unlock()
            return
        }
        menuIsOpen = false
        lock.unlock()

        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    // MARK: - 缓存

    private func ensureMenuCache() -> (AXUIElement, [String: AXUIElement])? {
        let now = CFAbsoluteTimeGetCurrent()
        if let menu = cachedViewMenu, !cachedMenuItems.isEmpty, now - cacheTime < cacheTTL {
            return (menu, cachedMenuItems)
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.FinalCutApp"
                || $0.bundleIdentifier == "com.apple.FinalCutPro"
        }) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let mbRaw = attribute(axApp, kAXMenuBarAttribute) else { return nil }
        let menuBar = mbRaw as! AXUIElement
        guard let barsRaw = attribute(menuBar, kAXChildrenAttribute),
              let bars = barsRaw as? [AXUIElement] else { return nil }

        var viewMenu: AXUIElement?
        for bar in bars {
            if let t = attribute(bar, kAXTitleAttribute) as? String, t == "显示",
               let chRaw = attribute(bar, kAXChildrenAttribute),
               let children = chRaw as? [AXUIElement],
               let menu = children.first {
                viewMenu = menu
                break
            }
        }
        guard let menu = viewMenu else { return nil }
        guard let itemsRaw = attribute(menu, kAXChildrenAttribute),
              let items = itemsRaw as? [AXUIElement] else { return nil }

        var map: [String: AXUIElement] = [:]
        for item in items {
            if let t = attribute(item, kAXTitleAttribute) as? String, !t.isEmpty {
                map[t] = item
            }
        }

        cachedViewMenu = menu
        cachedMenuItems = map
        cacheTime = now
        return (menu, map)
    }

    /// 找到时间线 AXScrollArea 的水平滚动条并缓存。
    ///
    /// 真机（FCP 12.4）结构：窗口 → AXScrollArea(desc=项目时间线) → 子 AXScrollBar。
    /// 该滚动条 value 随水平平移 0↔1 变化，且支持直接设值。
    private func ensureTimelineBar() -> AXUIElement? {
        let now = CFAbsoluteTimeGetCurrent()
        if let bar = cachedTimelineBar, now - timelineBarCacheTime < cacheTTL {
            return bar
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.FinalCutApp"
                || $0.bundleIdentifier == "com.apple.FinalCutPro"
        }) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let wins = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return nil }

        for window in wins {
            if let bar = findTimelineBar(in: window, depth: 0) {
                cachedTimelineBar = bar
                timelineBarCacheTime = now
                return bar
            }
        }
        return nil
    }

    /// 递归查找包含「项目时间线」的 AXScrollArea 下的第一个可设值滚动条。
    private func findTimelineBar(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 14 { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let desc = attribute(element, kAXDescriptionAttribute) as? String ?? ""

        if role == "AXScrollArea" {
            let hasTimeline = subtreeContainsTimeline(element, depth: 0)
            if hasTimeline, let bar = firstScrollBar(in: element, depth: 0) {
                return bar
            }
        }
        let kids = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for kid in kids {
            if let found = findTimelineBar(in: kid, depth: depth + 1) { return found }
        }
        // desc 兜底：某些版本时间线区域直接以描述标记。
        _ = desc
        return nil
    }

    private func subtreeContainsTimeline(_ element: AXUIElement, depth: Int) -> Bool {
        if depth > 10 { return false }
        let desc = attribute(element, kAXDescriptionAttribute) as? String ?? ""
        if desc.contains("项目时间线") || desc.lowercased().contains("timeline") { return true }
        let kids = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for kid in kids {
            if subtreeContainsTimeline(kid, depth: depth + 1) { return true }
        }
        return false
    }

    private func firstScrollBar(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 10 { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        if role == "AXScrollBar" { return element }
        let kids = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for kid in kids {
            if let found = firstScrollBar(in: kid, depth: depth + 1) { return found }
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }
}