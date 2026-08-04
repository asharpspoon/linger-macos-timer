//  DragLineView.swift
//  拖拽竖线 + 末端圆点的自定义绘制视图。
//  2026-08-04 第四轮：
//    - 线宽不再二值跳变（4→3），改由 DragPhysics.lineWidth 按 overshoot 连续变细
//    - Esc 断线动画：breakProgress 0→1 时线条从中间裂成两段、圆点下坠、整体淡出
//    - 发光沿用 2.0 紧致做法（线 glow 9 / 圆点 5，实心亮金圆点）
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
    /// Esc 断线动画进度 0→1（0=正常，1=完全断开）
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

        func drawSegment(fromTop: CGFloat, height: CGFloat, alpha: CGFloat) {
            guard height > 0.5 else { return }
            let rect = NSRect(x: midX - w / 2, y: fromTop - height, width: w, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: w / 2, yRadius: w / 2)
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
            drawSegment(fromTop: lineTop, height: h, alpha: 1)
            drawDot(center: NSPoint(x: midX, y: lineTop - h), diameter: dotDiameter, alpha: 1)
            return
        }

        // Esc 断线特效（两阶段）：
        //   t∈[0,0.5) 断裂期：从中间裂开，缝逐渐扩大（两段保持钉在原位）
        //   t∈[0.5,1] 坠落期：上段向上缩回菜单栏，下段带圆点加速下坠（重力感）并淡出
        let t = min(1, breakProgress)
        let alpha = 1 - t * t * 0.92   // 后期加速淡出

        if t < 0.5 {
            let phase = t / 0.5
            let gap = phase * 30
            let segH = max(0, (h - gap) / 2)
            drawSegment(fromTop: lineTop, height: segH, alpha: alpha)
            let lowerTop = lineTop - gap
            drawSegment(fromTop: lowerTop, height: segH, alpha: alpha)
            drawDot(center: NSPoint(x: midX, y: lowerTop - segH), diameter: dotDiameter, alpha: alpha)
        } else {
            let phase = (t - 0.5) / 0.5
            let baseSegH = max(0, (h - 30) / 2)
            // 上段向上缩回
            let upperH = baseSegH * (1 - phase * 0.85)
            drawSegment(fromTop: lineTop, height: upperH, alpha: alpha)
            // 下段 + 圆点重力下坠（phase² 加速），掉出面板底
            let drop = phase * phase * 300
            let lowerTop = lineTop - 30 - drop
            drawSegment(fromTop: lowerTop, height: baseSegH, alpha: alpha)
            drawDot(center: NSPoint(x: midX, y: lowerTop - baseSegH), diameter: dotDiameter, alpha: alpha)
        }
    }
}
