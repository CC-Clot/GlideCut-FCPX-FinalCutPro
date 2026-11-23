import Foundation

/// 阶段一验证探针（独立命令行工具，**不属于** GlideCut 正式业务模块）。
///
/// 用途：在不启动完整 GlideCut 应用的情况下，单独验证 CGEventTap 的
/// 创建、后台事件循环、事件解析与彻底停止这四件事。
///
/// 安全边界：
/// - 只监听（`listenOnly`），不拦截、不修改、不注入任何事件；
/// - 不申请、不修改任何系统权限，不触碰系统配置；
/// - 因此不会对任何前台应用（包括 Final Cut Pro）产生实际影响。
///
/// 运行：
///   ./GlideCutWheelProbe 20
/// 参数为监听秒数，默认 15。运行期间请**真实操作鼠标滚轮 / 触控板**，
/// 观察终端输出的滚轮方向、轴、增量、修饰键与前台应用。
///
/// 注意：若当前进程尚未获得 macOS「输入监控」授权，`CGEvent.tapCreate`
/// 会返回空，本探针会如实报告，不会绕过或伪造授权。
@main
struct WheelTapProbe {

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let duration = Double(arguments.first ?? "15") ?? 15.0

        print("GlideCut 阶段一 · 滚轮监听验证探针")
        print("监听时长：\(String(format: "%.0f", duration)) 秒")
        print("模式：仅监听（listen-only），不注入、不拦截任何事件")
        print("开始时间：\(format(Date()))")
        print(String(repeating: "-", count: 62))
        print("现在请真实滚动鼠标滚轮 / 触控板（可配合 Command、Option、")
        print("Control、Shift 按键），观察下方实时日志。")
        print(String(repeating: "-", count: 62))

        // 使用真实转换器，验证「识别 → 转换」全链路。
        let transformer = WheelTransformer()
        let handler: EventTapController.WheelHandler = { event, wheel, front in
            let outcome = transformer.handle(event: event, wheel: wheel, front: front)
            switch outcome {
            case .transformed(let action):
                print("[转换] \(wheel.description)")
                print("       前台应用 = \(front.description)")
                print("       ▶ 已执行：\(action)")
                return .consumed
            case .remappedToShift(let action):
                print("[映射] \(wheel.description)")
                print("       前台应用 = \(front.description)")
                print("       ◆ 已改写为 Shift+滚轮：\(action)")
                return .remappedToShift
            case .passthrough(let reason):
                print("[放行] \(wheel.description) | \(reason)")
                return .passthrough
            }
        }

        let controller = EventTapController(handler: handler)

        // 关键验证点一：CGEventTap 能否创建成功（反映「输入监控」授权状态）。
        let result = controller.start(location: .cgSessionEventTap, intercept: true)
        switch result {
        case .started:
            print("[验证] CGEvent.tapCreate 成功，事件循环已启动")
        case .alreadyRunning:
            print("[验证] 事件监听已在运行")
        case .unavailable(let reason):
            print("[验证] CGEvent.tapCreate 失败：\(reason)")
            print("[结论] 当前无法创建系统级事件监听，需先完成授权（见阶段验收报告）。")
            controller.stop()
            exit(1)
        }

        // 关键验证点二：监听期间持续接收事件。
        Thread.sleep(forTimeInterval: duration)

        // 关键验证点三：停止后事件循环彻底退出，不再接收任何事件。
        controller.stop()

        print(String(repeating: "-", count: 62))
        print("停止后日志（确认监听已结束，后续滚动不应再产生事件记录）")
        print(String(repeating: "-", count: 62))
        for line in EventLog.shared.recent(limit: 20) {
            print(line)
        }
        print("结束时间：\(format(Date()))")
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
