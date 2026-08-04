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

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var hasIcon = false

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

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
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
    }

    func setTitle(_ text: String) {
        titleLabel.stringValue = text
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        var width: CGFloat = 4
        if hasIcon { width += 16 + 2 }
        width += titleLabel.intrinsicContentSize.width
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

    // 刻意不调用 super —— 阻止任何 tracking loop 介入，
    // 保证 mouseUp / mouseDragged 沿正常事件路径送达本视图。
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
    override func rightMouseUp(with event: NSEvent) { onRightMouseUp?() }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}
