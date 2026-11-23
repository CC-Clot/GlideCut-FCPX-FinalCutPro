import AppKit
import Combine
import Foundation

/// 权限状态的可观察包装。
///
/// `PermissionStatus` 是纯静态查询，SwiftUI 无法直接订阅其变化；
/// 本类把结果暴露为 `@Published`，并支持手动刷新与定时轮询
/// （用户去系统设置授权后，切回应用即可看到状态更新）。
@MainActor
final class PermissionsMonitor: ObservableObject {

    static let shared = PermissionsMonitor()

    @Published private(set) var hasInputMonitoring: Bool = false
    @Published private(set) var hasAccessibility: Bool = false

    private var timer: Timer?

    private init() {
        refresh()
        startPolling()
    }

    var isReady: Bool {
        hasInputMonitoring && hasAccessibility
    }

    /// 重新读取系统权限状态。
    func refresh() {
        let im = PermissionStatus.hasInputMonitoring
        let ax = PermissionStatus.hasAccessibility
        if im != hasInputMonitoring { hasInputMonitoring = im }
        if ax != hasAccessibility { hasAccessibility = ax }
    }

    /// 轮询：用户可能在系统设置里改了授权，轮询能及时反映。
    ///
    /// 性能优化：
    /// - 间隔放宽到 5 秒（权限变更不是高频事件）
    /// - `tolerance` 设为间隔的 50%，让系统合并计时器唤醒，显著降低 CPU
    /// - 仅在窗口可见时才需要刷新，不可见时由 `pausePolling()` 停掉
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 2.5
    }

    /// 窗口不可见时暂停轮询，避免无谓的 CPU 消耗。
    func pausePolling() {
        timer?.invalidate()
        timer = nil
    }

    /// 窗口重新可见时恢复轮询。
    func resumePolling() {
        guard timer == nil else { return }
        refresh()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }
}