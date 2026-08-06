import XCTest
@testable import Linger

/// 完成弹窗（强提醒）冒烟测试：有标题/无标题两种视图能构建、布局、且子视图 frame 有效
final class CompletionBannerTests: XCTestCase {

    private func makeEntry(title: String?) -> TimerEntry {
        if let title {
            return TimerEntry(duration: 25 * 60, predefinedTitle: title)
        }
        return TimerEntry(duration: 5 * 60)
    }

    func testBannerWithTitleBuildsAndLaysOut() {
        let view = CompletionBannerView(entry: makeEntry(title: "写代码"),
                                        onClose: {}, onRepeat: {}, onConfirm: { _ in })
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.width, 300, accuracy: 1)
        XCTAssertGreaterThan(view.frame.height, 60)
        // 至少一个子视图（玻璃底 + 标题行 + 内容行）有有效 frame
        let laidOut = view.subviews.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        XCTAssertGreaterThanOrEqual(laidOut.count, 2)
    }

    func testBannerWithoutTitleBuildsAndLaysOut() {
        let view = CompletionBannerView(entry: makeEntry(title: nil),
                                        onClose: {}, onRepeat: {}, onConfirm: { _ in })
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.width, 300, accuracy: 1)
        XCTAssertGreaterThan(view.frame.height, 60)
        let laidOut = view.subviews.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        XCTAssertGreaterThanOrEqual(laidOut.count, 2)
    }
}
