import Cocoa

/// Linger 全局设计令牌（design token 单一来源）。
///
/// 集中管理颜色、圆角、间距、动画时长、字体与 UserDefaults 键，
/// 替换散落在各文件中的硬编码 `NSColor(calibratedRed:0.961,green:0.651,blue:0.137,...)`
/// （即 `#F5A623` 琥珀金）以及散落的字符串字面量。
///
/// 注意：本文件依赖 AppKit（颜色/字体令牌），因此**不应**被
/// `TimerEntry` / `TimerManager` 这类 Foundation-only 叶子模块导入。
/// 通知名常量（`timerStateChangedNotification` / `timerDidFinishNotification`）
/// 保留在 `TimerEntry.swift` 中（Foundation-only），以维持叶子模块的纯净性。
enum LingerTheme {

    // MARK: - 平台无关色值（自 Linger2.1 移植）
    //
    // 2.1 的渲染层（DragFeedbackView）以 `LingerTheme.Color.xxx` + `nsColor(_:)`
    // 的形式取色。这里原样补齐这套令牌，**不改动** 下方 2.0 既有的 NSColor 常量，
    // 两套并存互不干扰（`Color` 是嵌套命名空间，与顶层 amberLight/ink2/ink3 不冲突）。

    /// 平台无关的 RGBA 颜色分量（值域 0...255 / alpha 0...1）。
    struct RGBA: Equatable, Hashable {
        let r: Double
        let g: Double
        let b: Double
        let a: Double

        init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        /// 导出 CSS 风格十六进制串（如 "#F5A623" 或带 alpha 的 "#F5A623E6"）。
        var hex: String {
            func h(_ v: Double) -> String {
                let int = Int((min(255, max(0, v))).rounded())
                return String(format: "%02X", int)
            }
            let base = "#" + h(r) + h(g) + h(b)
            if a >= 0.999 { return base }
            return base + h(a * 255)
        }
    }

    /// 颜色令牌（琥珀金阶梯 + 面板 + 中性 + 状态），与 Linger2.1 逐值对齐。
    enum Color {
        // 琥珀金阶梯（唯一品牌色相 #F5A623）
        static let amber        = RGBA(245, 166, 35)          // #F5A623 主色
        static let amberLight   = RGBA(255, 201, 102)         // #FFC966
        static let amberLighter = RGBA(255, 224, 168)         // #FFE0A8
        static let amberDark    = RGBA(217, 142, 20)          // #D98E14
        static let amberDarker  = RGBA(143, 90, 13)           // #8F5A0D
        static let amberSoft    = RGBA(245, 166, 35, 0.14)    // 激活背景
        static let amberGlow    = RGBA(245, 166, 35, 0.40)    // 发光阴影

        // 面板背景
        static let panelBgDark  = RGBA(12, 12, 14, 0.92)
        static let panelBgLight = RGBA(242, 242, 245, 0.95)

        // 中性文字（暗色优先）
        static let ink  = RGBA(245, 245, 243)
        static let ink2 = RGBA(166, 166, 170)
        static let ink3 = RGBA(117, 117, 123)
        static let line = RGBA(255, 255, 255, 0.10)

        // 语义状态色
        static let success = RGBA(48, 209, 88)   // #30D158
        static let warning = RGBA(255, 159, 10)  // #FF9F0A
        static let error   = RGBA(255, 69, 58)   // #FF453A
        static let info    = RGBA(10, 132, 255)  // #0A84FF
    }

    /// 将平台无关的 RGBA 转为 NSColor（calibrated，自带 alpha）。
    static func nsColor(_ c: RGBA) -> NSColor {
        return NSColor(calibratedRed: c.r / 255.0,
                       green: c.g / 255.0,
                       blue: c.b / 255.0,
                       alpha: c.a)
    }

    // MARK: - 颜色：琥珀金主色系

    /// 主琥珀金 #F5A623
    static let amberGold = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 1.0)
    /// 渐变深端（顶部铜色，略调亮，避免过深）
    static let amberDeep = NSColor(calibratedRed: 0.88, green: 0.55, blue: 0.20, alpha: 1.0)
    /// 渐变亮端（底部亮金）
    static let amberLight = NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.30, alpha: 1.0)

    /// 由浅到深的琥珀金渐变（[亮金, 深铜]），供 NSGradient 使用
    static let amberGradient: [NSColor] = [amberLight, amberDeep]

    // MARK: - 语义状态色

    /// 成功/已授权（PRD §8 状态色 success #30D158）
    static let stateSuccess = NSColor(calibratedRed: 0.188, green: 0.820, blue: 0.345, alpha: 1.0)

    // MARK: - 中性文字 / 分隔色（语义色，深浅自适应）

    /// 主文字色（labelColor）
    static let ink = NSColor.labelColor
    /// 次级文字色
    static let ink2 = NSColor.secondaryLabelColor
    /// 三级文字色（占位 / 弱化）
    static let ink3 = NSColor.tertiaryLabelColor
    /// 分隔线色（separatorColor）
    static let line = NSColor.separatorColor
    /// 琥珀柔光填充（激活态背景，rgba(245,166,35,0.14)）
    static let amberSoft = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 0.14)

    // MARK: - 面板背景（深浅模式）

    /// 暗色面板背景 rgba(12,12,14,0.92)
    static let panelBackgroundDark = NSColor(calibratedRed: 12 / 255, green: 12 / 255, blue: 14 / 255, alpha: 0.92)
    /// 浅色面板背景 rgba(242,242,245,0.95)
    static let panelBackgroundLight = NSColor(calibratedRed: 242 / 255, green: 242 / 255, blue: 245 / 255, alpha: 0.95)

    /// 根据当前系统外观返回面板背景色
    static func panelBackground() -> NSColor {
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua) == .darkAqua
        return isDark ? panelBackgroundDark : panelBackgroundLight
    }

    // MARK: - 圆角

    static let radiusXS: CGFloat = 4
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16

    // MARK: - 间距（8pt 基准网格）

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32

    // MARK: - 动画时长

    static let durationFast: TimeInterval = 0.15
    static let durationBase: TimeInterval = 0.3
    static let durationSlow: TimeInterval = 0.45
    /// 设置窗口跨 Tab 高度过渡（PRD 原型 0.4s cubic-bezier(.32,.72,0,1)）
    static let durationResize: TimeInterval = 0.4
    /// 呼吸边框完整周期（半周期 1.0s × 2）
    static let durationBreath: TimeInterval = 2.0
    /// 呼吸「半周期」（自 Linger2.1 移植：CABasicAnimation + autoreverses 用，×2 即完整周期）
    static let durBreath: Double = 1.0

    // MARK: - 字体

    /// 等宽时间字体（计时数字用，保证宽度稳定不跳动）
    static func timeFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// 标签 / 正文系统字体
    static func labelFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - UserDefaults 键（集中管理，避免散落字符串）

    /// 所有 UserDefaults 键的单一来源
    enum UserDefaultsKey: String {
        case countdownLeadTime = "linger_countdownLeadTime"
        case recordedCalendarEntries = "linger_recordedCalendarEntries"
        case hoverListFontSize = "linger_hoverListFontSize"
        case cleanupInterval = "linger_cleanupInterval"
        case defaultDuration = "linger_defaultDuration"
        case calendarWriteMode = "linger_calendarWriteMode"

        // MARK: - T7 操作面板

        /// T7: 下拉线最大长度（25–75，默认 50）
        case maxDragLinePercent = "linger_maxDragLinePercent"
        /// T7: 最大计时时长（分钟，5–1440，默认 30）
        case maxDurationMinutes = "linger_maxDurationMinutes"
        /// T7: 时间格式（hms/hm/ms，默认 hms）
        case timeFormat = "linger_timeFormat"
        /// T12: 拖拽双轨模式（both/countdown/endTime，默认 both）
        case dualRailMode = "linger_dualRailMode"
        /// 2026-08-04: 拖拽预览计时字号（18–30pt，默认 22）
        case dragPreviewFontSize = "linger_dragPreviewFontSize"
        /// 2026-08-04: 拖拽引导提示已显示次数（前 3 次显示，之后永久隐藏）
        case dragHintUsageCount = "linger_dragHintUsageCount"

        // MARK: - T8 通知面板

        /// T8: 计时完成是否弹通知（Bool，默认开）
        case notifyOnComplete = "linger_notifyOnComplete"
        /// T6: 完成提示音开关（Bool，默认开）
        case playSound = "linger_playSound"
        /// T6: 完成提示音音效名（String，默认 "Glass"）
        case soundName = "linger_soundName"

        // MARK: - T9 日历面板

        /// T9: 目标日历（标题，默认 "Linger"）
        case targetCalendar = "linger_targetCalendar"
        /// T9: 默认标题（仅自动模式可用，默认空）
        case defaultTitle = "linger_defaultTitle"
        /// T9: Fn 快捷键预设标题
        case fnTitle = "linger_fnTitle"
        /// T9: Ctrl 快捷键预设标题
        case ctrlTitle = "linger_ctrlTitle"
        /// T9: Opt 快捷键预设标题
        case optTitle = "linger_optTitle"

        // MARK: - T10 通用面板

        /// T10: 开机自启（Bool，默认关）
        case launchAtLogin = "linger_launchAtLogin"
        /// T12: 菜单栏图标风格（ring/classic/timer，默认 ring）
        case iconStyle = "linger_iconStyle"
    }

    // MARK: - 默认值（自 Linger2.1 移植，供拖拽链路统一兜底）

    /// 下拉线最大长度百分比（25–75），默认 50
    static let defaultMaxDragLinePercent: Double = 50
    /// 最大计时时长（分钟），默认 30
    static let defaultMaxDurationMinutes: Double = 30
    /// 拖拽双轨模式，默认 both
    static let defaultDualRailMode: String = "both"
    /// 时间格式，默认 hms
    static let defaultTimeFormat: String = "hms"
    /// 拖拽预览计时字号，默认 18pt（2026-08-04 第三轮：用户嫌大，再调小）
    static let defaultDragPreviewFontSize: Double = 18
    /// 拖拽引导提示最多显示次数，默认 3
    static let maxDragHintShownCount: Int = 3
}
