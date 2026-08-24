import XCTest
@testable import Linger

/// 2026-08-24 bug 探针：预约提交后 0.42s 延迟交付期间面板销毁 → 创建请求静默丢失。
/// 复现链：confirm → closeInlineSchedule → 鼠标离开 → hideHoverListNow 释放 hoverListView
///        → 0.42s 后 `self?.onScheduleConfirm` weak self 已 nil → 预约永远不创建。
final class ScheduleDeliveryRaceTests: XCTestCase {

    /// 确认回调触发后、0.42s 交付前，面板被完整拆除（忠实复刻 hideHoverListNow：
    /// orderOut + window=nil + view 引用清空）—— 创建回调仍必须送达。
    /// 修复前本测试失败（fired == false，weak self 变 nil 静默丢交付）。
    func testConfirmDeliverySurvivesViewDealloc() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        let hoverView = HoverListView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        win.contentView = hoverView
        hoverView.expandScheduleDirectly()
        hoverView.layoutSubtreeIfNeeded()

        let sched = hoverView.subviews.compactMap { $0 as? ScheduleTimerView }.first
        XCTAssertNotNil(sched, "展开后应能找到 ScheduleTimerView")

        var fired = false
        hoverView.onScheduleConfirm = { _, _, _ in fired = true }

        // 用户点 ✓（内部 0.42s 后才交付 onScheduleConfirm）
        sched!.onConfirm?(Date().addingTimeInterval(120), 120, "probe")

        // 忠实复刻 MenuBarManager.hideHoverListNow 的完整拆除
        win.orderOut(nil)
        autoreleasepool {
            win.contentView = nil   // window 不再持有 view（等价 hoverListWindow = nil）
        }

        let exp = expectation(description: "delivery window passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exp.fulfill() }
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(fired,
                      "面板拆除后 0.42s 延迟交付仍应送达 —— 修复前 weak self 已 nil，预约静默丢失")
    }

    /// 对照组：面板存活时交付正常（锁定非竞态路径无回归）
    func testConfirmDeliversWhenViewAlive() {
        let hoverView = HoverListView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        hoverView.expandScheduleDirectly()
        hoverView.layoutSubtreeIfNeeded()
        let sched = hoverView.subviews.compactMap { $0 as? ScheduleTimerView }.first
        XCTAssertNotNil(sched)

        var fired = false
        hoverView.onScheduleConfirm = { _, _, _ in fired = true }
        sched!.onConfirm?(Date().addingTimeInterval(120), 120, "probe")

        let exp = expectation(description: "delivery window passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertTrue(fired, "面板存活时确认应正常交付")
    }
}
