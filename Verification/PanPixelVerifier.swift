import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

// 终极像素验证：AX 设值/触发 action，并调用 screencapture 截取 FCP 窗口。
// 判据是画面像素本身（交由 compare_pixels.py），不是滚动条数字（已被证明是假阳性）。

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return r == .success ? value : nil
}
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }

func hasTimeline(_ el: AXUIElement, _ depth: Int) -> Bool {
    if depth > 10 { return false }
    let d = attr(el, kAXDescriptionAttribute) as? String ?? ""
    if d.contains("项目时间线") || d.lowercased().contains("timeline") { return true }
    for c in children(el) { if hasTimeline(c, depth + 1) { return true } }
    return false
}
func firstBar(_ el: AXUIElement, depth: Int) -> AXUIElement? {
    if depth > 10 { return nil }
    if role(el) == "AXScrollBar" { return el }
    for c in children(el) { if let f = firstBar(c, depth: depth + 1) { return f } }
    return nil
}
func findTimelineBar(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 14 { return nil }
    if role(el) == "AXScrollArea", hasTimeline(el, 0), let bar = firstBar(el, depth: 0) {
        return bar
    }
    for c in children(el) { if let f = findTimelineBar(c, depth: depth + 1) { return f } }
    return nil
}
func findScrollArea(_ root: AXUIElement) -> AXUIElement? {
    func walk(_ el: AXUIElement, _ d: Int) -> AXUIElement? {
        if d > 14 { return nil }
        if role(el) == "AXScrollArea", hasTimeline(el, 0) { return el }
        for c in children(el) { if let f = walk(c, d + 1) { return f } }
        return nil
    }
    if let wins = attr(root, kAXWindowsAttribute) as? [AXUIElement] {
        for w in wins { if let f = walk(w, 0) { return f } }
    }
    return nil
}

struct WinInfo { var id: Int; var x: Int; var y: Int; var w: Int; var h: Int }
func fcpWindowInfo() -> WinInfo? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var best: (info: WinInfo, area: Int)?
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        if owner.contains("Final Cut") {
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }
            let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Int ?? 0
            let height = bounds["Height"] as? Int ?? 0
            guard width > 400, height > 300 else { continue }
            let area = width * height
            if best == nil || area > best!.area {
                let info = WinInfo(id: w[kCGWindowNumber as String] as? Int ?? -1,
                                   x: bounds["X"] as? Int ?? 0, y: bounds["Y"] as? Int ?? 0,
                                   w: width, h: height)
                best = (info, area)
            }
        }
    }
    return best?.info
}

func run(_ cmd: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmd)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try? p.run()
    p.waitUntilExit()
}

func capture(_ tag: String, windowID: Int, dir: String) {
    // 用全屏截图：命令行 -l 窗口ID 会拿到不刷新的静态帧（已实测），
    // 全屏截图正常刷新。Python 端按 FCP 窗口区域裁剪后对比。
    run("/usr/sbin/screencapture", ["-x", "-t", "png", "\(dir)/\(tag).png"])
    print("截图: \(tag)")
}

guard AXIsProcessTrusted() else { print("ERR:辅助功能权限未授予"); exit(1) }
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.apple.FinalCutApp" || $0.bundleIdentifier == "com.apple.FinalCutPro"
}) else { print("ERR:FCP未运行"); exit(1) }
let dir = "/tmp/pan_verify"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
    if f.hasSuffix(".png") { try? FileManager.default.removeItem(atPath: "\(dir)/\(f)") }
}

guard let win = fcpWindowInfo() else { print("ERR:未找到FCP窗口"); exit(1) }
let wid = win.id
// 写窗口区域到 json（全屏像素坐标 = 逻辑坐标 × 2，Retina）
let scale: Int = 2
let crop = "{\"x\":\(win.x * scale),\"y\":\(win.y * scale),\"w\":\(win.w * scale),\"h\":\(win.h * scale)}"
try? crop.write(toFile: "\(dir)/crop.json", atomically: true, encoding: .utf8)
print("FCP主窗口 id=\(wid) 逻辑坐标=\(win.x),\(win.y) \(win.w)×\(win.h)")

let axApp = AXUIElementCreateApplication(app.processIdentifier)
var bar: AXUIElement?
if let wins = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] {
    for w in wins { if let b = findTimelineBar(w) { bar = b; break } }
}
guard let scrollBar = bar else { print("ERR:未找到时间线滚动条"); exit(1) }

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "action"
print("FCP窗口ID=\(wid) 模式=\(mode)")

// 阶段1：静止基线 3 张（测画面自身噪点/动画）
capture("base_1", windowID: wid, dir: dir)
usleep(400_000)
capture("base_2", windowID: wid, dir: dir)
usleep(400_000)
capture("base_3", windowID: wid, dir: dir)

if mode == "setval" {
    let target = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 0.5) : 0.5
    let err = AXUIElementSetAttributeValue(scrollBar, kAXValueAttribute as CFString, NSNumber(value: target))
    print("设值 \(target) AXError=\(err.rawValue)")
} else {
    guard let area = findScrollArea(axApp) else { print("ERR:未找到时间线ScrollArea"); exit(1) }
    for _ in 0..<5 {
        let err = AXUIElementPerformAction(area, "AXScrollRightByPage" as CFString)
        print("RightByPage AXError=\(err.rawValue)")
        usleep(120_000)
    }
}
usleep(500_000)
capture("after_1", windowID: wid, dir: dir)
usleep(400_000)
capture("after_2", windowID: wid, dir: dir)
usleep(400_000)
capture("after_3", windowID: wid, dir: dir)

print("截图完成 目录=\(dir)")
print("PIXEL_COMPARE_READY")
