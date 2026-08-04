//  DragFeedbackView.swift
//  拖拽反馈面板（窗口级）：
//    - 竖线 + 末端光点由 DragLineView 手绘（发光重构，2026-08-04）
//    - 双轨：左「for + 倒计时」| 右「til + 结束时刻（HH:mm:ss）」
//    - 高亮侧：琥珀金 + 不透明度 1 + 字号 +2pt；对侧变暗
//    - 字号可设置（linger_dragPreviewFontSize，缺省 22），面板宽度自适应
//    - 提示文案只在前 3 次拖拽显示（linger_dragHintUsageCount）
//    - 越过最大长度：橡皮筋阻尼延伸（DragPhysics.dampedOvershoot），面板向下生长
//  铁律：无硬编码 #F5A623，全部走 LingerTheme。

import Cocoa

final class DragFeedbackView: NSView {

    // MARK: - 对外类型

    /// 双轨模式（对应 UserDefaults `linger_dualRailMode`）
    enum DualRailMode: String { case both, countdown, endTime }

    /// 左右半区高亮侧（拖拽时按鼠标 x 判定，见 MenuBarManager.highlightSide）
    enum HighlightSide { case forSide, tilSide }

    /// 对外暴露的窗口句柄（MenuBarManager 用于左右半区判定）。
    var panelWindow: NSWindow?

    // MARK: - 子视图

    private let lineView = DragLineView()
    private let separatorView = NSView()
    private let forPrefix = NSTextField(labelWithString: "for")
    private let forTime = NSTextField(labelWithString: "00:00")
    private let tilPrefix = NSTextField(labelWithString: "til")
    private let tilTime = NSTextField(labelWithString: "00:00")
    private let hintLabel = NSTextField(labelWithString: "从菜单栏图标向下拖拽 · 松手开始计时")

    // MARK: - 布局常量

    private static let kContentWidthMin: CGFloat = 280
    private static let kTopY: CGFloat = 12
    private static let kDefaultMaxLineHeight: CGFloat = 360
    private static let kBottomBlockHeight: CGFloat = 124   // 双轨 + 提示 + 边距
    private static let kRubberHeadroom: CGFloat = 24       // 橡皮筋最大延伸（触顶后「微微拉长」要看得见）
    private static let kHighlightFontBump: CGFloat = 4     // 高亮侧字号增量（要明显）
    private static let kHighlightFontShrink: CGFloat = 2   // 对侧字号减量（反差越大越明显）

    private let topY = DragFeedbackView.kTopY
    private let minLineHeight: CGFloat = 40
    private var contentWidth: CGFloat = DragFeedbackView.kContentWidthMin
    private var maxLineHeight: CGFloat = DragFeedbackView.kDefaultMaxLineHeight
    private var rubberHeight: CGFloat = 0                  // 橡皮筋延伸量（面板增高）

    private var currentHighlight: HighlightSide = .forSide
    /// Esc 断线动画进行中：期间忽略一切 update（防闪一帧完整线的影子）
    private var isBreaking = false

    /// 当前预览字号（UserDefaults `linger_dragPreviewFontSize`，缺省 16，范围 12–24）
    private var previewFontSize: CGFloat {
        let raw = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.dragPreviewFontSize.rawValue)
        let v = raw > 0 ? raw : LingerTheme.defaultDragPreviewFontSize
        return CGFloat(min(max(v, 12), 24))
    }

    /// 面板总高（含橡皮筋延伸）
    private var contentHeight: CGFloat {
        topY + maxLineHeight + DragFeedbackView.kBottomBlockHeight + rubberHeight
    }

    /// til 时刻格式化器（HH:mm:ss；30fps 更新，缓存避免每帧新建 DateFormatter）
    private static let tilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: DragFeedbackView.kContentWidthMin,
                                 height: DragFeedbackView.kTopY
                                    + DragFeedbackView.kDefaultMaxLineHeight
                                    + DragFeedbackView.kBottomBlockHeight))
        setupSubviews()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 竖线 + 光点（自定义绘制）
        lineView.frame = NSRect(x: 0, y: 0,
                                width: DragFeedbackView.kContentWidthMin,
                                height: DragFeedbackView.kTopY
                                    + DragFeedbackView.kDefaultMaxLineHeight
                                    + DragFeedbackView.kBottomBlockHeight)
        addSubview(lineView)

        // 双轨分隔线（原型 .dual-separator：1px × 18px）
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        addSubview(separatorView)

        // 双轨标签（label 13pt、value 等宽 semibold，两轨等大；字号可设置）
        forPrefix.font = LingerTheme.labelFont(size: 13)
        forPrefix.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        forTime.font = LingerTheme.timeFont(size: previewFontSize, weight: .semibold)
        forTime.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        forTime.wantsLayer = true   // 高亮「变大」弹跳动画需要 layer transform
        tilPrefix.font = LingerTheme.labelFont(size: 13)
        tilPrefix.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        tilTime.font = LingerTheme.timeFont(size: previewFontSize, weight: .semibold)
        tilTime.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        tilTime.wantsLayer = true   // 高亮「变大」弹跳动画需要 layer transform
        addSubview(forPrefix)
        addSubview(forTime)
        addSubview(tilPrefix)
        addSubview(tilTime)

        // 提示文案（原型 #drag-hint：11pt ink3）
        hintLabel.font = LingerTheme.labelFont(size: 11)
        hintLabel.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        hintLabel.alignment = .center
        hintLabel.maximumNumberOfLines = 1
        addSubview(hintLabel)
    }

    // MARK: - 显示 / 隐藏

    func show(at anchorRect: NSRect) {
        // 线长上限 = min(达到最大时长所需的距离, 用户百分比上限)，保证
        // 「时间到最大时长（如 30:00）时线正好到顶，之后不再长」。
        let percent = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        let p = (percent >= 25 && percent <= 75) ? percent : LingerTheme.defaultMaxDragLinePercent
        let percentLimit = DragFeedbackView.kDefaultMaxLineHeight * CGFloat(p / 50)
        let maxDur = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
        let syncDistance = CGFloat(DragPhysics.lineMaxDistance(maxMinutes: maxDur))
        maxLineHeight = max(100, min(syncDistance, percentLimit))
        rubberHeight = 0
        isBreaking = false
        lineView.breakProgress = 0   // 复位 Esc 断线动画

        // 面板宽度按字号自适应（两轨都按「高亮侧 +2pt」的最宽值算，避免切换时挤破）
        contentWidth = max(DragFeedbackView.kContentWidthMin, requiredPanelWidth())
        let height = contentHeight

        if panelWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: contentWidth,
                                                   height: height),
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .statusBar
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.isReleasedWhenClosed = false
            win.contentView = self
            panelWindow = win
        }

        // 水平居中于图标，边界不出主屏幕
        var x = anchorRect.midX - contentWidth / 2
        if let visible = NSScreen.main?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - contentWidth - 4)
        }
        // 窗口顶部对齐菜单栏按钮底边（anchorRect.minY），向下延伸。
        let y = anchorRect.minY - height

        panelWindow?.setFrame(NSRect(x: x, y: y, width: contentWidth, height: height), display: false)
        frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        lineView.frame = bounds
        panelWindow?.alphaValue = 1
        // accessory 应用未激活时 orderFront(nil) 可能不生效，用 Regardless 版本。
        panelWindow?.orderFrontRegardless()

        startBreathing()
    }

    func hide() {
        stopBreathing()
        isBreaking = false
        panelWindow?.orderOut(nil)
    }

    // MARK: - Esc 断线动画

    /// Esc 取消「收回」动画（约 0.5s）：圆球收缩消失 → 线变最细变暗 → 整体向上收回 icon。
    /// 首帧就从 0.05 起（不是 0），配合 isBreaking 锁，杜绝「闪一帧完整绳子的影子」。
    func animateBreak(completion: @escaping () -> Void) {
        stopBreathing()
        isBreaking = true
        lineView.breakProgress = 0.05
        let duration: TimeInterval = 0.5
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            let progress = CGFloat((CACurrentMediaTime() - start) / duration)
            if progress >= 1 {
                t.invalidate()
                self.lineView.breakProgress = 1
                self.isBreaking = false
                completion()
                return
            }
            self.lineView.breakProgress = min(1, progress)
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - 呼吸微动画（柔和的 opacity 脉动）

    private func startBreathing() {
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 0.85
        breath.toValue = 1.0
        breath.duration = LingerTheme.durBreath
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        lineView.layer?.add(breath, forKey: "breath")
    }

    private func stopBreathing() {
        lineView.layer?.removeAnimation(forKey: "breath")
        lineView.layer?.opacity = 1
    }

    // MARK: - 每帧更新（30fps 由 MenuBarManager.pollDrag 驱动）

    func update(distance: CGFloat,
                seconds: TimeInterval,
                til: Date,
                mode: DualRailMode,
                highlight: HighlightSide,
                overflow: Bool,
                title: String?) {
        // 断线动画期间忽略任何拖拽帧更新（Esc 后 pollDrag 可能还有一帧排队）
        guard !isBreaking else { return }

        // 1) 竖线：正常拉到 maxLineHeight；越过则按 iOS 橡皮筋阻尼继续延伸（阻力渐增）
        let baseLine = min(maxLineHeight, max(minLineHeight, distance))
        let overshoot = max(0, distance - maxLineHeight)
        let damped = CGFloat(DragPhysics.dampedOvershoot(Double(overshoot),
                                                        headroom: Double(DragFeedbackView.kRubberHeadroom)))
        rubberHeight = damped
        let lineHeight = baseLine + damped

        // 2) 面板随橡皮筋向下生长（顶部固定），避免线条压到双轨
        let neededHeight = topY + lineHeight + DragFeedbackView.kBottomBlockHeight
        if abs(neededHeight - bounds.height) > 0.5, let w = panelWindow {
            var wf = w.frame
            let oldHeight = wf.height
            wf.size.height = neededHeight
            wf.origin.y += (oldHeight - neededHeight)   // 顶部固定，下沿生长
            w.setFrame(wf, display: false)
            frame = NSRect(x: 0, y: 0, width: contentWidth, height: neededHeight)
            lineView.frame = bounds
        }
        let panelHeight = bounds.height

        // 3) 竖线 + 光点绘制参数
        let lineY = panelHeight - topY - lineHeight
        lineView.lineHeight = lineHeight
        lineView.topY = topY
        lineView.isOverflowing = overflow
        // 触顶后线宽按公式连续变细（4 → 2，指数衰减）
        lineView.lineWidth = CGFloat(DragPhysics.lineWidth(overshoot: Double(overshoot)))

        // 4) 双轨文本：for = 倒计时（走 linger_timeFormat），til = 结束时刻 HH:mm:ss
        let format = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue)
            ?? LingerTheme.defaultTimeFormat
        forTime.stringValue = TimerEntry.displayString(seconds: seconds, format: format)
        tilTime.stringValue = DragFeedbackView.tilFormatter.string(from: til)

        // 5) 双轨显隐（单轨模式）
        let showFor = (mode == .both || mode == .countdown)
        let showTil = (mode == .both || mode == .endTime)
        forPrefix.isHidden = !showFor
        forTime.isHidden = !showFor
        tilPrefix.isHidden = !showTil
        tilTime.isHidden = !showTil

        // 6) 提示文案：只在前 3 次拖拽显示
        let usage = UserDefaults.standard.integer(forKey: LingerTheme.UserDefaultsKey.dragHintUsageCount.rawValue)
        hintLabel.isHidden = usage >= LingerTheme.maxDragHintShownCount

        // 7) 高亮（字号 +2 在这步设好）→ 布局
        applyHighlight(highlight)
        let dotRadius = (overflow ? DragLineView.dotDiameter + 2 : DragLineView.dotDiameter) / 2
        layoutDualTrack(dotMinY: lineY - dotRadius, showFor: showFor, showTil: showTil)
    }

    // MARK: - 布局

    /// 按当前字号 + 高亮增量，计算两轨并排所需最小宽度。
    /// for 侧按最大时长决定占位：≥60 分钟才可能是 8 字符（HH:MM:SS），否则 5 字符（MM:SS）；
    /// til 侧固定 8 字符（HH:mm:ss）。
    private func requiredPanelWidth() -> CGFloat {
        let activeSize = previewFontSize + DragFeedbackView.kHighlightFontBump
        let timeFont = LingerTheme.timeFont(size: activeSize, weight: .semibold)
        let maxDur = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
        let forPlaceholder = (maxDur >= 60 ? "00:00:00" : "00:00") as NSString
        let tilPlaceholder = "00:00:00" as NSString
        let prefixW = max(forPrefix.intrinsicContentSize.width,
                          tilPrefix.intrinsicContentSize.width)
        let forTrackW = prefixW + 6 + forPlaceholder.size(withAttributes: [.font: timeFont]).width
        let tilTrackW = prefixW + 6 + tilPlaceholder.size(withAttributes: [.font: timeFont]).width
        let both = forTrackW + tilTrackW + 16 * 2 + 1
        return both + 40   // 左右留白（含 frame padding，防任何遮挡）
    }

    /// 水平双轨：左组 + 分隔线 + 右组，整体居中。
    private func layoutDualTrack(dotMinY: CGFloat, showFor: Bool, showTil: Bool) {
        let gapFromDot: CGFloat = 24     // 原型 #time-preview mt-6
        let innerGap: CGFloat = 16       // 原型 gap-4
        let labelGap: CGFloat = 6        // 原型 .dual-track gap 6px
        let separatorHeight: CGFloat = 18
        let base = previewFontSize
        let activeSize = base + DragFeedbackView.kHighlightFontBump
        let inactiveSize = base - DragFeedbackView.kHighlightFontShrink

        forTime.font = LingerTheme.timeFont(size: currentHighlight == .forSide ? activeSize : inactiveSize,
                                            weight: .semibold)
        tilTime.font = LingerTheme.timeFont(size: currentHighlight == .tilSide ? activeSize : inactiveSize,
                                            weight: .semibold)

        func trackWidth(_ prefix: NSTextField, _ time: NSTextField) -> CGFloat {
            prefix.intrinsicContentSize.width + labelGap + time.intrinsicContentSize.width
        }
        let forW = showFor ? trackWidth(forPrefix, forTime) : 0
        let tilW = showTil ? trackWidth(tilPrefix, tilTime) : 0
        let sepW: CGFloat = (showFor && showTil) ? 1 : 0
        let totalW = forW + (showFor && showTil ? innerGap : 0) + sepW
            + (showFor && showTil ? innerGap : 0) + tilW

        var x = (contentWidth - totalW) / 2
        // 双轨中心线：圆点下 24pt 处
        let centerY = dotMinY - gapFromDot - 12

        func place(_ prefix: NSTextField, _ time: NSTextField) {
            let pSize = prefix.intrinsicContentSize
            let tSize = time.intrinsicContentSize
            // frame 宽度留 padding（前缀 +2 / 数字 +4），文字永不贴右缘被裁
            prefix.frame = NSRect(x: x, y: centerY - pSize.height / 2,
                                  width: pSize.width + 2, height: pSize.height)
            x += pSize.width + labelGap
            time.frame = NSRect(x: x, y: centerY - tSize.height / 2,
                                width: tSize.width + 4, height: tSize.height)
            x += tSize.width
        }

        if showFor { place(forPrefix, forTime) }
        if showFor && showTil {
            separatorView.frame = NSRect(x: x + innerGap,
                                         y: centerY - separatorHeight / 2,
                                         width: 1,
                                         height: separatorHeight)
            x += innerGap * 2 + 1
        }
        if showTil { place(tilPrefix, tilTime) }

        // 提示文案：双轨下方 16pt（原型 mt-4）
        hintLabel.frame = NSRect(x: 0, y: centerY - 12 - 16 - 14,
                                 width: contentWidth, height: 14)
    }

    // MARK: - 高亮

    /// 悬停高亮：高亮侧琥珀金 + 不透明度 1 + 字号 +4pt（弹跳放大），
    /// 对侧 ink3 + 0.3 + 字号 -2pt，0.35s 过渡 —— 反差够大才「看得见」。
    private func applyHighlight(_ side: HighlightSide) {
        let sideChanged = (currentHighlight != side)
        currentHighlight = side
        let forActive = (side == .forSide)
        let amber = LingerTheme.nsColor(LingerTheme.Color.amber)
        let ink3 = LingerTheme.nsColor(LingerTheme.Color.ink3)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            forTime.animator().alphaValue = forActive ? 1.0 : 0.3
            forPrefix.animator().alphaValue = forActive ? 0.7 : 0.3
            tilTime.animator().alphaValue = forActive ? 0.3 : 1.0
            tilPrefix.animator().alphaValue = forActive ? 0.3 : 0.7
        }

        forTime.textColor = forActive ? amber : ink3
        forPrefix.textColor = forActive ? amber : ink3
        tilTime.textColor = forActive ? ink3 : amber
        tilPrefix.textColor = forActive ? ink3 : amber

        // 切换侧的瞬间给一个「变大」弹跳，让字号变化一眼可见（仅切侧时触发一次）
        if sideChanged {
            animateFontPop(forTime, growing: forActive)
            animateFontPop(tilTime, growing: !forActive)
        }
    }

    /// 字号弹跳：growing 侧 0.85 → 1.05 → 1.0（过冲回弹）；
    /// 对侧（已换成更小字号）0.92 → 0.97 → 1.0 —— 只做轻微收拢，
    /// 绝不能从 1.15 起跳（会盖住前缀末字符 + 顶掉右缘秒数，见 2026-08-04 bug）。
    private func animateFontPop(_ field: NSTextField, growing: Bool) {
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = growing ? [0.85, 1.05, 1.0] : [0.92, 0.97, 1.0]
        anim.keyTimes = [0, 0.6, 1]
        anim.duration = 0.35
        anim.timingFunctions = [CAMediaTimingFunction(name: .easeOut)]
        field.layer?.add(anim, forKey: "fontPop")
    }

    // MARK: - 调试/测试钩子

    /// 布局摘要（internal，供单测检查遮挡）：面板宽度 + 各标签 frame/intrinsic/文本。
    func debugLayoutSummary() -> String {
        func fmt(_ f: NSTextField) -> String {
            let i = f.intrinsicContentSize
            return "\(f.stringValue)[\(Int(f.frame.minX))...\(Int(f.frame.maxX)) w=\(Int(f.frame.width)) iw=\(String(format: "%.1f", i.width))]"
        }
        return "panelW=\(Int(contentWidth)) | for \(fmt(forPrefix)) \(fmt(forTime)) | til \(fmt(tilPrefix)) \(fmt(tilTime))"
    }
}
