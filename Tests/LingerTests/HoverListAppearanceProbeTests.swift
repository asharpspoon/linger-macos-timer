import XCTest
@testable import Linger

/// 悬浮窗 / 预约编辑面板外观回归测试
/// （2026-09-30 用户反馈：macOS 27 上「提交预约日期」时面板背景一片黑、文字看不见）
///
/// 根因与设置窗口（SettingsAppearanceProbeTests）同源：
/// 悬浮窗是写死深色的无边框窗口（HoverDesign.panelBg / LingerTheme.Color.input 都是深色），
/// 但文字色走系统动态色（LingerTheme.ink = labelColor）。
/// macOS 27 起系统不再把这类窗口自动压成暗色 → 浅色系统下动态色翻黑，
/// 深色胶囊里变成「黑字 + 深底」，观感就是一团黑。
///
/// 本测试锁定两条铁律：
/// 1. 悬浮窗必须显式锁定暗色外观；
/// 2. 预约编辑面板内控件的文字色必须解析为亮色（深色底上可读）。
final class HoverListAppearanceProbeTests: XCTestCase {

    private func allSubviews(_ v: NSView) -> [NSView] {
        var out: [NSView] = [v]
        for sub in v.subviews { out += allSubviews(sub) }
        return out
    }

    /// 复刻真实层级：HoverListWindow → HoverListView → ScheduleTimerView
    private func makeHoverHierarchy() -> (HoverListWindow, HoverListView, ScheduleTimerView) {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 300, height: 420)
        let win = HoverListWindow(contentRect: frame)
        let list = HoverListView(frame: NSRect(origin: .zero, size: frame.size))
        win.contentView = list
        let editor = ScheduleTimerView(frame: NSRect(x: 14, y: 0, width: 272,
                                                     height: ScheduleTimerView.preferredHeight()))
        list.addSubview(editor)
        return (win, list, editor)
    }

    /// 在「浅色系统」下构造，模拟 macOS 27 浅色模式（用户的真实环境）
    private func withLightSystemAppearance(_ body: () throws -> Void) rethrows {
        _ = NSApplication.shared
        let saved = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = saved }
        try body()
    }

    func testHoverWindowPinsDarkAppearance() {
        withLightSystemAppearance {
            let (win, _, _) = makeHoverHierarchy()
            XCTAssertEqual(win.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua,
                           "悬浮窗必须锁定暗色外观：macOS 27 下无边框窗口不再自动压暗，"
                           + "不锁定则浅色系统里动态文字色翻黑、深色底控件文字不可读")
        }
    }

    func testScheduleEditorTextResolvesToLightColor() {
        withLightSystemAppearance {
            let (_, _, editor) = makeHoverHierarchy()
            editor.layoutSubtreeIfNeeded()

            let controls = allSubviews(editor).compactMap { $0 as? NSControl }
            XCTAssertGreaterThanOrEqual(controls.count, 4,
                                        "预约编辑面板应有日期/时间/时长/名称 4 个控件（若为 0 说明面板未构建，测试失效）")

            var checked = 0
            for (i, control) in controls.enumerated() {
                let dynamic: NSColor?
                if let picker = control as? NSDatePicker {
                    dynamic = picker.textColor
                } else if let field = control as? NSTextField {
                    dynamic = field.textColor
                } else {
                    dynamic = nil
                }
                guard let color = dynamic else { continue }

                var resolved: NSColor?
                control.effectiveAppearance.performAsCurrentDrawingAppearance {
                    resolved = color.usingColorSpace(.deviceRGB)
                }
                guard let c = resolved else { return XCTFail("控件\(i) 文字色无法解析") }
                let brightness = (c.redComponent + c.greenComponent + c.blueComponent) / 3.0
                XCTAssertGreaterThan(brightness, 0.5,
                                     "\(type(of: control))#\(i) 文字色必须是亮色"
                                     + "（深色胶囊上可读），实际亮度 \(brightness)")
                checked += 1
            }
            XCTAssertGreaterThanOrEqual(checked, 4, "至少应校验到 4 个带文字色的控件")
        }
    }
}
