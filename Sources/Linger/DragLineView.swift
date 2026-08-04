//  DragLineView.swift
//  拖拽竖线 + 末端光点的自定义绘制视图。
//  2026-08-04 重构：放弃纯 CALayer 拼装（阴影不可见、圆点生硬），
//  改为 draw(_:) 手绘——外发光晕 + 渐变核心线（NSShadow 辉光）+ 径向渐变光点，
//  溢出（橡皮筋）时线变细、光点变大变亮，模拟「拉到最下方」的张力反馈。
//  铁律：无硬编码 #F5A623，全部走 LingerTheme。

import Cocoa

final class DragLineView: NSView {

    /// 当前竖线高度（含橡皮筋延伸部分，由 DragFeedbackView 传入）
    var lineHeight: CGFloat = 40 { didSet { needsDisplay = true } }
    /// 顶部留白（菜单栏下方起点）
    var topY: CGFloat = 12 { didSet { needsDisplay = true } }
    /// 是否越过最大长度（橡皮筋张力态）
    var isOverflowing: Bool = false { didSet { needsDisplay = true } }
    /// 橡皮筋延伸量（仅用于光点微调，不影响布局——布局已含在 lineHeight 里）
    var rubberOvershoot: CGFloat = 0 { didSet { needsDisplay = true } }

    /// 光点直径（溢出时 +2 放大）
    static let dotDiameter: CGFloat = 12

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

        // 1) 外发光晕：一条宽而淡的琥珀带，给「发光」打底（即使核心 glow 被系统压掉也可见）
        let haloWidth: CGFloat = 18
        let haloRect = NSRect(x: midX - haloWidth / 2, y: lineRect.minY, width: haloWidth, height: h)
        let haloPath = NSBezierPath(roundedRect: haloRect, xRadius: haloWidth / 2, yRadius: haloWidth / 2)
        LingerTheme.nsColor(LingerTheme.Color.amberGlow)
            .withAlphaComponent(isOverflowing ? 0.34 : 0.22)
            .setFill()
        haloPath.fill()

        // 2) 核心渐变线 + NSShadow 辉光（上深铜 → 中琥珀 → 下亮金）
        let corePath = NSBezierPath(roundedRect: lineRect, xRadius: w / 2, yRadius: w / 2)
        guard let gradient = NSGradient(colors: [
            LingerTheme.nsColor(LingerTheme.Color.amberDarker),
            LingerTheme.nsColor(LingerTheme.Color.amber),
            LingerTheme.nsColor(LingerTheme.Color.amberLight)
        ]) else { return }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow)
        glow.shadowBlurRadius = isOverflowing ? 22 : 16
        glow.shadowOffset = .zero
        glow.set()
        gradient.draw(in: corePath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 3) 末端光点：径向渐变（亮金核心 → 透明晕），光心压在线尖上，和竖线融为一体
        let dotDiameter = isOverflowing ? Self.dotDiameter + 2 : Self.dotDiameter
        let dotCenter = NSPoint(x: midX, y: lineRect.minY)
        let dotRect = NSRect(x: dotCenter.x - dotDiameter / 2,
                             y: dotCenter.y - dotDiameter / 2,
                             width: dotDiameter,
                             height: dotDiameter)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        if let dotGradient = NSGradient(colorsAndLocations:
            (LingerTheme.nsColor(LingerTheme.Color.amberLighter), 0.0),
            (LingerTheme.nsColor(LingerTheme.Color.amber), 0.5),
            (LingerTheme.nsColor(LingerTheme.Color.amberGlow).withAlphaComponent(0), 1.0)
        ) {
            dotGradient.draw(in: dotPath, relativeCenterPosition: .zero)
        }

        // 光点核心高亮（一小颗暖白，让「发光」有光源感）
        let coreRadius: CGFloat = isOverflowing ? 2.2 : 1.8
        let highlightCorePath = NSBezierPath(ovalIn: NSRect(x: dotCenter.x - coreRadius,
                                                             y: dotCenter.y - coreRadius,
                                                             width: coreRadius * 2,
                                                             height: coreRadius * 2))
        NSColor(calibratedWhite: 1.0, alpha: isOverflowing ? 0.95 : 0.85).setFill()
        highlightCorePath.fill()
    }
}
