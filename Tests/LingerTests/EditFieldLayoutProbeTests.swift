import XCTest
@testable import Linger

/// 悬浮窗「编辑标题」布局回归测试（2026-09-30：回车图标太靠右、被倒计时遮挡）
///
/// 根因：绘制态先给行内容区做左右内缩 12pt（`rowRect.insetBy(dx: 12)`）再排版，
/// 而编辑态 `startEditing` 直接拿卡片外框 `cardRect` 当右侧锚点，少减这 12pt，
/// 于是「输入框右缘 / 回车图标 / 倒计时左缘」整套判定整体右移 12pt：
/// 图标右缘越过倒计时左缘，视觉上被倒计时压住（用户截图反馈）。
///
/// 修复：编辑态与绘制态共用 `rowContentRect(forCardRect:)` + `timeRightAnchor(inContent:)`，
/// 即 `editingLayout` 的倒计时左缘必须等于绘制态 `timeRect.minX`。
/// 坐标系 = HoverListView 自身 bounds（卡片 x = cardPaddingX = 14）。
final class EditFieldLayoutProbeTests: XCTestCase {

    private let timeFontSize: CGFloat = 13
    /// SF Symbol "return" @10pt 的近似宽度（真机取不到图标时的兜底值也是 12）
    private let iconWidth: CGFloat = 12

    /// 真实卡片矩形：x = HoverDesign.cardPaddingX(14)，宽 = 面板 300 - 14*2
    private func cardRect() -> NSRect {
        NSRect(x: 14, y: 0, width: 300 - 14 * 2, height: 52)
    }

    /// 绘制态倒计时左缘（drawRowContent 里的 timeRect.minX），独立走一遍绘制链路
    private func drawnTimeLeft(card: NSRect, timeText: String) -> CGFloat {
        let contentRect = HoverListView.rowContentRect(forCardRect: card)
        let anchor = HoverListView.timeRightAnchor(inContent: contentRect)
        let font = NSFont.monospacedDigitSystemFont(ofSize: timeFontSize, weight: .semibold)
        let width = (timeText as NSString).size(withAttributes: [.font: font]).width
        return anchor - 12 - width
    }

    private func layout(for timeText: String) -> HoverListView.EditingLayout {
        HoverListView.editingLayout(cardRect: cardRect(),
                                    timeText: timeText,
                                    timeFontSize: timeFontSize,
                                    iconWidth: iconWidth)
    }

    /// 编辑态倒计时左缘 == 绘制态倒计时左缘（此前差 12pt，就是图标被压的直接原因）
    func testEditingTimeLeftMatchesDrawnTimeLeft() {
        let card = cardRect()
        for timeText in ["09:59", "18:49", "59:59"] {
            let l = layout(for: timeText)
            XCTAssertEqual(l.timeLeft, drawnTimeLeft(card: card, timeText: timeText), accuracy: 0.5,
                           "\(timeText)：编辑态倒计时左缘必须等于绘制态"
                           + "（编辑态少减行内容内缩 12pt 的回归）")
        }
    }

    /// 回车图标右缘必须在倒计时左缘左侧 ≥10pt（用户诉求：往左一点，别被倒计时遮挡）
    func testReturnIconClearsCountdown() {
        let card = cardRect()
        for timeText in ["09:59", "18:49", "59:59"] {
            let l = layout(for: timeText)
            let iconRight = l.iconLeft + l.iconWidth
            XCTAssertEqual(iconRight, l.timeLeft - 10, accuracy: 0.01,
                           "\(timeText)：图标右缘应锚定在倒计时左缘外 10pt")
            XCTAssertLessThanOrEqual(iconRight, drawnTimeLeft(card: card, timeText: timeText) - 9.5,
                                     "\(timeText)：图标右缘必须离实际绘制的倒计时左缘 ≥10pt，否则被遮挡")
        }
    }

    /// 输入框在图标左侧留 6pt 收口；左缘维持卡片外框（本次不改，避免输入文字位置跳动）
    func testEditFieldStopsBeforeReturnIcon() {
        let card = cardRect()
        let l = layout(for: "18:49")
        XCTAssertEqual(l.contentX, card.minX, accuracy: 0.01, "输入框左缘沿用卡片外框（历史行为）")
        XCTAssertLessThanOrEqual(l.contentX + l.fieldWidth, l.iconLeft - 5.99,
                                 "输入框右缘应在图标左侧 6pt 处收口，不得压到图标")
        XCTAssertGreaterThan(l.fieldWidth, 40, "常规时长下输入框不应被下限钳制（否则布局退化为堆叠）")
    }
}
