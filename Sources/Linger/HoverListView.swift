import Cocoa

// MARK: - 设计 token

private enum HoverDesign {
    // 颜色：暗色毛玻璃，暖橙主色（仅 running）
    static let panelBg = NSColor(calibratedWhite: 0.08, alpha: 0.92)
    static let cardBg = NSColor(calibratedWhite: 1.0, alpha: 0.06)
    static let cardBgActive = NSColor(calibratedWhite: 1.0, alpha: 0.09)   // running 卡片稍亮
    static let groupSeparator = NSColor(calibratedWhite: 0.5, alpha: 0.25)
    static let bottomSeparator = NSColor(calibratedWhite: 1.0, alpha: 0.10)
    static let progressTrack = NSColor(calibratedWhite: 1.0, alpha: 0.10)

    static let amber = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 1.0)
    static let textPrimary = NSColor.white
    static let textSecondary = NSColor(calibratedWhite: 1.0, alpha: 0.55)
    static let textTertiary = NSColor(calibratedWhite: 1.0, alpha: 0.42)

    // 尺寸：紧凑
    static let panelCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 8
    static let cardPaddingX: CGFloat = 8
    static let cardPaddingY: CGFloat = 6
    static let cardGap: CGFloat = 4
    static let colorBarWidth: CGFloat = 3
    static let cardHeight: CGFloat = 56
    static let progressBarHeight: CGFloat = 3
    static let topPadding: CGFloat = 8
    static let bottomAreaHeight: CGFloat = 36
    static let bottomPadding: CGFloat = 8
    static let groupSeparatorHeight: CGFloat = 14

    // 字体
    static func timeFontSize() -> CGFloat {
        let v = CGFloat(UserDefaults.standard.float(forKey: "linger_hoverListFontSize"))
        return v > 0 ? v : 20
    }
    static let subtitleFontSize: CGFloat = 11
    static let bottomFontSize: CGFloat = 12
    static let badgeFontSize: CGFloat = 11
    static let symbolPointSize: CGFloat = 11   // 按钮 icon
    static let bottomSymbolPointSize: CGFloat = 13

    static let panelWidth: CGFloat = 240
}

// MARK: - HoverListWindow

/// 暗色毛玻璃面板窗口
final class HoverListWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - HoverProgressBar（CALayer 动画进度条）

/// 3px 高圆角进度条，setProgress(_:animated:) 触发 0.3s 平滑动画
final class HoverProgressBar: NSView {

    var accentColor: NSColor = HoverDesign.amber {
        didSet { fillLayer.backgroundColor = accentColor.cgColor }
    }

    private let fillLayer = CALayer()
    private var currentProgress: CGFloat = 0
    /// 标记是否已完成首次布局（首次无动画直接从当前进度开始）
    var hasInitialProgress: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        // 轨道层（静态）：通过 layer.backgroundColor 即可
        layer?.backgroundColor = HoverDesign.progressTrack.cgColor
        layer?.cornerRadius = frameRect.height / 2

        // 填充层
        fillLayer.backgroundColor = accentColor.cgColor
        fillLayer.cornerRadius = frameRect.height / 2
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        fillLayer.cornerRadius = bounds.height / 2
        // 不在 layout 里改 fillLayer.frame —— 那是 setProgress 的活
    }

    func setProgress(_ p: CGFloat, animated: Bool) {
        let target = max(0, min(1, p))
        let targetRect = fillRect(for: target)
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillLayer.frame = targetRect
            CATransaction.commit()
        } else {
            let anim = CABasicAnimation(keyPath: "frame")
            anim.fromValue = NSValue(rect: fillLayer.frame)
            anim.toValue = NSValue(rect: targetRect)
            anim.duration = 0.3
            anim.timingFunction = CAMediaTimingFunction(name: .linear)  // v5 修复：匀速插值，避免 easeOut 在 1s tick 间隔下跳变明显
            fillLayer.add(anim, forKey: "progressAnim")
            fillLayer.frame = targetRect
        }
        currentProgress = target
    }

    private func fillRect(for progress: CGFloat) -> NSRect {
        let w = max(bounds.height, bounds.width * progress)
        return NSRect(x: 0, y: 0, width: w, height: bounds.height)
    }
}

// MARK: - HoverListView

final class HoverListView: NSView {

    // MARK: - 数据

    // ⑥ 三组排序: running / paused / scheduled
    private var running: [TimerEntry] = []
    private var paused: [TimerEntry] = []
    private var scheduled: [TimerEntry] = []

    /// 进度条子 view 池（按 entry.id 复用，避免每次 setEntries 重建打断动画）
    private var progressBars: [UUID: HoverProgressBar] = [:]

    // ① 按钮点击: 记录每个按钮的 hit rect (比图标大一倍防误触)
    private var pauseRects: [UUID: NSRect] = [:]
    private var stopRects: [UUID: NSRect] = [:]

    // ④ hover 高亮: 当前鼠标悬停的卡片 entry ID
    private var hoveredEntryID: UUID?

    // FLIP 动画状态
    private var animProgress: CGFloat = 1.0  // 1.0 = 未在动画中
    private var animTimer: Timer?
    private var animStartTime: CFTimeInterval = 0
    private let animDuration: CFTimeInterval = 0.5
    private var oldCardYs: [UUID: CGFloat] = [:]
    private var newCardYs: [UUID: CGFloat] = [:]
    private var oldSeparatorYs: [CGFloat] = []
    private var newSeparatorYs: [CGFloat] = []
    private var removedEntries: [(entry: TimerEntry, oldY: CGFloat)] = []
    private var oldPanelHeight: CGFloat = 0
    private var newPanelHeight: CGFloat = 0
    private var lastTargetHeight: CGFloat = 0
    private var isAnimating: Bool { animTimer != nil }

    // 窗口高度动画回调（每帧调用，参数为插值后的高度）
    var onHeightAnimation: ((CGFloat) -> Void)?

    // MARK: - 暴露给外部

    static var panelWidth: CGFloat { HoverDesign.panelWidth }

    // ① 按钮回调
    var onPauseToggle: ((UUID) -> Void)?
    var onStop: ((UUID) -> Void)?
    // ② 底栏回调
    var onToggleAllPause: (() -> Void)?
    // 日历预约按钮回调（左下 calendar.badge.plus）
    var onCalendarSchedule: (() -> Void)?
    // ⑤ 编辑标题回调
    var onTitleEdit: ((UUID, String) -> Void)?

    // 底栏两个按钮的 hit rect（drawBottomArea 中计算）
    private var calendarBtnRect: NSRect = .zero
    private var pauseAllBtnRect: NSRect = .zero

    static func panelHeight(runningPausedCount rp: Int, scheduledCount sc: Int) -> CGFloat {
        // 兼容旧调用: rp = running + paused
        guard rp + sc > 0 else { return HoverDesign.topPadding + HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding }
        let rowH = HoverDesign.cardHeight
        let gap = HoverDesign.cardGap
        let rows = CGFloat(rp + sc)
        let gaps = CGFloat(max(0, rp + sc - 1))
        // 最多两条分隔线 (running|paused, runningPaused|scheduled)
        var sepCount = 0
        if rp > 0 && sc > 0 { sepCount += 1 }
        // 简化: 旧调用不考虑 running/paused 分隔
        let groupH = CGFloat(sepCount) * HoverDesign.groupSeparatorHeight
        return HoverDesign.topPadding
             + rows * rowH
             + gaps * gap
             + groupH
             + HoverDesign.bottomAreaHeight
             + HoverDesign.bottomPadding
    }

    /// ⑥ 三组版本: 精确计算面板高度
    static func panelHeight3(runningCount r: Int, pausedCount p: Int, scheduledCount s: Int) -> CGFloat {
        let total = r + p + s
        guard total > 0 else { return HoverDesign.topPadding + HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding }
        let rowH = HoverDesign.cardHeight
        let gap = HoverDesign.cardGap
        let rows = CGFloat(total)
        let gaps = CGFloat(max(0, total - 1))
        var sepCount = 0
        if r > 0 && p > 0 { sepCount += 1 }
        if (r + p) > 0 && s > 0 { sepCount += 1 }
        let groupH = CGFloat(sepCount) * HoverDesign.groupSeparatorHeight
        return HoverDesign.topPadding
             + rows * rowH
             + gaps * gap
             + groupH
             + HoverDesign.bottomAreaHeight
             + HoverDesign.bottomPadding
    }

    // MARK: - 设置数据

    func setEntries(_ newEntries: [TimerEntry]) {
        // 1. Capture: 记录旧位置（BEFORE 更新数据）
        var oldYs: [UUID: CGFloat] = [:]
        for entry in running + paused + scheduled {
            oldYs[entry.id] = rectForEntry(entry).minY
        }
        let oldSepYs = computeSeparatorYs()
        let oldH = lastTargetHeight > 0 ? lastTargetHeight : bounds.height

        // 2. 找出被移除的条目
        let newFiltered = newEntries.filter { $0.remainingTime > 0 }
        let newIDs = Set(newFiltered.map { $0.id })
        var removed: [(entry: TimerEntry, oldY: CGFloat)] = []
        for entry in running + paused + scheduled where !newIDs.contains(entry.id) {
            if let y = oldYs[entry.id] {
                removed.append((entry, y))
            }
        }

        // 3. 更新数据（原有逻辑）
        let sorted = newFiltered.sorted { $0.remainingTime < $1.remainingTime }
        running = sorted.filter { !$0.isScheduled && !$0.isPaused }
        paused = sorted.filter { !$0.isScheduled && $0.isPaused }
        scheduled = sorted.filter { $0.isScheduled }

        rebuildProgressBars()
        layoutRows()  // 同步布局到目标位置

        // 4. Compute new: 计算新位置
        var newYs: [UUID: CGFloat] = [:]
        for entry in running + paused + scheduled {
            newYs[entry.id] = rectForEntry(entry).minY
        }
        let newSepYs = computeSeparatorYs()
        let newH = HoverListView.panelHeight3(
            runningCount: running.count, pausedCount: paused.count, scheduledCount: scheduled.count)

        lastTargetHeight = newH

        // 5. 判断是否需要动画
        let needsAnim = !removed.isEmpty
            || newYs.count != oldYs.count
            || !oldYs.allSatisfy { (id, oldY) -> Bool in newYs[id] == oldY }

        if needsAnim {
            oldCardYs = oldYs
            newCardYs = newYs
            oldSeparatorYs = oldSepYs
            newSeparatorYs = newSepYs
            removedEntries = removed
            oldPanelHeight = oldH
            newPanelHeight = newH
            startFlipAnimation()
        } else {
            needsDisplay = true
        }
    }

    /// 保留旧 progressBars（避免动画被打断），按 entry.id 增删
    private func rebuildProgressBars() {
        var keep: [UUID: HoverProgressBar] = [:]
        for entry in running + paused + scheduled {
            if let existing = progressBars[entry.id] {
                keep[entry.id] = existing
            } else {
                let pb = HoverProgressBar(frame: .zero)
                pb.translatesAutoresizingMaskIntoConstraints = true
                addSubview(pb)
                keep[entry.id] = pb
            }
        }
        // 删除不再用的
        for (id, pb) in progressBars where keep[id] == nil {
            pb.removeFromSuperview()
        }
        progressBars = keep
    }

    /// 计算当前组分隔线的 Y 坐标列表（用于动画 capture/compare）
    private func computeSeparatorYs() -> [CGFloat] {
        var seps: [CGFloat] = []
        var y = HoverDesign.topPadding
        y += CGFloat(running.count) * (HoverDesign.cardHeight + HoverDesign.cardGap)
        if !running.isEmpty && !paused.isEmpty {
            seps.append(y + (HoverDesign.groupSeparatorHeight - 1) / 2)
            y += HoverDesign.groupSeparatorHeight
        }
        y += CGFloat(paused.count) * (HoverDesign.cardHeight + HoverDesign.cardGap)
        if (!running.isEmpty || !paused.isEmpty) && !scheduled.isEmpty {
            seps.append(y + (HoverDesign.groupSeparatorHeight - 1) / 2)
        }
        return seps
    }

    // MARK: - 布局

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if !isAnimating {
            layoutRows()
        }
    }

    // MARK: - FLIP 动画

    private func startFlipAnimation() {
        animProgress = 0
        animStartTime = CACurrentMediaTime()
        animTimer?.invalidate()
        let t = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tickFlipAnimation()
        }
        RunLoop.current.add(t, forMode: .common)
        animTimer = t
    }

    private func tickFlipAnimation() {
        let elapsed = CACurrentMediaTime() - animStartTime
        let raw = CGFloat(min(elapsed / animDuration, 1.0))
        animProgress = easeInOutCubic(raw)

        // 插值窗口高度
        let h = oldPanelHeight + (newPanelHeight - oldPanelHeight) * animProgress
        onHeightAnimation?(h)

        // 更新进度条到插值位置
        updateProgressBarsAnimated()

        needsDisplay = true

        if raw >= 1.0 {
            animTimer?.invalidate()
            animTimer = nil
            animProgress = 1.0
            oldCardYs = [:]
            newCardYs = [:]
            oldSeparatorYs = []
            newSeparatorYs = []
            removedEntries = []
            // 最终布局确保一切到位
            needsLayout = true
        }
    }

    private func updateProgressBarsAnimated() {
        for entry in running + paused + scheduled {
            guard let pb = progressBars[entry.id] else { continue }
            guard let newY = newCardYs[entry.id] else { continue }
            let oldY = oldCardYs[entry.id] ?? newY
            let interpolatedY = oldY + (newY - oldY) * animProgress
            let progressY = interpolatedY + HoverDesign.cardHeight - HoverDesign.progressBarHeight - 4
            let progressX = HoverDesign.cardPaddingX + HoverDesign.colorBarWidth + 10
            let progressW = bounds.width - HoverDesign.cardPaddingX * 2 - HoverDesign.colorBarWidth - 10 - 10
            pb.frame = NSRect(x: progressX, y: progressY, width: progressW, height: HoverDesign.progressBarHeight)
        }
    }

    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        // cubic-bezier(0.2, 0.8, 0.2, 1.0) 近似
        let u = 1 - t
        return 1 - u * u * u * u
    }

    /// 计算每行位置 + 设置 progressBar 子 view frame
    private func layoutRows() {
        let contentX = HoverDesign.cardPaddingX
        let contentW = bounds.width - HoverDesign.cardPaddingX * 2
        var y: CGFloat = HoverDesign.topPadding

        // ⑥ 第一组：running
        for entry in running {
            layoutRow(entry: entry, y: y, contentX: contentX, contentW: contentW)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }

        // running|paused 分隔线高度
        if !running.isEmpty && !paused.isEmpty {
            y += HoverDesign.groupSeparatorHeight
        }

        // 第二组：paused
        for entry in paused {
            layoutRow(entry: entry, y: y, contentX: contentX, contentW: contentW)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }

        // runningPaused|scheduled 分隔线高度
        if (!running.isEmpty || !paused.isEmpty) && !scheduled.isEmpty {
            y += HoverDesign.groupSeparatorHeight
        }

        // 第三组：scheduled
        for entry in scheduled {
            layoutRow(entry: entry, y: y, contentX: contentX, contentW: contentW)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }
    }

    private func layoutRow(entry: TimerEntry, y: CGFloat, contentX: CGFloat, contentW: CGFloat) {
        guard let pb = progressBars[entry.id] else { return }
        let progressY = y + HoverDesign.cardHeight - HoverDesign.progressBarHeight - 4
        let progressX = contentX + HoverDesign.colorBarWidth + 10
        let progressW = contentW - HoverDesign.colorBarWidth - 10 - 10
        pb.frame = NSRect(x: progressX, y: progressY, width: progressW, height: HoverDesign.progressBarHeight)
        // ⑦ 颜色: running=琥珀金, paused=浅琥珀金, scheduled=灰色
        let accentColor: NSColor
        if entry.isScheduled {
            accentColor = NSColor(calibratedWhite: 1.0, alpha: 0.20)
        } else if entry.isPaused {
            accentColor = HoverDesign.amber.withAlphaComponent(0.45)
        } else {
            accentColor = HoverDesign.amber
        }
        pb.accentColor = accentColor
        let progress = computeProgress(entry: entry)
        // 首次布局无动画直接跳到当前进度，后续 tick 更新才有 0.3s 平滑动画
        pb.setProgress(CGFloat(progress), animated: pb.hasInitialProgress)
        pb.hasInitialProgress = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let _ = NSGraphicsContext.current?.cgContext else { return }
        drawPanelBackground()

        if running.isEmpty && paused.isEmpty && scheduled.isEmpty && removedEntries.isEmpty {
            drawEmptyHint()
            return
        }

        // 绘制分隔线（带动画）
        drawSeparatorsWithAnimation()

        // 绘制存活卡片（带插值位置）
        var y: CGFloat = HoverDesign.topPadding
        for entry in running {
            drawCardInterpolated(entry: entry, targetY: y)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }
        // 跳过分隔线高度（已单独绘制）
        if !running.isEmpty && !paused.isEmpty { y += HoverDesign.groupSeparatorHeight }
        for entry in paused {
            drawCardInterpolated(entry: entry, targetY: y)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }
        if (!running.isEmpty || !paused.isEmpty) && !scheduled.isEmpty { y += HoverDesign.groupSeparatorHeight }
        for entry in scheduled {
            drawCardInterpolated(entry: entry, targetY: y)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }

        // 绘制被移除的卡片（缩小淡出）
        if isAnimating {
            let p = animProgress
            for removed in removedEntries {
                drawCard(entry: removed.entry, y: removed.oldY, alpha: 1.0 - p, scale: 1.0 - 0.15 * p)
            }
        }

        drawBottomArea()
    }

    private func drawSeparatorsWithAnimation() {
        let p = animProgress
        let sepX = HoverDesign.cardPaddingX + 4
        let sepW = bounds.width - HoverDesign.cardPaddingX * 2 - 8

        // 新分隔线（插值位置或淡入）
        var sepIndex = 0
        var y = HoverDesign.topPadding
        y += CGFloat(running.count) * (HoverDesign.cardHeight + HoverDesign.cardGap)
        if !running.isEmpty && !paused.isEmpty {
            let targetY = y + (HoverDesign.groupSeparatorHeight - 1) / 2
            let drawY: CGFloat
            let alpha: CGFloat
            if isAnimating && sepIndex < oldSeparatorYs.count {
                drawY = oldSeparatorYs[sepIndex] + (targetY - oldSeparatorYs[sepIndex]) * p
                alpha = 1.0
            } else if isAnimating {
                drawY = targetY
                alpha = p
            } else {
                drawY = targetY
                alpha = 1.0
            }
            HoverDesign.groupSeparator.withAlphaComponent(alpha).setFill()
            NSRect(x: sepX, y: drawY, width: sepW, height: 1).fill()
            y += HoverDesign.groupSeparatorHeight
            sepIndex += 1
        }
        y += CGFloat(paused.count) * (HoverDesign.cardHeight + HoverDesign.cardGap)
        if (!running.isEmpty || !paused.isEmpty) && !scheduled.isEmpty {
            let targetY = y + (HoverDesign.groupSeparatorHeight - 1) / 2
            let drawY: CGFloat
            let alpha: CGFloat
            if isAnimating && sepIndex < oldSeparatorYs.count {
                drawY = oldSeparatorYs[sepIndex] + (targetY - oldSeparatorYs[sepIndex]) * p
                alpha = 1.0
            } else if isAnimating {
                drawY = targetY
                alpha = p
            } else {
                drawY = targetY
                alpha = 1.0
            }
            HoverDesign.groupSeparator.withAlphaComponent(alpha).setFill()
            NSRect(x: sepX, y: drawY, width: sepW, height: 1).fill()
            sepIndex += 1
        }

        // 旧分隔线淡出（超出新分隔线数量的部分）
        if isAnimating && sepIndex < oldSeparatorYs.count {
            for i in sepIndex..<oldSeparatorYs.count {
                let alpha = 1.0 - p
                HoverDesign.groupSeparator.withAlphaComponent(alpha).setFill()
                NSRect(x: sepX, y: oldSeparatorYs[i], width: sepW, height: 1).fill()
            }
        }
    }

    private func drawCardInterpolated(entry: TimerEntry, targetY: CGFloat) {
        let drawY: CGFloat
        let alpha: CGFloat
        if isAnimating {
            if let oldY = oldCardYs[entry.id] {
                // 存活卡片：从旧位置插值到新位置
                drawY = oldY + (targetY - oldY) * animProgress
                alpha = 1.0
            } else {
                // 新增卡片：淡入
                drawY = targetY
                alpha = animProgress
            }
        } else {
            drawY = targetY
            alpha = 1.0
        }
        drawCard(entry: entry, y: drawY, alpha: alpha)
    }

    // MARK: - 背景

    private func drawPanelBackground() {
        let path = NSBezierPath(roundedRect: bounds, xRadius: HoverDesign.panelCornerRadius, yRadius: HoverDesign.panelCornerRadius)
        HoverDesign.panelBg.setFill()
        path.fill()
    }

    private func drawEmptyHint() {
        let text = "暂无计时器"
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: HoverDesign.textSecondary
        ]
        let size = (text as NSString).size(withAttributes: attr)
        let rect = NSRect(x: (bounds.width - size.width) / 2,
                          y: (bounds.height - size.height) / 2,
                          width: size.width,
                          height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attr)
    }

    // MARK: - 卡片

    private func drawCard(entry: TimerEntry, y: CGFloat, alpha: CGFloat = 1.0, scale: CGFloat = 1.0) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if scale != 1.0 {
            let cardRect = NSRect(x: HoverDesign.cardPaddingX, y: y,
                                  width: bounds.width - HoverDesign.cardPaddingX * 2,
                                  height: HoverDesign.cardHeight)
            let cx = cardRect.midX
            let cy = cardRect.midY
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -cx, y: -cy)
        }
        if alpha < 1.0 {
            ctx.setAlpha(alpha)
        }

        let cardRect = NSRect(x: HoverDesign.cardPaddingX, y: y,
                              width: bounds.width - HoverDesign.cardPaddingX * 2,
                              height: HoverDesign.cardHeight)

        // ④ hover 高亮: 鼠标悬停的卡片用更亮背景
        let isHovered = hoveredEntryID == entry.id

        // ⑦ 颜色方案: running=稍亮半透明, paused=普通半透明, scheduled=普通半透明
        let cardBg: NSColor
        if entry.isScheduled {
            cardBg = isHovered ? NSColor(calibratedWhite: 1.0, alpha: 0.10) : HoverDesign.cardBg
        } else if entry.isPaused {
            cardBg = isHovered ? NSColor(calibratedWhite: 1.0, alpha: 0.10) : HoverDesign.cardBg
        } else {
            // running
            cardBg = isHovered ? NSColor(calibratedWhite: 1.0, alpha: 0.14) : HoverDesign.cardBgActive
        }

        // 卡片背景
        let path = NSBezierPath(roundedRect: cardRect,
                                xRadius: HoverDesign.cardCornerRadius,
                                yRadius: HoverDesign.cardCornerRadius)
        cardBg.setFill()
        path.fill()

        // ⑦ 左边缘色条: running=琥珀金, paused=浅琥珀金 alpha 0.45, scheduled=灰色 alpha 0.2
        let barColor: NSColor
        if entry.isScheduled {
            barColor = NSColor(calibratedWhite: 1.0, alpha: 0.20)
        } else if entry.isPaused {
            barColor = HoverDesign.amber.withAlphaComponent(0.45)
        } else {
            barColor = HoverDesign.amber
        }
        let barRect = NSRect(x: cardRect.minX, y: cardRect.minY + 2,
                             width: HoverDesign.colorBarWidth,
                             height: cardRect.height - 4)
        let barPath = NSBezierPath(roundedRect: barRect,
                                   xRadius: HoverDesign.colorBarWidth / 2,
                                   yRadius: HoverDesign.colorBarWidth / 2)
        barColor.setFill()
        barPath.fill()

        // 文本内容
        drawRowContent(entry: entry, cardRect: cardRect)

        // 被移除的卡片（alpha < 1.0）不保留 hit rects，避免动画期间误触
        if alpha < 1.0 {
            pauseRects.removeValue(forKey: entry.id)
            stopRects.removeValue(forKey: entry.id)
        }

        ctx.restoreGState()
    }

    private func drawRowContent(entry: TimerEntry, cardRect: NSRect) {
        let contentX = cardRect.minX + HoverDesign.colorBarWidth + 10
        let contentW = cardRect.width - HoverDesign.colorBarWidth - 10 - 10

        // 大号等宽数字（左）
        let timeText = entry.displayTime
        // ⑦ 颜色方案: running=白色bold, paused=浅琥珀金 alpha 0.45, scheduled=灰色 alpha 0.4
        let timeColor: NSColor
        let timeWeight: NSFont.Weight
        if entry.isScheduled {
            timeColor = NSColor(calibratedWhite: 1.0, alpha: 0.4)
            timeWeight = .regular
        } else if entry.isPaused {
            timeColor = NSColor(calibratedWhite: 1.0, alpha: 0.55)
            timeWeight = .bold
        } else {
            timeColor = HoverDesign.textPrimary
            timeWeight = .bold
        }
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: HoverDesign.timeFontSize(),
                                                        weight: timeWeight)
        let timeAttr: [NSAttributedString.Key: Any] = [
            .font: timeFont,
            .foregroundColor: timeColor
        ]
        let timeSize = (timeText as NSString).size(withAttributes: timeAttr)

        let hasTitle = !(entry.predefinedTitle ?? "").isEmpty
        let titleText = hasTitle ? entry.predefinedTitle! : ""

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: HoverDesign.subtitleFontSize, weight: .regular),
            .foregroundColor: HoverDesign.textTertiary
        ]
        let titleSize = hasTitle
            ? (titleText as NSString).size(withAttributes: titleAttr)
            : NSSize(width: 0, height: HoverDesign.subtitleFontSize)

        // 数字 + 副标题作为整体 block, 垂直居中于卡片中线
        let blockSpacing: CGFloat = 4
        let blockHeight = timeSize.height + blockSpacing + titleSize.height
        let blockStartY = cardRect.minY + (cardRect.height - blockHeight) / 2
        let timeY = blockStartY
        let titleY = blockStartY + timeSize.height + blockSpacing

        (timeText as NSString).draw(
            in: NSRect(x: contentX, y: timeY, width: timeSize.width, height: timeSize.height),
            withAttributes: timeAttr
        )

        if hasTitle {
            (titleText as NSString).draw(
                in: NSRect(x: contentX, y: titleY - 2, width: contentW, height: titleSize.height),
                withAttributes: titleAttr
            )
        }

        // 右侧控件
        drawRightControls(entry: entry, cardRect: cardRect, blockCenterY: blockStartY + blockHeight / 2)
    }

    private func drawRightControls(entry: TimerEntry, cardRect: NSRect, blockCenterY: CGFloat) {
        let rightEdge = cardRect.maxX - 10
        // 修复 3a: 按钮中心 = 文字 block 中心 (不再是硬编码 cardRect.minY + cardHeight/2)
        let iconY = blockCenterY

        if entry.isScheduled {
            // 清除该 entry 的按钮 hit rect
            pauseRects.removeValue(forKey: entry.id)
            stopRects.removeValue(forKey: entry.id)
            // 待开始文字
            let text = "待开始"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: HoverDesign.badgeFontSize, weight: .medium),
                .foregroundColor: HoverDesign.textTertiary
            ]
            let size = (text as NSString).size(withAttributes: attr)
            let rect = NSRect(x: rightEdge - size.width,
                              y: cardRect.minY + 8,
                              width: size.width,
                              height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attr)
        } else {
            // 按钮：play/pause + stop —— 用 SF Symbol + tint
            let primaryIcon = entry.isPaused ? "play.fill" : "pause.fill"
            let primaryColor: NSColor = entry.isPaused
                ? HoverDesign.amber
                : HoverDesign.textTertiary

            // v6 修复: 两个按钮之间的间距 14 → 20
            drawTintedSFSymbol(primaryIcon,
                               color: primaryColor,
                               pointSize: HoverDesign.symbolPointSize,
                               rightAnchor: rightEdge - 20,
                               centerY: iconY)

            drawTintedSFSymbol("stop.fill",
                               color: HoverDesign.textTertiary,
                               pointSize: HoverDesign.symbolPointSize,
                               rightAnchor: rightEdge,
                               centerY: iconY)

            // ① 记录按钮 hit rect (比图标大一倍防误触)
            let hitPad: CGFloat = HoverDesign.symbolPointSize  // 外扩一倍
            let pauseIconRect = NSRect(x: rightEdge - 20 - HoverDesign.symbolPointSize,
                                       y: iconY - HoverDesign.symbolPointSize / 2,
                                       width: HoverDesign.symbolPointSize,
                                       height: HoverDesign.symbolPointSize)
            pauseRects[entry.id] = pauseIconRect.insetBy(dx: -hitPad, dy: -hitPad)

            let stopIconRect = NSRect(x: rightEdge - HoverDesign.symbolPointSize,
                                      y: iconY - HoverDesign.symbolPointSize / 2,
                                      width: HoverDesign.symbolPointSize,
                                      height: HoverDesign.symbolPointSize)
            stopRects[entry.id] = stopIconRect.insetBy(dx: -hitPad, dy: -hitPad)
        }
    }

    /// 画带 tint 的 SF Symbol —— 内部通过 lockFocus 把 symbol 当 mask，用 color 填充
    private func drawTintedSFSymbol(_ name: String,
                                    color: NSColor,
                                    pointSize: CGFloat,
                                    rightAnchor: CGFloat,
                                    centerY: CGFloat) {
        guard let tinted = makeTintedSFSymbol(name, color: color, pointSize: pointSize) else { return }
        let size = tinted.size
        let rect = NSRect(x: rightAnchor - size.width,
                          y: centerY - size.height / 2,
                          width: size.width,
                          height: size.height)
        tinted.draw(in: rect)
    }

    private func makeTintedSFSymbol(_ name: String,
                                    color: NSColor,
                                    pointSize: CGFloat,
                                    weight: NSFont.Weight = .medium) -> NSImage? {
        guard let raw = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let symbol = raw.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
              ) else { return nil }
        symbol.isTemplate = true  // 关键：让 image 当 mask

        let result = NSImage(size: symbol.size)
        result.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: symbol.size).fill()
        // destinationIn：把 symbol 当作 mask，只保留 color 与 symbol 交集的像素
        symbol.draw(in: NSRect(origin: .zero, size: symbol.size),
                    from: NSRect(origin: .zero, size: symbol.size),
                    operation: .destinationIn,
                    fraction: 1.0)
        result.unlockFocus()
        return result
    }

    private func computeProgress(entry: TimerEntry) -> Double {
        let total = max(0.001, entry.duration)
        let elapsed = max(0, total - entry.remainingTime)
        return elapsed / total
    }

    // MARK: - 底部区域

    private func drawBottomArea() {
        let topY = bounds.height - HoverDesign.bottomAreaHeight - HoverDesign.bottomPadding + 4
        // 分隔线
        let sepRect = NSRect(x: HoverDesign.cardPaddingX, y: topY,
                             width: bounds.width - HoverDesign.cardPaddingX * 2, height: 1)
        HoverDesign.bottomSeparator.setFill()
        sepRect.fill()

        // 左下：calendar.badge.plus
        let calRightAnchor = HoverDesign.cardPaddingX + 4 + HoverDesign.bottomSymbolPointSize
        let calCenterY = topY + HoverDesign.bottomAreaHeight / 2 + 2
        drawTintedSFSymbol("calendar.badge.plus",
                           color: HoverDesign.textTertiary,
                           pointSize: HoverDesign.bottomSymbolPointSize,
                           rightAnchor: calRightAnchor,
                           centerY: calCenterY)
        // 日历按钮 hit area：以图标为中心外扩 20x20
        calendarBtnRect = NSRect(x: calRightAnchor - HoverDesign.bottomSymbolPointSize - 4,
                                 y: calCenterY - 10,
                                 width: HoverDesign.bottomSymbolPointSize + 8,
                                 height: 20)

        // ② 右下：动态切换 "全部暂停" / "全部继续"
        //   有任一 running → "全部暂停" + pause.rectangle
        //   全部 paused → "全部继续" + play
        //   只有 scheduled → 不显示
        let hasRunning = !running.isEmpty
        let hasPaused = !paused.isEmpty
        let hasActive = hasRunning || hasPaused

        if hasActive {
            let pauseText = hasRunning ? "全部暂停" : "全部继续"
            let pauseIcon = hasRunning ? "pause.rectangle" : "play"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: HoverDesign.bottomFontSize, weight: .medium),
                .foregroundColor: HoverDesign.textTertiary
            ]
            let textSize = (pauseText as NSString).size(withAttributes: attr)
            let textRect = NSRect(
                x: bounds.width - HoverDesign.cardPaddingX - 4 - textSize.width,
                y: topY + (HoverDesign.bottomAreaHeight - textSize.height) / 2 + 2,
                width: textSize.width,
                height: textSize.height
            )
            (pauseText as NSString).draw(in: textRect, withAttributes: attr)

            // icon 在文字左侧
            let iconRightAnchor = textRect.minX - 4
            drawTintedSFSymbol(pauseIcon,
                               color: HoverDesign.textTertiary,
                               pointSize: HoverDesign.bottomSymbolPointSize,
                               rightAnchor: iconRightAnchor,
                               centerY: textRect.midY)

            // 暂停全部按钮 hit area：从 icon 左边缘到文字右边缘
            let iconSize = makeTintedSFSymbol(pauseIcon, color: HoverDesign.textTertiary,
                                              pointSize: HoverDesign.bottomSymbolPointSize)?.size.width ?? 0
            pauseAllBtnRect = NSRect(x: iconRightAnchor - iconSize,
                                     y: topY,
                                     width: textRect.maxX - (iconRightAnchor - iconSize),
                                     height: HoverDesign.bottomAreaHeight)
        } else {
            pauseAllBtnRect = .zero
        }
    }

    // MARK: - 鼠标 enter/exit 回调

    var onPanelMouseEntered: (() -> Void)?
    var onPanelMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onPanelMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPanelMouseExited?()
        // ④ 离开面板时清除 hover
        if hoveredEntryID != nil {
            hoveredEntryID = nil
            needsDisplay = true
        }
    }

    // ④ hover 高亮: mouseMoved 追踪鼠标在哪张卡片上
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var found: UUID?
        for entry in running + paused + scheduled {
            let cardRect = rectForEntry(entry)
            if cardRect.contains(point) {
                found = entry.id
                break
            }
        }
        if found != hoveredEntryID {
            hoveredEntryID = found
            needsDisplay = true
        }
    }

    // ① 按钮点击: mouseDown hit test
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 先检查按钮 hit area
        for (id, rect) in pauseRects where rect.contains(point) {
            onPauseToggle?(id)
            return
        }
        for (id, rect) in stopRects where rect.contains(point) {
            onStop?(id)
            return
        }

        // ⑤ 点击卡片主体区域 → 编辑标题
        for entry in running + paused + scheduled {
            let cardRect = rectForEntry(entry)
            if cardRect.contains(point) {
                startEditing(entry: entry, cardRect: cardRect)
                return
            }
        }

        // ② 底栏两个独立按钮
        if calendarBtnRect.contains(point) {
            onCalendarSchedule?()
            return
        }
        if pauseAllBtnRect.contains(point) {
            onToggleAllPause?()
            return
        }
    }

    /// 根据 entry 在当前列表中的位置计算卡片 rect (三组版本)
    private func rectForEntry(_ entry: TimerEntry) -> NSRect {
        let allEntries = running + paused + scheduled
        guard let index = allEntries.firstIndex(where: { $0.id == entry.id }) else {
            return .zero
        }
        var y: CGFloat = HoverDesign.topPadding
        for i in 0..<index {
            y += HoverDesign.cardHeight + HoverDesign.cardGap
            // running|paused 分隔线
            if i == running.count - 1 && !paused.isEmpty {
                y += HoverDesign.groupSeparatorHeight
            }
            // runningPaused|scheduled 分隔线
            if i == running.count + paused.count - 1 && !scheduled.isEmpty {
                y += HoverDesign.groupSeparatorHeight
            }
        }
        return NSRect(x: HoverDesign.cardPaddingX, y: y,
                      width: bounds.width - HoverDesign.cardPaddingX * 2,
                      height: HoverDesign.cardHeight)
    }

    /// 底栏区域 rect
    private func bottomBarRect() -> NSRect {
        let topY = bounds.height - HoverDesign.bottomAreaHeight - HoverDesign.bottomPadding + 4
        return NSRect(x: 0, y: topY, width: bounds.width, height: HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding)
    }

    // MARK: - ⑤ 编辑标题

    private var editingField: NSTextField?
    private var editingEntryID: UUID?

    /// 编辑期间禁用自动隐藏
    var isEditing: Bool { editingField != nil }

    private func startEditing(entry: TimerEntry, cardRect: NSRect) {
        // 已在编辑则跳过
        guard editingField == nil else { return }
        // 已有自定义标题的条目不再进入编辑，避免重复编辑锁定
        if let title = entry.predefinedTitle, !title.isEmpty { return }

        let contentX = cardRect.minX + HoverDesign.colorBarWidth + 10
        let contentW = cardRect.width - HoverDesign.colorBarWidth - 10 - 10

        // 标题行 y 坐标（和 drawRowContent 一致）
        let timeText = entry.displayTime
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: HoverDesign.timeFontSize(),
                                                        weight: entry.isRunning ? .bold : .regular)
        let timeAttr: [NSAttributedString.Key: Any] = [.font: timeFont]
        let timeSize = (timeText as NSString).size(withAttributes: timeAttr)

        let title = entry.predefinedTitle ?? entry.scheduledTitle ?? ""
        let titleFont = NSFont.systemFont(ofSize: HoverDesign.subtitleFontSize, weight: .regular)
        let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont]
        let titleSize = (title as NSString).size(withAttributes: titleAttr)

        let blockSpacing: CGFloat = 4
        let blockHeight = timeSize.height + blockSpacing + titleSize.height
        let blockStartY = cardRect.minY + (cardRect.height - blockHeight) / 2
        let titleY = blockStartY + timeSize.height + blockSpacing

        // 非 scheduled 条目右侧有 pause/stop 按钮（约 50pt），输入框留 8pt 边距；scheduled 条目可更宽
        let fieldWidth = entry.isScheduled ? contentW - 16 : contentW - 58
        let field = NSTextField(frame: NSRect(x: contentX, y: titleY - 2,
                                               width: max(40, fieldWidth),
                                               height: titleSize.height + 4))
        field.font = titleFont
        field.textColor = HoverDesign.textPrimary
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.stringValue = title
        field.placeholderString = "输入标题"
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.sizeToFit()
        // sizeToFit() 会改宽度，这里把宽度锁回目标值，y 与 drawRowContent 绘制位置严格对齐
        field.setFrameOrigin(NSPoint(x: contentX, y: titleY - 2))
        field.setFrameSize(NSSize(width: max(40, fieldWidth), height: field.frame.height))

        addSubview(field)
        editingField = field
        editingEntryID = entry.id
        window?.makeFirstResponder(field)
    }

    private func finishEditing(accept: Bool) {
        guard let field = editingField, let id = editingEntryID else { return }
        if accept {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            onTitleEdit?(id, text)
        }
        field.removeFromSuperview()
        editingField = nil
        editingEntryID = nil
        needsDisplay = true
    }
}

// MARK: - NSTextFieldDelegate (⑤ 编辑标题)

extension HoverListView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        // 失去焦点 = 提交
        finishEditing(accept: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(accept: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishEditing(accept: false)
            return true
        }
        return false
    }
}

// MARK: - HoverTrackingOverlay

/// 透明 NSView —— 嵌到 statusItem.button 上作为 NSTrackingArea owner
/// hitTest 返回 nil 让事件穿透到 button，鼠标进出仍能正常触发
final class HoverTrackingOverlay: NSView {

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

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

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
