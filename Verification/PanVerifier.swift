import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

infix operator ** : MultiplicationPrecedence
func ** (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

// MARK: - GlideCut 水平平移 · 客观验证工具
//
// 用途：用「只读 AX 数值」判定 FCP 时间线是否真的发生了水平平移，
//       彻底排除截图假阳性（历史上 FCP 窗口反复变 1px 又恢复，导致像素差分误报）。
//
// 安全边界：
//   - 只读取辅助功能（Accessibility）属性，不注入、不改写、不 post 任何事件；
//   - 不修改 FCP 的任何设置或素材；
//   - 随时可 Ctrl+C 退出。
//
// 判据（基准先行，两步缺一不可）：
//   步骤 A【基准】：关闭 GlideCut 监听，按住 FCP 原生的 Shift+滚轮真实滚动。
//        记下本工具打印的、确实发生变化的滚动条读数 —— 这就是"成功时数值应该怎么变"的基准。
//   步骤 B【测试】：开启 GlideCut 监听，平移键设为 Option，真实滚动 Option+滚轮。
//        若步骤 A 中变化的那个读数在步骤 B 中同样变化 → 映射成功；
//        若完全不变 → 映射未生效（与旧方案的 0.000% 区分开）。
//
// 运行：./PanVerifier            （默认 60 秒，每 100ms 采样）
//       ./PanVerifier 120        （指定秒数）

// MARK: - AX 工具函数

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

func axRole(_ element: AXUIElement) -> String {
    axValue(element, kAXRoleAttribute) as? String ?? ""
}

func axDescription(_ element: AXUIElement) -> String {
    if let d = axValue(element, kAXDescriptionAttribute) as? String, !d.isEmpty { return d }
    if let t = axValue(element, kAXTitleAttribute) as? String, !t.isEmpty { return t }
    return ""
}

/// 把 AX value 转成可读字符串（CFNumber / AXValueRef / 其他）。
func readableValue(_ raw: CFTypeRef?) -> String {
    guard let raw = raw else { return "nil" }
    if let num = raw as? NSNumber { return num.stringValue }
    // AXValueRef：尝试读出 CGPoint / CGRect / CGSize。
    if CFGetTypeID(raw) == AXValueGetTypeID() {
        let axv = raw as! AXValue
        switch AXValueGetType(axv) {
        case .cgPoint:
            var p = CGPoint.zero
            if AXValueGetValue(axv, .cgPoint, &p) {
                return String(format: "(%.1f, %.1f)", p.x, p.y)
            }
        case .cgRect:
            var r = CGRect.zero
            if AXValueGetValue(axv, .cgRect, &r) {
                return String(format: "[%.1f, %.1f, %.1f, %.1f]", r.origin.x, r.origin.y, r.width, r.height)
            }
        case .cgSize:
            var s = CGSize.zero
            if AXValueGetValue(axv, .cgSize, &s) {
                return String(format: "%.1f×%.1f", s.width, s.height)
            }
        default: break
        }
    }
    return CFCopyDescription(raw) as String
}

struct ObserveTarget {
    let element: AXUIElement
    let path: String
}

/// 递归收集 FCP AX 树中带 value 的可观察元素（滚动条 + 时间线相关）。
func collectTargets(_ element: AXUIElement, depth: Int, path: String,
                    into output: inout [ObserveTarget]) {
    if depth > 16 { return }
    let r = axRole(element)
    let isInteresting = (r == "AXScrollBar") || (r == "AXScrollArea") || (r == "AXValueIndicator")
    if isInteresting {
        output.append(ObserveTarget(element: element, path: path))
    }
    guard let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
    // 菜单栏子树巨大且与时间线无关，跳过。
    for (index, child) in children.enumerated() {
        let childRole = axRole(child)
        if childRole == "AXMenuBar" { continue }
        collectTargets(child, depth: depth + 1, path: path + "/" + childRole + "[\(index)]", into: &output)
    }
}

// MARK: - 主流程

let args = Array(CommandLine.arguments.dropFirst())
let duration = Double(args.first ?? "60") ?? 60.0

print("GlideCut · FCP 水平平移客观验证工具（只读 AX，不注入任何事件）")
print("采样时长：\(String(format: "%.0f", duration)) 秒  |  间隔：100ms")
print("=" ** 64)

// 1. 辅助功能权限
if !AXIsProcessTrusted() {
    print("[权限不足] 本工具需要「辅助功能」授权才能读取 FCP 时间线数值。")
    print("           请到 系统设置 → 隐私与安全性 → 辅助功能，把本工具添加并勾选后重新运行。")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    exit(2)
}
print("[权限] 辅助功能已授权 ✓")

// 2. 定位 FCP
guard let fcp = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.apple.FinalCutApp" || $0.bundleIdentifier == "com.apple.FinalCutPro"
}) else {
    print("[未就绪] 未检测到运行中的 Final Cut Pro。")
    print("          请先启动 FCP 并打开一个测试项目，把时间线显示出来，再运行本工具。")
    exit(3)
}
print("[就绪] Final Cut Pro 正在运行（PID \(fcp.processIdentifier)）")
print("正在扫描 FCP 辅助功能树，查找可观察的滚动读数……")

let axApp = AXUIElementCreateApplication(fcp.processIdentifier)
var targets: [ObserveTarget] = []
collectTargets(axApp, depth: 0, path: "AXApplication", into: &targets)

guard !targets.isEmpty else {
    print("[未找到] 未发现任何滚动条/数值元素。")
    print("         请确认 FCP 已打开一个项目且时间线可见，然后重试。")
    exit(4)
}

print("[找到] \(targets.count) 个可观察读数：")
for (i, t) in targets.enumerated() {
    let desc = axDescription(t.element)
    print(String(format: "  [%02d] role=%@ desc=%@ value=%@",
                 i, axRole(t.element), desc.isEmpty ? "-" : desc,
                 readableValue(axValue(t.element, kAXValueAttribute))))
}
print("=" ** 64)
print("开始采样。只有数值发生变化时才打印（带时间戳）。")
print("")
print("【步骤 A · 基准】关闭 GlideCut 监听，真实滚动 Shift+滚轮 → 记下变化的读数编号")
print("【步骤 B · 测试】开启 GlideCut 监听，平移键设为 Option，真实滚动 Option+滚轮")
print("")
print("判据：若步骤 A 变化的读数在步骤 B 同样变化 → 映射成功；完全不变 → 未生效。")
print("=" ** 64)

var lastValues = targets.map { readableValue(axValue($0.element, kAXValueAttribute)) }
var changeCount = 0
let deadline = Date().addingTimeInterval(duration)

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"

while Date() < deadline {
    for (i, target) in targets.enumerated() {
        let current = readableValue(axValue(target.element, kAXValueAttribute))
        if current != lastValues[i] {
            let old = lastValues[i]
            lastValues[i] = current
            changeCount += 1
            print("[\(formatter.string(from: Date()))] #\(i) \(axRole(target.element)) "
                + "\(axDescription(target.element)): \(old) → \(current)")
        }
    }
    usleep(100_000) // 100ms
}

print("=" ** 64)
print("采样结束。本次共观察到 \(changeCount) 次数值变化。")
print("请对照步骤 A / B 的记录得出结论；若全程 0 次变化，说明两次滚动都未让时间线移动。")
