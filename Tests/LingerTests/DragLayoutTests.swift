import XCTest
@testable import Linger

final class DragLayoutTests: XCTestCase {

    /// 强断言：真实 show() 计算面板宽度后，每个标签 frame 必须在面板内，
    /// 且 frame 宽度 >= intrinsic（防止右端裁字）。
    func testPanelWidthAccommodatesTracks() {
        let view = DragFeedbackView()
        let anchor = NSRect(x: 600, y: 800, width: 24, height: 24)
        view.show(at: anchor)

        for fontSize in stride(from: 12.0, through: 24.0, by: 2.0) {
            UserDefaults.standard.set(fontSize, forKey: LingerTheme.UserDefaultsKey.dragPreviewFontSize.rawValue)
            view.show(at: anchor)   // 每字号重算面板宽
            for highlight in [DragFeedbackView.HighlightSide.forSide, .tilSide] {
                view.update(distance: 360,
                            seconds: 1800,
                            til: Date().addingTimeInterval(1800),
                            mode: .both,
                            highlight: highlight,
                            overflow: true,
                            title: nil)
                let s = view.debugLayoutSummary()
                guard let panelW = Self.panelWidth(from: s) else {
                    XCTFail("no panelW in \(s)"); return
                }
                for range in Self.frames(from: s) {
                    XCTAssertGreaterThanOrEqual(range.minX, 0, "font \(fontSize) \(highlight): off-left \(s)")
                    XCTAssertLessThanOrEqual(range.maxX, panelW, "font \(fontSize) \(highlight): off-right \(s)")
                    XCTAssertGreaterThanOrEqual(range.width, range.intrinsic - 0.5,
                                                "font \(fontSize) \(highlight): frame < text \(s)")
                }
            }
        }
    }

    // MARK: - 解析 debugLayoutSummary

    private struct FrameInfo {
        let minX: Int
        let maxX: Int
        let width: CGFloat
        let intrinsic: CGFloat
    }

    private static func panelWidth(from s: String) -> Int? {
        guard let r = s.range(of: #"panelW=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(String(s[r]).dropFirst("panelW=".count))
    }

    private static func frames(from s: String) -> [FrameInfo] {
        var out: [FrameInfo] = []
        let pattern = #"\[(-?\d+)\.\.\.(\d+) w=(\d+) iw=([\d.]+)\]"#
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let minX = Int(ns.substring(with: m.range(at: 1)))!
            let maxX = Int(ns.substring(with: m.range(at: 2)))!
            let w = CGFloat(Int(ns.substring(with: m.range(at: 3)))!)
            let iw = CGFloat(Double(ns.substring(with: m.range(at: 4)))!)
            out.append(FrameInfo(minX: minX, maxX: maxX, width: w, intrinsic: iw))
        }
        return out
    }
}
