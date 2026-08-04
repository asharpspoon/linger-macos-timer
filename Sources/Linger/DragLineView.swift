//  DragLineView.swift
//  拖拽竖线 + 末端圆点的自定义绘制视图。
//  2026-08-04 第七轮：Esc 断线改为「灯绳拉断」物理感特效（不再是 PPT 式平移淡出）：
//    1. 张力期（0–15%）：整根线高频颤动，断口处颈缩出 1pt 细丝 + 两侧纤维毛刺
//    2. 啪断（15%）：细丝拉断，上段向上弹、下段向下弹
//    3. 坠落期（15–55%）：上段加速缩回菜单栏；下段带圆点重力坠出 + 尾部钟摆甩动；
//       断口碎屑向两侧飞散；55% 后整体淡出
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
    /// Esc 断线动画进度 0→1（0=正常，1=完全断掉消失）
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

        func drawSegment(fromTop: CGFloat, height: CGFloat, alpha: CGFloat, x: CGFloat = bounds.midX) {
            guard height > 0.5 else { return }
            let rect = NSRect(x: x - w / 2, y: fromTop - height, width: w, height: height)
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

        // ============ 灯绳拉断特效 ============
        let t = min(1, breakProgress)
        let tensionEnd: CGFloat = 0.15   // 张力颤动期
        let fallEnd: CGFloat = 0.55      // 坠落期结束（之后整体淡出）
        let alpha = t >= fallEnd ? max(0, 1 - (t - fallEnd) / (1 - fallEnd)) : 1

        let breakY = lineTop - h / 2     // 初始断口（线正中）
        let lineBottom = lineTop - h

        // —— 1) 张力期：高频颤动 + 断口颈缩细丝/纤维 ——
        var cx = midX
        var neckAlpha: CGFloat = 0
        if t < tensionEnd {
            let p = t / tensionEnd
            cx = midX + sin(p * .pi * 16) * (1 - p) * 3   // 越拉越抖，断前振幅归零
            neckAlpha = p
        }

        if t < tensionEnd {
            drawSegment(fromTop: lineTop, height: h, alpha: alpha, x: cx)
            // 颈缩：断口处一根 1pt 细丝（比主线细，即将拉断）
            let neckRect = NSRect(x: cx - 0.6, y: breakY - 3, width: 1.2, height: 6)
            let neckPath = NSBezierPath(roundedRect: neckRect, xRadius: 0.6, yRadius: 0.6)
            LingerTheme.nsColor(LingerTheme.Color.amberLight)
                .withAlphaComponent(neckAlpha * alpha).setFill()
            neckPath.fill()
            // 两侧纤维毛刺
            for dir in [-1.0, 1.0] {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: cx + CGFloat(dir) * 1.5, y: breakY + 1.5))
                path.line(to: NSPoint(x: cx + CGFloat(dir) * 3.5, y: breakY - 2))
                path.lineWidth = 0.8
                LingerTheme.nsColor(LingerTheme.Color.amberLight)
                    .withAlphaComponent(neckAlpha * alpha * 0.8).setStroke()
                path.stroke()
            }
            drawDot(center: NSPoint(x: cx, y: lineBottom), diameter: dotDiameter, alpha: alpha)
            return
        }

        // —— 2) 啪断 + 坠落：上段弹回，下段带圆点重力坠出（尾部钟摆）—— 
        let snap = (t - tensionEnd) / (1 - tensionEnd)          // 断裂后进度 0→1
        let upEase = 1 - pow(1 - min(1, snap / 0.6), 3)         // 上段在前 60% 内 easeOut 缩回
        let upOffset = 6 + upEase * (h / 2 + 14)                // 先跳 6pt，再缩回菜单栏
        drawSegment(fromTop: lineTop + upOffset,
                    height: (lineTop - breakY),
                    alpha: alpha)

        // 下段：重力平方加速下坠（y 减小）+ 尾部钟摆衰减
        let fall = 6 + pow(max(0, snap), 2) * h * 0.85
        let swing = sin(snap * .pi * 2.2) * 7 * max(0, 1 - snap * 0.7)
        let lowerTop = breakY - fall
        drawSegment(fromTop: lowerTop,
                    height: (breakY - lineBottom),
                    alpha: alpha)
        drawDot(center: NSPoint(x: midX + swing, y: lowerTop - (breakY - lineBottom)),
                diameter: dotDiameter, alpha: alpha)

        // —— 3) 碎屑：断口 3 个小点向两侧/斜上飞散 ——
        if snap > 0.02 && snap < 0.8 {
            let debris: [(dir: CGFloat, spread: CGFloat)] = [(-1, 3.2), (1, 2.6), (0.6, 4.0)]
            for d in debris {
                let dx = d.dir * (2 + d.spread * snap)
                let dy = -2 - 6 * snap
                let r: CGFloat = 1.6 - 0.5 * snap
                let rect = NSRect(x: midX + dx - r / 2, y: breakY + dy - r / 2, width: r, height: r)
                let p = NSBezierPath(ovalIn: rect)
                LingerTheme.nsColor(LingerTheme.Color.amberLight)
                    .withAlphaComponent(max(0, 1 - snap * 1.4) * alpha).setFill()
                p.fill()
            }
        }
    }
}
