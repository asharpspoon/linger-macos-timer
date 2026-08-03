import Cocoa
import os.log

/// Linger 关于窗口（T11）。
///
/// 480×320 居中、毛玻璃、Level .normal、仅关闭按钮（最小化/缩放隐藏）；
/// 顶部 64×64 环形图标 + "Linger" + "版本 2.0" + 标语；
/// 两张权限卡片（日历 + 通知），各含状态文字与按钮，每 3 秒自动刷新授权状态。
final class AboutWindow: NSWindow {

    // MARK: - 常量

    private static let windowWidth: CGFloat = 480
    private static let windowHeight: CGFloat = 320
    private let titleBarHeight: CGFloat = 38
    private let cardWidth: CGFloat = 190
    private let log = OSLog(subsystem: "com.linger.about", category: "AboutWindow")

    // MARK: - 视图引用

    private var calStatusLabel: NSTextField?
    private var calButton: NSButton?
    private var notifStatusLabel: NSTextField?
    private var notifButton: NSButton?
    private var refreshTimer: Timer?

    // MARK: - 初始化

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        configureWindow()
        buildUI()
    }

    convenience init() {
        // 仅 .titled + .closable：标题栏只显示关闭按钮
        let rect = NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight)
        self.init(contentRect: rect, styleMask: [.titled, .closable],
                  backing: .buffered, defer: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .normal                  // PRD §3.7.1：Level .normal
        backgroundColor = .clear
        isOpaque = false
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

        // 标题栏（38pt，居中「关于 Linger」）
        let titleBar = NSView()
        root.addSubview(titleBar)
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: root.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: titleBarHeight)
        ])

        let titleLabel = NSTextField(labelWithString: "关于 Linger")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleBar.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titleBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor)
        ])

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        titleBar.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])

        // 内容容器
        let content = NSView()
        root.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        ])

        // 环形图标（64×64，琥珀金 tint）
        let icon = NSImageView(image: makeRingIcon(size: 64))
        icon.image?.isTemplate = true
        icon.contentTintColor = LingerTheme.amberGold
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(icon)

        let name = NSTextField(labelWithString: "Linger")
        name.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        name.textColor = .labelColor
        stack.addArrangedSubview(name)

        let version = NSTextField(labelWithString: "版本 2.0")
        version.font = NSFont.systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        stack.addArrangedSubview(version)

        let slogan = NSTextField(labelWithString: "一拉即走，松手计时")
        slogan.font = NSFont.systemFont(ofSize: 11)
        slogan.textColor = .tertiaryLabelColor
        let baseFont = NSFont.systemFont(ofSize: 11)
        slogan.font = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic),
                             size: 11) ?? baseFont
        stack.addArrangedSubview(slogan)

        // 权限卡片行
        let cardsRow = NSStackView()
        cardsRow.orientation = .horizontal
        cardsRow.spacing = 12
        cardsRow.alignment = .top
        let calCard = buildCard(symbol: "calendar", title: "日历",
                                statusLabel: &calStatusLabel, button: &calButton,
                                action: #selector(openCalSettings(_:)))
        let notifCard = buildCard(symbol: "bell", title: "通知",
                                  statusLabel: &notifStatusLabel, button: &notifButton,
                                  action: #selector(openNotifSettings(_:)))
        cardsRow.addArrangedSubview(calCard)
        cardsRow.addArrangedSubview(notifCard)
        stack.addArrangedSubview(cardsRow)
    }

    /// 构建一张权限卡片（190pt 宽），通过 inout 回传状态标签与按钮引用。
    private func buildCard(symbol: String, title: String,
                           statusLabel: inout NSTextField?, button: inout NSButton?,
                           action: Selector) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.04).cgColor
        card.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
        ])

        let img = NSImageView(image: NSImage(systemSymbolName: symbol,
                                             accessibilityDescription: title) ?? NSImage())
        img.contentTintColor = LingerTheme.amberGold
        img.imageScaling = .scaleProportionallyUpOrDown
        img.widthAnchor.constraint(equalToConstant: 20).isActive = true
        img.heightAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(img)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)

        let status = NSTextField(labelWithString: "检查中…")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        statusLabel = status
        stack.addArrangedSubview(status)

        let btn = NSButton(title: "开启", target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        button = btn
        stack.addArrangedSubview(btn)

        return card
    }

    /// 自绘环形图标（template，由 contentTintColor 着色为琥珀金）
    private func makeRingIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let inset: CGFloat = size * 0.12
        let ringRect = NSRect(x: inset, y: inset,
                              width: size - inset * 2, height: size - inset * 2)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = max(2, size * 0.12)
        ringPath.stroke()
        let dot = size * 0.16
        let dotRect = NSRect(x: size / 2 - dot / 2, y: size / 2 - dot / 2,
                             width: dot, height: dot)
        NSBezierPath(ovalIn: dotRect).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - 授权状态刷新（每 3 秒）

    private func startRefreshTimer() {
        refreshPermissionStatuses()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatuses()
        }
    }

    private func refreshPermissionStatuses() {
        let calOK = CalendarManager.shared.isAuthorized
        calStatusLabel?.stringValue = calOK ? "已授权" : "未授权"
        calStatusLabel?.textColor = calOK ? LingerTheme.stateSuccess : .secondaryLabelColor
        calButton?.title = calOK ? "管理…" : "开启"

        NotificationManager.shared.fetchAuthorizationStatus { [weak self] status in
            guard let self = self else { return }
            let ok = (status == .authorized)
            DispatchQueue.main.async {
                self.notifStatusLabel?.stringValue = ok ? "已授权" : "未授权"
                self.notifStatusLabel?.textColor = ok ? LingerTheme.stateSuccess : .secondaryLabelColor
                self.notifButton?.title = ok ? "管理…" : "开启"
            }
        }
    }

    /// 启动授权状态定时刷新（每 3 秒）。供 MenuBarManager 在打开窗口时显式调用。
    func startStatusRefresh() {
        startRefreshTimer()
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        startStatusRefresh()
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
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
}
