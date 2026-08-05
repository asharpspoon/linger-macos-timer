import Cocoa

/// 内联日程设置面板（300pt 宽，3 行胶囊布局）。
///
/// - 行1: 日期胶囊（今天 / 明天 / 具体日期）+ 时间胶囊（开始时间 HH:mm）
/// - 行2: 时长胶囊（分钟）+ 名称输入框（记录日程）
/// - 行3: 预计结束文案 + 确认（✓ 琥珀金）/ 取消（✕ 灰）按钮
///
/// 由 HoverListView 的日历预约按钮触发（替换原 `os_log("not yet implemented")` 桩），
/// 确认后通过 `onConfirm` 回调把 `startDate / duration / title` 交给上层创建预约计时。
final class ScheduleTimerView: NSView {

    // MARK: - 回调

    /// 确认：开始时间、时长（秒）、标题
    var onConfirm: ((_ startDate: Date, _ duration: TimeInterval, _ title: String) -> Void)?
    /// 取消
    var onCancel: (() -> Void)?

    // MARK: - 布局常量

    static let panelWidth: CGFloat = 300
    private let rowHeight: CGFloat = 32
    private let rowGap: CGFloat = 8
    private let sidePadding: CGFloat = 12
    private let controlHeight: CGFloat = 28

    // MARK: - 状态

    private var startDate: Date = Date()
    private var duration: TimeInterval = 25 * 60

    // MARK: - 子 view

    private let datePopup: NSPopUpButton
    private let timeField: NSTextField
    private let durationField: NSTextField
    private let nameField: NSTextField
    private let estimatedEndLabel: NSTextField
    private let confirmButton: NSButton
    private let cancelButton: NSButton

    // MARK: - 时间格式化

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    // MARK: - Init

    init(frame frameRect: NSRect, initialStartDate: Date = Date(), initialDuration: TimeInterval = 25 * 60) {
        self.startDate = initialStartDate
        self.duration = initialDuration

        let controlRect = NSRect(x: 0, y: 0, width: 100, height: controlHeight)

        // 行1: 日期胶囊
        datePopup = NSPopUpButton(frame: controlRect, pullsDown: false)
        datePopup.bezelStyle = .rounded

        // 行1: 时间胶囊
        timeField = NSTextField(frame: controlRect)
        timeField.bezelStyle = .roundedBezel
        timeField.usesSingleLineMode = true
        timeField.font = LingerTheme.timeFont(size: 13)
        timeField.alignment = .center

        // 行2: 时长胶囊
        durationField = NSTextField(frame: controlRect)
        durationField.bezelStyle = .roundedBezel
        durationField.usesSingleLineMode = true
        durationField.font = LingerTheme.timeFont(size: 13)
        durationField.alignment = .center
        durationField.formatter = IntegerFormatter()

        // 行2: 名称输入框
        nameField = NSTextField(frame: controlRect)
        nameField.bezelStyle = .roundedBezel
        nameField.placeholderString = CalendarManager.shared.defaultTitle
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.usesSingleLineMode = true

        // 行3: 预计结束文案
        estimatedEndLabel = NSTextField(labelWithString: "")
        estimatedEndLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        estimatedEndLabel.textColor = .secondaryLabelColor
        estimatedEndLabel.alignment = .left

        // 行3: 确认 / 取消
        confirmButton = NSButton(frame: controlRect)
        confirmButton.bezelStyle = .inline
        confirmButton.isBordered = false
        if let raw = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "确认") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            confirmButton.image = raw.withSymbolConfiguration(cfg)
        }
        confirmButton.contentTintColor = LingerTheme.amberGold

        cancelButton = NSButton(frame: controlRect)
        cancelButton.bezelStyle = .inline
        cancelButton.isBordered = false
        if let raw = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            cancelButton.image = raw.withSymbolConfiguration(cfg)
        }
        cancelButton.contentTintColor = NSColor.tertiaryLabelColor

        super.init(frame: frameRect)

        // 预设日期选项：今天 / 明天 / +2 / +3 天
        let titles: [(String, Date)] = [
            ("今天", Date()),
            ("明天", Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()),
            ("后天", Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date())
        ]
        for (label, _) in titles {
            datePopup.addItem(withTitle: label)
        }
        datePopup.target = self
        datePopup.action = #selector(datePopupChanged(_:))

        timeField.stringValue = timeFormatter.string(from: startDate)
        timeField.delegate = self
        durationField.stringValue = "\(Int(duration / 60))"
        nameField.delegate = self

        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped(_:))

        // 布局
        layoutSubviews()
        updateEstimatedEnd()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 布局

    private func layoutSubviews() {
        let w = bounds.width
        let innerW = w - sidePadding * 2
        let halfW = (innerW - rowGap) / 2

        // 行1: 日期（左半） + 时间（右半）
        datePopup.frame = NSRect(x: sidePadding, y: topY(forRow: 0), width: halfW, height: controlHeight)
        timeField.frame = NSRect(x: sidePadding + halfW + rowGap, y: topY(forRow: 0), width: halfW, height: controlHeight)

        // 行2: 时长（左半） + 名称（右半）
        durationField.frame = NSRect(x: sidePadding, y: topY(forRow: 1), width: halfW, height: controlHeight)
        nameField.frame = NSRect(x: sidePadding + halfW + rowGap, y: topY(forRow: 1), width: halfW, height: controlHeight)

        // 行3: 预计结束（左） + 取消 / 确认（右）
        estimatedEndLabel.frame = NSRect(x: sidePadding, y: topY(forRow: 2), width: innerW - 70, height: controlHeight)
        cancelButton.frame = NSRect(x: w - sidePadding - 56, y: topY(forRow: 2), width: 24, height: controlHeight)
        confirmButton.frame = NSRect(x: w - sidePadding - 28, y: topY(forRow: 2), width: 24, height: controlHeight)

        if datePopup.superview == nil { addSubview(datePopup) }
        if timeField.superview == nil { addSubview(timeField) }
        if durationField.superview == nil { addSubview(durationField) }
        if nameField.superview == nil { addSubview(nameField) }
        if estimatedEndLabel.superview == nil { addSubview(estimatedEndLabel) }
        if cancelButton.superview == nil { addSubview(cancelButton) }
        if confirmButton.superview == nil { addSubview(confirmButton) }
    }

    private func topY(forRow row: Int) -> CGFloat {
        // 从顶部向下排列三行
        return sidePadding + CGFloat(row) * (rowHeight + rowGap)
    }

    /// 面板总高度
    static func preferredHeight() -> CGFloat {
        let h: CGFloat = 12 + CGFloat(3 * 32) + CGFloat(2 * 8) + 12
        return h
    }

    // 2026-08-05：内联进 hover 列表后不再画独立玻璃胶囊背景，透明融入列表（用户要求）
    override func draw(_ dirtyRect: NSRect) {}

    // MARK: - 数据同步

    private func resolveStartDate() -> Date {
        let base: Date
        switch datePopup.indexOfSelectedItem {
        case 1:
            base = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        case 2:
            base = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        default:
            base = Date()
        }
        // 用时间胶囊的 HH:mm 覆盖 base 的时分
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: base)
        if let t = timeFormatter.date(from: timeField.stringValue) {
            let tc = cal.dateComponents([.hour, .minute], from: t)
            components.hour = tc.hour
            components.minute = tc.minute
        }
        return cal.date(from: components) ?? base
    }

    private func updateEstimatedEnd() {
        let start = resolveStartDate()
        let end = start.addingTimeInterval(duration)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        estimatedEndLabel.stringValue = "预计 \(f.string(from: end)) 结束"
    }

    // MARK: - 事件

    @objc private func datePopupChanged(_ sender: Any) {
        updateEstimatedEnd()
    }

    @objc private func confirmTapped(_ sender: Any) {
        let start = resolveStartDate()
        let minutes = max(1, Int(durationField.stringValue) ?? 25)
        let dur = TimeInterval(minutes) * 60
        let title = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        onConfirm?(start, dur, title)
    }

    @objc private func cancelTapped(_ sender: Any) {
        onCancel?()
    }
}

// MARK: - 辅助：非负整数格式化（时长输入框）

private final class IntegerFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        guard let num = obj as? NSNumber else { return nil }
        return "\(num.intValue)"
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if let v = Int(trimmed) {
            obj?.pointee = NSNumber(value: v)
            return true
        }
        error?.pointee = NSString(string: "请输入整数分钟")
        return false
    }
}

// MARK: - NSTextFieldDelegate（时间/名称编辑后刷新预计结束）

extension ScheduleTimerView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === durationField {
            if let v = Int(durationField.stringValue), v > 0 {
                duration = TimeInterval(v) * 60
            }
        }
        updateEstimatedEnd()
    }
}

// MARK: - 承载 ScheduleTimerView 的无边框窗口

/// 无边框窗口默认无法成为 key window，导致 ScheduleTimerView 内的文本框收不到键盘输入。
/// 此处覆写 `canBecomeKey` 使其可成为 key，从而正常编辑时间 / 时长 / 名称。
