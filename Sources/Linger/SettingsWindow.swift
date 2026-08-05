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
    private let tabTitles = ["操作", "通知", "日历", "通用", "关于"]
    /// 标签页 SF Symbol（与 tabTitles 一一对应，恰好 5 个）
    private let tabIcons = ["slider.horizontal.3", "bell", "calendar", "gearshape", "info"]
    /// 已构建面板缓存（恰好 5 个槽位，惰性构建）
    private var builtPanels: [NSView?] = [nil, nil, nil, nil, nil]

    // MARK: - 布局常量

    private static let windowWidth: CGFloat = 520
    private let tabBarHeight: CGFloat = 72
    private let contentHPadding: CGFloat = 24
    private let contentVSpacing: CGFloat = 24   // 底部留白加大（用户要求）
    private static let defaultWindowHeight: CGFloat = 520

    // MARK: - 视图引用

    private var tabButtons: [TabButtonView] = []
    /// 激活 tab 顶部琥珀指示线（tabBar 层）
    private var tabIndicator: NSView!
    private var tabBar: NSView!
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
        title = "设置"
        titlebarAppearsTransparent = false
        titleVisibility = .visible
        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = .windowBackgroundColor
        isOpaque = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        // 只保留关闭按钮，隐藏最小化/缩放（用户要求）
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        center()
    }

    // MARK: - UI 构建

    private func buildUI() {
        let root = NSVisualEffectView()
        // 磨砂玻璃质感 + 微微透明度（用户要求）
        root.material = .hudWindow
        root.blendingMode = .withinWindow
        root.state = .active
        contentView = root

        // Tab 栏（图标 + 文字，居中，激活态琥珀金高亮）—— 系统标题栏之下
        let tabBar = NSView()
        self.tabBar = tabBar
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
        tabStack.spacing = LingerTheme.space3   // 用户要求间距加宽
        tabStack.alignment = .centerY
        tabBar.addSubview(tabStack)
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabStack.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            // 图标下移，给 tab 顶部指示线留出空隙（icon 上方充足空间）
            tabStack.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 10)
        ])

        // 激活 tab 顶部指示线（独立视图，布局后按按钮 frame 定位，不依赖按钮 bounds）
        tabIndicator = NSView()
        tabIndicator.wantsLayer = true
        tabIndicator.layer?.backgroundColor = LingerTheme.amberGold.cgColor
        tabIndicator.layer?.cornerRadius = 1.5
        tabIndicator.isHidden = true
        tabBar.addSubview(tabIndicator)

        // PRD §6.3 P2：仅遍历恰好 5 个标签
        for index in 0..<tabTitles.count {
            let btn = TabButtonView(title: tabTitles[index], icon: tabIcons[index], index: index) { [weak self] i in
                self?.selectTab(i, animated: true)
            }
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

    /// 切换面板。`index` 越界时直接返回（PRD §6.3 P2 边界 guard）。
    private func selectTab(_ index: Int, animated: Bool) {
        guard index >= 0, index < tabTitles.count else {
            os_log("selectTab ignored: index %d out of bounds (count=%d)",
                   log: log, type: .error, index, tabTitles.count)
            return
        }
        currentIndex = index
        title = "设置"
        updateTabStyles()

        // 先测新 panel 理想高度（此时未加入容器，不受当前窗口高度约束）
        let panel = panelView(at: index)
        let panelFit = panel.fittingSize.height
        let panelHeight = max(panelFit, 100)
        let computed = tabBarHeight + panelHeight + contentVSpacing * 2
        // 窗口高度钳制到屏幕可用高度（防止窗口比屏幕高、顶部顶出屏幕盖住菜单栏）
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let maxHeight = max(240, screenFrame.height - 16)
        let targetHeight = min(computed, maxHeight)
        // 顶部固定且不超出屏幕可见区
        let topLimit = screenFrame.maxY - 8
        let topY = min(frame.maxY, topLimit)
        let targetFrame = NSRect(x: frame.minX, y: topY - targetHeight,
                                 width: Self.windowWidth, height: targetHeight)

        os_log("LingerDiag selectTab idx=%d animated=%d panelFit=%.1f targetH=%.1f frameH=%.1f screenH=%.1f",
               log: log, type: .info, index, animated ? 1 : 0, panelFit, targetHeight, frame.height, screenFrame.height)

        // 动画完成后（或非动画直接）切换面板内容 + 布局 + 指示线
        func finish() {
            panelContainer.subviews.forEach { $0.removeFromSuperview() }
            panel.translatesAutoresizingMaskIntoConstraints = false
            panelContainer.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: contentVSpacing),
                panel.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: contentHPadding),
                panel.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -contentHPadding),
                panel.bottomAnchor.constraint(lessThanOrEqualTo: panelContainer.bottomAnchor, constant: -contentVSpacing)
            ])
            panelContainer.layoutSubtreeIfNeeded()
            tabBar.layoutSubtreeIfNeeded()
            positionTabIndicator()
            refreshPermissionStatuses()
        }

        if animated {
            // 先做纯几何高度动画（容器内仍是旧内容，无约束/重绘干扰）→ 双向都丝滑
            let startH = frame.height
            let start = CACurrentMediaTime()
            let duration: CFTimeInterval = 0.55
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                let p = min(1, (CACurrentMediaTime() - start) / duration)
                // easeInOutCubic：先缓入再缓出
                let eased: CGFloat = p < 0.5 ? 4 * p * p * p : 1 - 4 * pow(1 - p, 3)
                let h = startH + (targetHeight - startH) * eased
                self.setFrame(NSRect(x: self.frame.minX, y: topY - h,
                                     width: Self.windowWidth, height: h), display: true)
                if p >= 1 {
                    t.invalidate()
                    finish()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        } else {
            setFrame(targetFrame, display: true)
            finish()
        }
    }

    private func updateTabStyles() {
        for (i, btn) in tabButtons.enumerated() {
            btn.isActive = (i == currentIndex)
        }
    }

    /// 激活 tab 顶部指示线：位于 tab 栏顶部、icon 上方（独立视图，按按钮 frame 定位）
    private func positionTabIndicator() {
        guard tabButtons.indices.contains(currentIndex), let tabIndicator else { return }
        let btn = tabButtons[currentIndex]
        let frameInBar = tabBar.convert(btn.bounds, from: btn)
        tabIndicator.frame = NSRect(x: frameInBar.minX, y: 2, width: frameInBar.width, height: 3)
        tabIndicator.isHidden = false
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
        case 4: view = buildAboutPanel()
        default: view = NSView()
        }
        builtPanels[index] = view
        return view
    }

    // MARK: - 通用控件助手

    // MARK: - 通用控件助手（原型 section/row 范式）

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = LingerTheme.labelFont(size: 13)
        f.textColor = LingerTheme.ink
        f.alignment = .left
        return f
    }

    private func makeHint(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = LingerTheme.labelFont(size: 11)
        f.textColor = .tertiaryLabelColor
        return f
    }

    private func spacerView() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    /// 行：左 label（13pt，可带 hint）+ 弹性 spacer + 右控件，min-height 34（原型 .row）
    private func makeRow(label: String, control: NSView, hint: String? = nil) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = LingerTheme.space3

        if let hint {
            let left = NSStackView()
            left.orientation = .vertical
            left.alignment = .leading
            left.spacing = 2
            left.addArrangedSubview(makeLabel(label))
            left.addArrangedSubview(makeHint(hint))
            row.addArrangedSubview(left)
        } else {
            row.addArrangedSubview(makeLabel(label))
        }
        row.addArrangedSubview(spacerView())
        row.addArrangedSubview(control)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return row
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    /// section：标题（11pt uppercase 灰）+ 行列表（行间 1px 分隔线，原型 .section/.section-rows）
    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let section = NSView()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = LingerTheme.labelFont(size: 11, weight: .semibold)
        titleLabel.textColor = LingerTheme.ink3
        section.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.topAnchor.constraint(equalTo: section.topAnchor).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor).isActive = true

        var prev: NSLayoutYAxisAnchor = titleLabel.bottomAnchor
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let div = makeDivider()
                section.addSubview(div)
                div.translatesAutoresizingMaskIntoConstraints = false
                div.leadingAnchor.constraint(equalTo: section.leadingAnchor).isActive = true
                div.trailingAnchor.constraint(equalTo: section.trailingAnchor).isActive = true
                div.topAnchor.constraint(equalTo: prev, constant: LingerTheme.space2).isActive = true
                prev = div.bottomAnchor
            }
            section.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.leadingAnchor.constraint(equalTo: section.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: section.trailingAnchor).isActive = true
            row.topAnchor.constraint(equalTo: prev, constant: LingerTheme.space2).isActive = true
            prev = row.bottomAnchor
            if i == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: section.bottomAnchor).isActive = true
            }
        }
        return section
    }

    /// 面板容器：多个 section 垂直排布（间距 18，原型 .section margin-bottom）
    private func makePanel(sections: [NSView]) -> NSView {
        let panel = NSView()
        var prev: NSLayoutYAxisAnchor = panel.topAnchor
        for (i, section) in sections.enumerated() {
            panel.addSubview(section)
            section.translatesAutoresizingMaskIntoConstraints = false
            section.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
            section.topAnchor.constraint(equalTo: prev, constant: (i == 0 ? 0 : 18)).isActive = true
            prev = section.bottomAnchor
            if i == sections.count - 1 {
                section.bottomAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true
            }
        }
        return panel
    }

    /// Select 自定义外观（铁律：禁 NSPopUpButton 默认 bezel；surface2 底 24pt 高 圆角4 12pt 字）
    private func styleSelect(_ popup: NSPopUpButton) {
        popup.bezelStyle = .inline
        popup.isBordered = false
        popup.wantsLayer = true
        popup.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface2).cgColor
        popup.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        popup.layer?.borderWidth = 1
        popup.layer?.cornerRadius = LingerTheme.radiusXS
        popup.font = LingerTheme.labelFont(size: 12)
        popup.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    /// 自定义胶囊开关（铁律：禁 NSButton(.switch) 复选框）
    private func makeSwitch(initial: Bool, action: Selector) -> NSView {
        let sw = LingerSwitch()
        sw.isOn = initial
        sw.target = self
        sw.action = action
        return sw
    }

    private func integerFormatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = NSNumber(value: min)
        f.maximum = NSNumber(value: max)
        f.allowsFloats = false
        f.minimumIntegerDigits = 1
        return f
    }

    /// kbd 键帽（快捷预设标题）：10px 等宽 + surface2 底 + 圆角 5 + 边框
    private func makeKbd(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = LingerTheme.timeFont(size: 10, weight: .regular)
        label.textColor = LingerTheme.ink2
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
        container.spacing = LingerTheme.space2
        container.alignment = .centerY
        let styles = [("ring", "Ring"), ("classic", "Classic"), ("timer", "SF Symbol")]
        for (i, st) in styles.enumerated() {
            let btn = NSButton(title: st.1, target: self, action: #selector(iconStylePicked(_:)))
            btn.setButtonType(NSButton.ButtonType.toggle)
            btn.tag = i
            btn.bezelStyle = .rounded
            btn.font = LingerTheme.labelFont(size: 11)
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
            btn.contentTintColor = on ? LingerTheme.amberGold : LingerTheme.ink2
        }
    }

    // MARK: - 面板 0：操作

    private func buildOperationsPanel() -> NSView {
        makePanel(sections: [
            makeSection(title: "拖拽计时", rows: [buildDragLineRow(), buildMaxDurationRow()]),
            makeSection(title: "显示", rows: [buildDualRailRow(), buildTimeFormatRow(), buildPreviewFontSizeRow()])
        ])
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
        group.spacing = LingerTheme.space2
        group.alignment = .centerY
        dragLineSlider = slider
        dragLineValueLabel = valueLabel
        return makeRow(label: "下拉线最大长度", control: group)
    }

    private func buildMaxDurationRow() -> NSView {
        let field = NSTextField()
        field.formatter = integerFormatter(min: 5, max: 1440)
        field.integerValue = currentMaxDurationMinutes()
        field.target = self
        field.action = #selector(maxDurationChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 5
        stepper.maxValue = 1440
        stepper.increment = 1
        stepper.integerValue = currentMaxDurationMinutes()
        stepper.target = self
        stepper.action = #selector(maxDurationStepperChanged(_:))
        maxDurationStepper = stepper
        let unit = makeLabel("分钟")
        unit.textColor = LingerTheme.ink2
        let group = NSStackView(views: [field, stepper, unit])
        group.orientation = .horizontal
        group.spacing = 6
        group.alignment = .centerY
        return makeRow(label: "最大计时时长", control: group)
    }

    private func buildDualRailRow() -> NSView {
        let popup = NSPopUpButton()
        styleSelect(popup)
        popup.addItems(withTitles: ["倒计时 + 结束时间", "仅倒计时", "仅结束时间"])
        let raws = ["both", "countdown", "endTime"]
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue) ?? "both"
        if let idx = raws.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(dualRailChanged(_:))
        return makeRow(label: "双轨显示", control: popup)
    }

    private func buildTimeFormatRow() -> NSView {
        let popup = NSPopUpButton()
        styleSelect(popup)
        popup.addItems(withTitles: ["HH:MM:SS", "HH:MM", "MM:SS"])
        let raws = ["hms", "hm", "ms"]
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue) ?? "hms"
        if let idx = raws.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(timeFormatChanged(_:))
        return makeRow(label: "时间格式", control: popup)
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
        group.spacing = LingerTheme.space2
        group.alignment = .centerY
        previewFontSizeSlider = slider
        previewFontSizeValueLabel = valueLabel
        return makeRow(label: "计时字号", control: group)
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
        let authStatus = NSTextField(labelWithString: "检查中…")
        authStatus.font = LingerTheme.labelFont(size: 12)
        authStatus.textColor = LingerTheme.ink2
        notifAuthLabel = authStatus
        let authDot = makeStatusDot()
        notifAuthDot = authDot
        let authBtn = NSButton(title: "管理…", target: self, action: #selector(openNotifSettings(_:)))
        authBtn.bezelStyle = .rounded
        authBtn.controlSize = .small
        let authControl = NSStackView(views: [makeAuthStatusView(label: authStatus, dot: authDot), authBtn])
        authControl.orientation = .horizontal
        authControl.spacing = 10
        authControl.alignment = .centerY

        let notifyRow = makeRow(label: "计时完成时通知",
                                control: makeSwitch(initial: currentNotifyOnComplete(),
                                                    action: #selector(notifyChanged(_:))))
        let playSwitch = makeSwitch(initial: currentPlaySound(), action: #selector(playSoundChanged(_:)))
        let soundPopup = NSPopUpButton()
        styleSelect(soundPopup)
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

        return makePanel(sections: [
            makeSection(title: "授权", rows: [makeRow(label: "通知授权", control: authControl)]),
            makeSection(title: "提醒方式", rows: [notifyRow, makeRow(label: "播放提示音", control: soundControl)])
        ])
    }

    // MARK: - 面板 2：日历

    private func buildCalendarPanel() -> NSView {
        let authStatus = NSTextField(labelWithString: "检查中…")
        authStatus.font = LingerTheme.labelFont(size: 12)
        authStatus.textColor = LingerTheme.ink2
        calAuthLabel = authStatus
        let authDot = makeStatusDot()
        calAuthDot = authDot
        let authBtn = NSButton(title: "管理…", target: self, action: #selector(openCalSettings(_:)))
        authBtn.bezelStyle = .rounded
        authBtn.controlSize = .small
        let authControl = NSStackView(views: [makeAuthStatusView(label: authStatus, dot: authDot), authBtn])
        authControl.orientation = .horizontal
        authControl.spacing = 10
        authControl.alignment = .centerY

        return makePanel(sections: [
            makeSection(title: "授权", rows: [makeRow(label: "日历授权", control: authControl)]),
            makeSection(title: "写入设置", rows: [buildTargetCalendarRow(), buildWriteModeRow(), buildDefaultTitleRow()]),
            makeSection(title: "快捷预设标题", rows: [
                buildPresetCardRow(key: .fnTitle, kbd: "fn"),
                buildPresetCardRow(key: .ctrlTitle, kbd: "⌃"),
                buildPresetCardRow(key: .optTitle, kbd: "⌥")
            ])
        ])
    }

    private func buildTargetCalendarRow() -> NSView {
        let calendars = CalendarManager.shared.availableCalendars()
        let titles = calendars.map { $0.title }
        let popup = NSPopUpButton()
        styleSelect(popup)
        popup.addItems(withTitles: titles.isEmpty ? ["Linger"] : titles)
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.targetCalendar.rawValue) ?? "Linger"
        if let idx = titles.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(targetCalendarChanged(_:))
        return makeRow(label: "目标日历", control: popup)
    }

    private func buildWriteModeRow() -> NSView {
        let popup = NSPopUpButton()
        styleSelect(popup)
        popup.addItems(withTitles: ["每次询问", "自动", "手动"])
        let modes: [CalendarManager.WriteMode] = [.ask, .auto, .manual]
        let current = CalendarManager.shared.writeMode
        if let idx = modes.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(writeModeChanged(_:))
        return makeRow(label: "写入方式", control: popup)
    }

    private func buildDefaultTitleRow() -> NSView {
        let field = NSTextField()
        field.placeholderString = "默认活动标题"
        field.stringValue = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.defaultTitle.rawValue) ?? ""
        field.target = self
        field.action = #selector(defaultTitleChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        field.isEnabled = CalendarManager.shared.writeMode == .auto
        defaultTitleField = field
        return makeRow(label: "默认标题", control: field, hint: "仅在「自动写入」模式下使用")
    }

    private func buildPresetCardRow(key: LingerTheme.UserDefaultsKey, kbd: String) -> NSView {
        let field = NSTextField()
        field.placeholderString = "（留空不激活）"
        field.stringValue = UserDefaults.standard.string(forKey: key.rawValue) ?? ""
        field.target = self
        field.action = #selector(presetChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        field.identifier = NSUserInterfaceItemIdentifier(rawValue: key.rawValue)
        // 原型：左 kbd + 输入框，右灰注释「留空则不激活」
        let left = NSStackView(views: [makeKbd(kbd), field])
        left.orientation = .horizontal
        left.spacing = LingerTheme.space2
        left.alignment = .centerY
        let row = NSStackView(views: [left, spacerView(), makeHint("留空则不激活")])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = LingerTheme.space3
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return row
    }

    // MARK: - 面板 3：通用

    private func buildGeneralPanel() -> NSView {
        let launchSwitch = makeSwitch(initial: currentLaunchAtLogin(), action: #selector(launchChanged(_:)))
        let cleanupPopup = NSPopUpButton()
        styleSelect(cleanupPopup)
        cleanupPopup.addItems(withTitles: ["每周", "每月", "从不"])
        let cleanupRaws = ["weekly", "monthly", "never"]
        let cleanup = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.cleanupInterval.rawValue) ?? "weekly"
        if let idx = cleanupRaws.firstIndex(of: cleanup) { cleanupPopup.selectItem(at: idx) }
        cleanupPopup.target = self
        cleanupPopup.action = #selector(cleanupChanged(_:))

        let iconPopup = NSPopUpButton()
        styleSelect(iconPopup)
        iconPopup.addItems(withTitles: ["Ring", "Classic", "SF Symbol"])
        let iconRaws = ["ring", "classic", "timer"]
        let icon = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue) ?? "ring"
        if let idx = iconRaws.firstIndex(of: icon) { iconPopup.selectItem(at: idx) }
        iconPopup.target = self
        iconPopup.action = #selector(iconStyleChanged(_:))
        self.iconPopup = iconPopup

        return makePanel(sections: [
            makeSection(title: "启动", rows: [makeRow(label: "开机自启", control: launchSwitch)]),
            makeSection(title: "维护", rows: [makeRow(label: "自动清理", control: cleanupPopup)]),
            makeSection(title: "菜单栏图标", rows: [
                makeRow(label: "图标风格", control: iconPopup),
                buildIconStylePicker()   // 三选一预览，左对齐（原型）
            ])
        ])
    }

    // MARK: - 面板 4：关于（票据风格）

    private func buildAboutPanel() -> NSView {
        let panel = NSView()
        let ticket = AboutTicketView()
        ticket.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(ticket)
        NSLayoutConstraint.activate([
            ticket.topAnchor.constraint(equalTo: panel.topAnchor),
            ticket.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            ticket.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            ticket.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
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

    @objc private func notifyChanged(_ sender: LingerSwitch) {
        UserDefaults.standard.set(sender.isOn,
                                  forKey: LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue)
    }

    @objc private func playSoundChanged(_ sender: LingerSwitch) {
        let on = sender.isOn
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

    @objc private func launchChanged(_ sender: LingerSwitch) {
        let on = sender.isOn
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
            cal.textColor = ok ? LingerTheme.stateSuccess : LingerTheme.ink2
            calAuthDot?.layer?.backgroundColor = (ok ? LingerTheme.stateSuccess : LingerTheme.ink3).cgColor
        }
        // 通知（异步）
        NotificationManager.shared.fetchAuthorizationStatus { [weak self] status in
            guard let self = self else { return }
            let ok = (status == .authorized)
            DispatchQueue.main.async {
                if let nf = self.notifAuthLabel {
                    nf.stringValue = ok ? "已授权" : "未授权"
                    nf.textColor = ok ? LingerTheme.stateSuccess : LingerTheme.ink2
                    self.notifAuthDot?.layer?.backgroundColor = (ok ? LingerTheme.stateSuccess : LingerTheme.ink3).cgColor
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
