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
    /// 行间距（缩短：gap1=6 / gap2=5，更紧凑）
    private let row1TopGap: CGFloat = 6
    private let row2TopGap: CGFloat = 5
    /// 同行胶囊间距（原型 gap-1.5=6）
    private let capsuleGap: CGFloat = 6
    private let sidePadding: CGFloat = 14          // 原型 px-3.5（水平）
    /// 编辑区内层垂直 padding（缩短：8，整体更紧凑）
    private let verticalPadding: CGFloat = 8
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
    private let confirmButton: CircularIconButton
    private let cancelButton: CircularIconButton
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
        // 日期格式跟随设置（通用 → 日期格式），默认 ISO 国际标准 yyyy-MM-dd（sv_SE 提供 2026-08-01 零填充）
        let localeID = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.dateLocale.rawValue)
        let resolvedLocale = (localeID?.isEmpty ?? true) ? "sv_SE" : localeID!
        datePicker.locale = Locale(identifier: resolvedLocale)
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
        // 显式可编辑/可选中（杜绝任何 disabled 状态导致点不进去）
        durationField.isEditable = true
        durationField.isSelectable = true
        durationField.isEnabled = true

        nameField = NSTextField()
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.font = LingerTheme.labelFont(size: 12, weight: .medium)
        nameField.textColor = LingerTheme.ink
        nameField.placeholderString = "日程"
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isEnabled = true

        estimatedEndLabel = NSTextField(labelWithString: "")
        estimatedEndLabel.font = LingerTheme.timeFont(size: 11)
        estimatedEndLabel.textColor = LingerTheme.ink3
        estimatedEndLabel.alignment = .left

        // 确认：琥珀实底正圆 + check（hover 提亮）
        // 2026-08-24 用户要求：勾/叉做成正圆形按钮（此前取消是裸 × 悬浮，观感差）
        confirmButton = CircularIconButton(
            symbol: "checkmark", pointSize: 13, weight: .bold,
            bg: LingerTheme.amberGold,
            hover: LingerTheme.nsColor(LingerTheme.Color.amberLight),
            tint: LingerTheme.nsColor(LingerTheme.Color.primaryForeground),
            label: "确认")

        // 取消：surface2 实底正圆 + ink2 ×（hover 提亮为 line 色）
        cancelButton = CircularIconButton(
            symbol: "xmark", pointSize: 11, weight: .medium,
            bg: LingerTheme.nsColor(LingerTheme.Color.surface2),
            hover: LingerTheme.nsColor(LingerTheme.Color.line),
            tint: LingerTheme.ink2,
            label: "取消")

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

        // 2026-08-24：按钮改 NSView 模式（CircularIconButton），target/action → onClick
        confirmButton.onClick = { [weak self] in self?.confirmTapped(()) }
        cancelButton.onClick = { [weak self] in self?.cancelTapped(()) }

        buildLayout()
        updateEstimatedEnd()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 布局（autolayout 三行胶囊，严格对齐原型 flex 布局）

    /// 用 autolayout 重建三行：胶囊内 icon/content 由 NSStackView alignment .centerY 保证垂直居中，
    /// 胶囊之间由行 stack 的 distribution/宽度约束控制（日期 flex、时间紧凑、时长固定、名称 flex），
    /// 不再手算 frame —— 消除 icon/文字错位。
    private func buildLayout() {
        // —— 胶囊（icon + content 垂直居中）——
        let dateCap = makeCapsule(icon: "calendar", content: datePicker)
        let timeCap = makeCapsule(icon: "clock", content: timePicker)
        let durContent = NSStackView(views: [durationField, makeUnitLabel("分")])
        durContent.orientation = .horizontal
        durContent.spacing = 4
        durContent.alignment = .centerY
        let durCap = makeCapsule(icon: "timer", content: durContent)
        let nameCap = makeCapsule(icon: "pencil", content: nameField)

        // —— 行1/行2：4 个输入框等宽（fillEqually，用户要求）——
        let row1 = NSStackView(views: [dateCap, timeCap])
        row1.orientation = .horizontal
        row1.spacing = capsuleGap
        row1.alignment = .centerY
        row1.distribution = .fillEqually

        let row2 = NSStackView(views: [durCap, nameCap])
        row2.orientation = .horizontal
        row2.spacing = capsuleGap
        row2.alignment = .centerY
        row2.distribution = .fillEqually

        // —— 行3：预计结束（左）+ spacer + 取消/确认（右），全部垂直居中 ——
        let arrow = NSImageView()
        arrow.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        arrow.contentTintColor = LingerTheme.ink3
        let endStack = NSStackView(views: [arrow, estimatedEndLabel])
        endStack.orientation = .horizontal
        endStack.spacing = 4
        endStack.alignment = .centerY
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row3 = NSStackView(views: [endStack, spacer, cancelButton, confirmButton])
        row3.orientation = .horizontal
        row3.spacing = 8
        row3.alignment = .centerY
        for b in [cancelButton, confirmButton] {
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }

        // —— 三行垂直堆叠（行间距 6/8，对齐原型）——
        let rows = NSStackView(views: [row1, row2, row3])
        rows.orientation = .vertical
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.setCustomSpacing(row1TopGap, after: row1)
        rows.setCustomSpacing(row2TopGap, after: row2)
        contentContainer.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: verticalPadding),
            rows.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: sidePadding),
            rows.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -sidePadding),
            // 行撑满容器宽度（flex 胶囊因此拉伸）
            row1.widthAnchor.constraint(equalTo: rows.widthAnchor),
            row2.widthAnchor.constraint(equalTo: rows.widthAnchor),
            row3.widthAnchor.constraint(equalTo: rows.widthAnchor)
        ])
    }

    private func makeUnitLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = LingerTheme.labelFont(size: 11)
        l.textColor = LingerTheme.ink3
        return l
    }

    /// 胶囊：input 底色 + 圆角 8 + icon + content，内部用 NSStackView alignment .centerY 垂直居中。
    private func makeCapsule(icon: String, content: NSView) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.input).cgColor
        cap.layer?.cornerRadius = 8

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        iconView.contentTintColor = LingerTheme.ink3
        iconView.widthAnchor.constraint(equalToConstant: 13).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 13).isActive = true

        let stack = NSStackView(views: [iconView, content])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
            cap.heightAnchor.constraint(equalToConstant: capsuleHeight)
        ])
        return cap
    }

    /// 面板总高度（三行 + 上下 padding + 行间距）
    /// 精确匹配 autolayout：row1/2=capsuleHeight(28), row3=button(24), top/bottom=verticalPadding(8)
    static func preferredHeight() -> CGFloat {
        // 8(top) + 28(row0) + 6(gap1) + 28(row1) + 5(gap2) + 24(row2) + 8(bottom) = 107
        return 107
    }

    // 2026-08-05：内联进 hover 列表后不画独立背景，透明融入列表
    override func draw(_ dirtyRect: NSRect) {}

    // 点击编辑区任意位置（含胶囊空白）都确保窗口成为 key window + app 激活，
    // 否则 .accessory 应用在窗口非 key 时点击 NSTextField 无法成为 firstResponder。
    // 同时打印命中诊断，便于排查「点不进去」。
    override func mouseDown(with event: NSEvent) {
        // 点击编辑区任意位置（含胶囊空白）都确保窗口成为 key window + app 激活，
        // 否则 .accessory 应用在窗口非 key 时点击 NSTextField 无法成为 firstResponder。
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    // 关键：手动 timer 改 frame 时 layout() 不一定触发，导致 contentContainer.bounds
    // 跟不上 scheduleView.bounds → 子 view 在 bounds 外 → hitTest 返回 nil → 无法编辑。
    // 重写 frame didSet 强制同步 contentContainer.frame，保证子 view 始终在 bounds 内可点击。
    override var frame: NSRect {
        didSet {
            contentContainer.frame = bounds
        }
    }

    // 内容容器始终匹配自身 bounds（兜底；动画期间主要由 frame didSet 同步）
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
        // 2026-08-24 bug 修复：预约时间不能早于现在 ——
        // 选了过去时间则钳制到当前时刻并回写选择器（所见即所得，创建即开始）
        let resolved = resolveStartDate()
        let start: Date
        if resolved < Date() {
            start = Date()
            datePicker.dateValue = start
            timePicker.dateValue = start
        } else {
            start = resolved
        }
        let minutes = max(1, Int(durationField.stringValue) ?? 25)
        let dur = TimeInterval(minutes) * 60
        let title = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        updateEstimatedEnd()
        onConfirm?(start, dur, title)
    }

    @objc private func cancelTapped(_ sender: Any) {
        onCancel?()
    }
}

// MARK: - 正圆形图标按钮（行3 确认/取消）

/// 2026-08-24 用户要求：勾/叉做成正圆形按钮。
/// ⚠️ 必须用 NSView 而非 NSButton：NSButton 的 cell 有内部最小高度行为，
/// 在 NSStackView 中会无视 required 高度约束（实测 26 约束被顶成 29/31 → 椭圆；
/// 约束 active 但 frame 不符，无冲突日志）。CalendarPulseButton 的 NSView 模式
/// 在本项目已验证渲染为完美正圆，照抄该模式。
private final class CircularIconButton: NSView {
    var onClick: (() -> Void)?

    private let normalBg: NSColor
    private let hoverBg: NSColor

    init(symbol: String, pointSize: CGFloat, weight: NSFont.Weight,
         bg: NSColor, hover: NSColor, tint: NSColor, label: String) {
        normalBg = bg
        hoverBg = hover
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = bg.cgColor
        layer?.masksToBounds = true

        let iconView = PassThroughImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
        iconView.contentTintColor = tint
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        toolTip = label
        setAccessibilityLabel(label)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 约束定尺寸后再算半径，保证任意尺寸下都是正圆
    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverBg.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalBg.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // ⚠️ 2026-08-24 教训：不要覆写 hitTest 做圆形热区 —— AppKit 传入的 point 是
    // superview 坐标系（文档原文），直接与自身 bounds 比较会全数 miss（真实点击
    // 全部穿透，仅「直接调用」假阳性）。改用 PassThroughImageView 让图标穿透，
    // 按钮走 NSView 默认方形热区（与 NSButton 语义一致）。
}

/// 穿透型图标视图：图标不参与事件命中（hitTest 恒 nil），
/// 点击全归 CircularIconButton 本体。真实子视图 NSImageView 若不穿透会截获
/// mouseDown 并默认吞掉（NSButton 时代图片是 cell 私有绘制、非子视图，无此问题）。
private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
