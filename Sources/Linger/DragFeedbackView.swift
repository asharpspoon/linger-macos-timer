//  DragFeedbackView.swift
//  Linger
//
//  自 Linger2.1 打磨版移植：**NSView 子视图 + 帧布局**，替换 2.0 旧版的
//  `draw()` 手绘 + 左右镜像数学（旧版把 for/til 拆到细线左右两侧，靠
//  railGap / prefixOnOuterSideForRightColumn / preferredWidth 一堆几何补丁维持对齐，
//  一旦字号或时间格式变化就错位）。
//
//  新布局（= 2.1 的实际做法）：
//    - 琥珀金发光竖线自菜单栏图标正下方向下延伸（渐变 amberDarker→amber→amberLight + glow）
//    - 竖线末端一个圆点
//    - 预览时间 **居中、纵向堆叠** 压在竖线下方：for（时长，大字）在上，til（结束时刻）在下
//    - 预设标题（Fn/Ctrl/Opt）再往下一行
//
//  与 2.1 的差异（有意为之，已在交付说明中列明）：
//    1. 面板高度不再写死 440：按 2.0 既有设置项 `linger_maxDragLinePercent`
//       推导 maxLineHeight，并预留 labelsBlockHeight 的标签区 —— 2.1 的 440/360
//       组合在满长度拖拽时会把 til / 标题裁掉。
//    2. 标签改为「动态堆叠」，单轨模式（countdown / endTime）下不留空洞。
//    3. `orderFrontRegardless()` 取代 `orderFront(nil)` —— Linger 是 accessory 应用，
//       非激活状态下 orderFront 可能不显示。
//
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

    private let lineView = NSView()
    private let dotView = NSView()
    private let forPrefix = NSTextField(labelWithString: "for")
    private let forTime = NSTextField(labelWithString: "00:00")
    private let tilPrefix = NSTextField(labelWithString: "til")
    private let tilTime = NSTextField(labelWithString: "00:00")
    private let titleLabel = NSTextField(labelWithString: "")

    // MARK: - 布局常量

    private static let kContentWidth: CGFloat = 280
    private static let kTopY: CGFloat = 12                 // 紧贴菜单栏下方
    private static let kLabelsBlockHeight: CGFloat = 170   // 竖线末端以下预留给标签堆叠的高度
    private static let kDefaultMaxLineHeight: CGFloat = 360

    private let contentWidth = DragFeedbackView.kContentWidth
    private let topY = DragFeedbackView.kTopY
    private let labelsBlockHeight = DragFeedbackView.kLabelsBlockHeight
    private let lineWidthNormal: CGFloat = 4
    private let lineWidthOverflow: CGFloat = 2.5
    private let minLineHeight: CGFloat = 40
    private let dotRadius: CGFloat = 5
    private let labelGap: CGFloat = 18                     // 圆点与第一行标签的间距

    /// 竖线最长长度（由 `linger_maxDragLinePercent` 推导，show(at:) 时刷新）
    private var maxLineHeight: CGFloat = DragFeedbackView.kDefaultMaxLineHeight

    /// 面板总高 = 顶部留白 + 竖线最长长度 + 标签区
    private var contentHeight: CGFloat { topY + maxLineHeight + labelsBlockHeight }

    /// til 时刻格式化器（30fps 更新，缓存避免每帧新建 DateFormatter）
    private static let tilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: DragFeedbackView.kContentWidth,
                                 height: DragFeedbackView.kTopY
                                    + DragFeedbackView.kDefaultMaxLineHeight
                                    + DragFeedbackView.kLabelsBlockHeight))
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

        // 竖线：渐变 + glow
        lineView.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            LingerTheme.nsColor(LingerTheme.Color.amberDarker).cgColor,
            LingerTheme.nsColor(LingerTheme.Color.amber).cgColor,
            LingerTheme.nsColor(LingerTheme.Color.amberLight).cgColor
        ]
        gradient.locations = [0.0, 0.55, 1.0]
        lineView.layer = gradient
        lineView.layer?.cornerRadius = lineWidthNormal / 2
        lineView.layer?.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow).cgColor
        lineView.layer?.shadowRadius = 9
        lineView.layer?.shadowOpacity = 1
        lineView.layer?.shadowOffset = .zero
        addSubview(lineView)

        // 竖线末端圆点
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.amberLight).cgColor
        dotView.layer?.cornerRadius = dotRadius
        dotView.layer?.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow).cgColor
        dotView.layer?.shadowRadius = 5
        dotView.layer?.shadowOpacity = 1
        dotView.layer?.shadowOffset = .zero
        addSubview(dotView)

        // 双轨标签（全部居中，纵向堆叠）
        configureLabel(forPrefix, size: 13, color: LingerTheme.Color.ink2)
        configureLabel(forTime, size: 30, color: LingerTheme.Color.amber, weight: .semibold)
        configureLabel(tilPrefix, size: 13, color: LingerTheme.Color.ink3)
        configureLabel(tilTime, size: 21, color: LingerTheme.Color.ink3)
        configureLabel(titleLabel, size: 12, color: LingerTheme.Color.amberLight)
        titleLabel.isHidden = true

        [forPrefix, forTime, tilPrefix, tilTime, titleLabel].forEach { addSubview($0) }

        startPulseIfNeeded()
    }

    private func configureLabel(_ field: NSTextField,
                                size: CGFloat,
                                color: LingerTheme.RGBA,
                                weight: NSFont.Weight = .regular) {
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false
        field.backgroundColor = .clear
        field.textColor = LingerTheme.nsColor(color)
        field.font = LingerTheme.timeFont(size: size, weight: weight)
        field.alignment = .center
    }

    // MARK: - 呼吸动画（尊重 reduced-motion）

    private func startPulseIfNeeded() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard lineView.layer?.animation(forKey: "linger-drag-pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.85
        pulse.toValue = 1.0
        pulse.duration = LingerTheme.durBreath
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        lineView.layer?.add(pulse, forKey: "linger-drag-pulse")
    }

    // MARK: - 窗口管理

    private func ensureWindow() {
        guard panelWindow == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.isMovableByWindowBackground = false
        // 新版反馈视图不再挂 NSTrackingArea（左右高亮改由 MenuBarManager 轮询鼠标位置判定），
        // 因此这里可以彻底不吃鼠标事件 —— 杜绝反馈窗口截走松手事件的可能。
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = self
        self.panelWindow = window
    }

    /// 依据 `linger_maxDragLinePercent`（T7 下拉线最大长度 25–75）刷新竖线最长长度。
    private func refreshMaxLineHeight() {
        let stored = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        let percent = stored > 0 ? stored : LingerTheme.defaultMaxDragLinePercent
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let raw = screenHeight * CGFloat(percent) / 100.0
        // 上界保证「顶部留白 + 竖线 + 标签区」不超出可视屏幕高度
        let upper = max(minLineHeight + 40, screenHeight - labelsBlockHeight - topY - 20)
        maxLineHeight = min(max(raw, minLineHeight + 40), upper)
    }

    /// 在状态栏按钮正下方显示；anchorRect 为按钮屏幕矩形。
    func show(at anchorRect: NSRect) {
        refreshMaxLineHeight()
        ensureWindow()
        guard let window = panelWindow else { return }

        let height = contentHeight
        var x = anchorRect.midX - contentWidth / 2
        let screen = NSScreen.screens.first { $0.frame.contains(anchorRect.origin) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - contentWidth - 4)
        }
        // 窗口顶部对齐菜单栏按钮底边（anchorRect.minY），向下延伸。
        let y = anchorRect.minY - height

        window.setFrame(NSRect(x: x, y: y, width: contentWidth, height: height), display: false)
        frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        window.alphaValue = 1
        startPulseIfNeeded()
        // accessory 应用未激活时 orderFront(nil) 可能不生效，用 Regardless 版本。
        window.orderFrontRegardless()
    }

    func hide() {
        panelWindow?.orderOut(nil)
    }

    // MARK: - 每帧更新（30fps 由 MenuBarManager.pollDrag 驱动）

    /// - Parameters:
    ///   - distance: 从按下点向下拖拽的像素距离
    ///   - seconds: 吸附后的时长秒数
    ///   - til: 预计结束时刻
    ///   - mode: 双轨模式
    ///   - highlight: 高亮侧（鼠标偏左 → for，偏右 → til）
    ///   - overflow: 是否已顶到最大时长（线宽变细提示）
    ///   - title: 预设标题（Fn/Ctrl/Opt），无则传 nil
    func update(distance: CGFloat,
                seconds: TimeInterval,
                til: Date,
                mode: DualRailMode,
                highlight: HighlightSide,
                overflow: Bool,
                title: String?) {
        let panelHeight = bounds.height

        // 1) 竖线
        let lineHeight = min(maxLineHeight, max(minLineHeight, distance))
        let width = overflow ? lineWidthOverflow : lineWidthNormal
        let lineX = contentWidth / 2 - width / 2
        let lineY = panelHeight - topY - lineHeight
        lineView.frame = NSRect(x: lineX, y: lineY, width: width, height: lineHeight)
        lineView.layer?.cornerRadius = width / 2

        // 2) 末端圆点
        dotView.frame = NSRect(x: contentWidth / 2 - dotRadius,
                               y: lineY - dotRadius * 2,
                               width: dotRadius * 2,
                               height: dotRadius * 2)

        // 3) 文案
        let format = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue)
            ?? LingerTheme.defaultTimeFormat
        forTime.stringValue = TimerEntry.displayString(seconds: seconds, format: format)
        tilTime.stringValue = DragFeedbackView.tilFormatter.string(from: til)

        // 4) 双轨显隐
        let showFor = (mode == .both || mode == .countdown)
        let showTil = (mode == .both || mode == .endTime)
        forPrefix.isHidden = !showFor
        forTime.isHidden = !showFor
        tilPrefix.isHidden = !showTil
        tilTime.isHidden = !showTil

        // 5) 左右半区高亮联动（只改字号 / 颜色 / 透明度，不改布局顺序）
        applyHighlight(highlight, showFor: showFor, showTil: showTil)

        // 6) 预设标题
        let hasTitle = !(title ?? "").isEmpty
        titleLabel.isHidden = !hasTitle
        if hasTitle { titleLabel.stringValue = title ?? "" }

        // 7) 居中纵向堆叠：for（上）→ til（下）→ 预设标题，全部压在竖线正下方
        layoutLabelStack(below: lineY, showFor: showFor, showTil: showTil, showTitle: hasTitle)
    }

    /// 自竖线末端向下依次摆放可见标签，跳过隐藏项（单轨模式不留空洞）。
    private func layoutLabelStack(below lineY: CGFloat,
                                  showFor: Bool,
                                  showTil: Bool,
                                  showTitle: Bool) {
        var cursor = lineY - labelGap   // 当前可用区域的顶边（y 越小越靠下）

        func place(_ field: NSTextField, height: CGFloat, gap: CGFloat) {
            cursor -= gap
            field.frame = NSRect(x: 0, y: cursor - height, width: contentWidth, height: height)
            cursor -= height
        }

        if showFor {
            place(forPrefix, height: 16, gap: 0)
            place(forTime, height: 40, gap: 2)
        }
        if showTil {
            place(tilPrefix, height: 16, gap: showFor ? 8 : 0)
            place(tilTime, height: 26, gap: 2)
        }
        if showTitle {
            place(titleLabel, height: 16, gap: 10)
        }
    }

    private func applyHighlight(_ side: HighlightSide, showFor: Bool, showTil: Bool) {
        // 高亮侧更大更亮，对侧变小变暗。
        let forBig = (side == .forSide)
        forTime.font = LingerTheme.timeFont(size: forBig ? 30 : 24, weight: .semibold)
        forTime.textColor = LingerTheme.nsColor(forBig ? LingerTheme.Color.amber : LingerTheme.Color.amberDark)
        forTime.alphaValue = showFor ? (forBig ? 1.0 : 0.7) : 0

        tilTime.font = LingerTheme.timeFont(size: forBig ? 18 : 21)
        tilTime.textColor = LingerTheme.nsColor(forBig ? LingerTheme.Color.ink3 : LingerTheme.Color.ink2)
        tilTime.alphaValue = showTil ? (forBig ? 0.6 : 1.0) : 0
    }
}
