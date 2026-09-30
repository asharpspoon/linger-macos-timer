import XCTest
@testable import Linger

/// 2026-09-30 用户反馈：「最大计时时长」填完要按回车才生效，且需要限制在 1440 分钟以内。
/// 本测试锁定：边输边落盘（不需要回车）、超上限立即钳回、中间态不被误改写。
final class MaxDurationFieldBinderTests: XCTestCase {

    private let suiteName = "linger.maxDurationBinder.tests"
    private let key = LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeBinder(stepper: NSStepper? = nil) -> MaxDurationFieldBinder {
        return MaxDurationFieldBinder(defaults: defaults, stepper: stepper)
    }

    /// 复现生产环境的步进器范围；NSStepper 默认上限只有 59，
    /// 若不配置会把 1440 静默钳成 59，导致测试误报失败。
    private func makeStepper() -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = Double(MaxDurationFieldBinder.minMinutes)
        stepper.maxValue = Double(MaxDurationFieldBinder.maxMinutes)
        return stepper
    }

    private func type(_ text: String, into field: NSTextField, binder: MaxDurationFieldBinder) {
        field.stringValue = text
        binder.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private func endEditing(_ field: NSTextField, binder: MaxDurationFieldBinder) {
        binder.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }

    // MARK: - 纯函数：范围与解析

    func testClampBounds() {
        XCTAssertEqual(MaxDurationFieldBinder.minMinutes, 5)
        XCTAssertEqual(MaxDurationFieldBinder.maxMinutes, 1440, "上限必须是一天（1440 分钟）")
        XCTAssertEqual(MaxDurationFieldBinder.clamp(0), 5)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(4), 5)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(5), 5)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(30), 30)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(1440), 1440)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(1441), 1440)
        XCTAssertEqual(MaxDurationFieldBinder.clamp(999_999), 1440)
    }

    func testParseRejectsIntermediateAndIllegalInput() {
        XCTAssertNil(MaxDurationFieldBinder.parse(""), "空串是输入中间态，不能当成 0")
        XCTAssertNil(MaxDurationFieldBinder.parse("   "))
        XCTAssertNil(MaxDurationFieldBinder.parse("-"), "只有负号是中间态")
        XCTAssertNil(MaxDurationFieldBinder.parse("1.5"), "只接受整数分钟")
        XCTAssertNil(MaxDurationFieldBinder.parse("12a"))
        XCTAssertNil(MaxDurationFieldBinder.parse("１２"), "全角数字不接受")
        XCTAssertEqual(MaxDurationFieldBinder.parse(" 30 "), 30, "首尾空格应被容忍")
        XCTAssertEqual(MaxDurationFieldBinder.parse("1440"), 1440)
    }

    // MARK: - 边输边生效（用户反馈的核心痛点）

    func testTypingTakesEffectImmediatelyWithoutReturnKey() {
        let stepper = makeStepper()
        let binder = makeBinder(stepper: stepper)
        let field = NSTextField()
        field.delegate = binder

        type("45", into: field, binder: binder)

        XCTAssertEqual(defaults.integer(forKey: key), 45,
                       "输完数字必须立刻写入，不能等到回车/失焦")
        XCTAssertEqual(stepper.integerValue, 45, "步进器读数必须同步")
    }

    func testTypingAboveMaxClampsImmediately() {
        let stepper = makeStepper()
        let binder = makeBinder(stepper: stepper)
        let field = NSTextField()
        field.delegate = binder

        type("1441", into: field, binder: binder)

        XCTAssertEqual(field.stringValue, "1440", "超过一天必须立即回显为上限")
        XCTAssertEqual(defaults.integer(forKey: key), 1440, "落盘值不得超过 1440")
        XCTAssertEqual(stepper.integerValue, 1440)
    }

    func testHugeInputClampsToMax() {
        let binder = makeBinder()
        let field = NSTextField()
        field.delegate = binder

        type("999999", into: field, binder: binder)

        XCTAssertEqual(field.stringValue, "1440")
        XCTAssertEqual(defaults.integer(forKey: key), 1440)
    }

    /// 关键回归：输入 "30" 的第一位 "3" 时不能被钳成 5，否则用户根本填不进两位数
    func testPartialInputBelowMinIsNotRewrittenMidTyping() {
        let binder = makeBinder()
        let field = NSTextField()
        field.delegate = binder

        type("3", into: field, binder: binder)
        XCTAssertEqual(field.stringValue, "3", "中间态不能改写，否则输 30 会变成 5")
        XCTAssertNil(defaults.object(forKey: key), "中间态不落盘")

        type("30", into: field, binder: binder)
        XCTAssertEqual(defaults.integer(forKey: key), 30, "补全成合法值后立即生效")
    }

    // MARK: - 离开输入框兜底

    func testEndEditingRestoresSavedValueWhenEmpty() {
        defaults.set(60, forKey: key)
        let binder = makeBinder()
        let field = NSTextField()
        field.delegate = binder

        field.stringValue = ""
        endEditing(field, binder: binder)

        XCTAssertEqual(field.stringValue, "60", "空输入应还原已保存值，不能留空框")
        XCTAssertEqual(defaults.integer(forKey: key), 60)
    }

    func testEndEditingClampsBelowMin() {
        let binder = makeBinder()
        let field = NSTextField()
        field.delegate = binder

        field.stringValue = "2"
        endEditing(field, binder: binder)

        XCTAssertEqual(field.stringValue, "5", "低于下限在离开输入框时钳到 5")
        XCTAssertEqual(defaults.integer(forKey: key), 5)
    }
}
