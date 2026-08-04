//  DragLineView.swift
//  拖拽竖线 + 末端圆点的自定义绘制视图。
//  2026-08-04 第三轮：回归 2.0 的「紧致发光」做法（用户认可 2.0 观感）——
//    渐变线用紧致 NSShadow glow（radius 9，替代过宽的 16–18 散射光），
//    末端是实心亮金小圆点 + 紧致 glow（radius 5），不再叠加宽光晕带 / 白色核心。
//  溢出（橡皮筋）时线变细、圆点略放大，保留张力反馈。
//  铁律：无硬编码 #F5A623，全部走 LingerTheme。

import Cocoa

final class DragLineView: NSView {

    /// 当前竖线高度（含橡皮筋延伸部分，由 DragFeedbackView 传入）
    var lineHeight: CGFloat = 40 { didSet { needsDisplay = true } }
    /// 顶部留白（菜单栏下方起点）
    var topY: CGFloat = 12 { didSet { needsDisplay = true } }
    /// 是否越过最大长度（橡皮筋张力态）
    var isOverflowing: Bool = false { didSet { needsDisplay = true } }

    /// 圆点直径（溢出时 +2 放大；对齐 2.0：10pt）
    static let dotDiameter: CGFloat = 10

    private let lineWidthNormal: CGFloat = 4
    private let lineWidthOverflow: CGFloat = 3
    private let minLineHeight: CGFloat = 40

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let h = max(minLineHeight, lineHeight)
        let w = isOverflowing ? lineWidthOverflow : lineWidthNormal
        let midX = bounds.midX
        let lineTop = bounds.height - topY
        let lineRect = NSRect(x: midX - w / 2, y: lineTop - h, width: w, height: h)

        // 1) 渐变核心线 + 紧致 glow（2.0：shadowRadius 9，整体不散开才有「发光」实感）
        let corePath = NSBezierPath(roundedRect: lineRect, xRadius: w / 2, yRadius: w / 2)
        guard let gradient = NSGradient(colors: [
            LingerTheme.nsColor(LingerTheme.Color.amberDarker),
            LingerTheme.nsColor(LingerTheme.Color.amber),
            LingerTheme.nsColor(LingerTheme.Color.amberLight)
        ]) else { return }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow)
        glow.shadowBlurRadius = isOverflowing ? 12 : 9
        glow.shadowOffset = .zero
        glow.set()
        gradient.draw(in: corePath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 2) 末端圆点：实心亮金 + 紧致 glow（2.0：radius 5），压在线尖上
        let dotDiameter = isOverflowing ? Self.dotDiameter + 2 : Self.dotDiameter
        let dotCenter = NSPoint(x: midX, y: lineRect.minY)
        let dotRect = NSRect(x: dotCenter.x - dotDiameter / 2,
                             y: dotCenter.y - dotDiameter / 2,
                             width: dotDiameter,
                             height: dotDiameter)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSGraphicsContext.saveGraphicsState()
        let dotGlow = NSShadow()
        dotGlow.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow)
        dotGlow.shadowBlurRadius = isOverflowing ? 8 : 5
        dotGlow.shadowOffset = .zero
        dotGlow.set()
        LingerTheme.nsColor(LingerTheme.Color.amberLight).setFill()
        dotPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
