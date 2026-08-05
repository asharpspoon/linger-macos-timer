//  TabButtonView.swift
//  自定义 Tab 按钮（NSButton 的 imageAbove 无法控制 icon 与文字间距）。
//    垂直排布：icon 27pt + spacing 8 + label 10pt；点击回调；激活态琥珀样式。
//  铁律：颜色/字号走 LingerTheme。

import Cocoa

final class TabButtonView: NSControl {

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var isActive: Bool = false {
        didSet { updateStyle() }
    }

    private let index: Int
    private var onClick: ((Int) -> Void)?

    init(title: String, icon: String, index: Int, onClick: @escaping (Int) -> Void) {
        self.index = index
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 27, weight: .medium))
        iconView.image?.isTemplate = true

        label.stringValue = title
        label.font = LingerTheme.labelFont(size: 10, weight: .medium)
        label.alignment = .center

        // icon 与文字间距调远（用户要求 8pt）
        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 必须实现 intrinsicContentSize，否则 NSStackView 里按钮尺寸塌缩为 0 → tab 栏消失
    override var intrinsicContentSize: NSSize {
        let iconW = iconView.image?.size.width ?? 27
        let labelW = label.intrinsicContentSize.width
        let w = max(iconW, labelW)
        let h = 27 + 8 + label.intrinsicContentSize.height   // icon + 间距 + label
        return NSSize(width: max(36, w + 8), height: max(48, h))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(index)
    }

    private func updateStyle() {
        let color = isActive ? LingerTheme.amberGold : LingerTheme.ink3
        iconView.contentTintColor = color
        label.textColor = color
        layer?.backgroundColor = isActive
            ? LingerTheme.amberGold.withAlphaComponent(0.08).cgColor
            : NSColor.clear.cgColor
    }
}
