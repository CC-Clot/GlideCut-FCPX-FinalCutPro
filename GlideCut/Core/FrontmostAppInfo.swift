import AppKit
import Foundation

/// 事件发生时前台应用的信息。
///
/// 用于回答「这个滚轮事件当时发给了哪个应用」，是后续判断
/// 「是否只在 Final Cut Pro 时间线上生效」的基础。
struct FrontmostAppInfo {

    let bundleIdentifier: String?
    let name: String?
    let bundlePath: String?
    let processIdentifier: pid_t?

    static func current() -> FrontmostAppInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return FrontmostAppInfo(bundleIdentifier: nil, name: nil, bundlePath: nil, processIdentifier: nil)
        }
        return FrontmostAppInfo(
            bundleIdentifier: app.bundleIdentifier,
            name: app.localizedName,
            bundlePath: app.bundleURL?.path,
            processIdentifier: app.processIdentifier
        )
    }

    /// 用于日志的一行描述。
    var description: String {
        let displayName = name ?? "未知应用"
        let bundle = bundleIdentifier ?? "无 bundle id"
        return "\(displayName) <\(bundle)>"
    }

    /// Final Cut Pro 的已知 bundle identifier。
    ///
    /// **实测确认**（FCP 12.4，macOS 27.2.1）：
    /// - 实际 bundle id 为 **`com.apple.FinalCutApp`**
    /// - 此前代码误写为 `com.apple.FinalCutPro`，精确匹配会失效
    ///
    /// 保留两个值以兼容不同时期/渠道的安装包。
    static let finalCutBundleIdentifiers: Set<String> = [
        "com.apple.FinalCutApp",   // 实测值（FCP 12.x）
        "com.apple.FinalCutPro"    // 历史/别名，作兼容保留
    ]

    /// 是否为 Final Cut Pro。
    ///
    /// 这是「仅对 FCP 生效」的核心判定，必须精确，不能只靠名称模糊匹配。
    var isFinalCutPro: Bool {
        if let bundle = bundleIdentifier {
            if Self.finalCutBundleIdentifiers.contains(bundle) {
                return true
            }
            // 兜底：bundle id 以 FCP 的标识开头（应对未来变体）。
            if bundle.hasPrefix("com.apple.FinalCut") {
                return true
            }
        }
        // 最后兜底：应用显示名匹配。
        if let name = name, name.localizedCaseInsensitiveContains("final cut pro") {
            return true
        }
        return false
    }
}
