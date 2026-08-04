import Cocoa
import QuartzCore
import os.log
import ServiceManagement

/// Linger 设置窗口（T7–T10）。
///
/// 外壳：520pt 宽；顶部图标 Tab 栏（操作 / 通知 / 日历 / 通用）居中、激活态琥珀金高亮；
/// 38pt 标题栏（仅关闭按钮可用，最小化/缩放隐藏）；跨 Tab 切换时高度自适应 resize 0.4s
/// cubic-bezier；毛玻璃 NSVisualEffectView 背景。
///
/// 面板：操作 / 通知 / 日历 / 通用 共 4 个。
///
/// ⚠️ PRD §6.3 P2 防护：标签/面板容器数组**必须恰好 4 个元素**，所有索引访问前做边界 guard，
/// 绝不越界。本类用显式 4 元素数组 + `guard index < count` 严守。
final class SettingsWindow: NSWindow {

    // MARK: - 4 元素容器（PRD §6.3 P2 越界防护）

    /// 标签页标题（恰好 4 个：操作 / 通知 / 日历 / 通用）
    private let tabTitles = ["操作", "通知", "日历", "通用"]
    /// 标签页 SF Symbol（与 tabTitles 一一对应，恰好 4 个）
    private let tabIcons = ["slider.horizontal.3", "bell", "calendar", "gearshape"]
    /// 已构建面板缓存（恰好 4 个槽位，惰性构建）
    private var builtPanels: [NSView?] = [nil, nil, nil, nil]

    // MARK: - 布局常量

    private static let windowWidth: CGFloat = 520
    private let tabBarHeight: CGFloat = 52
    private let contentHPadding: CGFloat = 24
    private let contentVSpacing: CGFloat = 16
    private static let defaultWindowHeight: CGFloat = 520

    // MARK: - 视图引用

    private var tabButtons: [NSButton] = []
    private var panelContainer: NSView!

    // 通知面板实时引用
    private var dragLineSlider: NSSlider?
    private var dragLineValueLabel: NSTextField?
    private var previewFontSizeSlider: NSSlider?
    private var previewFontSizeValueLabel: NSTextField?
    private var soundPopup: NSPopUpButton?
    private var defaultTitleField: NSTextField?
    private var notifAuthLabel: NSTextField?
    private var calAuthLabel: NSTextField?
    private var notifAuthDot: NSView?
    private var calAuthDot: NSView?
    private var maxDurationStepper: NSStepper?
    private var iconPopup: NSPopUpButton?
    private var iconStyleButtons: [NSButton] = []

    private var currentIndex: Int = 0
    private let log = OSLog(subsystem: "com.linger.settings", category: "SettingsWindow")

    // MARK: - 初始化

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        configureWindow()
        buildUI()
    }

    convenience init() {
        // 仅 .titled + .closable：标题栏只显示关闭按钮，最小化/缩放按钮不出现
        let rect = NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.defaultWindowHeight)
        self.init(contentRect: rect, styleMask: [.titled, .closable],
                  backing: .buffered, defer: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 窗口配置

    private func configureWindow() {
        // 2026-08-04 重构：回归标准 macOS 设置窗口。
        // 之前 titlebarAppearsTransparent + 自定义 38pt 标题栏导致系统标题栏按钮不渲染、
        // 窗口不像正常窗口（用户反馈）。改用系统标题栏（关闭按钮原生显示）+ 内容自适应高度。
        title = "Linger 设置"
        titlebarAppearsTransparent = false
        titleVisibility = .visible
        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = .windowBackgroundColor
        isOpaque = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        center()
    }

    // MARK: - UI 构建

    private func buildUI() {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .withinWindow
        root.state = .active
        contentView = root

        // Tab 栏（图标 + 文字，居中，激活态琥珀金高亮）—— 系统标题栏之下
        let tabBar = NSView()
        root.addSubview(tabBar)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: tabBarHeight)
        ])

        let tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 6
        tabStack.alignment = .centerY
        tabBar.addSubview(tabStack)
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabStack.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            tabStack.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor)
        ])

        // PRD §6.3 P2：仅遍历恰好 4 个标签
        for index in 0..<tabTitles.count {
            let btn = makeTabButton(title: tabTitles[index], icon: tabIcons[index], tag: index)
            tabButtons.append(btn)
            tabStack.addArrangedSubview(btn)
        }

        addHairline(to: tabBar, atBottom: true)

        // 面板容器
        panelContainer = NSView()
        root.addSubview(panelContainer)
        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            panelContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            panelContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            panelContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panelContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // 默认进入「操作」面板（索引 0）
        selectTab(0, animated: false)
    }


    private func addHairline(to parent: NSView, atBottom: Bool) {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        parent.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            atBottom ? line.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
                     : line.topAnchor.constraint(equalTo: parent.topAnchor)
        ])
    }

    private func makeTabButton(title: String, icon: String, tag: Int) -> NSButton {
        let btn = NSButton()
        btn.tag = tag
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            btn.image = img
            btn.image?.isTemplate = true
        }
        btn.title = title
        btn.imagePosition = .imageAbove
        btn.isBordered = false
        btn.setButtonType(.momentaryLight)
        btn.target = self
        btn.action = #selector(tabClicked(_:))
        btn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.contentTintColor = .tertiaryLabelColor
        return btn
    }

    // MARK: - Tab 切换

    @objc private func tabClicked(_ sender: NSButton) {
        selectTab(sender.tag, animated: true)
    }

    /// 切换面板。`index` 越界时直接返回（PRD §6.3 P2 边界 guard）。
    private func selectTab(_ index: Int, animated: Bool) {
        guard index >= 0, index < tabTitles.count else {
            os_log("selectTab ignored: index %d out of bounds (count=%d)",
                   log: log, type: .error, index, tabTitles.count)
            return
        }
        currentIndex = index
        updateTabStyles()

        // 替换容器内的面板视图
        panelContainer.subviews.forEach { $0.removeFromSuperview() }
        let panel = panelView(at: index)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: contentVSpacing),
            panel.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: contentHPadding),
            panel.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -contentHPadding),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: panelContainer.bottomAnchor, constant: -contentVSpacing)
        ])

        panelContainer.layoutSubtreeIfNeeded()
        // 内容自适应高度：tab 栏 + 面板内容（fittingSize 比 frame.height 可靠，
        // 避免窗口高度异常占满屏幕）
        let panelHeight = max(panelContainer.fittingSize.height, 100)
        let totalContentHeight = tabBarHeight + panelHeight
        let oldMaxY = frame.maxY

        if animated {
            let newFrame = NSRect(x: frame.minX,
                                  y: oldMaxY - totalContentHeight,
                                  width: Self.windowWidth,
                                  height: totalContentHeight)
            animateToFrame(newFrame)
        } else {
            setContentSize(NSSize(width: Self.windowWidth, height: totalContentHeight))
            // 顶部固定，只向下/上调整高度
            setFrameOrigin(NSPoint(x: frame.minX, y: oldMaxY - frame.height))
        }

        refreshPermissionStatuses()
    }

    private func animateToFrame(_ frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            // PRD §3.6.1：resize 0.4s cubic-bezier(.32,.72,0,1)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(frame, display: true)
        }
    }

    private func updateTabStyles() {
        for btn in tabButtons {
            let active = btn.tag == currentIndex
            if active {
                btn.contentTintColor = LingerTheme.amberGold
                btn.layer?.backgroundColor = NSColor(calibratedRed: 0.961,
                                                     green: 0.651, blue: 0.137,
                                                     alpha: 0.14).cgColor
            } else {
                btn.contentTintColor = .tertiaryLabelColor
                btn.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    /// 惰性构建并返回面板视图。`index` 越界时返回空视图（边界 guard）。
    private func panelView(at index: Int) -> NSView {
        guard index >= 0, index < builtPanels.count else { return NSView() }
        if let existing = builtPanels[index] { return existing }
        let view: NSView
        switch index {
        case 0: view = buildOperationsPanel()
        case 1: view = buildNotificationsPanel()
        case 2: view = buildCalendarPanel()
        case 3: view = buildGeneralPanel()
        default: view = NSView()
        }
        builtPanels[index] = view
        return view
    }

    // MARK: - 通用控件助手

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13)
        f.textColor = .labelColor
        f.alignment = .left
        return f
    }

    private func makeHint(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 11)
        f.textColor = .tertiaryLabelColor
        return f
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func spacerView() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    /// 行：左侧标题，右侧控件（中间弹性 spacer 把控件推到右侧）
    private func rowWithTitle(_ title: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let label = makeLabel(title)
        row.addArrangedSubview(label)
        row.addArrangedSubview(spacerView())
        row.addArrangedSubview(control)
        return row
    }

    private func makeSwitch(initial: Bool, action: Selector) -> NSButton {
        let b = NSButton()
        b.setButtonType(.switch)
        b.state = initial ? .on : .off
        b.target = self
        b.action = action
        b.title = ""
        return b
    }

    private func integerFormatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = NSNumber(value: min)
        f.maximum = NSNumber(value: max)
        f.allowsFloats = false
        f.minimumIntegerDigits = 1
        return f
    }

    /// 设置卡片容器：圆角 10 + surface 底 + 1px 边框 + p-4 内边距，行间 14。
    private func makeCard(rows: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        card.layer?.borderWidth = 1
        var prev: NSLayoutYAxisAnchor = card.topAnchor
        for (i, row) in rows.enumerated() {
            card.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16).isActive = true
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16).isActive = true
            row.topAnchor.constraint(equalTo: prev, constant: (i == 0 ? 16 : 14)).isActive = true
            prev = row.bottomAnchor
            if i == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16).isActive = true
            }
        }
        return card
    }

    /// 多个卡片竖直堆叠（首卡在 topAnchor 下，末卡贴 panel 底）
    private func layoutCards(_ cards: [NSView], in panel: NSView, below topAnchor: NSLayoutYAxisAnchor, gap: CGFloat) {
        var prev: NSLayoutYAxisAnchor = topAnchor
        for (i, card) in cards.enumerated() {
            panel.addSubview(card)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
            card.topAnchor.constraint(equalTo: prev, constant: gap).isActive = true
            prev = card.bottomAnchor
            if i == cards.count - 1 {
                card.bottomAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true
            }
        }
    }

    /// kbd 键帽（快捷预设标题）：10px 等宽 + surface2 底 + 圆角 5 + 边框
    private func makeKbd(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface2).cgColor
        box.layer?.cornerRadius = 5
        box.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        box.layer?.borderWidth = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 28),
            box.heightAnchor.constraint(equalToConstant: 18)
        ])
        return box
    }

    /// 授权状态绿点（6×6 圆）
    private func makeStatusDot() -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        dot.layer?.backgroundColor = LingerTheme.stateSuccess.cgColor
        return dot
    }

    /// 授权状态视图：绿点 + 文字
    private func makeAuthStatusView(label: NSTextField, dot: NSView) -> NSStackView {
        let stack = NSStackView(views: [dot, label])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        return stack
    }

    /// 通用页：图标三风格选择器（Ring / Classic / SF Symbol，选中琥珀边框）
    private func buildIconStylePicker() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 8
        container.alignment = .centerY
        let styles = [("ring", "Ring"), ("classic", "Classic"), ("timer", "SF Symbol")]
        for (i, st) in styles.enumerated() {
            let btn = NSButton(title: st.1, target: self, action: #selector(iconStylePicked(_:)))
            btn.setButtonType(NSButton.ButtonType.toggle)
            btn.tag = i
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.borderWidth = 1
            iconStyleButtons.append(btn)
            container.addArrangedSubview(btn)
        }
        updateIconStyleButtonStates()
        return container
    }

    private func updateIconStyleButtonStates() {
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue) ?? "ring"
        let raws = ["ring", "classic", "timer"]
        guard let idx = raws.firstIndex(of: current) else { return }
        for (i, btn) in iconStyleButtons.enumerated() {
            let on = (i == idx)
            btn.state = on ? .on : .off
            btn.layer?.borderColor = on ? LingerTheme.amberGold.cgColor : LingerTheme.nsColor(LingerTheme.Color.line).cgColor
            btn.contentTintColor = on ? LingerTheme.amberGold : .secondaryLabelColor
        }
    }

    /// 把若干行竖直排布进 panel（首行在 title 之下，末行贴 panel 底）
    private func layoutRows(_ rows: [NSView], in panel: NSView, below title: NSView, gap: CGFloat) {
        var previousBottom: NSLayoutAnchor<NSLayoutYAxisAnchor> = title.bottomAnchor
        for (i, row) in rows.enumerated() {
            panel.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
            row.topAnchor.constraint(equalTo: previousBottom, constant: gap).isActive = true
            previousBottom = row.bottomAnchor
            if i == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true
            }
        }
    }

    // MARK: - 面板 0：操作

    private func buildOperationsPanel() -> NSView {
        let panel = NSView()
        let title = makeSectionTitle("操作设置")
        panel.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.topAnchor.constraint(equalTo: panel.topAnchor).isActive = true
        title.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true

        layoutRows([
            buildDragLineRow(),
            buildMaxDurationRow(),
            buildDualRailRow(),
            buildTimeFormatRow(),
            buildPreviewFontSizeRow()
        ], in: panel, below: title, gap: 14)
        return panel
    }

    private func buildDragLineRow() -> NSView {
        let slider = NSSlider(value: Double(currentDragLinePercent()), minValue: 25, maxValue: 75,
                              target: self, action: #selector(dragLineChanged(_:)))
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let valueLabel = NSTextField(labelWithString: "\(currentDragLinePercent())%")
        valueLabel.alignment = .right
        valueLabel.font = LingerTheme.timeFont(size: 12)
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let group = NSStackView(views: [slider, valueLabel])
        group.orientation = .horizontal
        group.spacing = 8
        group.alignment = .centerY
        dragLineSlider = slider
        dragLineValueLabel = valueLabel
        return rowWithTitle("下拉线最大长度", control: group)
    }

    private func buildMaxDurationRow() -> NSView {
        let field = NSTextField()
        field.formatter = integerFormatter(min: 5, max: 1440)
        field.integerValue = currentMaxDurationMinutes()
        field.target = self
        field.action = #selector(maxDurationChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 52).isActive = true
        // 带上下箭头的数字框（对齐 settings-operations 原型）
        let stepper = NSStepper()
        stepper.minValue = 5
        stepper.maxValue = 1440
        stepper.increment = 1
        stepper.integerValue = currentMaxDurationMinutes()
        stepper.target = self
        stepper.action = #selector(maxDurationStepperChanged(_:))
        maxDurationStepper = stepper
        let unit = makeLabel("分钟")
        unit.textColor = .secondaryLabelColor
        let group = NSStackView(views: [field, stepper, unit])
        group.orientation = .horizontal
        group.spacing = 6
        group.alignment = .centerY
        return rowWithTitle("最大计时时长", control: group)
    }

    private func buildDualRailRow() -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["倒计时 + 结束时间", "仅倒计时", "仅结束时间"])
        let raws = ["both", "countdown", "endTime"]
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue) ?? "both"
        if let idx = raws.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(dualRailChanged(_:))
        return rowWithTitle("双轨显示", control: popup)
    }

    private func buildTimeFormatRow() -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["HH:MM:SS", "HH:MM", "MM:SS"])
        let raws = ["hms", "hm", "ms"]
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue) ?? "hms"
        if let idx = raws.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(timeFormatChanged(_:))
        return rowWithTitle("时间格式", control: popup)
    }

    private func buildPreviewFontSizeRow() -> NSView {
        let slider = NSSlider(value: currentPreviewFontSize(), minValue: 12, maxValue: 24,
                              target: self, action: #selector(previewFontSizeChanged(_:)))
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let valueLabel = NSTextField(labelWithString: "\(Int(currentPreviewFontSize()))pt")
        valueLabel.alignment = .right
        valueLabel.font = LingerTheme.timeFont(size: 12)
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let group = NSStackView(views: [slider, valueLabel])
        group.orientation = .horizontal
        group.spacing = 8
        group.alignment = .centerY
        previewFontSizeSlider = slider
        previewFontSizeValueLabel = valueLabel
        return rowWithTitle("计时字号", control: group)
    }

    private func currentPreviewFontSize() -> Double {
        let v = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.dragPreviewFontSize.rawValue)
        return v > 0 ? v : LingerTheme.defaultDragPreviewFontSize
    }

    @objc private func previewFontSizeChanged(_ sender: NSSlider) {
        let v = Double(sender.integerValue)
        UserDefaults.standard.set(v, forKey: LingerTheme.UserDefaultsKey.dragPreviewFontSize.rawValue)
        previewFontSizeValueLabel?.stringValue = "\(Int(v))pt"
    }

    // MARK: - 面板 1：通知

    private func buildNotificationsPanel() -> NSView {
        let panel = NSView()
        let title = makeSectionTitle("通知")
        panel.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.topAnchor.constraint(equalTo: panel.topAnchor).isActive = true
        title.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true

        // 授权状态行（绿点 + 状态 + 管理…）
        let authStatus = NSTextField(labelWithString: "检查中…")
        authStatus.font = NSFont.systemFont(ofSize: 12)
        authStatus.textColor = .secondaryLabelColor
        notifAuthLabel = authStatus
        let authDot = makeStatusDot()
        notifAuthDot = authDot
        let authBtn = NSButton(title: "管理…", target: self, action: #selector(openNotifSettings(_:)))
        authBtn.bezelStyle = .rounded
        authBtn.controlSize = .small
        let authRow = NSStackView(views: [makeLabel("通知授权"), spacerView(),
                                          makeAuthStatusView(label: authStatus, dot: authDot), authBtn])
        authRow.orientation = .horizontal
        authRow.spacing = 8
        authRow.alignment = .centerY

        let notifyRow = rowWithTitle("计时完成时通知",
                                     control: makeSwitch(initial: currentNotifyOnComplete(),
                                                        action: #selector(notifyChanged(_:))))

        // 播放提示音：select + switch
        let playSwitch = makeSwitch(initial: currentPlaySound(), action: #selector(playSoundChanged(_:)))
        let soundPopup = NSPopUpButton()
        let sounds = ["Ping", "Basso", "Blow", "Bottle", "Frog", "Funk",
                      "Glass", "Heroine", "Morse", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
        soundPopup.addItems(withTitles: sounds)
        let curSound = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.soundName.rawValue) ?? "Glass"
        soundPopup.selectItem(withTitle: curSound)
        soundPopup.target = self
        soundPopup.action = #selector(soundNameChanged(_:))
        soundPopup.isEnabled = currentPlaySound()
        self.soundPopup = soundPopup
        let soundControl = NSStackView(views: [soundPopup, playSwitch])
        soundControl.orientation = .horizontal
        soundControl.spacing = 8
        soundControl.alignment = .centerY
        let soundRow = rowWithTitle("播放提示音", control: soundControl)

        let card = makeCard(rows: [authRow, notifyRow, soundRow])
        layoutCards([card], in: panel, below: title.bottomAnchor, gap: 14)
        return panel
    }

    // MARK: - 面板 2：日历

    private func buildCalendarPanel() -> NSView {
        let panel = NSView()
        let title = makeSectionTitle("日历")
        panel.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.topAnchor.constraint(equalTo: panel.topAnchor).isActive = true
        title.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true

        // 授权状态行（绿点 + 状态 + 管理…，平铺在卡片外）
        let authStatus = NSTextField(labelWithString: "检查中…")
        authStatus.font = NSFont.systemFont(ofSize: 12)
        authStatus.textColor = .secondaryLabelColor
        calAuthLabel = authStatus
        let authDot = makeStatusDot()
        calAuthDot = authDot
        let authBtn = NSButton(title: "管理…", target: self, action: #selector(openCalSettings(_:)))
        authBtn.bezelStyle = .rounded
        authBtn.controlSize = .small
        let authRow = NSStackView(views: [makeLabel("日历授权"), spacerView(),
                                          makeAuthStatusView(label: authStatus, dot: authDot), authBtn])
        authRow.orientation = .horizontal
        authRow.spacing = 8
        authRow.alignment = .centerY
        panel.addSubview(authRow)
        authRow.translatesAutoresizingMaskIntoConstraints = false
        authRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
        authRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
        authRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14).isActive = true

        // 卡片1：目标日历 / 写入方式 / 默认标题 + 注释
        let defaultTitleRow = buildDefaultTitleRow()
        let hint1 = makeHint("默认标题仅在「自动」模式下使用")
        let card1 = makeCard(rows: [buildTargetCalendarRow(), buildWriteModeRow(), defaultTitleRow, hint1])

        // 卡片2：快捷预设标题（fn/ctrl/opt，带 kbd 键帽）
        let card2 = makeCard(rows: [makeSectionTitle("快捷预设标题"),
                                    buildPresetCardRow(key: .fnTitle, kbd: "fn"),
                                    buildPresetCardRow(key: .ctrlTitle, kbd: "⌃"),
                                    buildPresetCardRow(key: .optTitle, kbd: "⌥")])

        layoutCards([card1, card2], in: panel, below: authRow.bottomAnchor, gap: 14)
        return panel
    }

    private func buildTargetCalendarRow() -> NSView {
        let calendars = CalendarManager.shared.availableCalendars()
        let titles = calendars.map { $0.title }
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles.isEmpty ? ["Linger"] : titles)
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.targetCalendar.rawValue) ?? "Linger"
        if let idx = titles.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(targetCalendarChanged(_:))
        return rowWithTitle("目标日历", control: popup)
    }

    private func buildWriteModeRow() -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["每次询问", "自动", "手动"])
        let modes: [CalendarManager.WriteMode] = [.ask, .auto, .manual]
        let current = CalendarManager.shared.writeMode
        if let idx = modes.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(writeModeChanged(_:))
        return rowWithTitle("写入方式", control: popup)
    }

    private func buildDefaultTitleRow() -> NSView {
        let field = NSTextField()
        field.placeholderString = "默认活动标题"
        field.stringValue = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.defaultTitle.rawValue) ?? ""
        field.target = self
        field.action = #selector(defaultTitleChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        // 仅「自动」模式可用
        field.isEnabled = CalendarManager.shared.writeMode == .auto
        defaultTitleField = field
        return rowWithTitle("默认标题", control: field)
    }

    private func buildPresetCardRow(key: LingerTheme.UserDefaultsKey, kbd: String) -> NSView {
        let field = NSTextField()
        field.placeholderString = "（留空不激活）"
        field.stringValue = UserDefaults.standard.string(forKey: key.rawValue) ?? ""
        field.target = self
        field.action = #selector(presetChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        field.identifier = NSUserInterfaceItemIdentifier(rawValue: key.rawValue)
        let left = NSStackView(views: [makeKbd(kbd), field])
        left.orientation = .horizontal
        left.spacing = 8
        left.alignment = .centerY
        let row = NSStackView(views: [left, spacerView(), makeHint("留空则不激活")])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    // MARK: - 面板 3：通用

    private func buildGeneralPanel() -> NSView {
        let panel = NSView()
        let title = makeSectionTitle("通用")
        panel.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.topAnchor.constraint(equalTo: panel.topAnchor).isActive = true
        title.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true

        let launchSwitch = makeSwitch(initial: currentLaunchAtLogin(), action: #selector(launchChanged(_:)))
        let launchRow = rowWithTitle("开机自启", control: launchSwitch)

        let cleanupPopup = NSPopUpButton()
        cleanupPopup.addItems(withTitles: ["每周", "每月", "从不"])
        let cleanupRaws = ["weekly", "monthly", "never"]
        let cleanup = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.cleanupInterval.rawValue) ?? "weekly"
        if let idx = cleanupRaws.firstIndex(of: cleanup) { cleanupPopup.selectItem(at: idx) }
        cleanupPopup.target = self
        cleanupPopup.action = #selector(cleanupChanged(_:))
        let cleanupRow = rowWithTitle("自动清理", control: cleanupPopup)

        let iconPopup = NSPopUpButton()
        iconPopup.addItems(withTitles: ["Ring", "Classic", "timer"])
        let iconRaws = ["ring", "classic", "timer"]
        let icon = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue) ?? "ring"
        if let idx = iconRaws.firstIndex(of: icon) { iconPopup.selectItem(at: idx) }
        iconPopup.target = self
        iconPopup.action = #selector(iconStyleChanged(_:))
        self.iconPopup = iconPopup
        let iconRow = rowWithTitle("菜单栏图标", control: iconPopup)

        // 图标三风格选择器（Ring / Classic / SF Symbol，选中琥珀边框）
        let pickerRow = buildIconStylePicker()

        layoutRows([launchRow, cleanupRow, iconRow, pickerRow], in: panel, below: title, gap: 14)
        return panel
    }

    // MARK: - 动作：操作面板

    @objc private func dragLineChanged(_ sender: NSSlider) {
        let v = Int(sender.doubleValue)
        UserDefaults.standard.set(v, forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        dragLineValueLabel?.stringValue = "\(v)%"
    }

    @objc private func maxDurationChanged(_ sender: NSTextField) {
        var v = sender.integerValue
        v = max(5, min(1440, v))
        sender.integerValue = v
        maxDurationStepper?.integerValue = v
        UserDefaults.standard.set(v, forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
    }

    @objc private func maxDurationStepperChanged(_ sender: NSStepper) {
        let v = Int(sender.integerValue)
        UserDefaults.standard.set(v, forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
    }

    @objc private func dualRailChanged(_ sender: NSPopUpButton) {
        let raws = ["both", "countdown", "endTime"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(raws[sender.indexOfSelectedItem],
                                  forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue)
    }

    @objc private func timeFormatChanged(_ sender: NSPopUpButton) {
        let raws = ["hms", "hm", "ms"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(raws[sender.indexOfSelectedItem],
                                  forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue)
    }

    // MARK: - 动作：通知面板

    @objc private func notifyChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on,
                                  forKey: LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue)
    }

    @objc private func playSoundChanged(_ sender: NSButton) {
        let on = sender.state == .on
        UserDefaults.standard.set(on, forKey: LingerTheme.UserDefaultsKey.playSound.rawValue)
        soundPopup?.isEnabled = on
    }

    @objc private func soundNameChanged(_ sender: NSPopUpButton) {
        let name = sender.titleOfSelectedItem ?? "Glass"
        UserDefaults.standard.set(name, forKey: LingerTheme.UserDefaultsKey.soundName.rawValue)
    }

    // MARK: - 动作：日历面板

    @objc private func targetCalendarChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? "Linger"
        UserDefaults.standard.set(title, forKey: LingerTheme.UserDefaultsKey.targetCalendar.rawValue)
    }

    @objc private func writeModeChanged(_ sender: NSPopUpButton) {
        let modes: [CalendarManager.WriteMode] = [.ask, .auto, .manual]
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        let mode = modes[sender.indexOfSelectedItem]
        CalendarManager.shared.setWriteMode(mode)
        // 仅「自动」模式允许编辑默认标题
        defaultTitleField?.isEnabled = (mode == .auto)
    }

    @objc private func defaultTitleChanged(_ sender: NSTextField) {
        UserDefaults.standard.set(sender.stringValue,
                                  forKey: LingerTheme.UserDefaultsKey.defaultTitle.rawValue)
    }

    @objc private func presetChanged(_ sender: NSTextField) {
        guard let raw = sender.identifier?.rawValue,
              let key = LingerTheme.UserDefaultsKey(rawValue: raw) else { return }
        UserDefaults.standard.set(sender.stringValue, forKey: key.rawValue)
    }

    // MARK: - 动作：通用面板

    @objc private func iconStylePicked(_ sender: NSButton) {
        let raws = ["ring", "classic", "timer"]
        guard raws.indices.contains(sender.tag) else { return }
        UserDefaults.standard.set(raws[sender.tag], forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue)
        NotificationCenter.default.post(name: Notification.Name("linger.iconStyleChanged"), object: nil)
        updateIconStyleButtonStates()
        if let popup = iconPopup, popup.indexOfSelectedItem != sender.tag {
            popup.selectItem(at: sender.tag)
        }
    }

    @objc private func launchChanged(_ sender: NSButton) {
        let on = sender.state == .on
        UserDefaults.standard.set(on, forKey: LingerTheme.UserDefaultsKey.launchAtLogin.rawValue)
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                os_log("launchAtLogin toggle failed: %{public}@", log: log, type: .error,
                       error.localizedDescription)
            }
        }
    }

    @objc private func cleanupChanged(_ sender: NSPopUpButton) {
        let raws = ["weekly", "monthly", "never"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(raws[sender.indexOfSelectedItem],
                                  forKey: LingerTheme.UserDefaultsKey.cleanupInterval.rawValue)
    }

    @objc private func iconStyleChanged(_ sender: NSPopUpButton) {
        let raws = ["ring", "classic", "timer"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(raws[sender.indexOfSelectedItem],
                                  forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue)
        // 通知 MenuBarManager 立即刷新菜单栏图标（复用其 linger.iconStyleChanged 观察）
        NotificationCenter.default.post(name: Notification.Name("linger.iconStyleChanged"), object: nil)
        updateIconStyleButtonStates()
    }

    // MARK: - 跳转系统设置

    @objc private func openCalSettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openNotifSettings(_ sender: Any?) {
        NotificationManager.shared.openSystemSettings()
    }

    // MARK: - 授权状态刷新

    func refreshPermissionStatuses() {
        // 日历（同步）
        if let cal = calAuthLabel {
            let ok = CalendarManager.shared.isAuthorized
            cal.stringValue = ok ? "已授权" : "未授权"
            cal.textColor = ok ? LingerTheme.stateSuccess : .secondaryLabelColor
            calAuthDot?.layer?.backgroundColor = (ok ? LingerTheme.stateSuccess : NSColor.tertiaryLabelColor).cgColor
        }
        // 通知（异步）
        NotificationManager.shared.fetchAuthorizationStatus { [weak self] status in
            guard let self = self else { return }
            let ok = (status == .authorized)
            DispatchQueue.main.async {
                if let nf = self.notifAuthLabel {
                    nf.stringValue = ok ? "已授权" : "未授权"
                    nf.textColor = ok ? LingerTheme.stateSuccess : .secondaryLabelColor
                    self.notifAuthDot?.layer?.backgroundColor = (ok ? LingerTheme.stateSuccess : NSColor.tertiaryLabelColor).cgColor
                }
            }
        }
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        refreshPermissionStatuses()
    }


    // MARK: - 当前值读取（含默认值兜底）

    private func currentDragLinePercent() -> Int {
        let v = UserDefaults.standard.integer(forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        return v == 0 ? 50 : v
    }

    private func currentMaxDurationMinutes() -> Int {
        let v = UserDefaults.standard.integer(forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
        return v == 0 ? 30 : v
    }

    private func currentNotifyOnComplete() -> Bool {
        (UserDefaults.standard.object(forKey: LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue) as? Bool) ?? true
    }

    private func currentPlaySound() -> Bool {
        (UserDefaults.standard.object(forKey: LingerTheme.UserDefaultsKey.playSound.rawValue) as? Bool) ?? true
    }

    private func currentLaunchAtLogin() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: LingerTheme.UserDefaultsKey.launchAtLogin.rawValue)
    }
}
