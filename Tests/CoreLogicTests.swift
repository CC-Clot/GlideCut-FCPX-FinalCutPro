import CoreGraphics
import XCTest

/// 核心逻辑单元测试。
///
/// 覆盖纯函数部分：修饰键解析、滚轮方向判定、冲突检测。
/// 这些逻辑不依赖 FCP 或系统权限，可独立验证。
final class CoreLogicTests: XCTestCase {

    // MARK: - 修饰键解析

    func testModifierParsingCommand() {
        let state = ModifierState.from([.maskCommand])
        XCTAssertTrue(state.contains(.command))
        XCTAssertFalse(state.contains(.option))
    }

    func testModifierParsingOption() {
        // 关键：Option 在 CoreGraphics 中对应 maskAlternate
        let state = ModifierState.from([.maskAlternate])
        XCTAssertTrue(state.contains(.option), "maskAlternate 必须解析为 Option")
        XCTAssertFalse(state.contains(.command))
    }

    func testModifierParsingControl() {
        XCTAssertTrue(ModifierState.from([.maskControl]).contains(.control))
    }

    func testModifierParsingShift() {
        XCTAssertTrue(ModifierState.from([.maskShift]).contains(.shift))
    }

    func testModifierParsingCombined() {
        let state = ModifierState.from([.maskCommand, .maskShift])
        XCTAssertTrue(state.contains(.command))
        XCTAssertTrue(state.contains(.shift))
        XCTAssertFalse(state.contains(.option))
        XCTAssertEqual(state.description, "Command+Shift")
    }

    func testModifierParsingEmpty() {
        let state = ModifierState.from([])
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.description, "无")
    }

    func testModifierEquality() {
        // 用于修饰键冲突检测
        XCTAssertEqual(ModifierState.command, .command)
        XCTAssertNotEqual(ModifierState.command, .option)
    }

    // MARK: - 功能映射：flags 改写（Option/Control → Shift）

    func testRemapOptionToShiftReplacesAlternateWithShift() {
        // 真实场景：Option+滚轮的原始 flags 是 maskAlternate
        let result = ModifierState.shiftedFlags(from: [.maskAlternate, .maskNonCoalesced],
                                                replacing: .option)
        XCTAssertFalse(result.contains(.maskAlternate), "Option 标志必须被移除")
        XCTAssertTrue(result.contains(.maskShift), "必须加上 Shift 标志")
        XCTAssertTrue(result.contains(.maskNonCoalesced), "无关标志位必须原样保留")
    }

    /// 真机日志复现：0x80020（高位 Option + 低位左 Option）
    /// 必须改写成 0x20002（高位 Shift + 低位左 Shift），不能停在 0x20020。
    func testRemapRealOptionFlagsToRealShiftFlags() {
        let optionFlags = CGEventFlags(rawValue: 0x80020)
        let result = ModifierState.shiftedFlags(from: optionFlags, replacing: .option)
        let expected = CGEventFlags(rawValue: 0x20002)
        XCTAssertEqual(result.rawValue, expected.rawValue,
                       String(format: "低位设备位必须一起改写：期望 0x%X，实际 0x%X",
                              expected.rawValue, result.rawValue))
    }

    func testRemapControlToShiftReplacesControlWithShift() {
        // 真机场景：Control+滚轮 = 0x40008（高位 Control + 低位左 Control）
        let controlFlags = CGEventFlags(rawValue: 0x40008)
        let result = ModifierState.shiftedFlags(from: controlFlags, replacing: .control)
        let expected = CGEventFlags(rawValue: 0x20002)
        XCTAssertEqual(result.rawValue, expected.rawValue,
                       String(format: "Control 映射后应为真实 Shift 0x20002，实际 0x%X",
                              result.rawValue))
    }

    func testRemapPreservesUnrelatedModifiers() {
        // 若事件同时带 Command（正常不会与平移键相同，但验证纯函数不误伤）
        let result = ModifierState.shiftedFlags(from: [.maskAlternate, .maskCommand],
                                                replacing: .option)
        XCTAssertTrue(result.contains(.maskCommand), "Command 标志不应被改写函数移除")
        XCTAssertTrue(result.contains(.maskShift))
    }

    func testRemapOnAlreadyShiftKeepsShift() {
        // 幂等性：输入已含 Shift 时结果仍含 Shift，不会意外丢失。
        let result = ModifierState.shiftedFlags(from: [.maskShift], replacing: .option)
        XCTAssertTrue(result.contains(.maskShift))
    }

    /// 核心前提验证：功能映射必须作用在**真实事件对象**上原地改写，
    /// 且不能破坏事件来源（否则会重蹈「合成事件被 FCP 过滤」的覆辙）。
    func testInPlaceFlagRewritePreservesEventSource() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw XCTSkip("无法创建 HID 事件源，跳过")
        }
        guard let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel, wheelCount: 1,
                                  wheel1: 10, wheel2: 0, wheel3: 0) else {
            throw XCTSkip("无法创建测试事件，跳过")
        }
        event.flags = [.maskAlternate]
        let sourceBefore = event.getIntegerValueField(.eventSourceStateID)

        // 模拟 tap 回调中的原地改写
        event.flags = ModifierState.shiftedFlags(from: event.flags, replacing: .option)

        XCTAssertTrue(event.flags.contains(.maskShift), "事件 flags 应含 Shift")
        XCTAssertFalse(event.flags.contains(.maskAlternate), "事件 flags 不应再含 Option")
        let sourceAfter = event.getIntegerValueField(.eventSourceStateID)
        XCTAssertEqual(sourceAfter, sourceBefore, "事件来源不得改变（必须仍是真实来源）")
    }

    /// 真实 Shift 结构验证：改写后必须保留垂直增量 Δ1（不能搬到水平轴），
    /// flags 精确等于真实 Shift 0x20002，事件来源不变。
    ///
    /// 用户实测真实 Shift+滚轮 = flags 0x20002 + Δ1 有值 + Δ2=0。
    /// FCP 靠「Shift + 垂直增量」内部转水平平移，搬走 Δ1 会导致平移失效。
    func testPanRewriteKeepsVerticalDeltaLikeRealShift() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw XCTSkip("无法创建 HID 事件源，跳过")
        }
        guard let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel, wheelCount: 1,
                                  wheel1: 10, wheel2: 0, wheel3: 0) else {
            throw XCTSkip("无法创建测试事件，跳过")
        }
        event.flags = CGEventFlags(rawValue: 0x80020)
        let sourceBefore = event.getIntegerValueField(.eventSourceStateID)
        let p1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let p2 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)

        // 模拟业务改写：只改 flags，不碰任何滚动轴字段
        event.flags = ModifierState.shiftedFlags(from: event.flags, replacing: .option)

        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), p1,
                       "垂直增量 Δ1 必须原样保留（FCP 靠它做平移）")
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2), p2,
                       "水平增量 Δ2 必须保持原值（通常为 0）")
        XCTAssertEqual(event.flags.rawValue, CGEventFlags(rawValue: 0x20002).rawValue,
                       "flags 应精确等于真实 Shift 0x20002")
        XCTAssertEqual(event.getIntegerValueField(.eventSourceStateID), sourceBefore,
                       "事件来源不得改变")
    }

    // MARK: - AX 平移步长

    func testPanStepSignByDirection() {
        // sign 只表示滚动条 value 的偏移方向，不绑定具体物理方向。
        XCTAssertGreaterThan(ModifierState.panStep(for: 3, sign: 1), 0)
        XCTAssertLessThan(ModifierState.panStep(for: 3, sign: -1), 0)
    }

    func testPanSignFollowsCorrectedUserFacingDirection() {
        // 真机反馈校正后的映射：物理上滚(.down) → value 减小；物理下滚(.up) → value 增大。
        XCTAssertEqual(ModifierState.panSign(for: .down), -1)
        XCTAssertEqual(ModifierState.panSign(for: .up), 1)
        XCTAssertNil(ModifierState.panSign(for: .left))
        XCTAssertNil(ModifierState.panSign(for: .right))
        XCTAssertNil(ModifierState.panSign(for: .unknown))
    }

    func testPanStepClamped() {
        // 幅度再大也有上限（避免一格滚到底），再小也有下限（保证肉眼可见）。
        XCTAssertLessThanOrEqual(ModifierState.panStep(for: 100, sign: 1), 0.15)
        XCTAssertGreaterThanOrEqual(ModifierState.panStep(for: 0.01, sign: 1), 0.04)
        // 像素验证确定的可见步长：典型幅度应产生 >=0.04 的位移。
        XCTAssertGreaterThanOrEqual(ModifierState.panStep(for: 3, sign: 1), 0.04)
    }

    // MARK: - 滚轮方向

    func testVerticalDirectionNegativeIsUp() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: -3, deltaAxis2: 0, modifiers: [])
        XCTAssertEqual(wheel.direction, .up, "deltaAxis1 < 0 应判定为向上")
    }

    func testVerticalDirectionPositiveIsDown() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: 3, deltaAxis2: 0, modifiers: [])
        XCTAssertEqual(wheel.direction, .down, "deltaAxis1 > 0 应判定为向下")
    }

    func testHorizontalDirectionPositiveIsRight() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: 0, deltaAxis2: 5, modifiers: [])
        XCTAssertEqual(wheel.primaryAxis, .horizontal)
        XCTAssertEqual(wheel.direction, .right)
    }

    func testHorizontalDirectionNegativeIsLeft() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: 0, deltaAxis2: -5, modifiers: [])
        XCTAssertEqual(wheel.direction, .left)
    }

    func testPrimaryAxisChoosesLarger() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: 2, deltaAxis2: 10, modifiers: [])
        XCTAssertEqual(wheel.primaryAxis, .horizontal, "水平分量更大时主轴应为水平")
    }

    func testMagnitudeReturnsAbsoluteValue() {
        let wheel = WheelEvent(timestamp: Date(), deltaAxis1: -7, deltaAxis2: 0, modifiers: [])
        XCTAssertEqual(wheel.magnitude, 7)
    }

    // MARK: - 缩放方向映射（业务规则）

    /// 验证业务规则：物理上滚 = 放大，物理下滚 = 缩小。
    ///
    /// 本机自然滚动关闭时，物理上滚上报 deltaAxis1 > 0（系统语义为 .down），
    /// 因此缩放映射必须把 .down 视为放大。
    func testZoomDirectionMappingMatchesUserExpectation() {
        // 物理上滚（本机环境下系统标为 .down）
        let physicalUp = WheelEvent(timestamp: Date(), deltaAxis1: 3, deltaAxis2: 0, modifiers: [.command])
        // 物理下滚（系统标为 .up）
        let physicalDown = WheelEvent(timestamp: Date(), deltaAxis1: -3, deltaAxis2: 0, modifiers: [.command])

        XCTAssertEqual(physicalUp.direction, .down)
        XCTAssertEqual(physicalDown.direction, .up)

        // 业务映射：.down → 放大(+1)，.up → 缩小(-1)
        XCTAssertEqual(zoomSign(for: physicalUp.direction), 1, "物理上滚应放大")
        XCTAssertEqual(zoomSign(for: physicalDown.direction), -1, "物理下滚应缩小")
    }

    /// 与 WheelTransformer.enqueueZoom 中的映射保持一致。
    private func zoomSign(for direction: ScrollDirection) -> Int {
        switch direction {
        case .down: return 1
        case .up:   return -1
        default:    return 0
        }
    }

    // MARK: - FCP 识别

    func testFinalCutProBundleIdentifiers() {
        let ids = FrontmostAppInfo.finalCutBundleIdentifiers
        XCTAssertTrue(ids.contains("com.apple.FinalCutApp"), "实测值必须包含")
        XCTAssertTrue(ids.contains("com.apple.FinalCutPro"), "兼容值必须保留")
    }

    func testIsFinalCutProWithRealBundleID() {
        let info = FrontmostAppInfo(
            bundleIdentifier: "com.apple.FinalCutApp",
            name: "Final Cut Pro",
            bundlePath: "/Applications/Final Cut Pro.app",
            processIdentifier: 1
        )
        XCTAssertTrue(info.isFinalCutPro)
    }

    func testIsNotFinalCutProWithOtherApp() {
        let info = FrontmostAppInfo(
            bundleIdentifier: "com.google.Chrome",
            name: "Google Chrome",
            bundlePath: nil,
            processIdentifier: 2
        )
        XCTAssertFalse(info.isFinalCutPro, "其他应用绝不能被识别为 FCP")
    }

    func testIsFinalCutProRejectsPrefixOnlyLookalike() {
        // 名称相似但不是 FCP 的应用不应误判
        let info = FrontmostAppInfo(
            bundleIdentifier: "com.example.finalcuthelper",
            name: "Final Cut Helper",
            bundlePath: nil,
            processIdentifier: 3
        )
        // hasPrefix("com.apple.FinalCut") 为 false，名称不含 "final cut pro"
        XCTAssertFalse(info.isFinalCutPro)
    }
}
