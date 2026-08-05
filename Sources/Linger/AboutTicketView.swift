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

    /// 离屏缓存：点状纹理 + 锯齿边只渲染一次（否则逐点 12 万个 oval 每帧重绘，
    /// 会在窗口高度动画期间卡死主线程 → 从矮到高看起来「瞬间跳变」）
    private var backgroundCache: CGImage?

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if backgroundCache == nil {
            backgroundCache = makeBackgroundCache(size: bounds.size)
        }
        if let cg = backgroundCache, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.draw(cg, in: bounds)   // 缩放 blit，动画期间快
        }
    }

    private func makeBackgroundCache(size: NSSize) -> CGImage? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx

        let bw = size.width, bh = size.height
        // 白纸底
        LingerTheme.nsColor(LingerTheme.Color.ticketPaper).setFill()
        NSRect(x: 0, y: 0, width: bw, height: bh).fill()

        // 点状纹理（双层）
        let dotColor = NSColor(calibratedWhite: 0, alpha: 0.015)
        dotColor.setFill()
        for yy in stride(from: 1, to: Int(bh), by: 3) {
            for xx in stride(from: 1, to: Int(bw), by: 3) {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(xx), y: CGFloat(yy), width: 1, height: 1)).fill()
            }
        }
        let dot2 = NSColor(calibratedWhite: 0, alpha: 0.010)
        dot2.setFill()
        for yy in stride(from: 2, to: Int(bh), by: 7) {
            for xx in stride(from: 2, to: Int(bw), by: 7) {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(xx), y: CGFloat(yy), width: 1, height: 1)).fill()
            }
        }

        // 上下锯齿边：黑点圆心与白纸上下边缘对齐（圆心 y=0 / y=bh）
        let notch = LingerTheme.nsColor(LingerTheme.Color.panelBgDark)
        notch.setFill()
        var x: CGFloat = 8
        while x < bw {
            NSBezierPath(ovalIn: NSRect(x: x - 5, y: -5, width: 10, height: 10)).fill()
            x += 16
        }
        x = 8
        while x < bw {
            NSBezierPath(ovalIn: NSRect(x: x - 5, y: bh - 5, width: 10, height: 10)).fill()
            x += 16
        }

        ctx?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    // MARK: - 头部

    private func makeHeader() -> NSView {
        let icon = makeAppIcon()

        let name = NSTextField(labelWithString: "Linger")
        name.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        name.textColor = Self.ticketInk

        let version = NSTextField(labelWithString: "Version 2.0.0")
        version.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        version.textColor = Self.ticketInk2

        let slogan = NSTextField(labelWithString: "一拉即走，松手计时")
        slogan.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        slogan.textColor = Self.ticketInk2

        let header = NSStackView(views: [icon, name, version, slogan])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 4
        header.setCustomSpacing(14, after: icon)
        header.setCustomSpacing(8, after: name)
        header.setCustomSpacing(6, after: version)
        return header
    }

    /// 48pt 琥珀渐变圆角图标 + Linger ring（外环 + 内点）
    private func makeAppIcon() -> NSView {
        let icon = NSView()
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 12
        icon.layer?.borderWidth = 1
        icon.layer?.borderColor = LingerTheme.amberGold.withAlphaComponent(0.25).cgColor

        let grad = CAGradientLayer()
        grad.colors = [LingerTheme.amberGold.withAlphaComponent(0.20).cgColor,
                       LingerTheme.amberGold.withAlphaComponent(0.06).cgColor]
        grad.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        icon.layer?.addSublayer(grad)

        let ring = CAShapeLayer()
        let r: CGFloat = 14
        ring.path = CGPath(ellipseIn: CGRect(x: 24 - r, y: 24 - r, width: r * 2, height: r * 2), transform: nil)
        ring.strokeColor = LingerTheme.amberGold.cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 2

        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: 24 - 3.5, y: 24 - 3.5, width: 7, height: 7), transform: nil)
        dot.fillColor = LingerTheme.amberGold.cgColor

        icon.layer?.addSublayer(ring)
        icon.layer?.addSublayer(dot)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48)
        ])
        return icon
    }

    // MARK: - 键值字段

    private func makeFields() -> NSView {
        // 原型占位字段（「你的名字」等待用户确认后替换）
        let fields: [(String, String, Bool)] = [
            ("Developer", "你的名字", false),
            ("Blog", "https://your.blog", true),
            ("Email", "hello@example.com", true),
            ("Build", "2026.08.02", true),
            ("License", "MIT", false)
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for f in fields {
            let row = makeField(label: f.0, value: f.1, mono: f.2)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeField(label: String, value: String, mono: Bool) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = Self.ticketInk3

        let v = NSTextField(labelWithString: value)
        v.font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                       : NSFont.systemFont(ofSize: 12)
        v.textColor = Self.ticketInk
        v.alignment = .right

        let row = NSStackView(views: [l, NSView(), v])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        // 弹性 spacer 把 value 推到右侧
        row.arrangedSubviews[1].setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 行距增高
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return row
    }

    // MARK: - 页脚

    private func makeFooter() -> NSView {
        let t1 = NSTextField(labelWithString: "Made with care · 感谢使用 Linger")
        t1.font = NSFont.systemFont(ofSize: 11)
        t1.textColor = Self.ticketInk3
        t1.alignment = .center

        let t2 = NSTextField(labelWithString: "— LINGER · 2026 —")
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
