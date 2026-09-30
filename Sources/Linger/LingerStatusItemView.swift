//  LingerStatusItemView.swift
//  自定义状态栏视图：鼠标事件直接在视图层处理，绕开 NSStatusBarButton 的
//  cell tracking loop —— 旧方案（button.sendAction(on:)）的 tracking loop
//  会吞掉 mouseUp，导致拖拽状态机卡死在 .dragging、松手不计时。
//  这是该类老 bug 的根治方案。

import Cocoa

final class LingerStatusItemView: NSView {

    var onMouseDown: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var onRightMouseUp: (() -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    /// 内容宽度变化回调（2026-08-23）：
    /// AppKit 对「variableLength + custom view」只在内容变宽时自动跟随 intrinsicContentSize，
    /// 变窄不缩回 → 倒计时结束切回纯图标时菜单栏留大片空白。
    /// 因此每次 setIcon/setTitle 后把最新固有宽度上报，由持有 statusItem 的
    /// MenuBarManager 手动同步 statusItem.length（双向生效）。
    var onContentWidthChanged: ((CGFloat) -> Void)?

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var hasIcon = false
    /// 图标宽度约束（倒计时文本态收拢为 0，不留图标空位）
    private var iconWidthConstraint: NSLayoutConstraint!

    /// 菜单栏图标边长：2026-08-23 从 16 调到 18；2026-09-30 再调到 20
    /// （用户反馈「稍微小了一点，不太协调」）。
    /// 唯一真相源放在 MenuBarIconStyle.renderSize —— NSImage 的 size 与这里的约束
    /// 必须同档位，否则图标只按自身尺寸居中绘制，视觉上并没有变大。
    /// 素材是 36×36 PDF 矢量画板，按 20pt 渲染 Retina 下依然无损；
    /// 图标态固有宽度 = 2 + 20 + 2 + 2 = 26，与原先 max(26, 24) 的结果一致 ——
    /// 图标视觉变大一圈，菜单栏占位宽度不变，不会挤压倒计时文字。
    private static let iconSize: CGFloat = MenuBarIconStyle.renderSize

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        wantsLayer = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = LingerTheme.timeFont(size: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byClipping
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: Self.iconSize)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            imageView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setIcon(_ image: NSImage?) {
        imageView.image = image
        hasIcon = (image != nil)
        invalidateIntrinsicContentSize()
        onContentWidthChanged?(intrinsicContentSize.width)
    }

    func setTitle(_ text: String) {
        titleLabel.stringValue = text
        applyDisplayMode()
        invalidateIntrinsicContentSize()
        onContentWidthChanged?(intrinsicContentSize.width)
    }

    /// 显示模式（2026-08-23 用户需求）：有倒计时文字（含拖拽预览）→ 只显示时间，
    /// 图标隐藏且宽度收拢为 0；无文字（空闲）→ 只显示图标。
    private func applyDisplayMode() {
        let textMode = !titleLabel.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        imageView.isHidden = textMode
        iconWidthConstraint.constant = textMode ? 0 : Self.iconSize
    }

    /// 设置标题文字颜色（nil 恢复默认 labelColor；最后 10s 闪烁提醒用）
    func setTitleColor(_ color: NSColor?) {
        titleLabel.textColor = color ?? .labelColor
    }

    override var intrinsicContentSize: NSSize {
        // 文本态：2 + 0(图标收拢) + 2 + 文字 + 2；图标态：2 + iconSize + 2 + 2
        let textMode = !titleLabel.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        let width: CGFloat
        if textMode {
            width = 6 + titleLabel.intrinsicContentSize.width
        } else if hasIcon {
            width = 2 + Self.iconSize + 2 + 2
        } else {
            width = 8
        }
        return NSSize(width: max(26, width), height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    /// macOS 27 起，点击图标会先命中 NSImageView / NSTextField 子视图，
    /// 父视图的 mouseDown 不再可靠触发。图标与文字只负责绘制，所有点击
    /// 统一交给本容器，恢复按下拖拽、松开结束和右键菜单的事件链路。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        return self
    }

    /// 菜单栏 App 不在前台时，第一次点击默认只用于激活应用，AppKit 会立刻
    /// 合成 mouseUp，导致拖拽刚开始就结束。菜单栏图标必须接受 first mouse。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // 刻意不调用 super —— 阻止任何 tracking loop 介入，
    // 保证 mouseUp / mouseDragged 沿正常事件路径送达本视图。
    override func mouseDown(with event: NSEvent) {
        // ctrl+左键 = 右键语义（2026-08-24 用户需求，标准 Mac 交互）
        if event.modifierFlags.contains(.control) {
            onRightMouseUp?()
            return
        }
        onMouseDown?()
    }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
    override func rightMouseUp(with event: NSEvent) { onRightMouseUp?() }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}
