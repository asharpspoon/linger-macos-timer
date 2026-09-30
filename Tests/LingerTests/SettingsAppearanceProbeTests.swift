import XCTest
@testable import Linger

/// 设置窗口外观回归测试（2026-09-24，macOS 27 升级后「设置窗口按钮发黑、文字看不见」）
///
/// 根因：本窗口原型是「暗色毛玻璃 + 琥珀金」，底色（surface / surface2 / input）写死深色，
/// 而文字色走系统动态色（LingerTheme.ink/ink2/ink3 = labelColor 系列）。
/// macOS 27 起 `.hudWindow` 材质不再把窗口压成暗色 → 浅色系统下动态色翻成黑，
/// 下拉框等控件变成「深色底 + 黑字」，文字不可读。
///
/// 本测试锁定两条铁律：
/// 1. 设置窗口必须显式锁定暗色外观；
/// 2. 窗口内控件的文字色必须解析为亮色（即在深色底上可读）。
final class SettingsAppearanceProbeTests: XCTestCase {

    private func allSubviews(_ v: NSView) -> [NSView] {
        var out: [NSView] = [v]
        for sub in v.subviews { out += allSubviews(sub) }
        return out
    }

    func testWindowPinsDarkAppearance() {
        _ = NSApplication.shared
        let win = SettingsWindow()
        XCTAssertEqual(win.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua,
                       "设置窗口必须锁定暗色外观：macOS 27 下 .hudWindow 不再自动压暗，"
                       + "不锁定则浅色系统里动态文字色翻黑、深色底控件文字不可读")
    }

    func testPopupButtonTextResolvesToLightColor() {
        _ = NSApplication.shared
        let win = SettingsWindow()
        guard let root = win.contentView else { return XCTFail("设置窗口无 contentView") }
        root.layoutSubtreeIfNeeded()

        let popups = allSubviews(root).compactMap { $0 as? NSPopUpButton }
        XCTAssertGreaterThan(popups.count, 0, "设置窗口应有下拉框（若为 0 说明面板未构建，测试失效）")

        for (i, popup) in popups.enumerated() {
            var resolved: NSColor?
            popup.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.controlTextColor.usingColorSpace(.deviceRGB)
            }
            guard let c = resolved else { return XCTFail("下拉框\(i) 文字色无法解析") }
            let brightness = (c.redComponent + c.greenComponent + c.blueComponent) / 3.0
            XCTAssertGreaterThan(brightness, 0.5,
                                 "下拉框\(i) 文字色必须是亮色（深色底上可读），实际亮度 \(brightness)")
        }
    }
}
