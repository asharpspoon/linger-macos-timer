import XCTest
@testable import Linger

/// 预约编辑区 ✓/✕ 按钮形状回归测试（2026-08-24 椭圆 bug）
/// 根因：NSButton cell 在 NSStackView 中会无视 required 高度约束
/// （实测 26 被顶成 29/31 → 椭圆），修复为 CircularIconButton（NSView 模式）。
/// 本测试锁定：布局后两个按钮必须 26×26 正方形且不溢出行边界。
final class ButtonShapeProbeTests: XCTestCase {

    /// 递归找 CircularIconButton（fileprivate 类，用类型名匹配）
    private func findCircularButtons(in v: NSView, out: inout [NSView]) {
        if String(describing: type(of: v)).contains("CircularIconButton") {
            out.append(v)
        }
        for sub in v.subviews { findCircularButtons(in: sub, out: &out) }
    }

    func testConfirmCancelButtonsArePerfectSquares() {
        let w: CGFloat = 300 - 14 * 2
        let sv = ScheduleTimerView(frame: NSRect(x: 14, y: 0, width: w,
                                                 height: ScheduleTimerView.preferredHeight()))
        sv.layoutSubtreeIfNeeded()

        var buttons: [NSView] = []
        findCircularButtons(in: sv, out: &buttons)
        XCTAssertEqual(buttons.count, 2, "应有确认/取消两个圆形按钮，实际 \(buttons.count)")

        for (i, b) in buttons.enumerated() {
            XCTAssertEqual(b.bounds.width, 26, accuracy: 0.5,
                            "按钮\(i) 宽度应为 26（NSButton cell 高度侵蚀回归）")
            XCTAssertEqual(b.bounds.height, 26, accuracy: 0.5,
                            "按钮\(i) 高度应为 26（NSButton cell 高度侵蚀回归）")
            XCTAssertEqual(b.bounds.width / max(b.bounds.height, 0.001), 1.0, accuracy: 0.03,
                            "按钮\(i) 长宽比应为 1.0（正圆前提）")
            // 不溢出父视图（此前 NSButton 高度 29/31 导致 y 为负、上下越界）
            if let p = b.superview {
                XCTAssertGreaterThanOrEqual(b.frame.minY, p.bounds.minY - 0.5,
                                            "按钮\(i) 不应溢出行上边界")
                XCTAssertLessThanOrEqual(b.frame.maxY, p.bounds.maxY + 0.5,
                                         "按钮\(i) 不应溢出行下边界")
            }
        }
    }
}
