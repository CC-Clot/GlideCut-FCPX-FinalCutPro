import Foundation
import ApplicationServices
import AppKit

// 客观验证：对 FCP 时间线的 AXScrollArea 触发 AXScrollRightByPage / AXScrollLeftByPage，
// 观察水平滚动条 value 是否变化、播放头时间是否不变（区分「平移视图」与「移动播放头」）。
// 只触发视图滚动 action，不修改任何素材内容。

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return r == .success ? value : nil
}
func strAttr(_ el: AXUIElement, _ name: String) -> String { attr(el, name) as? String ?? "" }
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { strAttr(el, kAXRoleAttribute) }

func findTimelineScrollArea(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 12 { return nil }
    if role(el) == "AXScrollArea" && subtreeHasTimeline(el, depth: 0) { return el }
    for c in children(el) {
        if let found = findTimelineScrollArea(c, depth: depth + 1) { return found }
    }
    return nil
}
func subtreeHasTimeline(_ el: AXUIElement, depth: Int) -> Bool {
    if depth > 10 { return false }
    let d = strAttr(el, kAXDescriptionAttribute)
    if d.contains("项目时间线") || d.lowercased().contains("timeline") { return true }
    for c in children(el) { if subtreeHasTimeline(c, depth: depth + 1) { return true } }
    return false
}

func findPlayhead(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 12 { return nil }
    if role(el) == "AXValueIndicator" && strAttr(el, kAXDescriptionAttribute).contains("播放头") { return el }
    for c in children(el) { if let f = findPlayhead(c, depth: depth + 1) { return f } }
    return nil
}

func findScrollBars(_ el: AXUIElement, into: inout [AXUIElement], depth: Int = 0) {
    if depth > 12 { return }
    if role(el) == "AXScrollBar" { into.append(el) }
    for c in children(el) { findScrollBars(c, into: &into, depth: depth + 1) }
}

guard AXIsProcessTrusted() else { print("AX 权限未授予"); exit(1) }
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.apple.FinalCutApp" || $0.bundleIdentifier == "com.apple.FinalCutPro"
}) else { print("FCP 未运行"); exit(1) }

let axApp = AXUIElementCreateApplication(app.processIdentifier)
guard let windows = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] else { print("无窗口"); exit(1) }

var timelineArea: AXUIElement?
var playhead: AXUIElement?
for w in windows {
    if let a = findTimelineScrollArea(w) { timelineArea = a; break }
}
guard let area = timelineArea else { print("未找到时间线 AXScrollArea"); exit(1) }
playhead = findPlayhead(area)

// 扫描全窗口所有滚动条，客观对比触发前后哪个数值变化
var bars: [AXUIElement] = []
for w in windows { findScrollBars(w, into: &bars) }

func snapshot(_ tag: String) {
    let ph = playhead.flatMap { attr($0, kAXValueAttribute) }.map { "\($0)" } ?? "?"
    let barVals = bars.map { v in (attr(v, kAXValueAttribute) as? NSNumber)?.doubleValue ?? -1 }
        .map { String(format: "%.6f", $0) }.joined(separator: ", ")
    print("[\(tag)] 播放头=\(ph)  滚动条value=[\(barVals)]")
}
print("共发现 \(bars.count) 个滚动条")

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "read"
snapshot("基准")

if mode == "right" || mode == "left" {
    let action = mode == "right" ? "AXScrollRightByPage" : "AXScrollLeftByPage"
    let err = AXUIElementPerformAction(area, action as CFString)
    print("触发 \(action) -> AXError=\(err.rawValue)")
    usleep(300_000)
    snapshot("触发后")
} else if mode == "setval" {
    // 测试：直接设置第一个滚动条的 value 到目标值，看 FCP 是否响应
    let target = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 0.5) : 0.5
    guard let bar = bars.first else { print("无滚动条"); exit(1) }
    let setErr = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, target as CFNumber)
    print("设值滚动条 -> \(target) AXError=\(setErr.rawValue)")
    usleep(300_000)
    snapshot("设值后")
} else {
    // 列出时间线 scroll area 支持的全部 action
    var raw: CFArray?
    let r = AXUIElementCopyActionNames(area, &raw)
    let acts = (r == .success ? (raw as? [String]) : nil) ?? []
    print("时间线 AXScrollArea 支持的 actions: \(acts)")
}
