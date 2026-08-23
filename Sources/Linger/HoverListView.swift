import Cocoa

// MARK: - 设计 token

private enum HoverDesign {
    // 颜色：暗色毛玻璃（对齐 hover-list.html glass-panel），暖橙主色（仅 running）
    static let panelBg = NSColor(calibratedRed: 24/255.0, green: 24/255.0, blue: 28/255.0, alpha: 0.72)
    static let rowHover = NSColor(calibratedWhite: 1.0, alpha: 0.06)       // hover 行淡高亮
    static let rowDivider = NSColor(calibratedWhite: 1.0, alpha: 0.07)     // 行间 1px 分隔线（弱，突出分组线）
    static let groupSeparator = NSColor(calibratedWhite: 0.5, alpha: 0.22)  // 分组分隔线（灰色，克制）
    static let bottomSeparator = NSColor(calibratedWhite: 1.0, alpha: 0.10)
    static let progressTrack = NSColor(calibratedWhite: 1.0, alpha: 0.06)  // 原型 timer-progress

    static let amber = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 1.0)
    static let amberSoft = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 0.14)
    static let amberDim = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 0.45)
    static let textPrimary = NSColor.white
    static let textSecondary = NSColor(calibratedWhite: 1.0, alpha: 0.55)
    static let textTertiary = NSColor(calibratedWhite: 1.0, alpha: 0.42)

    // 尺寸：紧凑平铺列表（对齐 hover-list.html：300pt、圆角 16、行间 1px 分隔）
    static let panelCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 8
    static let cardPaddingX: CGFloat = 14          // px-3.5
    static let cardPaddingY: CGFloat = 8
    static let cardGap: CGFloat = 0                // 平铺，行间用分隔线
    static let colorBarWidth: CGFloat = 0          // 去掉左色条
    static let cardHeight: CGFloat = 52
    static let progressBarHeight: CGFloat = 2      // 原型 timer-progress 2px
    static let topPadding: CGFloat = 8
    static let bottomAreaHeight: CGFloat = 36
    static let bottomPadding: CGFloat = 8
    static let groupSeparatorHeight: CGFloat = 16

    // 字体（对齐原型：时间 13px 等宽 semibold、标题 13px）
    static func timeFontSize() -> CGFloat {
        let v = CGFloat(UserDefaults.standard.float(forKey: "linger_hoverListFontSize"))
        return v > 0 ? v : 13
    }
    static let subtitleFontSize: CGFloat = 11
    static let bottomFontSize: CGFloat = 12
    static let badgeFontSize: CGFloat = 11
    static let symbolPointSize: CGFloat = 11
    static let bottomSymbolPointSize: CGFloat = 13

    static let panelWidth: CGFloat = 300
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

    /// .accessory 应用 + 无边框 statusBar 窗口的已知坑：点击窗口内的文本控件时，
    /// 窗口不一定自动成为 key window，导致 NSTextField 无法成为 firstResponder。
    /// 在事件派发前强制 makeKey + activate，保证点击任意输入框都能直接输入。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
}

// MARK: - HoverProgressBar（CALayer 动画进度条）

/// 2px 高圆角进度条（对齐 hover-list.html .timer-progress）：
/// 琥珀渐变 fill + 发光 glow；running 时渐变流动动画；paused 降透明；scheduled 灰色。
final class HoverProgressBar: NSView {

    /// 进度条状态（决定渐变/发光/流动/透明度）
    enum Style { case running, paused, scheduled }
    var style: Style = .running { didSet { applyStyle() } }

    /// 最后 10s 提醒：进度条琥珀闪烁。
    /// 相位由 HoverListView 的 urgentBlinkTimer 统一驱动（applyUrgentBlinkPhase），
    /// 与倒计时数字严格同步，不再各自跑 CAAnimation。
    var urgent: Bool = false {
        didSet {
            guard urgent != oldValue else { return }
            if urgent {
                fillContainer.opacity = 1.0   // 进入提醒即亮
            } else {
                fillContainer.opacity = (style == .paused) ? 0.40 : 1.0
            }
        }
    }

    /// 由外部统一相位驱动：on=true 亮、false 暗（仅 urgent 时生效）
    func applyUrgentBlinkPhase(_ on: Bool) {
        guard urgent else { return }
        fillContainer.opacity = on ? 1.0 : 0.30
    }

    private let fillContainer = CALayer()      // 进度容器（发光 + 圆角 + 裁剪）
    private let fillGradient = CAGradientLayer()
    private var currentProgress: CGFloat = 0
    /// 标记是否已完成首次布局（首次无动画直接从当前进度开始）
    var hasInitialProgress: Bool = false

    private static let glowColor = NSColor(calibratedRed: 0.961, green: 0.651, blue: 0.137, alpha: 0.40)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = HoverDesign.progressTrack.cgColor
        layer?.cornerRadius = frameRect.height / 2

        fillContainer.cornerRadius = frameRect.height / 2
        fillContainer.masksToBounds = true
        fillContainer.shadowColor = Self.glowColor.cgColor
        fillContainer.shadowRadius = 3
        fillContainer.shadowOpacity = 1
        fillContainer.shadowOffset = .zero

        fillGradient.colors = [
            HoverDesign.amber.withAlphaComponent(0.70).cgColor,
            HoverDesign.amber.cgColor,
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1.0).cgColor
        ]
        fillGradient.locations = [0.0, 0.55, 1.0]
        fillContainer.addSublayer(fillGradient)
        layer?.addSublayer(fillContainer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        fillContainer.cornerRadius = bounds.height / 2
        // 同步当前进度下的 frame（layout 不触发进度动画）
        updateFillFrame(animated: false)
    }

    func setProgress(_ p: CGFloat, animated: Bool) {
        currentProgress = max(0, min(1, p))
        updateFillFrame(animated: animated)
    }

    private func updateFillFrame(animated: Bool) {
        let targetRect = NSRect(x: 0, y: 0,
                                width: max(bounds.height, bounds.width * currentProgress),
                                height: bounds.height)
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillContainer.frame = targetRect
            CATransaction.commit()
        } else {
            let anim = CABasicAnimation(keyPath: "frame")
            anim.fromValue = NSValue(rect: fillContainer.frame)
            anim.toValue = NSValue(rect: targetRect)
            anim.duration = 0.3
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            fillContainer.add(anim, forKey: "progressAnim")
            fillContainer.frame = targetRect
        }
        syncGradientFrame()
    }

    /// 渐变层宽度 = 容器 2 倍，供流动动画平移
    private func syncGradientFrame() {
        fillGradient.frame = NSRect(x: 0, y: 0,
                                    width: max(1, fillContainer.bounds.width * 2),
                                    height: fillContainer.bounds.height)
    }

    private func applyStyle() {
        switch style {
        case .running:
            fillContainer.opacity = 1
            fillContainer.shadowOpacity = 1
            fillGradient.colors = [
                HoverDesign.amber.withAlphaComponent(0.70).cgColor,
                HoverDesign.amber.cgColor,
                NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1.0).cgColor
            ]
            startFlowIfNeeded()
        case .paused:
            fillContainer.opacity = 0.40
            fillContainer.shadowOpacity = 0.4
            fillGradient.colors = [
                HoverDesign.amber.withAlphaComponent(0.28).cgColor,
                HoverDesign.amber.withAlphaComponent(0.45).cgColor,
                HoverDesign.amber.withAlphaComponent(0.60).cgColor
            ]
            stopFlow()
        case .scheduled:
            fillContainer.opacity = 0.30
            fillContainer.shadowOpacity = 0
            fillGradient.colors = [NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor]
            stopFlow()
        }
    }

    /// running：渐变流动动画（对齐原型 progress-flow 2.4s 无限循环）
    private func startFlowIfNeeded() {
        if fillGradient.animation(forKey: "flow") != nil { return }
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -fillContainer.bounds.width
        anim.duration = 2.4
        anim.repeatCount = .greatestFiniteMagnitude
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        fillGradient.add(anim, forKey: "flow")
    }

    private func stopFlow() {
        fillGradient.removeAnimation(forKey: "flow")
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
    /// 预约行的删除按钮 hit rect
    private var deleteScheduledRects: [UUID: NSRect] = [:]

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
    /// 预约行删除按钮（删除计时 + 同步删除日历事件）
    var onDeleteScheduled: ((UUID) -> Void)?
    // ② 底栏回调
    var onToggleAllPause: (() -> Void)?
    /// 内联预约确认（start, duration, title）—— 由 MenuBarManager 创建预约计时
    var onScheduleConfirm: ((Date, TimeInterval, String) -> Void)?
    /// 内联预约编辑视图（原型：hover-list 底部内联展开，非独立窗口）
    private var scheduleView: ScheduleTimerView?
    var isScheduling: Bool = false
    /// 底栏日历预约按钮（脉动/点击/激活反馈）
    private let calendarButton = CalendarPulseButton()
    // ⑤ 编辑标题回调
    var onTitleEdit: ((UUID, String) -> Void)?

    // 底栏「全部暂停」按钮 hit rect（drawBottomArea 中计算）
    private var pauseAllBtnRect: NSRect = .zero

    // 最后 10s 提醒：时间文本闪烁状态
    private var urgentBlinkOn = false
    private var urgentBlinkTimer: Timer?
    /// 悬浮窗整体高度动画 timer（onHeightAnimation 回调驱动外部改 HoverListView bounds）
    private var heightAnimTimer: Timer?
    /// scheduleView 自身高度动画 timer（expand / close），独立于 heightAnimTimer
    /// 否则 closeInlineSchedule 里 notifyHeightChange → animateHeight 会把刚创建的 close timer invalidate 掉
    private var scheduleHeightAnimTimer: Timer?

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

        // 3. 更新数据（原有逻辑 + 修复：已激活的预约 isRunning=true 但 isScheduled 仍为 true，
        //    需按 isRunning 归入 running/paused，未触发的留 scheduled）
        let sorted = newFiltered.sorted { $0.remainingTime < $1.remainingTime }
        running = sorted.filter { (!$0.isScheduled || $0.isRunning) && !$0.isPaused }
        paused = sorted.filter { (!$0.isScheduled || $0.isRunning) && $0.isPaused }
        scheduled = sorted.filter { $0.isScheduled && !$0.isRunning }

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
        // 底栏日历按钮定位（与 drawBottomArea 底栏同位置）+ 首次接线
        if calendarButton.superview == nil {
            calendarButton.onClick = { [weak self] in
                self?.toggleInlineSchedule()
            }
            addSubview(calendarButton)
        }
        let topY = bounds.height - HoverDesign.bottomAreaHeight - HoverDesign.bottomPadding + 4
        let btnSize: CGFloat = 28
        let btnCenterX = HoverDesign.cardPaddingX + 4 + btnSize / 2
        let btnCenterY = topY + HoverDesign.bottomAreaHeight / 2 + 2
        calendarButton.frame = NSRect(x: btnCenterX - btnSize / 2, y: btnCenterY - btnSize / 2,
                                      width: btnSize, height: btnSize)
        // 收起态脉动提示
        if !isScheduling {
            calendarButton.startHintPulse()
        }
        // 内联预约区：位于底栏上方（原型：计时列表 → 编辑区 → 底栏）。
        // HoverListView isFlipped（y 向下、原点左上），底部 = bounds.height，
        // 底栏高约 40pt，编辑区底边贴底栏顶。
        if let sv = scheduleView {
            let bottomBarTop = HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding - 4
            sv.frame = NSRect(x: HoverDesign.cardPaddingX,
                              y: bounds.height - bottomBarTop - sv.frame.height,
                              width: bounds.width - HoverDesign.cardPaddingX * 2,
                              height: sv.frame.height)
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

        // 最后 10s 提醒：有运行中且剩余 ≤10s 的条目时启动文字闪烁
        refreshUrgentBlink()
    }

    /// 扫描运行中条目：剩余 ≤10s → 启动时间文本闪烁；否则停止。
    private func refreshUrgentBlink() {
        let hasUrgent = running.contains { $0.remainingTime <= 10 }
        if hasUrgent {
            guard urgentBlinkTimer == nil else { return }
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.urgentBlinkOn.toggle()
                // 进度条与倒计时数字用同一相位，严格同步
                for entry in self.running where entry.remainingTime <= 10 {
                    self.progressBars[entry.id]?.applyUrgentBlinkPhase(self.urgentBlinkOn)
                }
                self.needsDisplay = true
            }
            RunLoop.main.add(t, forMode: .common)
            urgentBlinkTimer = t
        } else {
            urgentBlinkTimer?.invalidate()
            urgentBlinkTimer = nil
            urgentBlinkOn = false
        }
    }

    deinit {
        urgentBlinkTimer?.invalidate()
        heightAnimTimer?.invalidate()
        scheduleHeightAnimTimer?.invalidate()
    }

    private func updateProgressBarsAnimated() {
        for entry in running + paused + scheduled {
            guard let pb = progressBars[entry.id] else { continue }
            guard let newY = newCardYs[entry.id] else { continue }
            let oldY = oldCardYs[entry.id] ?? newY
            let interpolatedY = oldY + (newY - oldY) * animProgress
            let progressY = interpolatedY + HoverDesign.cardHeight - HoverDesign.progressBarHeight - 10
            let progressX = HoverDesign.cardPaddingX
            let progressW = bounds.width - HoverDesign.cardPaddingX * 2
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
        // 进度条贴行底部（原型 mt-2 + pb-2.5），左右与内容同 padding
        let progressY = y + HoverDesign.cardHeight - HoverDesign.progressBarHeight - 10
        let progressX = contentX
        let progressW = contentW
        pb.frame = NSRect(x: progressX, y: progressY, width: progressW, height: HoverDesign.progressBarHeight)
        // ⑦ 状态: running=渐变+发光+流动, paused=降透明, scheduled=灰色
        // 预约「待开始」= 灰色；已激活运行/暂停的预约按实际状态渲染
        if entry.isScheduled && !entry.isRunning && !entry.isPaused {
            pb.style = .scheduled
            pb.urgent = false
        } else if entry.isPaused {
            pb.style = .paused
            pb.urgent = false
        } else {
            pb.style = .running
            // 最后 10s：进度条琥珀闪烁提醒
            pb.urgent = (entry.remainingTime <= 10)
        }
        let progress = computeProgress(entry: entry)
        pb.setProgress(CGFloat(progress), animated: pb.hasInitialProgress)
        pb.hasInitialProgress = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let _ = NSGraphicsContext.current?.cgContext else { return }
        drawPanelBackground()

        if running.isEmpty && paused.isEmpty && scheduled.isEmpty && removedEntries.isEmpty {
            drawEmptyHint()
            drawBottomArea()   // 空态也保留底栏分隔线 + 日历按钮（预约入口）
            return
        }

        // 绘制分隔线（带动画）
        drawSeparatorsWithAnimation()

        // 绘制存活卡片（带插值位置；组内行间画 1px 分隔线，组间由 drawSeparatorsWithAnimation 处理）
        var y: CGFloat = HoverDesign.topPadding
        for (i, entry) in running.enumerated() {
            drawCardInterpolated(entry: entry, targetY: y, drawDivider: i < running.count - 1)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }
        if !running.isEmpty && !paused.isEmpty { y += HoverDesign.groupSeparatorHeight }
        for (i, entry) in paused.enumerated() {
            drawCardInterpolated(entry: entry, targetY: y, drawDivider: i < paused.count - 1)
            y += HoverDesign.cardHeight + HoverDesign.cardGap
        }
        if (!running.isEmpty || !paused.isEmpty) && !scheduled.isEmpty { y += HoverDesign.groupSeparatorHeight }
        for (i, entry) in scheduled.enumerated() {
            drawCardInterpolated(entry: entry, targetY: y, drawDivider: i < scheduled.count - 1)
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
            drawGroupSeparator(at: drawY, alpha: alpha)
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
            drawGroupSeparator(at: drawY, alpha: alpha)
            sepIndex += 1
        }

        // 旧分隔线淡出（超出新分隔线数量的部分）
        if isAnimating && sepIndex < oldSeparatorYs.count {
            for i in sepIndex..<oldSeparatorYs.count {
                drawGroupSeparator(at: oldSeparatorYs[i], alpha: 1.0 - p)
            }
        }
    }

    /// 统一的分组分隔线：发丝线优化方案（40pt 居中，灰色 0.22 alpha）
    /// 设计意图：最克制的视觉锚点，仅暗示分组边界，不抢内容焦点
    private func drawGroupSeparator(at y: CGFloat, alpha: CGFloat) {
        let lineLength: CGFloat = 40
        let x = (bounds.width - lineLength) / 2
        HoverDesign.groupSeparator.withAlphaComponent(alpha).setFill()
        NSRect(x: x, y: y, width: lineLength, height: 1).fill()
    }

    private func drawCardInterpolated(entry: TimerEntry, targetY: CGFloat, drawDivider: Bool = true) {
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
        drawCard(entry: entry, y: drawY, alpha: alpha, drawDivider: drawDivider)
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
        // 垂直居中在底栏上方的内容区
        let bottomTop = bounds.height - HoverDesign.bottomAreaHeight - HoverDesign.bottomPadding
        let centerY = (bounds.height - size.height) / 2
        let y = min(centerY, bottomTop / 2)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: y,
                          width: size.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attr)
    }

    // MARK: - 卡片

    private func drawCard(entry: TimerEntry, y: CGFloat, alpha: CGFloat = 1.0, scale: CGFloat = 1.0, drawDivider: Bool = true) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let rowRect = NSRect(x: HoverDesign.cardPaddingX, y: y,
                             width: bounds.width - HoverDesign.cardPaddingX * 2,
                             height: HoverDesign.cardHeight)
        if scale != 1.0 {
            let cx = rowRect.midX
            let cy = rowRect.midY
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -cx, y: -cy)
        }
        if alpha < 1.0 {
            ctx.setAlpha(alpha)
        }

        // ④ hover 高亮：平铺行用极淡背景（对齐原型，无卡片/色条）
        // 2026-08-06：高亮保持行全宽，内容向内缩 12pt 留出左右内边距，
        // 避免计时元素紧贴高亮边缘（之前误把高亮向内缩，反而更窄）
        if hoveredEntryID == entry.id {
            HoverDesign.rowHover.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: 8, yRadius: 8).fill()
        }

        // 内容区在高亮内缩 12pt 排版，分隔线仍贯穿整行
        let contentRect = rowRect.insetBy(dx: 12, dy: 0)
        drawRowContent(entry: entry, rowRect: contentRect)

        // 组内行间 1px 分隔线（原型 h-px line）
        if drawDivider {
            HoverDesign.rowDivider.setFill()
            NSRect(x: rowRect.minX, y: rowRect.minY - 0.5, width: rowRect.width, height: 1).fill()
        }

        // 被移除的卡片（alpha < 1.0）不保留 hit rects，避免动画期间误触
        if alpha < 1.0 {
            pauseRects.removeValue(forKey: entry.id)
            stopRects.removeValue(forKey: entry.id)
            deleteScheduledRects.removeValue(forKey: entry.id)
        }

        ctx.restoreGState()
    }

    private func drawRowContent(entry: TimerEntry, rowRect: NSRect) {
        let contentX = rowRect.minX
        let centerY = rowRect.midY

        // 右侧控件（按钮/badge），返回时间文本右对齐锚点
        let rightAnchor = drawRightControls(entry: entry, rowRect: rowRect, centerY: centerY)

        // 时间文本（右对齐于按钮左侧；running 琥珀 / paused 白 / scheduled 灰）
        let timeText = entry.displayTime
        let timeColor: NSColor
        let timeWeight: NSFont.Weight
        if entry.isScheduled && !entry.isRunning && !entry.isPaused {
            timeColor = NSColor(calibratedWhite: 1.0, alpha: 0.4)
            timeWeight = .regular
        } else if entry.isPaused {
            timeColor = HoverDesign.textPrimary
            timeWeight = .semibold
        } else {
            // running：最后 10s 用琥珀强调色闪烁提醒
            if entry.remainingTime <= 10 {
                timeColor = urgentBlinkOn ? HoverDesign.amber : HoverDesign.amber.withAlphaComponent(0.35)
            } else {
                timeColor = HoverDesign.amber
            }
            timeWeight = .semibold
        }
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: HoverDesign.timeFontSize(), weight: timeWeight)
        let timeAttr: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: timeColor]
        let timeSize = (timeText as NSString).size(withAttributes: timeAttr)
        let timeRect = NSRect(x: rightAnchor - 12 - timeSize.width,
                              y: centerY - timeSize.height / 2,
                              width: timeSize.width,
                              height: timeSize.height)
        (timeText as NSString).draw(in: timeRect, withAttributes: timeAttr)

        // 左侧标题区（最大宽度到时间左缘）
        let maxTitleX = timeRect.minX - 16
        drawLeftTitle(entry: entry, contentX: contentX, centerY: centerY, maxWidth: maxTitleX - contentX)
    }

    /// 左区标题：running = 铅笔 + 文本(placeholder「日程」) + 回车图标（视觉 = 原型输入框）；
    /// paused/scheduled = 名称文本。
    private func drawLeftTitle(entry: TimerEntry, contentX: CGFloat, centerY: CGFloat, maxWidth: CGFloat) {
        // 该行正在编辑时，左区完全交给输入框，不再绘制铅笔/文本/回车
        //（否则占位文本与 NSTextField 叠加成重影，且每次重绘闪烁）
        if editingEntryID == entry.id { return }

        let hasTitle = !(entry.predefinedTitle ?? "").isEmpty
        var x = contentX

        // running（含已激活的预约）= 铅笔 + 可编辑文本；paused/scheduled = 名称文本（灰色暗示未运行）
        if entry.isRunning && !entry.isPaused {
            // 铅笔
            if let pencil = makeTintedSFSymbol("pencil", color: HoverDesign.textTertiary, pointSize: 12) {
                pencil.draw(in: NSRect(x: x, y: centerY - pencil.size.height / 2,
                                       width: pencil.size.width, height: pencil.size.height))
                x += pencil.size.width + 6
            }
            // 文本 / placeholder（回车图标只在编辑时显示在输入框最右侧，见 startEditing）
            let text = hasTitle ? entry.predefinedTitle! : "日程"
            let color = hasTitle ? HoverDesign.textPrimary : HoverDesign.textTertiary
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: color
            ]
            let textSize = (text as NSString).size(withAttributes: attr)
            let drawW = min(textSize.width, max(20, maxWidth))
            (text as NSString).draw(in: NSRect(x: x, y: centerY - textSize.height / 2,
                                               width: drawW, height: textSize.height),
                                    withAttributes: attr)
        } else {
            // paused（已暂停）和 scheduled（未开始）：标题用灰色 textTertiary 暗示非运行态
            let text = hasTitle ? entry.predefinedTitle! : (entry.scheduledTitle ?? "")
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: HoverDesign.textTertiary
            ]
            let textSize = (text as NSString).size(withAttributes: attr)
            let drawW = min(textSize.width, max(20, maxWidth))
            (text as NSString).draw(in: NSRect(x: x, y: centerY - textSize.height / 2,
                                               width: drawW, height: textSize.height),
                                    withAttributes: attr)
        }
    }

    /// 右侧控件；返回时间文本右对齐锚点（badge/按钮左缘）。
    private func drawRightControls(entry: TimerEntry, rowRect: NSRect, centerY: CGFloat) -> CGFloat {
        let rightEdge = rowRect.maxX

        // 预约「待开始」：✕ 删除按钮 + 徽标；已激活运行的预约走正常控制
        if entry.isScheduled && !entry.isRunning && !entry.isPaused {
            pauseRects.removeValue(forKey: entry.id)
            stopRects.removeValue(forKey: entry.id)
            // 右侧：删除按钮（xmark，点击删除计时 + 同步删日历事件）+ 「待开始」徽标在左
            let iconSize = HoverDesign.symbolPointSize
            drawTintedSFSymbol("xmark",
                               color: HoverDesign.textTertiary,
                               pointSize: iconSize,
                               rightAnchor: rightEdge,
                               centerY: centerY)
            let hitPad: CGFloat = iconSize
            let delRect = NSRect(x: rightEdge - iconSize,
                                 y: centerY - iconSize / 2,
                                 width: iconSize,
                                 height: iconSize)
            deleteScheduledRects[entry.id] = delRect.insetBy(dx: -hitPad, dy: -hitPad)

            let text = "待开始"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: HoverDesign.badgeFontSize, weight: .medium),
                .foregroundColor: HoverDesign.textTertiary
            ]
            let size = (text as NSString).size(withAttributes: attr)
            let rect = NSRect(x: rightEdge - iconSize - 12 - size.width,
                              y: centerY - size.height / 2,
                              width: size.width,
                              height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attr)
            return rect.minX
        }

        let isPaused = entry.isPaused
        // stop 在右缘；pause/play 在 stop 左 20pt（原型：square 14 / pause|play 15）
        // 操作按钮图标用次级中性色，不抢时间数字的琥珀强调焦点
        // （琥珀仅用于 running 时间数字 + 进度条 fill 这类 active 核心数据）
        drawTintedSFSymbol("stop.fill",
                           color: HoverDesign.textTertiary,
                           pointSize: HoverDesign.symbolPointSize,
                           rightAnchor: rightEdge,
                           centerY: centerY)
        drawTintedSFSymbol(isPaused ? "play.fill" : "pause.fill",
                           color: HoverDesign.textSecondary,
                           pointSize: HoverDesign.symbolPointSize,
                           rightAnchor: rightEdge - 20,
                           centerY: centerY)

        let hitPad: CGFloat = HoverDesign.symbolPointSize
        let stopRect = NSRect(x: rightEdge - HoverDesign.symbolPointSize,
                              y: centerY - HoverDesign.symbolPointSize / 2,
                              width: HoverDesign.symbolPointSize,
                              height: HoverDesign.symbolPointSize)
        stopRects[entry.id] = stopRect.insetBy(dx: -hitPad, dy: -hitPad)
        let pauseRect = NSRect(x: rightEdge - 20 - HoverDesign.symbolPointSize,
                               y: centerY - HoverDesign.symbolPointSize / 2,
                               width: HoverDesign.symbolPointSize,
                               height: HoverDesign.symbolPointSize)
        pauseRects[entry.id] = pauseRect.insetBy(dx: -hitPad, dy: -hitPad)

        return rightEdge - 20 - HoverDesign.symbolPointSize
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
        HoverDesign.bottomSeparator.setFill()
        NSRect(x: HoverDesign.cardPaddingX, y: topY,
               width: bounds.width - HoverDesign.cardPaddingX * 2, height: 1).fill()

        // 左下日历按钮由 CalendarPulseButton 承担（脉动/点击/激活），此处不再绘制

        // ② 右下：动态切换 "全部暂停" / "全部继续"
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

            let iconRightAnchor = textRect.minX - 4
            drawTintedSFSymbol(pauseIcon,
                               color: HoverDesign.textTertiary,
                               pointSize: HoverDesign.bottomSymbolPointSize,
                               rightAnchor: iconRightAnchor,
                               centerY: textRect.midY)

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

    // ④ hover 高亮: mouseMoved 追踪鼠标在哪张卡片/底栏按钮上
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
        for (id, rect) in deleteScheduledRects where rect.contains(point) {
            onDeleteScheduled?(id)
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

        // ② 底栏日历按钮（CalendarPulseButton 视觉 + 此处区域判定兜底，确保点击必触发）
        if calendarButton.frame.contains(point) {
            calendarButton.playTap()
            toggleInlineSchedule()
            return
        }
        // ② 底栏「全部暂停」按钮
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

    // MARK: - 内联预约展开（原型：hover-list 底部内联，无独立窗口）

    private func toggleInlineSchedule() {
        if scheduleView != nil {
            closeInlineSchedule()
        } else {
            expandInlineSchedule()
        }
    }

    /// 展开：日历按钮反馈 → 浮窗延长 → 220ms 后编辑区高度动画 + 内容滑入（原型时序）
    private func expandInlineSchedule() {
        calendarButton.setActive(true)   // 停止脉动 + is-active
        let h = ScheduleTimerView.preferredHeight()
        let pad = HoverDesign.cardPaddingX
        let v = ScheduleTimerView(frame: NSRect(x: pad, y: 0,
                                                width: bounds.width - pad * 2,
                                                height: 0))
        v.wantsLayer = true
        v.layer?.masksToBounds = true    // clipsToBounds：编辑区从底部「长出来」
        v.onConfirm = { [weak self] start, dur, title in
            guard let self else { return }
            // spec §13.4 / §2.5：编辑区收回 → 420ms 后新日程滑入
            self.closeInlineSchedule()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
                self?.onScheduleConfirm?(start, dur, title)
            }
        }
        v.onCancel = { [weak self] in
            self?.closeInlineSchedule()
        }
        addSubview(v)
        scheduleView = v
        isScheduling = true
        // 菜单栏 app（.accessory）必须 activate 才能 makeKey + firstResponder 接收键盘输入
        // makeKeyAndOrderFront 比 makeKey 更可靠：显式 orderFront 让窗口真正成为 key window
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // reduced-motion：跳过动画直接设最终高度 + 显示内容
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let bottomBarTop = HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding - 4
            let superH = bounds.height
            v.frame = NSRect(x: pad, y: superH - bottomBarTop - h,
                             width: bounds.width - pad * 2, height: h)
            v.alphaValue = 1
            v.contentContainerTransformIdentity()
            notifyHeightChange()
            return
        }

        notifyHeightChange()             // 浮窗高度延长（0.38s，与编辑区同步）

        // 220ms 后编辑区高度 0→preferredHeight（380ms）+ 内容滑入/淡入
        let token = scheduleView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.scheduleView === token else { return }
            self.animateScheduleViewHeight(to: h)
            v.revealContent()
        }
    }

    /// 编辑区高度动画（0→h，380ms cubic-bezier(.2,.8,.2,1) 近似）。
    /// 用手动 timer 插值 frame（animator 在此场景可能不生效导致高度停在 0 → 内容被裁空白）。
    /// 独立 scheduleHeightAnimTimer，避免被 animateHeight 的 invalidate 误杀。
    private func animateScheduleViewHeight(to h: CGFloat) {
        guard let sv = scheduleView else { return }
        scheduleHeightAnimTimer?.invalidate()
        let startH = sv.frame.height
        let start = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.38
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak sv] t in
            guard let self, let sv else { t.invalidate(); return }
            let p = CGFloat(min(1, (CACurrentMediaTime() - start) / duration))
            let eased = CGFloat(1 - pow(1 - Double(p), 3))   // cubic-bezier(.2,.8,.2,1) 近似
            let hh = startH + (h - startH) * eased
            let bottomBarTop = HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding - 4
            let superH: CGFloat = sv.superview?.bounds.height ?? self.bounds.height
            sv.frame = NSRect(x: sv.frame.minX,
                              y: superH - bottomBarTop - hh,
                              width: sv.frame.width, height: hh)
            if p >= 1 {
                t.invalidate()
                self.scheduleHeightAnimTimer = nil
                // 延迟到当前 layout pass 结束后再强制解析子树（直接调用会触发
                // "layoutSubtreeIfNeeded on a view already being laid out" 警告）
                DispatchQueue.main.async { [weak sv] in
                    sv?.layoutSubtreeIfNeeded()
                    sv?.window?.contentView?.layoutSubtreeIfNeeded()
                }
                // 动画结束再确认一次 key window（保险）
                NSApp.activate(ignoringOtherApps: true)
                sv.window?.makeKeyAndOrderFront(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleHeightAnimTimer = timer
    }

    private func closeInlineSchedule() {
        guard let sv = scheduleView else { return }
        calendarButton.setActive(false)  // 恢复收起 + 脉动
        isScheduling = false
        // 编辑区收回（高度→0 + 内容淡出）与浮窗变矮并行
        sv.hideContent()
        // reduced-motion：跳过动画直接收起
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            sv.frame.size.height = 0
            sv.alphaValue = 0
            sv.removeFromSuperview()
            scheduleView = nil
            scheduleHeightAnimTimer?.invalidate()
            scheduleHeightAnimTimer = nil
            notifyHeightChange()
            return
        }
        // 高度动画用手动 timer（与 expand 一致；独立 scheduleHeightAnimTimer 避免被 animateHeight invalidate）
        scheduleHeightAnimTimer?.invalidate()
        let startH = sv.frame.height
        let targetH: CGFloat = 0
        let start = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.38
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak sv] t in
            guard let self, let sv else { t.invalidate(); return }
            let p = CGFloat(min(1, (CACurrentMediaTime() - start) / duration))
            let eased = CGFloat(1 - pow(1 - Double(p), 3))   // cubic-bezier(.2,.8,.2,1) 近似
            let hh = startH + (targetH - startH) * eased
            let bottomBarTop = HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding - 4
            let superH: CGFloat = sv.superview?.bounds.height ?? self.bounds.height
            sv.frame = NSRect(x: sv.frame.minX,
                              y: superH - bottomBarTop - hh,
                              width: sv.frame.width, height: hh)
            if p >= 1 {
                t.invalidate()
                sv.removeFromSuperview()
                self.scheduleView = nil
                self.scheduleHeightAnimTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleHeightAnimTimer = timer
        notifyHeightChange()
    }

    private func notifyHeightChange() {
        animateHeight(to: currentContentHeight())
    }

    /// 悬浮窗高度变化动画（0.3s，顶部固定由 MenuBarManager 保证）
    private func animateHeight(to target: CGFloat) {
        heightAnimTimer?.invalidate()
        let startH = bounds.height
        let start = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.38
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let p = min(1, (CACurrentMediaTime() - start) / duration)
            // cubic-bezier(.2,.8,.2,1) 近似：先快后慢
            let eased = 1 - pow(1 - p, 3)
            let h = startH + (target - startH) * eased
            self.onHeightAnimation?(h)
            if p >= 1 {
                t.invalidate()
                self.heightAnimTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heightAnimTimer = timer
    }

    private func currentContentHeight() -> CGFloat {
        let base = HoverListView.panelHeight3(runningCount: running.count,
                                              pausedCount: paused.count,
                                              scheduledCount: scheduled.count)
        return base + (isScheduling ? ScheduleTimerView.preferredHeight() + 12 : 0)
    }

    /// 底栏区域 rect
    private func bottomBarRect() -> NSRect {
        let topY = bounds.height - HoverDesign.bottomAreaHeight - HoverDesign.bottomPadding + 4
        return NSRect(x: 0, y: topY, width: bounds.width, height: HoverDesign.bottomAreaHeight + HoverDesign.bottomPadding)
    }

    // MARK: - ⑤ 编辑标题

    private var editingField: NSTextField?
    private var editingEntryID: UUID?
    /// 编辑期输入框最右侧的灰色回车暗示图标（↩︎）
    private var editingReturnIcon: NSView?

    /// 编辑期间禁用自动隐藏
    var isEditing: Bool { editingField != nil }

    private func startEditing(entry: TimerEntry, cardRect: NSRect) {
        // 已在编辑则跳过
        guard editingField == nil else { return }
        // 已有自定义标题的暂停/预约条目不重复编辑（运行中行常驻输入框语义，始终可编辑）
        if !entry.isRunning, let title = entry.predefinedTitle, !title.isEmpty { return }

        let contentX = cardRect.minX                       // 与 drawLeftTitle 起点一致
        let centerY = cardRect.midY
        // 输入框宽度按右侧时间文本实际宽度收窄，保证回车图标不被时间挡住：
        // 时间左缘 = 右缘 - 按钮区(31) - 间距(12) - 时间宽；再留出图标(≈12)+间距
        let rightEdge = cardRect.maxX
        let timeText = entry.displayTime
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: HoverDesign.timeFontSize(), weight: .semibold)
        let timeW = (timeText as NSString).size(withAttributes: [.font: timeFont]).width
        let timeLeft = rightEdge - 31 - 12 - timeW
        let fieldWidth = max(40, timeLeft - 10 - 6 - 12 - contentX)
        let fieldHeight: CGFloat = 18
        let field = NSTextField(frame: NSRect(x: contentX, y: centerY - fieldHeight / 2,
                                               width: max(40, fieldWidth),
                                               height: fieldHeight + 4))
        field.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        field.textColor = HoverDesign.textPrimary
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.stringValue = entry.predefinedTitle ?? entry.scheduledTitle ?? ""
        // 用户要求：输入时不要显示「日程」占位（多此一举）
        field.placeholderString = nil
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        // 固定 frame（不 sizeToFit），避免输入框创建瞬间高度跳动
        field.frame = NSRect(x: contentX, y: centerY - fieldHeight / 2,
                             width: max(40, fieldWidth), height: fieldHeight + 4)

        addSubview(field)
        editingField = field
        editingEntryID = entry.id

        // 输入框最右侧的灰色回车暗示（↩︎）：按回车提交
        if let ret = makeTintedSFSymbol("return", color: HoverDesign.textTertiary, pointSize: 10) {
            let icon = NSImageView(image: ret)
            icon.frame = NSRect(x: field.frame.maxX + 6,
                                y: centerY - ret.size.height / 2,
                                width: ret.size.width,
                                height: ret.size.height)
            addSubview(icon)
            editingReturnIcon = icon
        }

        window?.makeFirstResponder(field)
    }

    private func finishEditing(accept: Bool) {
        guard let field = editingField, let id = editingEntryID else { return }
        if accept {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            onTitleEdit?(id, text)
        }
        field.removeFromSuperview()
        editingReturnIcon?.removeFromSuperview()
        editingReturnIcon = nil
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
