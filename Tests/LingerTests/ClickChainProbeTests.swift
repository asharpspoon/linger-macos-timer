import XCTest
@testable import Linger

/// 预约编辑区 ✓/✕ 按钮「点击链路」回归测试（2026-08-24 「按不了」bug）
///
/// 根因：hitTest 覆写把传入 point 当「自身坐标系」用，而 AppKit 约定 point 是
/// **superview 坐标系**（文档原文）→ 真实点击（window 自顶向下派发）全部错位 miss →
/// 事件落到父级 NSStackView（无点击处理）→「按钮按不了」。
/// 修复：删除 hitTest 覆写（回到 NSView 默认方形热区）+ PassThroughImageView
/// 让图标子视图穿透（真实子视图 NSImageView 会截获 mouseDown 吞掉事件）。
///
/// 测试坐标约定：hitTest(p) 的 p 必须用「接收者 superview 坐标系」的点
/// —— 用 button.convert(center, to: row3) 生成，不能用 convert(to: button)。
final class ClickChainProbeTests: XCTestCase {

    private func findButtons(in v: NSView, out: inout [NSView]) {
        if String(describing: type(of: v)).contains("CircularIconButton") { out.append(v) }
        for sub in v.subviews { findButtons(in: sub, out: &out) }
    }

    func testHitTestFromDirectSuperviewHitsButtonBody() {
        let w: CGFloat = 300 - 14 * 2
        let sv = ScheduleTimerView(frame: NSRect(x: 14, y: 0, width: w,
                                                 height: ScheduleTimerView.preferredHeight()))
        sv.layoutSubtreeIfNeeded()

        var buttons: [NSView] = []
        findButtons(in: sv, out: &buttons)
        XCTAssertEqual(buttons.count, 2, "应有确认/取消两个按钮")

        for (i, b) in buttons.enumerated() {
            guard let row3 = b.superview else {
                XCTFail("按钮\(i) 无父视图"); continue
            }
            // 按钮中心 → 转到 row3 坐标（= 按钮 superview 坐标系）—— hitTest 的正确传参
            let center = NSPoint(x: b.bounds.midX, y: b.bounds.midY)
            let pInSuperview = b.convert(center, to: row3)
            let hit = row3.hitTest(pInSuperview)
            XCTAssertTrue(String(describing: hit).contains("CircularIconButton"),
                          "按钮\(i) 中心点击必须命中按钮本体，实际命中 \(String(describing: hit))"
                          + "（hitTest 坐标系回归：point 是 superview 坐标系，别当自身坐标用）")
            XCTAssertFalse(String(describing: hit).contains("ImageView"),
                           "按钮\(i) 点击命中图标视图（PassThroughImageView 穿透失效，icon 会吞 mouseDown）")
            // 反向锚点：把自身坐标系的点直接传（错误用法）必须 miss —— 证明坐标系约定没被破坏
            // （若未来有人改回错误覆写，上面正例先红；此断言防止「两种传法都命中」的假实现）
            XCTAssertNil(b.hitTest(center),
                         "按钮\(i) 自身坐标直传应 miss（superview 坐标约定），双命中说明 hitTest 实现有假")
        }
    }

    /// 图标穿透：PassThroughImageView 的 hitTest 恒 nil（点击全归按钮本体）
    func testIconViewPassesThroughAllHits() {
        let w: CGFloat = 300 - 14 * 2
        let sv = ScheduleTimerView(frame: NSRect(x: 14, y: 0, width: w,
                                                 height: ScheduleTimerView.preferredHeight()))
        sv.layoutSubtreeIfNeeded()
        var icons: [NSView] = []
        func findIcons(in v: NSView) {
            if String(describing: type(of: v)).contains("PassThroughImageView") { icons.append(v) }
            v.subviews.forEach(findIcons)
        }
        findIcons(in: sv)
        XCTAssertEqual(icons.count, 2, "应有确认/取消两个穿透图标")
        for (i, icon) in icons.enumerated() {
            XCTAssertNil(icon.hitTest(NSPoint(x: icon.bounds.midX, y: icon.bounds.midY)),
                         "图标\(i) 任意点必须穿透（hitTest 恒 nil）")
        }
    }
}
