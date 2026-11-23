import Foundation
import ServiceManagement

/// 可持久化的应用配置。
///
/// 使用 `UserDefaults` 存储，重启系统后配置保持。
/// 修饰键以 `ModifierState.rawValue` 的整数形式保存。
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private enum Key {
        static let zoomModifier = "zoomModifier"
        static let panModifier = "panModifier"
        static let launchAtLogin = "launchAtLogin"
        static let featureEnabled = "featureEnabled"
        /// 迁移标记：旧版默认平移键是 Option（走合成事件，已确认不可行）。
        /// 升级到功能映射版后，需把「从未主动改过设置的存量用户」迁移到 Shift。
        static let panDefaultMigrated = "panDefaultMigrated_v2"
    }

    private let defaults = UserDefaults.standard

    /// 缩放使用的修饰键，默认 Command。
    @Published var zoomModifier: ModifierState {
        didSet { defaults.set(zoomModifier.rawValue, forKey: Key.zoomModifier) }
    }

    /// 水平移动使用的修饰键，默认 Shift（FCP 原生平移）。
    /// 可选 Option / Control 走功能映射（改写真实事件 flags 为 Shift）。
    @Published var panModifier: ModifierState {
        didSet { defaults.set(panModifier.rawValue, forKey: Key.panModifier) }
    }

    /// 功能总开关。
    @Published var featureEnabled: Bool {
        didSet { defaults.set(featureEnabled, forKey: Key.featureEnabled) }
    }

    /// 开机启动（默认关闭）。
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// 两个修饰键是否冲突。
    var hasConflict: Bool {
        zoomModifier == panModifier && !zoomModifier.isEmpty
    }

    private init() {
        // 读取已保存值，未保存过则用默认值。
        let zoomRaw = defaults.object(forKey: Key.zoomModifier) as? Int
        zoomModifier = zoomRaw.map { ModifierState(rawValue: $0) } ?? .command

        // 存量配置迁移：旧版默认是 Option。首次升级时，若用户从未改过该值
        // （存下来仍是 .option 且无迁移标记），则切到 Shift 原生平移。
        // 已主动选过 Option 的用户同样迁移——因为旧 Option 走的是失败方案，
        // 新版本 Option 仍是可选映射项，用户可随时再选回。
        let panRaw = defaults.object(forKey: Key.panModifier) as? Int
        let migrated = defaults.bool(forKey: Key.panDefaultMigrated)
        if !migrated {
            panModifier = .shift
            defaults.set(true, forKey: Key.panDefaultMigrated)
            EventLog.shared.log("平移键默认值已迁移：Option → Shift（功能映射版）")
        } else {
            panModifier = panRaw.map { ModifierState(rawValue: $0) } ?? .shift
        }

        if defaults.object(forKey: Key.featureEnabled) == nil {
            featureEnabled = true
        } else {
            featureEnabled = defaults.bool(forKey: Key.featureEnabled)
        }

        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        // 启动时主动同步一次系统登录项状态。
        //
        // 为什么需要：`launchAtLogin` 的 `didSet` 只在"值发生变化"时触发。
        // 如果用户在旧版本里已开启，但当时注册失败（例如签名变化），
        // 之后永远不会有第二次尝试。这里在每次启动时校准一次。
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeLoginItem()
        }
    }

    /// 让系统登录项状态与 `launchAtLogin` 配置保持一致。
    private func synchronizeLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        let want = launchAtLogin
        let registered = (service.status == .enabled)

        if want && !registered {
            do {
                try service.register()
                EventLog.shared.log("登录项已注册（启动时同步）")
            } catch {
                EventLog.shared.log("登录项注册失败（启动时同步）：\(error.localizedDescription)")
            }
        } else if !want && registered {
            do {
                try service.unregister()
                EventLog.shared.log("登录项已移除（启动时同步）")
            } catch {
                EventLog.shared.log("登录项移除失败：\(error.localizedDescription)")
            }
        } else {
            EventLog.shared.log("登录项状态正常：want=\(want) registered=\(registered)")
        }
    }

    /// 恢复默认配置。
    func restoreDefaults() {
        zoomModifier = .command
        panModifier = .shift
        featureEnabled = true
        // 开机启动也恢复默认（关闭）
        launchAtLogin = false
    }

    /// 应用开机启动设置。
    ///
    /// 使用 `SMAppService.mainApp`（macOS 13.0+），正好满足最低部署目标。
    /// 失败时只记录日志，不弹窗打扰用户。
    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                EventLog.shared.log("开机启动：已注册，status=\(service.status.rawValue)")
            } else {
                try service.unregister()
                EventLog.shared.log("开机启动：已取消注册，status=\(service.status.rawValue)")
            }
        } catch {
            EventLog.shared.log("开机启动设置失败：\(error.localizedDescription)，status=\(service.status.rawValue)")
        }
    }
}