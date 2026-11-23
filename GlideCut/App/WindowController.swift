import AppKit
import SwiftUI

/// 主窗口 / 设置窗口管理器。
///
/// **为什么不用 SwiftUI 的 `Settings` 场景**：
/// 在 `LSUIElement=true`（纯菜单栏应用）下，`showSettingsWindow:` selector
/// 经常找不到目标而静默失败，用户点「打开设置」毫无反应。
/// 因此这里用 AppKit 的 `NSWindow` 手动承载 SwiftUI 视图，行为完全可控。
@MainActor
final class WindowController: NSObject, NSWindowDelegate {

    private let controller: EventController
    private var window: NSWindow?

    init(controller: EventController) {
        self.controller = controller
        super.init()
    }

    /// 显示主窗口（首次调用时创建）。
    func showSettingsWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: SettingsView(controller: controller))
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 762)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 762),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = NSLocalizedString("settings.title", comment: "")
        win.minSize = NSSize(width: 720, height: 762)
        win.maxSize = NSSize(width: 720, height: 762)
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
        PermissionsMonitor.shared.resumePolling()
        EventLog.shared.log("设置窗口已打开，权限轮询已恢复")
    }

    /// 窗口关闭后保留实例，下次可快速复用。
    ///
    /// 同时暂停权限轮询，避免应用在后台空转消耗 CPU。
    func windowWillClose(_ notification: Notification) {
        PermissionsMonitor.shared.pausePolling()
        EventLog.shared.log("设置窗口已关闭，权限轮询已暂停")
    }
}