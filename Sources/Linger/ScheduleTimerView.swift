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
    /// 行间距（对齐原型 mt-1.5=6 / mt-2=8，非统一 8pt 网格）
    private let row1TopGap: CGFloat = 6
    private let row2TopGap: CGFloat = 8
    /// 同行胶囊间距（原型 gap-1.5=6）
    private let capsuleGap: CGFloat = 6
    private let sidePadding: CGFloat = 14          // 原型 px-3.5（水平）
    /// 编辑区内层垂直 padding（原型 py-2.5=10，与水平 14 区分）
    private let verticalPadding: CGFloat = 10
    private let capsuleHeight: CGFloat = 28

    // MARK: - 状态

    private var startDate: Date = Date()
    private var duration: TimeInterval = 25 * 60

    // MARK: - 子 view

    private let datePicker: NSDatePicker
    private let timePicker: NSDatePicker
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

        // macOS 官方日期/时间选择器：支持任意一天任意时间（NSDatePicker）
        datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textField        // 原型胶囊纯文本视觉（无 stepper）
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.isBordered = false
        datePicker.font = LingerTheme.labelFont(size: 12)
        datePicker.textColor = LingerTheme.ink
        // 中文 locale 显示「2026年8月5日」（贴近原型「8月3日 周一」，NSDatePicker 无星期元素）
        datePicker.locale = Locale(identifier: "zh_CN")
        datePicker.dateValue = initialStartDate

        timePicker = NSDatePicker()
        timePicker.datePickerStyle = .textField        // 原型胶囊纯文本视觉（无 stepper）
        timePicker.datePickerElements = [.hourMinute]
        timePicker.isBordered = false
        timePicker.font = LingerTheme.timeFont(size: 12)
        timePicker.textColor = LingerTheme.ink
        // 强制 24h HH:mm
        timePicker.locale = Locale(identifier: "en_US_POSIX")
        timePicker.dateValue = initialStartDate

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
        confirmButton.contentTintColor = LingerTheme.nsColor(LingerTheme.Color.primaryForeground)

        // 取消：灰 x 圆，hover surface2 底
        cancelButton = NSButton()
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 12
        if let raw = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消") {
            cancelButton.image = raw.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        }
        cancelButton.contentTintColor = LingerTheme.ink3

        super.init(frame: frameRect)
        contentContainer.frame = bounds
        contentContainer.autoresizingMask = [.width, .height]
        addSubview(contentContainer)

        durationField.stringValue = "\(Int(duration / 60))"
        nameField.delegate = self

        datePicker.target = self
        datePicker.action = #selector(dateChanged(_:))
        timePicker.target = self
        timePicker.action = #selector(dateChanged(_:))

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

        // 行1：日期胶囊（左，flex-1 自适应）+ 时间胶囊（右，shrink-0 紧凑）
        // 原型：日期 min-w-0 flex-1，时间 shrink-0；HH:mm 紧凑约 56pt，日期占剩余
        let timeW: CGFloat = 78
        let dateW = innerW - timeW - capsuleGap
        let dateCap = makeCapsule(icon: "calendar", content: datePicker)
        placeCapsule(dateCap, x: sidePadding, y: topY(forRow: 0), width: dateW)
        let timeCap = makeCapsule(icon: "clock", content: timePicker)
        placeCapsule(timeCap, x: sidePadding + dateW + capsuleGap, y: topY(forRow: 0), width: timeW)

        // 行2：时长胶囊（左，窄）+ 日程名称胶囊（右，flex-1）—— 原型两胶囊都有 bg-input 底色
        let durW: CGFloat = 92
        let durationContent = NSStackView(views: [durationField, makeUnitLabel("分")])
        durationContent.orientation = .horizontal
        durationContent.spacing = 4
        durationContent.alignment = .centerY
        let durCap = makeCapsule(icon: "timer", content: durationContent)
        placeCapsule(durCap, x: sidePadding, y: topY(forRow: 1), width: durW)

        // 原型：日程名称胶囊 = pen-line 图标 + input（无 return 图标，gap-1.5=6）
        let nameCap = makeCapsule(icon: "pencil", content: nameField)
        placeCapsule(nameCap, x: sidePadding + durW + capsuleGap, y: topY(forRow: 1),
                     width: innerW - durW - capsuleGap)

        // 行3：预计结束（左）+ 取消 / 确认（右）
        let arrow = NSImageView()
        arrow.image = NSImage(systemSymbolName: "arrow.right",
                              accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
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

    /// 胶囊：input 底色 + 圆角 8 + 图标 + 内容（原型 .bg-input rounded-lg）。
    /// 内部用 frame + autoresizingMask（不依赖 autolayout，避免未布局时 icon/控件 frame=0 不可见）
    private func makeCapsule(icon: String, content: NSView) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.input).cgColor
        cap.layer?.cornerRadius = 8

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        iconView.contentTintColor = LingerTheme.ink3
        iconView.frame = NSRect(x: 8, y: (capsuleHeight - 16) / 2, width: 16, height: 16)
        cap.addSubview(iconView)

        // content 初始用占位 frame，placeCapsule 设 cap.frame 后由 layoutContent 手动修正
        content.frame = NSRect(x: 30, y: 0, width: 60, height: capsuleHeight)
        content.autoresizingMask = [.width]
        cap.addSubview(content)
        return cap
    }

    private func placeCapsule(_ cap: NSView, x: CGFloat, y: CGFloat, width: CGFloat) {
        cap.frame = NSRect(x: x, y: y, width: width, height: capsuleHeight)
        contentContainer.addSubview(cap)
        // cap.bounds.width 现在是实际值，手动修正 content frame（autoresize 在某些控件上不可靠）
        if let content = cap.subviews.dropFirst().first {
            content.frame = NSRect(x: 30, y: 0,
                                   width: max(20, cap.bounds.width - 38),
                                   height: capsuleHeight)
        }
        cap.layoutSubtreeIfNeeded()
    }

    private func topY(forRow row: Int) -> CGFloat {
        switch row {
        case 0: return verticalPadding
        case 1: return verticalPadding + rowHeight + row1TopGap
        case 2: return verticalPadding + rowHeight + row1TopGap + rowHeight + row2TopGap
        default: return verticalPadding
        }
    }

    /// 面板总高度（三行 + 上下 padding + 行间距）
    static func preferredHeight() -> CGFloat {
        // 10(top, py-2.5) + 30(row0) + 6(gap1) + 30(row1) + 8(gap2) + 30(row2) + 10(bottom, py-2.5)
        return 10 + 30 + 6 + 30 + 8 + 30 + 10
    }

    // 2026-08-05：内联进 hover 列表后不画独立背景，透明融入列表
    override func draw(_ dirtyRect: NSRect) {}

    // 内容容器始终匹配自身 bounds（高度动画期间 autoresize 可能不更新，手动同步保证内容不裁）
    override func layout() {
        super.layout()
        contentContainer.frame = bounds
    }

    // MARK: - 展开动画（原型 .schedule-expand__content translateY + opacity）

    /// 展开：内容从 translateY(10) 滑入 0（340ms delay 120ms）+ 自身淡入（300ms delay 100ms）。
    /// spec §3.1：opacity 300ms ease-out delay 100ms；translateY 340ms cubic-bezier(.2,.8,.2,1) delay 120ms。
    /// 用 view.alphaValue + asyncAfter，避免 CABasicAnimation beginTime/fillMode 失效导致整块透明。
    func revealContent() {
        wantsLayer = true
        contentContainer.wantsLayer = true
        alphaValue = 0
        contentContainer.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: 10))
        NSLog("LingerDiag reveal: subviews=%d contentSubviews=%d bounds=%@ alpha=%.2f",
              subviews.count, contentContainer.subviews.count,
              NSStringFromRect(bounds), alphaValue)

        // 淡入：opacity 0→1，300ms ease-out，delay 100ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.alphaValue = 1
            let oa = CABasicAnimation(keyPath: "opacity")
            oa.fromValue = 0
            oa.toValue = 1
            oa.duration = 0.3
            oa.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.layer?.add(oa, forKey: "revealOpacity")
        }

        // 滑入：translateY 10→0，340ms cubic-bezier(.2,.8,.2,1)，delay 120ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let ta = CABasicAnimation(keyPath: "transform.translation.y")
            ta.fromValue = 10
            ta.toValue = 0
            ta.duration = 0.34
            ta.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            self.contentContainer.layer?.add(ta, forKey: "revealY")
            self.contentContainer.layer?.setAffineTransform(.identity)
        }
    }

    /// 收回：内容下移 10 + 淡出
    func hideContent() {
        wantsLayer = true
        contentContainer.wantsLayer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            self.alphaValue = 0
            let oa = CABasicAnimation(keyPath: "opacity")
            oa.fromValue = 1
            oa.toValue = 0
            oa.duration = 0.28
            oa.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.layer?.add(oa, forKey: "hideOpacity")

            let ta = CABasicAnimation(keyPath: "transform.translation.y")
            ta.fromValue = 0
            ta.toValue = 10
            ta.duration = 0.34
            ta.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            self.contentContainer.layer?.add(ta, forKey: "hideY")
            self.contentContainer.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: 10))
        }
    }

    /// reduced-motion 用：跳过动画直接显示内容（alpha=1 + transform identity）
    func contentContainerTransformIdentity() {
        wantsLayer = true
        contentContainer.wantsLayer = true
        alphaValue = 1
        contentContainer.layer?.setAffineTransform(.identity)
    }

    // MARK: - 数据同步

    private func resolveStartDate() -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let t = cal.dateComponents([.hour, .minute], from: timePicker.dateValue)
        var c = DateComponents()
        c.year = d.year
        c.month = d.month
        c.day = d.day
        c.hour = t.hour
        c.minute = t.minute
        return cal.date(from: c) ?? Date()
    }

    private func updateEstimatedEnd() {
        let start = resolveStartDate()
        let end = start.addingTimeInterval(duration)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        estimatedEndLabel.stringValue = "预计 \(f.string(from: end))"
    }

    // MARK: - 事件

    @objc private func dateChanged(_ sender: Any) {
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
