//  DragLineView.swift
//  拖拽竖线 + 末端圆点的自定义绘制视图。
//  2026-08-04 第八轮：Esc 取消动画按用户分镜实现（克制、无碎屑）：
//    1. 圆球从外向内收缩消失（0–22%，easeOut）
//    2. 线变到最细（4→1pt）同时颜色变暗（alpha 1→0.45）（22%–52%）
//    3. 整体向上收缩回菜单栏 icon（52%–100%，easeOut 收尾加速），末端淡出
//  线宽触顶后由 DragPhysics.lineWidth 公式连续变细；发光沿用 2.0 紧致做法。
//  铁律：无硬编码 #F5A623，全部走 LingerTheme。

import Cocoa

final class DragLineView: NSView {

    /// 当前竖线高度（含橡皮筋延伸部分，由 DragFeedbackView 传入）
    var lineHeight: CGFloat = 40 { didSet { needsDisplay = true } }
    /// 顶部留白（菜单栏下方起点）
    var topY: CGFloat = 12 { didSet { needsDisplay = true } }
    /// 当前线宽（触顶后由公式连续变细，DragFeedbackView 传入）
    var lineWidth: CGFloat = 4 { didSet { needsDisplay = true } }
    /// 是否越过最大长度（圆点略放大 + glow 稍强）
    var isOverflowing: Bool = false { didSet { needsDisplay = true } }
    /// Esc 取消动画进度 0→1（0=正常，1=完全收回消失）
    var breakProgress: CGFloat = 0 { didSet { needsDisplay = true } }

    /// 圆点直径（溢出时 +2 放大；对齐 2.0：10pt）
    static let dotDiameter: CGFloat = 10

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
        let w = max(1, lineWidth)
        let midX = bounds.midX
        let lineTop = bounds.height - topY

        func drawSegment(fromTop: CGFloat, height: CGFloat, alpha: CGFloat,
                         x: CGFloat = bounds.midX, width: CGFloat = max(1, lineWidth)) {
            guard height > 0.5 else { return }
            let rect = NSRect(x: x - width / 2, y: fromTop - height, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)
            guard let gradient = NSGradient(colors: [
                LingerTheme.nsColor(LingerTheme.Color.amberDarker).withAlphaComponent(alpha),
                LingerTheme.nsColor(LingerTheme.Color.amber).withAlphaComponent(alpha),
                LingerTheme.nsColor(LingerTheme.Color.amberLight).withAlphaComponent(alpha)
            ]) else { return }
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow).withAlphaComponent(alpha)
            glow.shadowBlurRadius = isOverflowing ? 12 : 9
            glow.shadowOffset = .zero
            glow.set()
            gradient.draw(in: path, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }

        func drawDot(center: NSPoint, diameter: CGFloat, alpha: CGFloat) {
            guard diameter > 0.5 else { return }
            let dotRect = NSRect(x: center.x - diameter / 2,
                                 y: center.y - diameter / 2,
                                 width: diameter,
                                 height: diameter)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            NSGraphicsContext.saveGraphicsState()
            let dotGlow = NSShadow()
            dotGlow.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow).withAlphaComponent(alpha)
            dotGlow.shadowBlurRadius = isOverflowing ? 8 : 5
            dotGlow.shadowOffset = .zero
            dotGlow.set()
            LingerTheme.nsColor(LingerTheme.Color.amberLight).withAlphaComponent(alpha).setFill()
            dotPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let dotDiameter = isOverflowing ? Self.dotDiameter + 2 : Self.dotDiameter

        guard breakProgress > 0 else {
            drawSegment(fromTop: lineTop, height: h, alpha: 1, x: midX, width: w)
            drawDot(center: NSPoint(x: midX, y: lineTop - h), diameter: dotDiameter, alpha: 1)
            return
        }

        // ===== Esc 收回动画（用户分镜）=====
        let t = min(1, breakProgress)

        // 1) 圆球从外向内收缩消失（0–22%，easeOut）
        let dotPhase = min(1, t / 0.22)
        let dotEase = 1 - pow(1 - dotPhase, 2)
        let dotD = dotDiameter * (1 - dotEase)          // → 0

        // 2) 线变到最细 + 颜色变暗（22%–52%）
        let thinPhase = min(1, max(0, (t - 0.22) / 0.30))
        let thinW = max(1, w * (1 - thinPhase * 0.75))  // 当前宽 → 1pt
        let darkAlpha = 1 - thinPhase * 0.55            // 1 → 0.45（变暗）

        // 3) 整体向上收缩回 icon（52%–100%，easeOut 收尾加速）
        let retractPhase = min(1, max(0, (t - 0.52) / 0.48))
        let retractEase = 1 - pow(1 - retractPhase, 2)
        let segH = h * (1 - retractEase)                // h → 0
        let segTop = lineTop + retractEase * 8          // 顶部微收进菜单栏

        // 末端 15% 快速淡出
        let fade = t > 0.85 ? max(0, 1 - (t - 0.85) / 0.15) : 1
        let alpha = darkAlpha * fade

        drawSegment(fromTop: segTop, height: segH, alpha: alpha, x: midX, width: thinW)
        if dotD > 0.5 {
            drawDot(center: NSPoint(x: midX, y: lineTop - h), diameter: dotD, alpha: alpha)
        }
    }
}
