import XCTest
@testable import Linger

/// 设置「关于」票据文案回归测试（2026-09-30 用户要求：Version → 2.5.2、Release Date → 2026.09.30）
///
/// 版本号以 AppVersion.current 为唯一真源（构建脚本 Info.plist 也读它），
/// 关于页直接引用该常量，避免「发版改了版本号、关于页还写着旧号」的漂移。
final class AboutTicketTextTests: XCTestCase {

    private func allSubviews(_ v: NSView) -> [NSView] {
        var out: [NSView] = [v]
        for sub in v.subviews { out += allSubviews(sub) }
        return out
    }

    func testAboutTicketShowsCurrentVersionAndReleaseDate() {
        _ = NSApplication.shared
        let view = AboutTicketView(frame: NSRect(x: 0, y: 0, width: 340, height: 400))
        view.layoutSubtreeIfNeeded()

        let texts = allSubviews(view).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(texts.contains("Version \(AppVersion.current)"),
                      "关于页版本号必须跟随 AppVersion.current（当前 2.5.2），实际文案：\(texts)")
        XCTAssertTrue(texts.contains("2026.09.30"),
                      "关于页 Release Date 必须是 2026.09.30，实际文案：\(texts)")
    }
}
