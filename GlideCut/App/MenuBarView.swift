import AppKit

/// 打开 SwiftUI `Settings` 场景的兼容实现。
///
/// `@Environment(\.openSettings)` 与 `SettingsLink` 都是 macOS 14.0+，
/// 在 macOS 13 上需通过 AppKit 的 selector 触发：
/// - macOS 13+：`showSettingsWindow:`
/// - 更早：`showPreferencesWindow:`
///
/// 使用字符串 selector 没有 availability 约束，且两者都作用于 SwiftUI 的
/// `Settings` 场景，行为与系统「偏好设置」菜单项一致。
enum SettingsWindowOpener {

    static func open() {
        // 优先使用 macOS 13 起的设置窗口 selector。
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // 回退到旧版偏好设置窗口 selector。
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
