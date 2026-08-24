//  AboutTicketView.swift
//  设置「关于」票据面板 —— 对齐 settings-window.html .ticket：
//    白底纸张 #faf9f6 + 双层点状纹理 + 上下锯齿边（挖空成窗口背景色）+ 圆角 10
//    + 虚线分割（两端剪刀口）+ 头部图标/名称/版本/Slogan + 键值字段 + 页脚。
//  铁律：颜色走 LingerTheme；票据深色文字用局部令牌（原型 #1d1d1f / #6e6e73 / #8e8e93）。

import Cocoa

final class AboutTicketView: NSView {

    // 票据深色文字（白纸上的深色，与暗色窗口强对比；铁律：走 LingerTheme）
    private static let ticketInk  = LingerTheme.nsColor(LingerTheme.Color.ticketInk)
    private static let ticketInk2 = LingerTheme.nsColor(LingerTheme.Color.ticketInk2)
    private static let ticketInk3 = LingerTheme.nsColor(LingerTheme.Color.ticketInk3)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.ticketPaper).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.08).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26)
        ])

        // 用户要求：所有行距增高（header / 虚线 / fields / footer 之间拉开）
        let header = makeHeader()
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(20, after: header)
        let d1 = makeDashed()
        stack.addArrangedSubview(d1)
        stack.setCustomSpacing(20, after: d1)
        let fields = makeFields()
        stack.addArrangedSubview(fields)
        stack.setCustomSpacing(20, after: fields)
        stack.addArrangedSubview(makeDashed())
        let footer = makeFooter()
        stack.addArrangedSubview(footer)
        stack.setCustomSpacing(22, after: footer)
    }

    /// 2026-08-23 增强：热敏纸粗糙纹理（三层点阵 + 一层纤维竖纹）
    private lazy var paperPattern: NSColor = makePattern(dotAlpha: 0.035, spacing: 3)
    private lazy var paperPattern2: NSColor = makePattern(dotAlpha: 0.025, spacing: 7)
    private lazy var paperPattern3: NSColor = makePattern(dotAlpha: 0.015, spacing: 13)
    private lazy var paperLines: NSColor = makeLinePattern(alpha: 0.05, spacing: 4)

    private func makePattern(dotAlpha: CGFloat, spacing: CGFloat) -> NSColor {
        let size = NSSize(width: spacing, height: spacing)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedWhite: 0, alpha: dotAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: (spacing - 1) / 2, y: (spacing - 1) / 2, width: 1, height: 1)).fill()
        image.unlockFocus()
        return NSColor(patternImage: image)
    }

    /// 细垂直线纹理（模拟热敏纸纤维纹路）
    private func makeLinePattern(alpha: CGFloat, spacing: CGFloat) -> NSColor {
        let size = NSSize(width: spacing, height: spacing)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedWhite: 0, alpha: alpha).setFill()
        NSRect(x: spacing * 0.5 - 0.5, y: 0, width: 1, height: spacing).fill()
        image.unlockFocus()
        return NSColor(patternImage: image)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 白纸底
        LingerTheme.nsColor(LingerTheme.Color.ticketPaper).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height).fill()

        // 点状纹理（三层叠加，制造粗糙纸面感）
        paperPattern.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height).fill()
        paperPattern2.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height).fill()
        paperPattern3.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height).fill()
        // 纤维竖纹（热敏纸质感）
        paperLines.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height).fill()

        // 上下锯齿边：黑点圆心与白纸上下边缘对齐（圆心 y=0 / y=bounds.height）
        let notch = LingerTheme.nsColor(LingerTheme.Color.panelBgDark)
        notch.setFill()
        var x: CGFloat = 8
        while x < bounds.width {
            NSBezierPath(ovalIn: NSRect(x: x - 5, y: -5, width: 10, height: 10)).fill()
            x += 16
        }
        x = 8
        while x < bounds.width {
            NSBezierPath(ovalIn: NSRect(x: x - 5, y: bounds.height - 5, width: 10, height: 10)).fill()
            x += 16
        }
    }

    // MARK: - 头部

    private func makeHeader() -> NSView {
        let icon = makeAppIcon()

        let name = NSTextField(labelWithString: "Linger")
        name.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        name.textColor = Self.ticketInk

        let version = NSTextField(labelWithString: "Version 2.5.0")
        version.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        version.textColor = Self.ticketInk2

        let header = NSStackView(views: [icon, name, version])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 4
        header.setCustomSpacing(14, after: icon)
        header.setCustomSpacing(8, after: name)
        return header
    }

    /// 48pt 应用图标（Support/LingerIcon-Fullbleed.png，与 app/Dock 图标同源）
    private func makeAppIcon() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        if let img = loadImage("LingerIcon-Fullbleed") {
            let iv = NSImageView(image: img)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                iv.topAnchor.constraint(equalTo: container.topAnchor),
                iv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 48),
            container.heightAnchor.constraint(equalToConstant: 48)
        ])
        return container
    }

    /// 从 SwiftPM 资源 bundle 加载（与 MenuBarManager.loadImage 同款）。
    /// 2026-08-24 修复：.copy 资源在子目录里，url(forResource:) 不搜子目录 → 之前加载 nil
    private func loadImage(_ name: String) -> NSImage? {
        if let img = NSImage(named: name) { return img }
        for ext in ["png", "pdf"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext,
                                           subdirectory: "AboutAssets"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }

    // MARK: - 键值字段

    /// 小红书品牌红（#FF2442，外部品牌色，不属于 LingerTheme 设计系统 → 局部令牌）
    private static let xhsRed = NSColor(srgbRed: 1.0, green: 0.141, blue: 0.259, alpha: 1)

    private func makeFields() -> NSView {
        // 2026-08-24 用户定稿内容；Release Date 每次发版时更新
        // Blog/Email 为可点击链接（默认浏览器 / 默认邮件 app）
        let fields: [(String, String, Bool, NSView?, URL?)] = [
            ("Developer", "早餐酒", false, nil, nil),
            ("Blog", "https://xhslink.cn/m/5Ky2s8BvViA", true, makeXhsIcon(),
             URL(string: "https://xhslink.cn/m/5Ky2s8BvViA")),
            ("Email", "breakfastwine@agent.qq.com", true, nil,
             URL(string: "mailto:breakfastwine@agent.qq.com")),
            ("Release Date", "2026.08.24", true, nil, nil)
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for f in fields {
            let row = makeField(label: f.0, value: f.1, mono: f.2,
                                leadingIcon: f.3, linkURL: f.4)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeField(label: String, value: String, mono: Bool,
                           leadingIcon: NSView? = nil, linkURL: URL? = nil) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = Self.ticketInk3

        let v: NSTextField
        if let url = linkURL {
            let link = LinkLabel(labelWithString: value,
                                 font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular))
            link.onOpen = { NSWorkspace.shared.open(url) }
            v = link
        } else {
            v = NSTextField(labelWithString: value)
            v.font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                          : NSFont.systemFont(ofSize: 12)
            v.textColor = Self.ticketInk
        }
        v.alignment = .right

        // 值文字（含可选前置 icon）：icon 与文字同高、垂直居中
        let valueStack = NSStackView(views: leadingIcon.map { [$0, v] } ?? [v])
        valueStack.orientation = .horizontal
        valueStack.alignment = .centerY
        valueStack.spacing = 4

        let row = NSStackView(views: [l, NSView(), valueStack])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        // 弹性 spacer 把 value 推到右侧
        row.arrangedSubviews[1].setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 行距增高
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return row
    }

    /// 小红书 icon：SF Symbol book.fill + 小红书红，与值文字（mono 11pt）同高，不突兀
    private func makeXhsIcon() -> NSView {
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "book.fill", accessibilityDescription: "小红书")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        iv.contentTintColor = Self.xhsRed
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 12),
            iv.heightAnchor.constraint(equalToConstant: 12)
        ])
        return iv
    }

    // MARK: - 页脚

    private func makeFooter() -> NSView {
        let t1 = NSTextField(labelWithString: "酒后制造")
        t1.font = NSFont.systemFont(ofSize: 12)
        t1.textColor = Self.ticketInk3
        t1.alignment = .center

        let t2 = NSTextField(labelWithString: "Made while drunk")
        t2.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        t2.textColor = LingerTheme.nsColor(LingerTheme.Color.ticketInk4)
        t2.alignment = .center

        let footer = NSStackView(views: [t1, t2])
        footer.orientation = .vertical
        footer.alignment = .centerX
        footer.spacing = 6
        return footer
    }

    private func makeDashed() -> NSView {
        let v = DashedSeparatorView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}

/// 可点击链接文字：amberDarker + 下划线（白纸上对比度足），hover 指针变手型，
/// 点击调 onOpen（浏览器 / 邮件 app）。点击热区为整个 label bounds。
private final class LinkLabel: NSTextField {
    var onOpen: (() -> Void)?
    private var isHovering = false
    private var tracking: NSTrackingArea?

    init(labelWithString string: String, font: NSFont) {
        super.init(frame: .zero)
        isEditable = false
        isBezeled = false
        drawsBackground = false
        self.font = font
        stringValue = string
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateStyle() {
        let color = LingerTheme.nsColor(LingerTheme.Color.amberDarker)
        attributedStringValue = NSAttributedString(
            string: stringValue,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: color
            ])
        toolTip = "点击打开"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.pointingHand.pop()
    }

    override func mouseDown(with event: NSEvent) {
        // 记录 hover 态，mouseUp 时若仍在热区内才触发（标准按钮语义，防拖出误触）
        isHovering = true
    }

    override func mouseUp(with event: NSEvent) {
        if isHovering { onOpen?() }
        isHovering = false
    }
}

/// 虚线分割（4px 虚线 + 两端剪刀口圆，挖空成窗口背景色）
private final class DashedSeparatorView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        // 虚线
        let dash = NSColor(calibratedWhite: 0, alpha: 0.12)
        dash.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        var x: CGFloat = 0
        while x < bounds.width {
            path.move(to: NSPoint(x: x, y: 0.5))
            path.line(to: NSPoint(x: min(x + 4, bounds.width), y: 0.5))
            x += 9
        }
        path.stroke()

        // 两端剪刀口圆
        let notch = LingerTheme.nsColor(LingerTheme.Color.panelBgDark)
        notch.setFill()
        for cx in [CGFloat(0), bounds.width] {
            NSBezierPath(ovalIn: NSRect(x: cx - 5, y: 0.5 - 5, width: 10, height: 10)).fill()
        }
    }
}
