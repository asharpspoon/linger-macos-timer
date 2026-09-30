import XCTest
@testable import Linger

/// 状态栏点击链路回归测试（2026-09-25，macOS 27 升级后下拉计时失效）
///
/// 根因：状态栏容器内叠放 NSImageView / NSTextField，点击图标时 AppKit
/// 默认命中这些子视图，父容器不再稳定收到 mouseDown，拖拽状态机无法启动。
/// 修复后容器内任意位置都必须把点击交还 LingerStatusItemView。
final class StatusItemClickChainTests: XCTestCase {

    private func makeView(title: String = "") -> LingerStatusItemView {
        let view = LingerStatusItemView(frame: NSRect(x: 0, y: 0, width: 60, height: 22))
        view.setIcon(NSImage(size: NSSize(width: 18, height: 18)))
        view.setTitle(title)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func hit(in parent: NSView, at point: NSPoint) -> NSView? {
        parent.hitTest(point)
    }

    func testClickOnIconReturnsContainerView() {
        let view = makeView()
        let parent = NSView(frame: view.frame)
        parent.addSubview(view)
        parent.layoutSubtreeIfNeeded()

        guard let image = view.subviews.compactMap({ $0 as? NSImageView }).first else {
            return XCTFail("状态栏视图缺少图标子视图")
        }
        let iconCenter = NSPoint(x: image.frame.midX, y: image.frame.midY)
        XCTAssertTrue(view.hitTest(iconCenter) === view,
                      "点击图标必须命中 LingerStatusItemView，不能被子视图截走")
        XCTAssertTrue(hit(in: parent, at: iconCenter) === view,
                      "父级派发的图标点击也必须回到 LingerStatusItemView")
    }

    func testClickOnTextReturnsContainerView() {
        let view = makeView(title: "25:00")
        let parent = NSView(frame: view.frame)
        parent.addSubview(view)
        parent.layoutSubtreeIfNeeded()

        guard let label = view.subviews.compactMap({ $0 as? NSTextField }).first else {
            return XCTFail("状态栏视图缺少文字子视图")
        }
        let textPoint = NSPoint(x: label.frame.midX, y: label.frame.midY)
        XCTAssertTrue(view.hitTest(textPoint) === view,
                      "点击倒计时文字必须命中 LingerStatusItemView，不能被子视图截走")
    }
}
