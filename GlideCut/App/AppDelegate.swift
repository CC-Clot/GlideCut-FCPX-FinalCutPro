import AppKit

/// 应用生命周期管理。
///
/// 职责：
/// - 持有业务侧的 `EventController`，供 SwiftUI 场景共享；
/// - 应用启动时在**权限就绪**的前提下自动开启监听（对应产品原则「启动即可使用」）；
/// - 在应用退出时确保事件监听被彻底停止，不残留系统级监听器。
///
/// 权限说明：
/// - 输入监控：监听滚轮事件必需。
/// - 辅助功能：驱动 FCP 菜单（缩放）必需。
/// 权限不足时**不自动开启**，也不假装功能正常，只在日志与设置界面如实提示。
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 业务侧监听控制器，供菜单栏与设置界面共享。
    let controller: EventController = EventController()

    /// 菜单栏控制器（AppKit 实现）。
    private var menuBar: MenuBarController?

    /// 窗口控制器（设置/主窗口）。
    private var windowController: WindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        EventLog.shared.log("GlideCut 启动完成")
        EventLog.shared.log("权限状态：\(PermissionStatus.summary)")

        // 创建窗口控制器（必须早于菜单栏，菜单栏要回调它）
        let windows = WindowController(controller: controller)
        windowController = windows

        // 安装菜单栏图标（使用 NSStatusItem，避开 MenuBarExtra 的渲染问题）
        let bar = MenuBarController(controller: controller, windowController: windows)
        bar.install()
        menuBar = bar

        // 双击图标（重新打开应用）时显示主窗口
        if ProcessInfo.processInfo.environment["GLIDECUT_SHOW_WINDOW_ON_LAUNCH"] == "1" {
            windows.showSettingsWindow()
        }

        // 启动时是否自动开启滚轮增强。
        //
        // ## 产品规则（按用户确认）
        // 1. 每次启动（含开机自启动、手动双击）都**默认开启**滚轮增强；
        // 2. 滚轮增强可随时手动关闭，关闭后**本次会话**保持关闭；
        // 3. 下次启动时再次默认开启 —— 即"手动关闭"不跨启动延续；
        // 4. 开机自启动开关与滚轮增强开关完全独立，互不影响。
        //
        // 因此这里**不再区分启动来源**，统一按"默认开启"处理。
        // `ListeningPreference` 仅用于记住用户在本次会话的临时选择
        // （供菜单栏状态显示），不再作为下次启动的唯一依据。
        _ = ListeningPreference.shared.isEnabled
        EventLog.shared.log("按产品规则：每次启动默认开启滚轮增强")

        if PermissionStatus.isReady {
            controller.startListening()
            EventLog.shared.log("权限已就绪，已自动开启滚轮增强")
        } else {
            EventLog.shared.log("权限不完整，未自动开启监听。请在设置中查看并授权后重试。")
            notifyPermissionNeeded()
        }
    }

    /// 用户再次双击应用图标时调用（Dock/访达）。
    ///
    /// 纯菜单栏应用通常没有 Dock 图标，但访达里双击 .app 会触发此方法，
    /// 此时打开设置/主窗口，让用户能看到界面。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showSettingsWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 无论用户如何退出，都确保监听器被移除，恢复原生滚动行为。
        controller.stopListening()
        EventLog.shared.log("GlideCut 退出，事件监听已彻底停止")
    }

    /// 权限不足时的轻量提示。
    ///
    /// 仅记录日志，不弹系统对话框、不触发系统授权弹窗，
    /// 避免打扰用户；具体引导在设置窗口中提供。
    private func notifyPermissionNeeded() {
        EventLog.shared.log(
            "需要权限：① 系统设置 → 隐私与安全性 → 输入监控（监听滚轮）"
                + "② 隐私与安全性 → 辅助功能（控制 FCP 时间线）"
        )
    }
}