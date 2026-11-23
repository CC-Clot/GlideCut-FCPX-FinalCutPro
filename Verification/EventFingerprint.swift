import Foundation
import CoreGraphics
import AppKit

// MARK: - 事件指纹诊断探针（纯只读）
//
// 目的：抓取「真实 Shift+滚轮」与「真实 Option/Control+滚轮」在 CGEvent 层面的
//       完整字段差异，终结此前靠猜 flag 字段反复试错的循环。
//
// 安全边界：
//   - 使用 .listenOnly + .cgSessionEventTap，回调原样返回事件；
//   - 不改写、不消费、不注入、不 post 任何事件；
//   - 不申请任何新权限、不修改任何系统设置或 FCP 配置。
//   - 唯一副作用：需要「输入监控」授权（与 GlideCut 相同，已授权）。

infix operator ** : MultiplicationPrecedence
func ** (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

let duration = Double(CommandLine.arguments.dropFirst().first ?? "45") ?? 45.0

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"

func flagNames(_ f: CGEventFlags) -> String {
    var parts: [String] = []
    if f.contains(.maskShift)    { parts.append("Shift") }
    if f.contains(.maskAlternate){ parts.append("Option") }
    if f.contains(.maskControl)  { parts.append("Control") }
    if f.contains(.maskCommand)  { parts.append("Command") }
    return parts.isEmpty ? "-" : parts.joined(separator: "+")
}

print("GlideCut · 事件指纹诊断探针（纯监听，绝不改写任何事件）")
print("时长 \(String(format: "%.0f", duration)) 秒 | 每 \(String(repeating: "-", count: 55))")
print("请在 Final Cut Pro 时间线上，依次真实滚动以下三种组合，每种滚几下：")
print("  1) 只滚滚轮（无修饰键）  —— 基准")
print("  2) 按住 Shift + 滚轮      —— FCP 原生有效平移（关键基准）")
print("  3) 按住 Option + 滚轮     —— 我们要模拟的目标")
print("  4) 按住 Control + 滚轮    —— 同上")
print(String(repeating: "-", count: 55))
print("格式: 时间 | 修饰键 | flags(高/低全值) | Δ1垂直 Δ2水平 | phase/momentum | 前台")
print(String(repeating: "-", count: 55))

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
var printed = 0

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, _, event, _ in
        let f = event.flags
        let a1 = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let a2 = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let appTag: String = app.contains("FinalCut") ? "FCP" : app

        let timeStr = formatter.string(from: Date())
        let flagStr = flagNames(f).padding(toLength: 14, withPad: " ", startingAt: 0)
        let hexStr = String(f.rawValue, radix: 16).uppercased().padding(toLength: 8, withPad: "0", startingAt: 0)
        let a1Str = String(format: "%+.2f", a1)
        let a2Str = String(format: "%+.2f", a2)
        let line = "[\(timeStr)] \(flagStr) flags=0x\(hexStr) Δ1=\(a1Str) Δ2=\(a2Str) "
            + "phase=\(phase)/\(momentum) 前台=\(appTag)"
        print(line)
        printed += 1
        // listen-only：必须原样返回事件，绝不改写。
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
)

guard let tap = tap else {
    print("[失败] 无法创建事件监听。请确认本工具已获得「输入监控」授权。")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
print("[就绪] 探针已启动，现在开始在 FCP 中滚动。\n")

let deadline = Date().addingTimeInterval(duration)
while Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.25, false)
}

CFMachPortInvalidate(tap)
CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
print("\n\(String(repeating: "-", count: 55))")
print("采样结束，共捕获 \(printed) 个滚轮事件。")
print("请把每种组合（Shift / Option / Control）各复制 2-3 行发我，用于精确比对。")
