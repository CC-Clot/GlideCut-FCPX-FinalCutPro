import CoreGraphics
import Foundation

/// 修饰键状态。
///
/// 由 `CGEventFlags` 解析而来，覆盖 GlideCut 需要的四个键：
/// Command、Option、Control、Shift。
///
/// 说明：CoreGraphics 中 Option 对应的标志位是 `maskAlternate`，
/// 这是 macOS 的既定命名，不是笔误。
struct ModifierState: OptionSet, Hashable {
    let rawValue: Int

    static let command = ModifierState(rawValue: 1 << 0)
    static let option = ModifierState(rawValue: 1 << 1)
    static let control = ModifierState(rawValue: 1 << 2)
    static let shift = ModifierState(rawValue: 1 << 3)

    /// 从事件标志位解析修饰键。
    static func from(_ flags: CGEventFlags) -> ModifierState {
        var state: ModifierState = []
        if flags.contains(.maskCommand) {
            state.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            state.insert(.option)
        }
        if flags.contains(.maskControl) {
            state.insert(.control)
        }
        if flags.contains(.maskShift) {
            state.insert(.shift)
        }
        return state
    }

    var isCommand: Bool { contains(.command) }
    var isOption: Bool { contains(.option) }
    var isControl: Bool { contains(.control) }
    var isShift: Bool { contains(.shift) }
    var isEmpty: Bool { rawValue == 0 }

    /// 人类可读的修饰键描述，例如 "Command+Shift"、"无"。
    var description: String {
        var parts: [String] = []
        if isCommand { parts.append("Command") }
        if isOption  { parts.append("Option") }
        if isControl { parts.append("Control") }
        if isShift   { parts.append("Shift") }
        return parts.isEmpty ? "无" : parts.joined(separator: "+")
    }

    /// 功能映射：把原事件标志中的指定修饰键替换为 Shift。
    ///
    /// 这是「Option/Control + 滚轮 → FCP 原生 Shift+滚轮水平平移」的核心纯函数。
    /// 与旧方案（新建 CGEvent 再 post）的本质区别：这里只改写**真实事件**的 flags，
    /// 事件的来源（hidSystemState）、滚动相位（scrollPhase/momentumPhase）与
    /// 增量（deltaAxis1/2）全部原样保留，因此 FCP 收到的是真实滚动手势。
    ///
    /// ## 关键：必须同时改写「高位语义位」与「低位设备位」
    ///
    /// CGEventFlags 有两组修饰键信息：
    /// - 高位语义位：`.maskAlternate`=0x80000、`.maskControl`=0x40000、`.maskShift`=0x20000
    /// - 低位设备位（NX device mask，随真实按键产生）：
    ///   左Option=0x20、右Option=0x40、左Control=0x08、右Control=0x10、
    ///   左Shift=0x02、右Shift=0x04
    ///
    /// 真机日志证据：按住 Option 滚动时 flags=0x80020（高位 Option + 低位左 Option）。
    /// 若只把高位改成 Shift（得 0x20020），低位仍报告「按着 Option」，两条信息冲突，
    /// 导致水平平移时灵时不灵。真实 Shift+滚轮应为 0x20002（高位 Shift + 低位左 Shift）。
    /// 因此这里必须同时修正两组位。
    ///
    /// - Parameters:
    ///   - flags: 原始事件的 `CGEventFlags`。
    ///   - source: 需要被替换掉的修饰键（当前为已配置的平移键 Option 或 Control）。
    /// - Returns: 语义位与设备位都改写为 Shift 的标志位；其余标志保持不变。
    static func shiftedFlags(from flags: CGEventFlags, replacing source: ModifierState) -> CGEventFlags {
        var result = flags

        // 低位设备位常量（CGEventFlags 未定义命名，按 NX device mask 数值构造）。
        let leftShiftDevice = CGEventFlags(rawValue: 0x02)
        let leftShiftRightDevice = CGEventFlags(rawValue: 0x04)
        let leftOptionDevice = CGEventFlags(rawValue: 0x20)
        let rightOptionDevice = CGEventFlags(rawValue: 0x40)
        let leftControlDevice = CGEventFlags(rawValue: 0x08)
        let rightControlDevice = CGEventFlags(rawValue: 0x10)

        if source.contains(.option) {
            result.remove(.maskAlternate)               // 高位：去 Option
            result.remove(leftOptionDevice)             // 低位：去左 Option
            result.remove(rightOptionDevice)            // 低位：去右 Option
        }
        if source.contains(.control) {
            result.remove(.maskControl)                 // 高位：去 Control
            result.remove(leftControlDevice)            // 低位：去左 Control
            result.remove(rightControlDevice)           // 低位：去右 Control
        }

        result.insert(.maskShift)                       // 高位：加 Shift
        result.insert(leftShiftDevice)                  // 低位：加左 Shift → 模拟真实按键
        _ = leftShiftRightDevice                        // 保留命名以备将来区分左右手
        return result
    }

    /// 滚轮方向 → 时间线滚动条 value 的偏移方向（AX 平移方案的纯函数，便于测试）。
    ///
    /// 真机反馈：上一版方向相反，这里整体取反。
    /// 本机「自然滚动」关闭时，物理上滚上报为 `.down`（Δ1 > 0），
    /// 用户期望它让水平滚动条 value **减小**；物理下滚 `.up`（Δ1 < 0）则让 value **增大**。
    static func panSign(for direction: ScrollDirection) -> Int? {
        switch direction {
        case .down: return -1
        case .up:   return 1
        default:    return nil
        }
    }

    /// 滚轮幅度 → 时间线滚动条 value 的偏移量（AX 平移方案的纯函数，便于测试）。
    ///
    /// 滚动条 value 范围 0~1，步长钳制在 0.04~0.15：
    /// 像素级真机验证表明 0.02 的步长画面变化 <1%，肉眼几乎不可见；
    /// 0.1 的步长产生约 2.4% 画面变化（静止基线仅 0.09%），清晰可感。
    /// 因此提高下限到 0.04，上限 0.15 避免一格冲到底。
    /// - Parameters:
    ///   - magnitude: 滚轮增量绝对值。
    ///   - sign: 方向，+1 向时间线右侧（value 增大），-1 向左。
    /// - Returns: 带符号的 value 偏移量。
    static func panStep(for magnitude: CGFloat, sign: Int) -> CGFloat {
        return CGFloat(sign) * max(0.04, min(0.15, magnitude * 0.05))
    }
}
