import AppKit
import Combine
import SwiftUI

/// 菜单栏控制器（AppKit 实现）。
///
/// **为什么不用 SwiftUI 的 `MenuBarExtra`**：
/// 在本机 macOS 27.2 环境下实测，`MenuBarExtra` 场景虽被系统创建
/// （日志可见 `NSStatusItemSceneHostSettings`），但**状态项图标始终不渲染**，
/// 连最简实现（仅 SF Symbol）也无法显示。
/// 因此改用 AppKit 的 `NSStatusItem` + `NSMenu`，这是最底层且可靠的方式。
///
/// 兼容性：`NSStatusItem` 自 macOS 10.0 起可用，完全满足 macOS 13.0 要求。
@MainActor
final class MenuBarController: NSObject {

    private let controller: EventController
    private let windowController: WindowController
    private var statusItem: NSStatusItem?
    private var listenMenuItem: NSMenuItem?
    /// 订阅监听状态变化，确保菜单栏与设置窗口始终一致。
    private var cancellables = Set<AnyCancellable>()

    init(controller: EventController, windowController: WindowController) {
        self.controller = controller
        self.windowController = windowController
        super.init()
    }

    /// 创建并显示菜单栏图标。
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = makeIcon()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "GlideCut"

        let menu = NSMenu()

        let listen = NSMenuItem(
            title: NSLocalizedString("menu.listen.title", comment: ""),
            action: #selector(toggleListening),
            keyEquivalent: ""
        )
        listen.target = self
        listen.state = controller.isListening ? .on : .off
        menu.addItem(listen)
        listenMenuItem = listen

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: NSLocalizedString("menu.openSettings.title", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("menu.quit.title", comment: ""),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        EventLog.shared.log("菜单栏图标已创建（NSStatusItem）")

        // 关键：订阅 isListening 的变化。
        // 之前菜单项状态只在点击时手动刷新，导致用户在设置窗口里改开关后，
        // 菜单栏仍显示旧状态（反键）。订阅后两边始终同步。
        controller.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)
    }

    /// 生成菜单栏图标（template 模式，自动适配深浅色）。
    private func makeIcon() -> NSImage? {
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        // 兜底：系统符号
        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "GlideCut")
        fallback?.isTemplate = true
        return fallback
    }

    /// 更新图标与菜单状态。
    func refreshState() {
        listenMenuItem?.state = controller.isListening ? .on : .off
        statusItem?.button?.appearsDisabled = !controller.isListening
    }

    @objc private func toggleListening() {
        if controller.isListening {
            controller.stopListening()
        } else {
            controller.startListening()
        }
        refreshState()
    }

    @objc private func openSettings() {
        windowController.showSettingsWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
