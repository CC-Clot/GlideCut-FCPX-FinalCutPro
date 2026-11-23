import SwiftUI

/// GlideCut 应用入口。
///
/// 架构说明（重要）：
/// - 菜单栏图标：由 `MenuBarController`（AppKit `NSStatusItem`）创建。
///   SwiftUI 的 `MenuBarExtra` 在本机 macOS 27.2 上实测无法渲染图标。
/// - 设置窗口：由 `WindowController`（AppKit `NSWindow` + `NSHostingView`）创建。
///   SwiftUI 的 `Settings` 场景在 `LSUIElement` 应用上配合 selector 常失效。
///
/// 因此本 App 只保留一个空场景承载生命周期，界面全部由 AppKit 驱动，
/// 行为完全可预期。
///
/// 兼容性：所有 API 兼容 macOS 13.0。
@main
struct GlideCutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        // 不声明可见场景；菜单栏与窗口均由 AppDelegate/AppKit 负责。
        // 使用 Settings 场景仅为满足 App 协议要求，内容不会自动展示。
        Settings {
            EmptyView()
        }
    }
}
