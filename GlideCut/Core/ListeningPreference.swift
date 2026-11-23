import Combine
import Foundation

/// 监听开关的持久化状态。
///
/// 产品要求：**安装后默认开启；只要用户不手动关闭，永远保持开启**。
/// 因此把用户的选择存进 `UserDefaults`，下次启动时沿用。
///
/// 与 `EventController.isListening` 的区别：
/// - `EventController.isListening` 是**运行时**的真实状态（tap 是否在跑）；
/// - 本类是**用户的意愿**（希望它是开还是关）。
///   启动时若用户意愿为开，且权限就绪，就自动开启监听。
final class ListeningPreference {

    static let shared = ListeningPreference()

    private let key = "listeningEnabledByUser"
    private let defaults = UserDefaults.standard

    private init() {}

    /// 用户是否希望开启滚轮增强。
    ///
    /// **默认值为 `true`**——首次安装后直接可用，符合产品原则「启动即可使用」。
    /// 只有在用户主动关闭后才会变成 `false`，并持久保存。
    var isEnabled: Bool {
        get {
            if defaults.object(forKey: key) == nil {
                return true   // 从未设置过 → 默认开启
            }
            return defaults.bool(forKey: key)
        }
        set {
            defaults.set(newValue, forKey: key)
        }
    }
}