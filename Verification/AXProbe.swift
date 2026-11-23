import Foundation
import ApplicationServices
import AppKit

// 只读 AX 探针：枚举 FCP 的菜单命令与时间线可操作元素，不做任何点击或设值。

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return r == .success ? value : nil
}

func strAttr(_ el: AXUIElement, _ name: String) -> String {
    return attr(el, name) as? String ?? ""
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    return attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func actions(_ el: AXUIElement) -> [String] {
    var raw: CFArray?
    let r = AXUIElementCopyActionNames(el, &raw)
    guard r == .success, let arr = raw else { return [] }
    return (arr as? [String]) ?? []
}

func role(_ el: AXUIElement) -> String { strAttr(el, kAXRoleAttribute) }

guard AXIsProcessTrusted() else {
    print("AX 权限未授予")
    exit(1)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.apple.FinalCutApp" || $0.bundleIdentifier == "com.apple.FinalCutPro"
}) else {
    print("FCP 未运行")
    exit(1)
}

let ver = Bundle(url: app.bundleURL!)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
print("FCP PID=\(app.processIdentifier) 版本=\(ver)")
let axApp = AXUIElementCreateApplication(app.processIdentifier)

// 1) 枚举菜单栏所有菜单标题 + 一级子项，重点标出 scroll/pan/平移/滚动 相关命令
print("=== 菜单栏命令 ===")
if let mbRaw = attr(axApp, kAXMenuBarAttribute) {
    let mb = mbRaw as! AXUIElement
    for bar in children(mb) {
        let barTitle = strAttr(bar, kAXTitleAttribute)
        let menus = children(bar)
        for menu in menus {
            let menuTitle = strAttr(menu, kAXTitleAttribute)
            let items = children(menu)
            if items.isEmpty { continue }
            print("【\(barTitle) / \(menuTitle)】 \(items.count) 项")
            for item in items {
                let t = strAttr(item, kAXTitleAttribute)
                if t.isEmpty { continue }
                let keyword = ["滚", "平移", "移动", "scroll", "pan", "nudge", "移位", "shift", "放大", "缩小", "适配", "fit", "zoom", "左", "右", "上", "下"]
                let hit = keyword.contains { t.localizedCaseInsensitiveContains($0) }
                print("   \(hit ? "★" : "  ") \(t)")
            }
        }
    }
}

// 2) 递归扫描窗口 AX 树，找滚动条/时间线相关的可操作元素
print("=== 窗口可操作元素（滚动/时间线相关）===")
var nodeCount = 0
func walk(_ el: AXUIElement, depth: Int) {
    if depth > 14 || nodeCount > 5000 { return }
    nodeCount += 1
    let r = role(el)
    let desc = strAttr(el, kAXDescriptionAttribute)
    let title = strAttr(el, kAXTitleAttribute)
    let acts = actions(el)
    let interesting = r.contains("Scroll") || r.contains("ValueIndicator")
        || desc.localizedCaseInsensitiveContains("时间线") || desc.localizedCaseInsensitiveContains("timeline")
        || title.localizedCaseInsensitiveContains("时间线") || title.localizedCaseInsensitiveContains("timeline")
        || (!acts.isEmpty && (desc.localizedCaseInsensitiveContains("滚动") || desc.localizedCaseInsensitiveContains("平移")))

    if interesting {
        var valDesc = ""
        if let v = attr(el, kAXValueAttribute) { valDesc = " value=\(v)" }
        let hidden = attr(el, kAXHiddenAttribute) as? Bool ?? false
        print("[\(depth)] role=\(r) title=\(title) desc=\(desc) hidden=\(hidden) actions=\(acts)\(valDesc)")
    }
    for c in children(el) { walk(c, depth: depth + 1) }
}
if let winsRaw = attr(axApp, kAXWindowsAttribute), let wins = winsRaw as? [AXUIElement] {
    print("窗口数=\(wins.count)")
    for w in wins { walk(w, depth: 0) }
}
print("扫描节点数=\(nodeCount)")
