//  CompletionBanner.swift
//  倒计时完成弹窗（强提醒）—— 自绘玻璃横幅，替换系统通知（2026-08-06）
//
//  对齐原型 notification-inline.html + PRD §3.4：
//   - 300pt 毛玻璃圆角横幅，右上角纵向堆叠
//   - 标题行：Ring 图标 + Linger + ✓（circle-check 绿）+ 时间戳「现在」+ 关闭 ✕
//   - 内容行：日程模块（有标题显名 / 无标题内联输入）+ 记录时间 mm:ss + 重复 ↻ + 确认 ✓
//   - 交互全程在横幅内完成，不唤醒/不抢占焦点；8s 无交互自动淡出
//   - 尊重「完成弹窗」开关（linger_notifyOnComplete，默认开）

import Cocoa
import os.log

// MARK: - 管理器

final class CompletionBannerManager {

    static let shared = CompletionBannerManager()

    private let log = OSLog(subsystem: "com.linger.timer", category: "CompletionBanner")
    private var banners: [CompletionBannerWindow] = []
    private let bannerWidth: CGFloat = 300
    private let bannerHeight: CGFloat = 82
    private let bannerGap: CGFloat = 8
    private let edgeMargin: CGFloat = 12

    private init() {
        NotificationCenter.default.addObserver(
            forName: timerDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleTimerDidFinish(note)
        }
    }

    private func handleTimerDidFinish(_ note: Notification) {
        guard let entry = note.object as? TimerEntry else { return }
        let key = LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue
        let enabled = UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
        guard enabled else {
            os_log("Completion banner disabled, skip", log: log, type: .debug)
            return
        }
        show(entry: entry)
    }

    private func show(entry: TimerEntry) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // 位置由用户设置决定（topRight / center），默认 topRight
        let positionRaw = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.bannerPosition.rawValue) ?? "topRight"
        let isCenter = positionRaw == "center"

        let rect: NSRect
        if isCenter {
            // 屏幕正中央：多横幅垂直堆叠在中心
            let totalStackH = bannerHeight + CGFloat(banners.count) * (bannerHeight + bannerGap)
            let baseY = visible.midY + totalStackH / 2 - bannerHeight
            var y = baseY
            if let last = banners.last {
                y = min(y, last.frame.minY - bannerGap - bannerHeight)
            }
            rect = NSRect(x: visible.midX - bannerWidth / 2,
                          y: y,
                          width: bannerWidth,
                          height: bannerHeight)
        } else {
            // 右上角：最新横幅在最上，已有横幅依次下移
            let topY = visible.maxY - edgeMargin
            var y = topY - bannerHeight
            if let last = banners.last {
                y = min(y, last.frame.minY - bannerGap - bannerHeight)
            }
            rect = NSRect(x: visible.maxX - edgeMargin - bannerWidth,
                          y: y,
                          width: bannerWidth,
                          height: bannerHeight)
        }
        let banner = CompletionBannerWindow(entry: entry, frame: rect, manager: self)
        banners.append(banner)
        banner.show()
        os_log("Banner shown for entry %{public}@ at %s", log: log, type: .info, entry.id.uuidString, isCenter ? "center" : "topRight")
    }

    fileprivate func dismiss(_ banner: CompletionBannerWindow) {
        banner.dismissAnimated()
        banners.removeAll { $0 === banner }
    }

    fileprivate func dismissAll() {
        let all = banners
        banners.removeAll()
        all.forEach { $0.dismissAnimated() }
    }
}

// MARK: - 横幅窗口

final class CompletionBannerWindow: NSWindow {

    private weak var manager: CompletionBannerManager?
    private let entry: TimerEntry
    private var dismissWorkItem: DispatchWorkItem?
    private let autoDismissAfter: TimeInterval = 8.0

    init(entry: TimerEntry, frame: NSRect, manager: CompletionBannerManager) {
        self.entry = entry
        self.manager = manager
        super.init(contentRect: frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = CompletionBannerView(entry: entry,
                                        onClose: { [weak self] in
                                            guard let self else { return }
                                            self.manager?.dismiss(self)
                                        },
                                        onRepeat: { [weak self] in
                                            guard let self else { return }
                                            // 重复时带入原标题，避免新计时丢标题
                                            _ = TimerManager.shared.addTimer(
                                                duration: entry.duration,
                                                predefinedTitle: entry.predefinedTitle
                                            )
                                            os_log("Banner repeat: new timer %.0fs title=%{public}@", log: OSLog(subsystem: "com.linger.timer", category: "CompletionBanner"), type: .info, entry.duration, entry.predefinedTitle ?? "(nil)")
                                            self.manager?.dismiss(self)
                                        },
                                        onConfirm: { [weak self] title in
                                            guard let self else { return }
                                            CalendarRecorder.shared.recordFromBanner(entry, title: title)
                                            self.manager?.dismiss(self)
                                        },
                                        onBeginEditing: { [weak self] in
                                            // 输入日程标题时暂停自动消失，避免被打断
                                            self?.dismissWorkItem?.cancel()
                                        },
                                        onEndEditing: { [weak self] in
                                            self?.scheduleAutoDismiss()
                                        })
        contentView = view
        setContentSize(frame.size)
    }

    /// 无边框 statusBar 窗口在 .accessory 应用里点击输入框需强制 key（复用 hover 列表经验）
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    func show() {
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.manager?.dismiss(self)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter, execute: work)
    }

    func dismissAnimated() {
        dismissWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.contentView = nil
        })
    }
}

// MARK: - 横幅视图

final class CompletionBannerView: NSView {

    private let entry: TimerEntry
    private let onClose: () -> Void
    private let onRepeat: () -> Void
    private let onConfirm: (String?) -> Void
    private let onBeginEditing: () -> Void
    private let onEndEditing: () -> Void

    private let titleField: NSTextField
    private let timeLabel: NSTextField
    private let closeButton: NSButton
    private let repeatButton: NSButton
    private let confirmButton: NSButton

    // 无标题时的内联输入
    private let scheduleInput: NSTextField?
    private let scheduleLabel: NSTextField?

    init(entry: TimerEntry,
         onClose: @escaping () -> Void,
         onRepeat: @escaping () -> Void,
         onConfirm: @escaping (String?) -> Void,
         onBeginEditing: @escaping () -> Void = {},
         onEndEditing: @escaping () -> Void = {}) {
        self.entry = entry
        self.onClose = onClose
        self.onRepeat = onRepeat
        self.onConfirm = onConfirm
        self.onBeginEditing = onBeginEditing
        self.onEndEditing = onEndEditing

        let hasTitle = !(entry.predefinedTitle ?? "").isEmpty

        // —— 标题行 ——
        titleField = NSTextField(labelWithString: "Linger")
        titleField.font = LingerTheme.labelFont(size: 12, weight: .semibold)
        titleField.textColor = LingerTheme.ink
        timeLabel = NSTextField(labelWithString: "现在")
        timeLabel.font = LingerTheme.labelFont(size: 11)
        timeLabel.textColor = LingerTheme.ink3

        closeButton = Self.makeIconButton("xmark", pointSize: 10)
        repeatButton = Self.makeIconButton("arrow.counterclockwise", pointSize: 14)
        confirmButton = Self.makeIconButton("checkmark", pointSize: 14)

        // —— 内容行 ——
        if hasTitle {
            scheduleInput = nil
            scheduleLabel = NSTextField(labelWithString: entry.predefinedTitle!)
            scheduleLabel!.font = LingerTheme.labelFont(size: 13, weight: .medium)
            scheduleLabel!.textColor = LingerTheme.ink
            scheduleLabel!.lineBreakMode = .byTruncatingTail
        } else {
            scheduleLabel = nil
            let field = NSTextField()
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = LingerTheme.labelFont(size: 13, weight: .medium)
            field.textColor = LingerTheme.ink
            field.placeholderString = "日程"
            field.usesSingleLineMode = true
            field.isEditable = true
            field.isSelectable = true
            field.isEnabled = true
            scheduleInput = field
        }

        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 82))

        wantsLayer = true
        // 玻璃底：NSVisualEffectView + 圆角 + 边框
        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = LingerTheme.radiusLG
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        addSubview(glass)

        // 标题行：Ring + Linger + ✓ + spacer + 现在 + ✕
        let ring = Self.makeRingIcon(color: LingerTheme.amberGold, size: 16)
        let ringView = NSImageView(image: ring)
        let check = NSImage(systemSymbolName: "checkmark.circle.fill",
                            accessibilityDescription: "完成")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        let checkView = NSImageView(image: check ?? NSImage())
        checkView.contentTintColor = LingerTheme.stateSuccess

        let titleStack = NSStackView(views: [ringView, titleField, checkView,
                                             Self.spacer(), timeLabel, closeButton])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleStack)

        // 内容行：日程模块 + mm:ss + ↻ + ✓
        let timeText = TimerEntry.displayString(seconds: entry.duration, format: "ms")
        let timeCapsule = Self.makeTimeCapsule(text: timeText)

        let scheduleModule = makeScheduleModule()
        let contentStack = NSStackView(views: [scheduleModule, timeCapsule, repeatButton, confirmButton])
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        // 布局：标题行贴顶，内容行贴底，均水平 12pt padding
        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            repeatButton.widthAnchor.constraint(equalToConstant: 28),
            repeatButton.heightAnchor.constraint(equalToConstant: 28),
            confirmButton.widthAnchor.constraint(equalToConstant: 28),
            confirmButton.heightAnchor.constraint(equalToConstant: 28),
            scheduleModule.heightAnchor.constraint(equalToConstant: 28),
            timeCapsule.heightAnchor.constraint(equalToConstant: 28)
        ])

        closeButton.target = self
        closeButton.action = #selector(closeTapped(_:))
        repeatButton.target = self
        repeatButton.action = #selector(repeatTapped(_:))
        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped(_:))
        if let field = scheduleInput {
            field.delegate = self
            field.target = self
            field.action = #selector(confirmTapped(_:))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 子模块

    private func makeScheduleModule() -> NSView {
        let module = NSView()
        module.wantsLayer = true
        module.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.input).cgColor
        module.layer?.cornerRadius = LingerTheme.radiusSM

        if let label = scheduleLabel {
            label.translatesAutoresizingMaskIntoConstraints = false
            module.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: module.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: module.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: module.centerYAnchor)
            ])
        } else if let field = scheduleInput {
            let pencil = NSImageView()
            pencil.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "日程")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            pencil.contentTintColor = LingerTheme.ink3
            pencil.widthAnchor.constraint(equalToConstant: 12).isActive = true
            pencil.heightAnchor.constraint(equalToConstant: 12).isActive = true
            let stack = NSStackView(views: [pencil, field])
            stack.orientation = .horizontal
            stack.spacing = 5
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
            module.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: module.leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: module.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: module.centerYAnchor)
            ])
        }
        module.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return module
    }

    private static func makeTimeCapsule(text: String) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.input).cgColor
        cap.layer?.cornerRadius = LingerTheme.radiusSM
        let label = NSTextField(labelWithString: text)
        label.font = LingerTheme.timeFont(size: 13, weight: .semibold)
        label.textColor = LingerTheme.amberGold
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: cap.centerYAnchor)
        ])
        return cap
    }

    private static func makeIconButton(_ symbol: String, pointSize: CGFloat) -> NSButton {
        let btn = BannerIconButton()
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        btn.contentTintColor = LingerTheme.ink2
        return btn
    }

    private static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    /// Ring 图标（琥珀描边环 + 实心点），对齐菜单栏图标
    private static func makeRingIcon(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.setStroke()
        color.setFill()
        let inset = size * 0.12
        let ringRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = 1.6
        ring.stroke()
        let dotR = size * 0.13
        NSBezierPath(ovalIn: NSRect(x: size / 2 - dotR, y: size / 2 - dotR,
                                    width: dotR * 2, height: dotR * 2)).fill()
        img.unlockFocus()
        return img
    }

    // MARK: - 动作

    @objc private func closeTapped(_ sender: Any?) { onClose() }
    @objc private func repeatTapped(_ sender: Any?) { onRepeat() }
    @objc private func confirmTapped(_ sender: Any?) {
        if let field = scheduleInput {
            let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            onConfirm(typed.isEmpty ? nil : typed)
        } else {
            onConfirm(nil)
        }
    }
}

// MARK: - 图标按钮（hover 琥珀，对齐原型 button hover）

private final class BannerIconButton: NSButton {

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        contentTintColor = LingerTheme.amberGold
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        contentTintColor = LingerTheme.ink2
    }
}

// MARK: - 输入框回车提交

extension CompletionBannerView: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        onBeginEditing()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onEndEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmTapped(nil)
            return true
        }
        return false
    }
}
