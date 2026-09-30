import Cocoa

/// 「最大计时时长」输入框的即时生效绑定器。
///
/// 2026-09-30 用户反馈两点：
///   1. 填完数字必须按回车/点别处才生效，不直观；
///   2. 需要明确限制在 1440 分钟（一天）以内。
///
/// 原先只有 `NSTextField.action`（回车 / 失焦才触发）一条写入路径，边输边不写。
/// 现在补上 `NSTextFieldDelegate`：
///   - 合法数字**立即**写入 UserDefaults（无需回车）；
///   - 超过 1440 立即回写成 1440（"只允许填 1440 以内"）；
///   - 小于下限 5 时**先不写**（用户可能正在输入 "30" 的第一位），离开输入框时再钳到下限；
///   - 空串 / 非纯数字中间态不写入，不打断输入；
///   - 离开输入框时兜底校验一次，非法输入还原为已保存值，不留空框。
///
/// 说明：`NSTextField.formatter` 仍保留 min/max 做显示层校验（双保险），
/// 但范围真相源在本类，便于单元测试。
final class MaxDurationFieldBinder: NSObject, NSTextFieldDelegate {

    /// 业务下限（沿用 2026-08 起的规定：拖拽最短 1 分钟，设置项最短 5 分钟）
    static let minMinutes = 5
    /// 业务上限：1440 分钟 = 一天（2026-09-30 用户要求）
    static let maxMinutes = 1440

    private let defaults: UserDefaults
    private let key: String
    private weak var stepper: NSStepper?

    init(defaults: UserDefaults = .standard,
         key: String = LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue,
         stepper: NSStepper? = nil) {
        self.defaults = defaults
        self.key = key
        self.stepper = stepper
        super.init()
    }

    // MARK: - 纯函数（便于单测，不依赖 AppKit 运行环境）

    /// 把任意整数钳到 [minMinutes, maxMinutes]。
    static func clamp(_ raw: Int) -> Int {
        return min(max(raw, minMinutes), maxMinutes)
    }

    /// 解析输入文本。仅接受纯 ASCII 数字（拒绝 ""、"-"、"1.5"、"12a"、全角数字等中间态/非法态）。
    /// 返回 nil 表示"这不是一次可用的输入"，调用方应保持不动。
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(trimmed)
    }

    /// 当前已保存值（0 / 从未设置 → LingerTheme 默认 30 分钟）。
    var currentValue: Int {
        let v = defaults.integer(forKey: key)
        return v == 0 ? Int(LingerTheme.defaultMaxDurationMinutes) : v
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let raw = Self.parse(field.stringValue) else { return }

        if raw > Self.maxMinutes {
            // 超出一天：立即纠正回上限并回显，用户无法停留在非法值上
            field.stringValue = String(Self.maxMinutes)
            apply(Self.maxMinutes)
            return
        }
        if raw >= Self.minMinutes {
            // 合法区间 → 边输边落盘（"填写完数字自动生效"，不需要回车）
            apply(raw)
        }
        // raw < 下限：可能是 "30" 的中间态 "3"，先不写，等用户输完或离开输入框兜底
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let value = Self.parse(field.stringValue).map(Self.clamp) ?? Self.clamp(currentValue)
        field.stringValue = String(value)
        apply(value)
    }

    // MARK: - 写入

    private func apply(_ value: Int) {
        defaults.set(value, forKey: key)
        stepper?.integerValue = value
    }
}
