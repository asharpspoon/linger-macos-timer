//  ScheduleTimerView.swift
//  预约计时编辑面板（内联进 hover 列表底部）—— 按 schedule-timer-expand.html 原型：
//    行1：日期胶囊（calendar 图标 + 日期）+ 时间胶囊（clock 图标 + HH:mm）
//    行2：时长胶囊（timer 图标 + 分钟）+ 名称胶囊（pen-line 图标 + 输入框）
//    行3：预计结束（arrow-right + HH:mm）+ 取消（灰圆）/ 确认（琥珀实底圆）
//  胶囊底色 LingerTheme.Color.input（rgba(255,255,255,0.08)），圆角 8；透明融入列表无独立背景。
//  铁律：颜色/字号走 LingerTheme；禁 NSPopUpButton / NSTextField 默认 bezel。

import Cocoa

final class ScheduleTimerView: NSView {

    // MARK: - 回调

    /// 确认：开始时间、时长（秒）、标题
    var onConfirm: ((_ startDate: Date, _ duration: TimeInterval, _ title: String) -> Void)?
    /// 取消
    var onCancel: (() -> Void)?

    // MARK: - 布局常量

    static let panelWidth: CGFloat = 300
    private let rowHeight: CGFloat = 30
    private let rowGap: CGFloat = 8
    private let sidePadding: CGFloat = 12
    private let capsuleHeight: CGFloat = 28

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
    /// 内容容器：展开动画时整体 translateY 滑入
    private let contentContainer = NSView()

    // MARK: - 时间格式化

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Init

    init(frame frameRect: NSRect, initialStartDate: Date = Date(), initialDuration: TimeInterval = 25 * 60) {
        self.startDate = initialStartDate
        self.duration = initialDuration

        // 透明无边框控件（胶囊底色由 makeCapsule 提供）
        datePopup = NSPopUpButton()
        datePopup.bezelStyle = .inline
        datePopup.isBordered = false
        datePopup.font = LingerTheme.labelFont(size: 12)
        datePopup.contentTintColor = LingerTheme.ink

        timeField = NSTextField()
        timeField.isBordered = false
        timeField.drawsBackground = false
        timeField.focusRingType = .none
        timeField.usesSingleLineMode = true
        timeField.font = LingerTheme.timeFont(size: 12)
        timeField.textColor = LingerTheme.ink
        timeField.alignment = .center

        durationField = NSTextField()
        durationField.isBordered = false
        durationField.drawsBackground = false
        durationField.focusRingType = .none
        durationField.usesSingleLineMode = true
        durationField.font = LingerTheme.timeFont(size: 12)
        durationField.textColor = LingerTheme.ink
        durationField.alignment = .center
        durationField.formatter = IntegerFormatter()

        nameField = NSTextField()
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.font = LingerTheme.labelFont(size: 12, weight: .medium)
        nameField.textColor = LingerTheme.ink
        nameField.placeholderString = "日程"

        estimatedEndLabel = NSTextField(labelWithString: "")
        estimatedEndLabel.font = LingerTheme.timeFont(size: 11)
        estimatedEndLabel.textColor = LingerTheme.ink3
        estimatedEndLabel.alignment = .left

        // 确认：琥珀实底圆 + 白 check
        confirmButton = NSButton()
        confirmButton.isBordered = false
        confirmButton.wantsLayer = true
        confirmButton.layer?.backgroundColor = LingerTheme.amberGold.cgColor
        confirmButton.layer?.cornerRadius = 12
        if let raw = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "确认") {
            confirmButton.image = raw.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        }
        confirmButton.contentTintColor = NSColor(calibratedWhite: 0.10, alpha: 1)

        // 取消：灰 x 圆，hover surface2 底
        cancelButton = NSButton()
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 12
        if let raw = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消") {
            cancelButton.image = raw.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        }
        cancelButton.contentTintColor = LingerTheme.ink3

        super.init(frame: frameRect)
        contentContainer.frame = bounds
        contentContainer.autoresizingMask = [.width, .height]
        addSubview(contentContainer)

        // 预设日期选项：今天 / 明天 / 后天
        datePopup.addItems(withTitles: ["今天", "明天", "后天"])
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

        layoutSubviews()
        updateEstimatedEnd()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 布局（三行胶囊）

    private func layoutSubviews() {
        let w = bounds.width
        let innerW = w - sidePadding * 2
        let halfW = (innerW - rowGap) / 2

        // 行1：日期胶囊（左）+ 时间胶囊（右）
        let dateCap = makeCapsule(icon: "calendar", content: datePopup)
        placeCapsule(dateCap, x: sidePadding, y: topY(forRow: 0), width: halfW)
        let timeCap = makeCapsule(icon: "clock", content: timeField)
        placeCapsule(timeCap, x: sidePadding + halfW + rowGap, y: topY(forRow: 0), width: halfW)

        // 行2：时长胶囊（左，窄）+ 名称胶囊（右，flex）
        let durW: CGFloat = 92
        let durationContent = NSStackView(views: [durationField, makeUnitLabel("分")])
        durationContent.orientation = .horizontal
        durationContent.spacing = 4
        durationContent.alignment = .centerY
        let durCap = makeCapsule(icon: "timer", content: durationContent)
        placeCapsule(durCap, x: sidePadding, y: topY(forRow: 1), width: durW)
        let nameCap = makeCapsule(icon: "pen.line", content: nameField)
        placeCapsule(nameCap, x: sidePadding + durW + rowGap, y: topY(forRow: 1),
                     width: innerW - durW - rowGap)

        // 行3：预计结束（左）+ 取消 / 确认（右）
        let arrow = NSImageView()
        arrow.image = NSImage(systemSymbolName: "arrow.right",
                              accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        arrow.contentTintColor = LingerTheme.ink3
        let endStack = NSStackView(views: [arrow, estimatedEndLabel])
        endStack.orientation = .horizontal
        endStack.spacing = 4
        endStack.alignment = .centerY
        endStack.frame = NSRect(x: sidePadding, y: topY(forRow: 2) + (capsuleHeight - 16) / 2,
                                width: innerW - 70, height: 16)
        cancelButton.frame = NSRect(x: w - sidePadding - 56, y: topY(forRow: 2) + (capsuleHeight - 24) / 2,
                                    width: 24, height: 24)
        confirmButton.frame = NSRect(x: w - sidePadding - 28, y: topY(forRow: 2) + (capsuleHeight - 24) / 2,
                                     width: 24, height: 24)

        contentContainer.addSubview(endStack)
        contentContainer.addSubview(cancelButton)
        contentContainer.addSubview(confirmButton)
    }

    private func makeUnitLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = LingerTheme.labelFont(size: 11)
        l.textColor = LingerTheme.ink3
        return l
    }

    /// 胶囊：input 底色 + 圆角 8 + 图标 + 内容（原型 .bg-input rounded-lg）
    private func makeCapsule(icon: String, content: NSView) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.input).cgColor
        cap.layer?.cornerRadius = 8

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        iconView.contentTintColor = LingerTheme.ink3

        let stack = NSStackView(views: [iconView, content])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cap.centerYAnchor)
        ])
        return cap
    }

    private func placeCapsule(_ cap: NSView, x: CGFloat, y: CGFloat, width: CGFloat) {
        cap.frame = NSRect(x: x, y: y, width: width, height: capsuleHeight)
        contentContainer.addSubview(cap)
    }

    private func topY(forRow row: Int) -> CGFloat {
        return sidePadding + CGFloat(row) * (rowHeight + rowGap)
    }

    /// 面板总高度（三行 + 上下 padding）
    static func preferredHeight() -> CGFloat {
        return 12 + CGFloat(3 * 30) + CGFloat(2 * 8) + 12
    }

    // 2026-08-05：内联进 hover 列表后不画独立背景，透明融入列表
    override func draw(_ dirtyRect: NSRect) {}

    // MARK: - 展开动画（原型 .schedule-expand__content translateY + opacity）

    /// 展开：内容从 translateY(10) 滑入 0（340ms delay 120ms）+ 自身 opacity 0→1（300ms delay 100ms）
    func revealContent() {
        wantsLayer = true
        contentContainer.wantsLayer = true

        // 先设起始态
        layer?.opacity = 0
        contentContainer.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: 10))

        let now = CACurrentMediaTime()
        // opacity
        let oa = CABasicAnimation(keyPath: "opacity")
        oa.fromValue = 0
        oa.toValue = 1
        oa.duration = 0.3
        oa.beginTime = now + 0.1
        oa.timingFunction = CAMediaTimingFunction(name: .easeOut)
        oa.isRemovedOnCompletion = false
        oa.fillMode = .forwards
        layer?.add(oa, forKey: "revealOpacity")

        // translateY 滑入
        let ta = CABasicAnimation(keyPath: "transform.translation.y")
        ta.fromValue = 10
        ta.toValue = 0
        ta.duration = 0.34
        ta.beginTime = now + 0.12
        ta.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        ta.isRemovedOnCompletion = false
        ta.fillMode = .forwards
        contentContainer.layer?.add(ta, forKey: "revealY")
    }

    /// 收回：内容下移 10 + 淡出（供收起动画使用）
    func hideContent() {
        let now = CACurrentMediaTime()
        let oa = CABasicAnimation(keyPath: "opacity")
        oa.fromValue = 1
        oa.toValue = 0
        oa.duration = 0.28
        oa.beginTime = now
        oa.timingFunction = CAMediaTimingFunction(name: .easeOut)
        oa.isRemovedOnCompletion = false
        oa.fillMode = .forwards
        layer?.add(oa, forKey: "hideOpacity")

        let ta = CABasicAnimation(keyPath: "transform.translation.y")
        ta.fromValue = 0
        ta.toValue = 10
        ta.duration = 0.34
        ta.beginTime = now
        ta.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        ta.isRemovedOnCompletion = false
        ta.fillMode = .forwards
        contentContainer.layer?.add(ta, forKey: "hideY")
    }

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
        estimatedEndLabel.stringValue = "预计 \(f.string(from: end))"
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
