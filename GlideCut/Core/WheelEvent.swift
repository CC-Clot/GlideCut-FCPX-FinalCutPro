import CoreGraphics
import Foundation

/// 滚轮事件的主轴。
enum ScrollAxis: String {
    case vertical = "垂直"
    case horizontal = "水平"
}

/// 滚动方向，按原始增量符号判定。
///
/// 注意：`CGEvent` 只给出带符号的原始增量，**符号与视觉方向的对应关系
/// 必须用真实鼠标/触控板在可见滚动目标上实测确认**，见阶段验收报告「待实测」一节。
enum ScrollDirection: String {
    case up = "向上"
    case down = "向下"
    case left = "向左"
    case right = "向右"
    case unknown = "未知"
}

/// 从 `CGEvent` 解析出的滚轮事件。
///
/// `deltaAxis1` 为垂直分量，`deltaAxis2` 为水平分量。主轴取绝对值较大的一方。
struct WheelEvent {

    let timestamp: Date
    let deltaAxis1: CGFloat
    let deltaAxis2: CGFloat
    let modifiers: ModifierState

    /// 本次滚动的主轴：水平分量更大则视为水平滚动。
    var primaryAxis: ScrollAxis {
        if abs(deltaAxis2) > abs(deltaAxis1) {
            return .horizontal
        }
        return .vertical
    }

    /// 主轴方向，按增量符号判定。
    var direction: ScrollDirection {
        switch primaryAxis {
        case .vertical:
            if deltaAxis1 > 0 { return .down }
            if deltaAxis1 < 0 { return .up }
            return .unknown
        case .horizontal:
            if deltaAxis2 > 0 { return .right }
            if deltaAxis2 < 0 { return .left }
            return .unknown
        }
    }

    /// 主轴上的增量绝对值，用于观察触控板惯性产生的连续小增量。
    var magnitude: CGFloat {
        switch primaryAxis {
        case .vertical:
            return abs(deltaAxis1)
        case .horizontal:
            return abs(deltaAxis2)
        }
    }

    /// 人类可读的一行描述，直接用于日志。
    var description: String {
        "滚轮\(direction.rawValue)·\(primaryAxis.rawValue) Δ1=\(String(format: "%.3f", deltaAxis1)) "
            + "Δ2=\(String(format: "%.3f", deltaAxis2)) 修饰键=\(modifiers.description)"
    }

    /// 从原始事件解析。两个分量都为 0 时视为无效事件，返回 `nil`。
    static func from(_ event: CGEvent) -> WheelEvent? {
        let axis1 = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let axis2 = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        if axis1 == 0, axis2 == 0 {
            return nil
        }
        return WheelEvent(
            timestamp: Date(),
            deltaAxis1: axis1,
            deltaAxis2: axis2,
            modifiers: ModifierState.from(event.flags)
        )
    }
}
