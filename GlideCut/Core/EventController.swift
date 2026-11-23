import CoreGraphics
import Foundation
import SwiftUI

/// 监听控制的对外入口，菜单栏与设置界面共享同一份状态。
///
/// 职责：
/// - 控制监听开关；
/// - 把滚轮事件交给 `WheelTransformer` 决定「转换」还是「放行」；
/// - 把处理结果写入日志并反馈到界面，便于用户与开发者确认实际行为。
final class EventController: ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var lastEventText: String?
    @Published private(set) var lastFrontmostApp: String?
    @Published private(set) var totalWheelEvents = 0
    @Published private(set) var transformedCount = 0

    private var tapController: EventTapController?
    private let transformer = WheelTransformer()
    private let lock = NSLock()

    func startListening(location: CGEventTapLocation = .cgAnnotatedSessionEventTap,
                        intercept: Bool = true) {
        lock.lock()
        guard tapController == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        let controller = EventTapController { [weak self] event, wheel, front in
            guard let self = self else { return .passthrough }
            return self.handle(event: event, wheel: wheel, front: front)
        }

        let result = controller.start(location: location, intercept: intercept)
        switch result {
        case .started:
            lock.lock()
            tapController = controller
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.isListening = true
            }
        case .alreadyRunning:
            break
        case .unavailable(let reason):
            EventLog.shared.log("监听启动失败：\(reason)")
        }
    }

    func stopListening() {
        lock.lock()
        let controller = tapController
        tapController = nil
        lock.unlock()

        controller?.stop()
        // 注意：这里**不**持久化"关闭"状态。
        // 按产品规则，手动关闭只影响本次会话，下次启动仍默认开启。
        DispatchQueue.main.async { [weak self] in
            self?.isListening = false
        }
    }

    /// 供 SwiftUI `Toggle` 使用的双向绑定。
    var isListeningBinding: Binding<Bool> {
        Binding(
            get: { self.isListening },
            set: { newValue in
                if newValue {
                    self.startListening()
                } else {
                    self.stopListening()
                }
            }
        )
    }

    /// 处理单个滚轮事件，返回事件去向。
    private func handle(event: CGEvent, wheel: WheelEvent, front: FrontmostAppInfo)
        -> EventTapController.EventDisposition {
        let outcome = transformer.handle(event: event, wheel: wheel, front: front)

        switch outcome {
        case .transformed(let action):
            let text = "\(wheel.description) | 前台=\(front.description) | ▶ \(action)"
            EventLog.shared.log(text)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastEventText = text
                self.lastFrontmostApp = front.description
                self.totalWheelEvents += 1
                self.transformedCount += 1
            }
            return .consumed

        case .remappedToShift(let action):
            let text = "\(wheel.description) | 前台=\(front.description) | ◆ \(action)"
            EventLog.shared.log(text)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastEventText = text
                self.lastFrontmostApp = front.description
                self.totalWheelEvents += 1
                self.transformedCount += 1
            }
            return .remappedToShift

        case .passthrough(let reason):
            // 放行事件不逐条写日志，避免刷屏；仅在调试需要时可打开。
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastFrontmostApp = front.description
                self.totalWheelEvents += 1
            }
            _ = reason
            return .passthrough
        }
    }
}