import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 权限状态检测与引导。
///
/// GlideCut 需要两项系统权限：
/// - **输入监控**（Input Monitoring）：`CGEventTap` 监听全局滚轮事件必需。
/// - **辅助功能**（Accessibility）：通过 AX 驱动 FCP 菜单（缩放）必需。
///
/// 约束：不绕过系统安全机制，不擅自修改系统配置，只做检测与引导。
enum PermissionStatus {

    /// 输入监控是否已授权。
    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// 辅助功能是否已授权。
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 两项权限是否都已就绪。
    static var isReady: Bool {
        hasInputMonitoring && hasAccessibility
    }

    /// 人类可读的状态摘要，用于界面显示与日志。
    static var summary: String {
        "输入监控=\(hasInputMonitoring ? "已授权" : "未授权")，"
            + "辅助功能=\(hasAccessibility ? "已授权" : "未授权")"
    }

    /// 打开「系统设置 → 隐私与安全性 → 输入监控」。
    ///
    /// 使用 `x-apple.systempreferences:` URL scheme，在 macOS 13+ 上可直达对应面板。
    static func openInputMonitoringSettings() {
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    /// 打开「系统设置 → 隐私与安全性 → 辅助功能」。
    static func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    private static func openPrivacyPane(anchor: String) {
        // macOS 13+ 使用 com.apple.settings.PrivacySecurity.extension
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}