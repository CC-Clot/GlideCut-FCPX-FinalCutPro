import CoreFoundation
import CoreGraphics
import Foundation

enum EventTapStartResult {
    case started
    case alreadyRunning
    case unavailable(String)
}

/// 对 `CGEventTap` 的封装：负责创建、后台事件循环、停止。
///
/// 设计要点：
///
/// 1. **可拦截模式**。使用 `CGEventTapOptions.defaultTap`，回调可以消费（返回 nil）
///    或替换事件。仅当命中「FCP + 指定修饰键」时才消费并转换，其余事件原样放行，
///    因此不影响任何其他应用与 FCP 的原生滚动。
/// 2. **独立后台 RunLoop**。Tap 注册在专用线程的 `CFRunLoop` 上，回调只做判定与
///    转换，不占用主线程，避免拖慢前台应用响应。
/// 3. **可彻底停止**。`stop()` 置位停止标志并停止 RunLoop，由后台线程完成
///    Tap 失效与源移除。
/// 4. **防事件循环**。自身注入的事件带标记，回调中直接放行，不会被再次处理。
///
/// 说明：本 SDK（MacOSX27.2）的 CoreFoundation 不提供 `CFMachPortStart` /
/// `CFMachPortStop`，事件投递由 `CFMachPortCreateRunLoopSource` +
/// `CFRunLoopAddSource` + `CFRunLoopRun` 建立，停止时用 `CFMachPortInvalidate`。
final class EventTapController {

    /// 事件处理结果的三种去向。
    ///
    /// - `passthrough`：原样放行，FCP 走自己的原生逻辑。
    /// - `consumed`：吞掉事件（缩放已由 AX 菜单执行，无需再向下传递）。
    /// - `remappedToShift`：事件对象本身是引用类型，handler 已把它的 flags
    ///   从 Option/Control **原地改写**为 Shift；这里放行同一个事件对象，
    ///   让 FCP 把它当作原生 Shift+滚轮。事件来源、滚动相位与增量全部保留。
    enum EventDisposition {
        case passthrough
        case consumed
        case remappedToShift
    }

    /// 事件处理回调。
    ///
    /// 入参：原始 `CGEvent`（引用类型，可被原地改写）、解析后的滚轮事件、当前前台应用。
    /// 返回：事件去向，见 `EventDisposition`。
    typealias WheelHandler = (CGEvent, WheelEvent, FrontmostAppInfo) -> EventDisposition

    private let handler: WheelHandler
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var stopSemaphore: DispatchSemaphore?
    private var stopRequested = false

    /// 用于标记自身注入的事件，避免回调再次处理形成循环。
    private static let injectedEventMarker: Int64 = 0x4743_4C44  // "GCLD"

    init(handler: @escaping WheelHandler) {
        self.handler = handler
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tap != nil
    }

    /// 创建并启动事件监听。
    ///
    /// - Parameter intercept: `true` 时使用可拦截模式（可消费事件）；
    ///   `false` 时使用 listen-only（只观察，绝不改变事件流向）。
    ///
    /// ## tap 层级与位置（关键，勿随意回退）
    ///
    /// 挂在 `.cgAnnotatedSessionEventTap` + `.tailAppendEventTap`：
    /// - **Annotated 层**是 AppKit 把 CGEvent 转成 NSEvent 之前的最后一层。
    ///   在此改写 flags，不会被下层用「物理按键真实状态」重新注释覆盖——
    ///   这正是此前 session 层改写「时灵时不灵」的成因。
    /// - **tailAppend** 让本 tap 排在所有其它 tap 之后，改写结果直达目标应用，
    ///   不会再被别的 tap 二次处理。
    ///
    /// 与成熟开源滚轮工具 Mos 的落点一致。
    func start(location: CGEventTapLocation = .cgAnnotatedSessionEventTap,
               intercept: Bool = true) -> EventTapStartResult {
        lock.lock()
        guard tap == nil else {
            lock.unlock()
            return .alreadyRunning
        }
        lock.unlock()

        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let owner = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
            let disposition = owner.dispatch(eventType: eventType, event: event)
            switch disposition {
            case .consumed:
                return nil
            case .passthrough, .remappedToShift:
                // 两种情形都放行同一个事件对象。remappedToShift 的 flags
                // 已由 handler 在该对象上原地改写，无需重新 post。
                return Unmanaged.passUnretained(event)
            }
        }

        guard let newTap = CGEvent.tapCreate(
            tap: location,
            place: .tailAppendEventTap,
            options: intercept ? .defaultTap : .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .unavailable(
                "CGEvent.tapCreate 返回空。最常见原因是缺少「输入监控」授权；"
                    + "请在 系统设置 → 隐私与安全性 → 输入监控 中为 GlideCut 开启后重试。"
            )
        }

        let semaphore = DispatchSemaphore(value: 0)

        lock.lock()
        tap = newTap
        stopSemaphore = semaphore
        stopRequested = false
        lock.unlock()

        let mode = intercept ? "可拦截（仅命中 FCP 增强组合时消费）" : "仅监听（不拦截、不注入）"
        EventLog.shared.log("事件监听已启动：位置=\(location.rawValue)，模式=\(mode)")

        let thread = Thread { [weak self] in
            self?.runLoopBody(with: newTap, completionSignal: semaphore)
        }
        thread.name = "GlideCutEventTap"
        thread.stackSize = 512 * 1024
        lock.lock()
        self.thread = thread
        lock.unlock()
        thread.start()

        return .started
    }

    /// 彻底停止监听，并等待后台线程完成 Tap 失效与源移除。
    func stop() {
        let loopToStop: CFRunLoop?
        let semaphore: DispatchSemaphore?
        lock.lock()
        loopToStop = runLoop
        semaphore = stopSemaphore
        stopRequested = true
        tap = nil
        runLoop = nil
        lock.unlock()

        if let loop = loopToStop {
            CFRunLoopStop(loop)
        }
        if let semaphore = semaphore {
            _ = semaphore.wait(timeout: .now() + 3.0)
        }

        EventLog.shared.log("事件监听已停止，事件循环已退出，Tap 已失效")
    }

    private func isStopRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    private func runLoopBody(with activeTap: CFMachPort, completionSignal: DispatchSemaphore) {
        let currentLoop = CFRunLoopGetCurrent()
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, activeTap, 0) else {
            EventLog.shared.log("后台事件循环创建失败：无法为 Tap 创建 RunLoop 源")
            completionSignal.signal()
            return
        }
        CFRunLoopAddSource(currentLoop, source, .defaultMode)

        lock.lock()
        runLoop = currentLoop
        lock.unlock()

        EventLog.shared.log("后台事件循环已就绪，开始监听滚轮事件")

        while !isStopRequested() {
            CFRunLoopRun()
        }

        CFMachPortInvalidate(activeTap)
        CFRunLoopRemoveSource(currentLoop, source, .defaultMode)
        EventLog.shared.log("后台事件循环已退出，Tap 已失效并移除")

        completionSignal.signal()
    }

    /// 处理单个事件，返回事件去向。
    private func dispatch(eventType: CGEventType, event: CGEvent) -> EventDisposition {
        switch eventType {
        case .scrollWheel:
            // 跳过自身注入的事件，避免事件循环。
            if event.getIntegerValueField(.eventSourceUserData) == Self.injectedEventMarker {
                return .passthrough
            }
            guard let wheel = WheelEvent.from(event) else { return .passthrough }
            return handler(event, wheel, FrontmostAppInfo.current())
        case .tapDisabledByTimeout:
            EventLog.shared.log("系统因超时停用了事件监听（tapDisabledByTimeout），尝试重新启用")
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return .passthrough
        case .tapDisabledByUserInput:
            EventLog.shared.log("系统因用户输入停用了事件监听（tapDisabledByUserInput），尝试重新启用")
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return .passthrough
        default:
            return .passthrough
        }
    }

    /// 标记并投递一个合成事件，供注入使用。
    static func postInjected(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        event.post(tap: .cgSessionEventTap)
    }
}