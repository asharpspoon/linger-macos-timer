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

    /// 窗口宽度：600pt（2026-08-06 从 520 加宽，让位置卡片/输入框更舒展，对齐 macOS 系统设置常见宽度）
    private static let windowWidth: CGFloat = 600
    private let tabBarHeight: CGFloat = 72
    private let contentHPadding: CGFloat = 28
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
    /// 「计入日历」下拉（授权状态变化时重建选项）
    private var targetCalendarPopup: NSPopUpButton?
    private var calAuthLabel: NSTextField?
    private var maxDurationStepper: NSStepper?
    /// 强提醒弹窗位置选择卡片（topRight / center），选中态琥珀边框
    private var bannerPositionCards: [String: NSView] = [:]
    /// 日历授权"管理/去授权"按钮引用（标题随授权状态动态切换）
    private var calAuthButton: NSButton?

    private var currentIndex: Int = 0
    private let log = OSLog(subsystem: "com.linger.settings", category: "SettingsWindow")

    // MARK: - 初始化

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        configureWindow()
        buildUI()
        // 2026-08-06：监听日历授权状态变更（probeAccessOnLaunch 回调 / requestPermissionIfNeeded 回调），
        // 授权状态变化时实时刷新设置页的"日历授权"行（状态文字 + 状态点 + 按钮标题）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCalendarAccessRefresh(_:)),
            name: .lingerCalendarAccessDidRefresh, object: nil)
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
    /// 供外部（菜单「关于 Linger」）切换到指定 tab
    func showTab(_ index: Int) {
        selectTab(index, animated: false)
    }

    private func selectTab(_ index: Int, animated: Bool) {
        guard index >= 0, index < tabTitles.count else {
            os_log("selectTab ignored: index %d out of bounds (count=%d)",
                   log: log, type: .error, index, tabTitles.count)
            return
        }
        currentIndex = index
        title = "设置"
        updateTabStyles()

        // 先测新 panel 理想高度（未加入容器，不受当前窗口高度约束）
        let panel = panelView(at: index)
        let panelFit = panel.fittingSize.height
        let panelHeight = max(panelFit, 100)
        let computed = tabBarHeight + panelHeight + contentVSpacing * 2
        // 窗口高度钳制到屏幕可用高度（防止顶出屏幕盖住菜单栏）
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let maxHeight = max(240, screenFrame.height - 16)
        let targetHeight = min(computed, maxHeight)
        let topLimit = screenFrame.maxY - 8
        let topY = min(frame.maxY, topLimit)
        let targetFrame = NSRect(x: frame.minX, y: topY - targetHeight,
                                 width: Self.windowWidth, height: targetHeight)

        /// 安装新面板（alpha 控制渐入起点），并完成布局/指示线
        func installPanel(alpha: CGFloat) {
            panelContainer.subviews.forEach { $0.removeFromSuperview() }
            panel.translatesAutoresizingMaskIntoConstraints = false
            panelContainer.addSubview(panel)
            // 2026-08-23：所有 sheet 统一内容宽度 520 + 水平居中（含关于页），
            // 避免关于页（独立构建不走 makePanel）宽度与其他 sheet 不一致。
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: contentVSpacing),
                panel.widthAnchor.constraint(equalToConstant: 520),
                panel.centerXAnchor.constraint(equalTo: panelContainer.centerXAnchor),
                panel.bottomAnchor.constraint(lessThanOrEqualTo: panelContainer.bottomAnchor, constant: -contentVSpacing)
            ])
            panel.alphaValue = alpha
            panelContainer.layoutSubtreeIfNeeded()
            tabBar.layoutSubtreeIfNeeded()
            positionTabIndicator()
            refreshPermissionStatuses()
        }

        if animated {
            // 1) 旧内容渐出（0.3s）
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panelContainer.subviews.forEach { $0.animator().alphaValue = 0 }
            }

            // 2) 窗口高度动画（0.8s 几何，顶部固定，双向一致，更优雅）
            let startH = frame.height
            let start = CACurrentMediaTime()
            let duration: CFTimeInterval = 0.8
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                let p = min(1, (CACurrentMediaTime() - start) / duration)
                // easeInOutCubic：先缓入再缓出
                let eased: CGFloat = p < 0.5 ? 4 * p * p * p : 1 - 4 * pow(1 - p, 3)
                let h = startH + (targetHeight - startH) * eased
                self.setFrame(NSRect(x: self.frame.minX, y: topY - h,
                                     width: Self.windowWidth, height: h), display: true)
                if p >= 1 { t.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)

            // 3) 0.3s 后换内容并渐入（0.4s）——与高度动画同时间轴完成
            let token = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.currentIndex == token else { return }
                installPanel(alpha: 0)   // 局部函数，闭包内直接调用
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }
            }
        } else {
            setFrame(targetFrame, display: true)
            installPanel(alpha: 1)
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
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = LingerTheme.labelFont(size: 11)
        f.textColor = .tertiaryLabelColor
        f.maximumNumberOfLines = 3
        f.lineBreakMode = .byWordWrapping
        return f
    }

    private func spacerView() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    /// 行：左 label（13pt，可带 hint、可挂 Beta 胶囊标签）+ 弹性 spacer + 右控件，min-height 34（原型 .row）
    private func makeRow(label: String, control: NSView, hint: String? = nil,
                         labelBetaBadge: Bool = false) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = LingerTheme.space3

        // label 部分：可选挂 Beta 胶囊标签（横向排列，badge 与文字垂直居中）
        let labelView: NSView = {
            guard labelBetaBadge else { return makeLabel(label) }
            let s = NSStackView(views: [makeLabel(label), makeBetaBadge()])
            s.orientation = .horizontal
            s.spacing = 6
            s.alignment = .centerY
            return s
        }()

        if let hint {
            let left = NSStackView()
            left.orientation = .vertical
            left.alignment = .leading
            left.spacing = 2
            left.addArrangedSubview(labelView)
            left.addArrangedSubview(makeHint(hint))
            // 2026-08-23：label+hint 列宽上限，防长 hint 把面板/窗口撑宽
            left.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
            row.addArrangedSubview(left)
        } else {
            row.addArrangedSubview(labelView)
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

    /// section：可选标题（13pt semibold ink，nil 时无标题；可挂 Beta 胶囊标签）+ 行列表（行间 1px 分隔线）
    /// 2026-08-06 排版重设计：title 改可选，用于去掉冗余的单一 section 总标题（如通知面板的"提醒方式"）
    private func makeSection(title: String?, rows: [NSView], titleBetaBadge: Bool = false) -> NSView {
        let section = NSView()
        var prev: NSLayoutYAxisAnchor = section.topAnchor

        if let title, !title.isEmpty {
            let titleLabel = NSTextField(labelWithString: title)
            // title 13pt semibold ink（主文字色），与 row label(13pt regular) 同号加粗，形成 title > label > hint 三级层级
            titleLabel.font = LingerTheme.labelFont(size: 13, weight: .semibold)
            titleLabel.textColor = LingerTheme.ink

            let titleView: NSView = {
                guard titleBetaBadge else { return titleLabel }
                let s = NSStackView(views: [titleLabel, makeBetaBadge()])
                s.orientation = .horizontal
                s.spacing = 6
                s.alignment = .centerY
                return s
            }()

            section.addSubview(titleView)
            titleView.translatesAutoresizingMaskIntoConstraints = false
            titleView.topAnchor.constraint(equalTo: section.topAnchor).isActive = true
            titleView.leadingAnchor.constraint(equalTo: section.leadingAnchor).isActive = true
            prev = titleView.bottomAnchor
        }

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
            // 有标题时 title→首行 space3(12pt) 拉开分组；无标题时首行 space2(8pt) 紧凑
            let topSpacing: CGFloat = (i == 0 && title != nil) ? LingerTheme.space3 : LingerTheme.space2
            row.topAnchor.constraint(equalTo: prev, constant: topSpacing).isActive = true
            prev = row.bottomAnchor
            if i == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: section.bottomAnchor).isActive = true
            }
        }
        return section
    }

    /// 面板容器：多个 section 垂直排布（section 间距 24pt = space5，分组更清晰）
    private func makePanel(sections: [NSView]) -> NSView {
        let panel = NSView()
        var prev: NSLayoutYAxisAnchor = panel.topAnchor
        for (i, section) in sections.enumerated() {
            panel.addSubview(section)
            section.translatesAutoresizingMaskIntoConstraints = false
            section.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
            // 2026-08-06 排版重设计：section 间距 18→24(space5)，分组分开
            section.topAnchor.constraint(equalTo: prev, constant: (i == 0 ? 0 : LingerTheme.space5)).isActive = true
            prev = section.bottomAnchor
            if i == sections.count - 1 {
                section.bottomAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true
            }
        }
        // 2026-08-23：面板宽度统一由 selectTab.installPanel 约束（520 + 居中），
        // 此处不再加宽度约束，避免与外部约束重复冲突。
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

    /// Beta 胶囊标签（2026-08-23 用户要求：Beta 标记从纯文字改为标签样式）：
    /// 10pt medium ink2 + surface2 底 + line 边框 + 全圆角胶囊，宽随内容。
    private func makeBetaBadge() -> NSView {
        let label = NSTextField(labelWithString: "Beta")
        label.font = LingerTheme.labelFont(size: 10, weight: .medium)
        label.textColor = LingerTheme.ink2
        label.alignment = .center
        // 2026-08-23：修复约束冲突 —— label 加入 box 前必须关掉 autoresizing mask
        // （否则 NSAutoresizingMaskConstraint 与手动约束冲突，控制台刷屏 "Will attempt to recover by breaking"）
        label.translatesAutoresizingMaskIntoConstraints = false
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface2).cgColor
        box.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            box.heightAnchor.constraint(equalToConstant: 16)
        ])
        return box
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

    // MARK: - 面板 0：操作

    private func buildOperationsPanel() -> NSView {
        makePanel(sections: [
            makeSection(title: "拖拽计时", rows: [buildDragLineRow(), buildMaxDurationRow()]),
            makeSection(title: "显示", rows: [buildDualRailRow(), buildTimeFormatRow(), buildPreviewFontSizeRow()])
        ])
    }

    private func buildDragLineRow() -> NSView {
        let slider = NSSlider(value: Double(currentDragLinePercent()), minValue: 0, maxValue: 100,
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
        popup.addItems(withTitles: ["倒计时 + 结束时间", "仅倒计时"])
        let raws = ["both", "countdown"]
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue) ?? "both"
        if let idx = raws.firstIndex(of: current) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(dualRailChanged(_:))
        return makeRow(label: "双轨显示", control: popup)
    }

    /// 2026-08-23 用户修正：时间格式 ≠ 是否显示秒钟，而是适配不同国家地区习惯。
    /// 统一使用 24 小时制，日期格式随以下地区习惯自动切换：
    /// - ISO（sv_SE）：2026-08-01
    /// - 中国（zh_CN）：2026/8/1
    /// - 美国（en_US）：8/1/2026
    /// - 日本（ja_JP）：2026/8/1
    private func buildTimeFormatRow() -> NSView {
        let popup = NSPopUpButton()
        styleSelect(popup)
        popup.addItems(withTitles: [
            "国际标准 ISO（2026-08-01 24:00）",
            "中国（2026/8/1 24:00）",
            "美国（8/1/2026 24:00）",
            "日本（2026/8/1 24:00）"
        ])
        let raws = ["sv_SE", "zh_CN", "en_US", "ja_JP"]
        let stored = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue) ?? "sv_SE"
        if let idx = raws.firstIndex(of: stored) { popup.selectItem(at: idx) }
        popup.target = self
        popup.action = #selector(timeFormatChanged(_:))
        return makeRow(label: "时间格式", control: popup, hint: "影响拖拽预览结束时刻、完成弹窗时间、记录导出日期的地区格式")
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
        // 2026-08-06 排版重设计：去掉冗余的"提醒方式"总标题（整个面板就是提醒方式），
        // 用无标题 section 直接承载 rows；弹窗位置改纵向 block 解决横向溢出"略宽"问题
        let bannerRow = makeRow(label: "计时完成时提醒",
                                control: makeSwitch(initial: currentNotifyOnComplete(),
                                                    action: #selector(notifyChanged(_:))),
                                hint: "计时完成时弹出横幅；关闭后仅保留菜单栏倒计时与提示音")
        let positionBlock = makeBannerPositionBlock()
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
            makeSection(title: nil, rows: [bannerRow, positionBlock, makeRow(label: "播放提示音", control: soundControl)])
        ])
    }

    // MARK: - 强提醒弹窗位置选择（2 个可点击示意图卡片）

    /// 弹窗位置纵向 block：上方标题+说明，下方两张等宽卡片占满 panel 宽度
    /// 2026-08-06 从横向 row 改为纵向 block，解决 hint 文字 + 两张卡片横向溢出导致面板"略宽"
    private func makeBannerPositionBlock() -> NSView {
        let current = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.bannerPosition.rawValue) ?? "topRight"

        // 上：标题 + 说明（纵向，左对齐）
        let titleLabel = makeLabel("弹窗位置")
        let hintLabel = makeHint("强提醒横幅在屏幕上的显示位置")
        let textStack = NSStackView(views: [titleLabel, hintLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // 下：两张卡片并排，fillEqually 等宽占满 panel 宽度
        let topRightCard = makePositionCard(title: "屏幕右上角", subtitle: "不遮挡中心工作区", position: "topRight", isTopRight: true)
        let centerCard = makePositionCard(title: "屏幕正中央", subtitle: "强提醒更显眼", position: "center", isTopRight: false)
        bannerPositionCards = ["topRight": topRightCard, "center": centerCard]
        updatePositionCardSelection(current)

        let cardStack = NSStackView(views: [topRightCard, centerCard])
        cardStack.orientation = .horizontal
        cardStack.spacing = LingerTheme.space3
        cardStack.alignment = .top
        cardStack.distribution = .fillEqually
        cardStack.heightAnchor.constraint(equalToConstant: 64).isActive = true
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        let block = NSView()
        block.addSubview(textStack)
        block.addSubview(cardStack)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: block.topAnchor),
            textStack.leadingAnchor.constraint(equalTo: block.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: block.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: LingerTheme.space2),
            cardStack.leadingAnchor.constraint(equalTo: block.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: block.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: block.bottomAnchor),
        ])
        return block
    }

    /// 单个位置示意图卡片：屏幕缩略图 + 横幅位置亮点 + 标题/副标题（宽度自适应，由外部 stack fillEqually 撑开）
    private func makePositionCard(title: String, subtitle: String, position: String, isTopRight: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = LingerTheme.radiusSM
        card.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface2).cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        // 2026-08-06：去掉 fixed width，由 cardStack.distribution=.fillEqually 等宽撑开
        card.heightAnchor.constraint(equalToConstant: 64).isActive = true
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 屏幕缩略图（暗色底 + 圆角，模拟显示器）
        let screenThumb = NSView()
        screenThumb.wantsLayer = true
        screenThumb.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        screenThumb.layer?.cornerRadius = 3
        screenThumb.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(screenThumb)

        // 横幅位置亮点（琥珀小方块）
        let bannerDot = NSView()
        bannerDot.wantsLayer = true
        bannerDot.layer?.backgroundColor = LingerTheme.amberGold.cgColor
        bannerDot.layer?.cornerRadius = 2
        bannerDot.translatesAutoresizingMaskIntoConstraints = false
        screenThumb.addSubview(bannerDot)

        // 标题 + 副标题
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = LingerTheme.labelFont(size: 12, weight: .medium)
        titleLabel.textColor = LingerTheme.ink
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = LingerTheme.labelFont(size: 10)
        subtitleLabel.textColor = LingerTheme.ink3
        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        NSLayoutConstraint.activate([
            screenThumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            screenThumb.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            screenThumb.widthAnchor.constraint(equalToConstant: 64),
            screenThumb.heightAnchor.constraint(equalToConstant: 44),
            textStack.leadingAnchor.constraint(equalTo: screenThumb.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            // 横幅亮点尺寸
            bannerDot.widthAnchor.constraint(equalToConstant: 22),
            bannerDot.heightAnchor.constraint(equalToConstant: 6),
        ])
        // 横幅亮点位置：右上角 or 正中央
        if isTopRight {
            NSLayoutConstraint.activate([
                bannerDot.topAnchor.constraint(equalTo: screenThumb.topAnchor, constant: 4),
                bannerDot.trailingAnchor.constraint(equalTo: screenThumb.trailingAnchor, constant: -4),
            ])
        } else {
            NSLayoutConstraint.activate([
                bannerDot.centerXAnchor.constraint(equalTo: screenThumb.centerXAnchor),
                bannerDot.centerYAnchor.constraint(equalTo: screenThumb.centerYAnchor),
            ])
        }

        // 点击识别
        card.identifier = NSUserInterfaceItemIdentifier(rawValue: "bannerPos_\(position)")
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(bannerPositionCardClicked(_:)))
        card.addGestureRecognizer(clickGesture)
        return card
    }

    /// 更新卡片选中态视觉（选中=琥珀边框，未选中=line 边框）
    private func updatePositionCardSelection(_ selected: String) {
        for (key, card) in bannerPositionCards {
            let isSelected = key == selected
            card.layer?.borderColor = isSelected
                ? LingerTheme.amberGold.cgColor
                : LingerTheme.nsColor(LingerTheme.Color.line).cgColor
            card.layer?.borderWidth = isSelected ? 2 : 1
        }
    }

    @objc private func bannerPositionCardClicked(_ sender: NSClickGestureRecognizer) {
        guard let id = sender.view?.identifier?.rawValue,
              let pos = id.split(separator: "_").last.map(String.init) else { return }
        UserDefaults.standard.set(pos, forKey: LingerTheme.UserDefaultsKey.bannerPosition.rawValue)
        updatePositionCardSelection(pos)
        os_log("Banner position changed to %s", log: log, type: .info, pos)
    }

    // MARK: - 面板 2：日历

    private func buildCalendarPanel() -> NSView {
        let authStatus = NSTextField(labelWithString: "检查中…")
        authStatus.font = LingerTheme.labelFont(size: 12)
        authStatus.textColor = LingerTheme.ink2
        calAuthLabel = authStatus
        // 2026-08-23 用户要求：状态只保留文字前的 ✓/⚠ 勾标（去掉左侧绿点，避免「点+勾」重复）
        let authBtn = NSButton(title: "管理授权", target: self, action: #selector(openCalSettings(_:)))
        authBtn.bezelStyle = .rounded
        authBtn.controlSize = .small
        calAuthButton = authBtn   // 保存引用，refreshPermissionStatuses 时同步标题
        // 2026-08-23 用户要求：循环 icon 按钮 —— 重置授权并再次申请
        // （解药：grantedByRequest 假授权残留时，清标记 → 重新走系统授权流程）
        let resetBtn = NSButton(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                               accessibilityDescription: "重置授权") ?? NSImage(),
                                target: self, action: #selector(resetCalAuthorization(_:)))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        resetBtn.toolTip = "重置授权并重新申请"
        let authControl = NSStackView(views: [authStatus, resetBtn, authBtn])
        authControl.orientation = .horizontal
        authControl.spacing = 10
        authControl.alignment = .centerY

        return makePanel(sections: [
            // 2026-08-06 排版重设计：合并"授权"+"写入设置"为一个 section（授权是写入前提，单行 section 太碎）
            // 2026-08-24：「写入方式」行隐藏（用户：三种模式实际体验没区别，统一用自动；
            // buildWriteModeRow/writeModeChanged 代码保留，想恢复把行加回来即可）
            makeSection(title: "日历写入", rows: [
                makeRow(label: "日历授权", control: authControl),
                buildTargetCalendarRow(),
                buildDefaultTitleRow()
            ]),
            makeSection(title: "快捷键预设", rows: [
                buildPresetCardRow(key: .fnTitle, kbd: "fn"),
                buildPresetCardRow(key: .ctrlTitle, kbd: "⌃"),
                buildPresetCardRow(key: .optTitle, kbd: "⌥")
            ], titleBetaBadge: true)
        ])
    }

    /// 2026-08-23 用户要求：「目标日历」改名「计入日历」，并改回下拉菜单 ——
    /// 读取日历 app 中用户已创建的可写日历供选择，默认 "Linger"（写入时自动创建）。
    private func buildTargetCalendarRow() -> NSView {
        let popup = NSPopUpButton()
        styleSelect(popup)
        rebuildTargetCalendarOptions(popup)
        popup.target = self
        popup.action = #selector(targetCalendarChanged(_:))
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        targetCalendarPopup = popup
        return makeRow(label: "计入日历", control: popup,
                       hint: "计时完成后自动记录到此日历")
    }

    /// 重建「计入日历」下拉选项：Linger 固定第一项（默认），
    /// 其余为日历 app 中用户已创建的可写日历（按系统顺序、去重）。
    private func rebuildTargetCalendarOptions(_ popup: NSPopUpButton) {
        let current = CalendarManager.shared.targetCalendarTitle
        var seen = Set<String>()
        let others = CalendarManager.shared.availableCalendars()
            .map { $0.title }
            .filter { $0 != "Linger" && seen.insert($0).inserted }
        popup.removeAllItems()
        popup.addItem(withTitle: "Linger")
        popup.addItems(withTitles: others)
        // current 无效时已回退 "Linger"（第一项），找不到时保持默认选中第一项
        popup.selectItem(withTitle: current)
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
        field.widthAnchor.constraint(equalToConstant: 240).isActive = true
        // 2026-08-24：写入方式已统一为自动（选择器隐藏），输入框恒可用
        field.isEnabled = true
        defaultTitleField = field
        return makeRow(label: "默认标题", control: field,
                       hint: "计时完成后自动写入时使用的标题",
                       labelBetaBadge: true)
    }

    private func buildPresetCardRow(key: LingerTheme.UserDefaultsKey, kbd: String) -> NSView {
        let field = NSTextField()
        field.placeholderString = "（留空不激活）"
        field.stringValue = UserDefaults.standard.string(forKey: key.rawValue) ?? ""
        field.target = self
        field.action = #selector(presetChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 160).isActive = true
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
        // 菜单栏图标选择（2026-08-23）：下拉项带图标预览，选择即生效
        // （MenuBarManager 监听 lingerMenuBarIconDidChange 热更新，无需重启）
        let iconPopup = NSPopUpButton()
        styleSelect(iconPopup)
        for style in MenuBarIconStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: nil, keyEquivalent: "")
            item.image = style.loadImage()   // 预览：菜单项左侧显示图标
            iconPopup.menu?.addItem(item)
        }
        if let idx = MenuBarIconStyle.allCases.firstIndex(of: MenuBarIconStyle.current) {
            iconPopup.selectItem(at: idx)
        }
        iconPopup.target = self
        iconPopup.action = #selector(menuBarIconChanged(_:))

        // 计时粒度（2026-08-23）：拖拽细线时倒计时读数的最小步进
        let granularityPopup = NSPopUpButton()
        styleSelect(granularityPopup)
        let granularities: [TimeInterval] = [10, 20, 30, 60]
        for g in granularities {
            granularityPopup.addItem(withTitle: "\(Int(g)) 秒")
        }
        let currentG = currentTimerGranularity()
        if let idx = granularities.firstIndex(where: { abs($0 - currentG) < 0.5 }) {
            granularityPopup.selectItem(at: idx)
        }
        granularityPopup.target = self
        granularityPopup.action = #selector(timerGranularityChanged(_:))

        let launchSwitch = makeSwitch(initial: currentLaunchAtLogin(), action: #selector(launchChanged(_:)))

        // 2026-08-23：「自动清理」「日历归档导出」「导出目录」暂隐藏（用户：功能还没想好怎么做，
        // 后端代码与 @objc action 全部保留，想清楚后把行加回来即可）

        return makePanel(sections: [
            // 2026-08-06 排版重设计：合并"启动"+"维护"为"通用"（都是日常维护类，单行 section 太碎）
            makeSection(title: "通用", rows: [
                makeRow(label: "菜单栏图标", control: iconPopup,
                        hint: "无计时时显示所选图标；倒计时进行中只显示时间"),
                makeRow(label: "计时粒度", control: granularityPopup,
                        hint: "下拉细线时倒计时读数的最小步进（如 10 秒：1:00 → 1:10 → 1:20）"),
                makeRow(label: "开机自启", control: launchSwitch)
            ]),
            // 日期格式已合并到时间格式选择器（2026-08-23）
        ])
    }

    /// 计时粒度当前值（`linger_timerGranularity`，缺省 60s）
    private func currentTimerGranularity() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.timerGranularity.rawValue)
        return v > 0 ? v : LingerTheme.defaultTimerGranularity
    }

    /// 计时粒度切换（2026-08-23）：持久化即可，拖拽链路每次实时读取
    @objc private func timerGranularityChanged(_ sender: NSPopUpButton) {
        let options: [TimeInterval] = [10, 20, 30, 60]
        let idx = sender.indexOfSelectedItem
        guard options.indices.contains(idx) else { return }
        UserDefaults.standard.set(options[idx],
                                  forKey: LingerTheme.UserDefaultsKey.timerGranularity.rawValue)
    }

    /// 菜单栏图标切换（2026-08-23）：持久化选择 + 广播热更新
    @objc private func menuBarIconChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard MenuBarIconStyle.allCases.indices.contains(idx) else { return }
        let style = MenuBarIconStyle.allCases[idx]
        UserDefaults.standard.set(style.rawValue,
                                  forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue)
        NotificationCenter.default.post(name: .lingerMenuBarIconDidChange, object: nil)
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
        let raws = ["both", "countdown"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(raws[sender.indexOfSelectedItem],
                                  forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue)
    }

    @objc private func timeFormatChanged(_ sender: NSPopUpButton) {
        let raws = ["sv_SE", "zh_CN", "en_US", "ja_JP"]
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
        guard let title = sender.titleOfSelectedItem, !title.isEmpty else { return }
        UserDefaults.standard.set(title,
                                  forKey: LingerTheme.UserDefaultsKey.targetCalendar.rawValue)
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

    @objc private func exportMarkdownChanged(_ sender: LingerSwitch) {
        UserDefaults.standard.set(sender.isOn,
                                  forKey: LingerTheme.UserDefaultsKey.exportMarkdown.rawValue)
        if sender.isOn && RecordExporter.savedDirectory() == nil {
            // 首次开启：弹目录选择
            exportDirTapped(nil)
        }
    }

    @objc private func exportDirTapped(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择导出目录"
        panel.message = "Linger 会在此目录下按月生成 Markdown 归档文档"
        if let current = RecordExporter.savedDirectory() {
            panel.directoryURL = current
        }
        if panel.runModal() == .OK, let url = panel.url {
            RecordExporter.setSavedDirectory(url)
            rebuildGeneralPanelDirDisplay()
            // 选择目录后立即触发一次增量导出
            RecordExporter.exportIncremental(directory: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func exportNowTapped(_ sender: Any?) {
        // 立即导出：当前月全量
        let now = Date()
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let written = RecordExporter.exportRange(from: monthStart, to: now)
        let dir = RecordExporter.savedDirectory() ?? RecordExporter.defaultDirectory()
        if written > 0 {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } else {
            let alert = NSAlert()
            alert.messageText = "本月暂无可导出的日历事件"
            alert.informativeText = "请确认日历已授权，且本月有日程记录"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func currentExportDirDisplay() -> String {
        if let url = RecordExporter.savedDirectory() {
            return url.path
        }
        return RecordExporter.defaultDirectory().path + "（默认）"
    }

    private func rebuildGeneralPanelDirDisplay() {
        // 重建通用面板让目录显示更新
        // 2026-08-06：设置页是惰性构建 + 缓存。清缓存后重选当前 tab 触发重建。
        if currentIndex == 3 {  // 通用 tab 索引
            builtPanels[3] = nil
            selectTab(3, animated: false)
        }
    }

    @objc private func dateLocaleChanged(_ sender: NSPopUpButton) {
        let raws = ["sv_SE", "zh_CN", "en_US", "ja_JP"]
        guard raws.indices.contains(sender.indexOfSelectedItem) else { return }
        let localeID = raws[sender.indexOfSelectedItem]
        UserDefaults.standard.set(localeID, forKey: LingerTheme.UserDefaultsKey.dateLocale.rawValue)
        // 通知下次创建的预约编辑区按新地区渲染（编辑区每次展开重建，通知仅作广播一致性）
        NotificationCenter.default.post(name: Notification.Name("linger.dateLocaleChanged"), object: nil, userInfo: ["locale": localeID])
    }

    // MARK: - 跳转系统设置

    @objc private func openCalSettings(_ sender: Any?) {
        // 2026-08-06 修复"点管理不主动授权"bug：
        // 旧版直接跳系统设置 URL，但未授权且 notDetermined 时 TCC 还没登记 Linger，
        // 用户在系统设置里找不到开关。新版先主动触发系统对话框，granted=false 再跳系统设置。
        // 用 hasAccess 兜底裸 bundle 场景（isAuthorized 恒 false）。
        if CalendarManager.shared.hasAccess {
            // 已授权 → 直接跳系统设置让用户管理（开关已在系统设置里）
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        // 未授权 → 统一入口（notDetermined 触发系统对话框；denied 弹 NSAlert 引导去系统设置）
        CalendarManager.shared.requestPermissionIfNeeded { [weak self] granted in
            guard let self = self else { return }
            // 授权结束后刷新本窗口状态（按钮标题/状态点同步）
            self.refreshPermissionStatuses()
        }
    }

    // MARK: - 授权状态刷新

    /// 循环按钮：重置授权并再次申请（清 grantedByRequest 假标记 → 重新走系统授权流程）。
    /// 场景：UI 显示「已授权」但日历读取 Access denied（裸二进制 TCC 漂移残留）。
    @objc private func resetCalAuthorization(_ sender: Any?) {
        CalendarManager.shared.resetAuthorization()
        // 授权回调后 lingerCalendarAccessDidRefresh 通知会触发刷新 + 重建下拉
    }

    func refreshPermissionStatuses() {
        // 日历（同步）：状态文字 + 按钮标题 两处同步
        // 用 hasAccess 兜底裸 bundle 场景（isAuthorized 恒 false，grantedByRequest 才是真实状态）
        let ok = CalendarManager.shared.hasAccess
        if let cal = calAuthLabel {
            // 2026-08-23 用户要求：只保留 ✓/⚠ 勾标（不再叠加左侧状态点）
            cal.stringValue = ok ? "✓ 已授权" : "⚠ 未授权"
            cal.textColor = ok ? LingerTheme.stateSuccess : LingerTheme.ink2
        }
        if let btn = calAuthButton {
            // 按钮标题动态化：未授权"去授权…"引导主动点击；已授权"管理授权"跳系统设置
            btn.title = ok ? "管理授权" : "去授权…"
        }
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        refreshPermissionStatuses()
        // 重建「计入日历」选项：用户可能在日历 app 中新建/删除了日历
        if let popup = targetCalendarPopup {
            rebuildTargetCalendarOptions(popup)
        }
    }

    /// 日历授权状态变更通知回调：实时刷新设置页授权显示 + 重建「计入日历」选项
    /// （未授权时日历列表为空，授权成功后才能读到用户已创建的日历）。
    @objc private func handleCalendarAccessRefresh(_ note: Notification) {
        refreshPermissionStatuses()
        if let popup = targetCalendarPopup {
            rebuildTargetCalendarOptions(popup)
        }
    }


    // MARK: - 当前值读取（含默认值兜底）

    private func currentDragLinePercent() -> Int {
        // 2026-08-23：0 是合法值（= 线最长 25% 屏高），只在从未设置过时才用默认 50
        guard UserDefaults.standard.object(
            forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue) != nil else { return 50 }
        let v = UserDefaults.standard.integer(forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        return max(0, min(100, v))
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

    private func currentExportMarkdown() -> Bool {
        UserDefaults.standard.bool(forKey: LingerTheme.UserDefaultsKey.exportMarkdown.rawValue)
    }

    private func currentLaunchAtLogin() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: LingerTheme.UserDefaultsKey.launchAtLogin.rawValue)
    }
}
