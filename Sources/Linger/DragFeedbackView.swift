//  DragFeedbackView.swift
//  拖拽反馈视图 —— 严格按 menubar-drag.html 原型实现：
//    - 4pt 琥珀金渐变竖线（上深铜 → 中琥珀 55% → 下亮金）+ 18px glow
//    - 竖线末端 10pt 亮金圆点 + 10px glow
//    - 竖线下方水平双轨：左「for + 倒计时」| 右「til + 结束时刻」
//      双轨等大 24pt 等宽数字（原型注释明确「两轨字号一致 24pt」），
//      鼠标偏左 → for 亮琥珀金、til 变暗 0.3；偏右反之，0.35s 过渡
//    - 最下方 11pt 提示文案「从菜单栏图标向下拖拽 · 松手开始计时」
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
    private let separatorView = NSView()
    private let forPrefix = NSTextField(labelWithString: "for")
    private let forTime = NSTextField(labelWithString: "00:00")
    private let tilPrefix = NSTextField(labelWithString: "til")
    private let tilTime = NSTextField(labelWithString: "00:00")
    private let hintLabel = NSTextField(labelWithString: "从菜单栏图标向下拖拽 · 松手开始计时")

    // MARK: - 布局常量（原型：窗宽 280，起点紧贴菜单栏 topY=12）

    private static let kContentWidth: CGFloat = 280
    private static let kTopY: CGFloat = 12
    private static let kDefaultMaxLineHeight: CGFloat = 360
    private static let kBottomBlockHeight: CGFloat = 124   // 双轨 + 提示 + 边距

    private let contentWidth = DragFeedbackView.kContentWidth
    private let topY = DragFeedbackView.kTopY
    private let lineWidthNormal: CGFloat = 4
    private let lineWidthOverflow: CGFloat = 2.5
    private let dotDiameter: CGFloat = 10
    private let minLineHeight: CGFloat = 40

    /// 竖线最长长度（由 `linger_maxDragLinePercent` 推导，show(at:) 时刷新）
    private var maxLineHeight: CGFloat = DragFeedbackView.kDefaultMaxLineHeight

    /// 面板总高 = 顶部留白 + 竖线最长长度 + 底部标签区
    private var contentHeight: CGFloat { topY + maxLineHeight + DragFeedbackView.kBottomBlockHeight }

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

        // 竖线：渐变 + glow（原型 .drag-line：4px 圆角、darker→amber 55%→light、glow 18px）
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
        lineView.layer?.shadowOpacity = 1
        lineView.layer?.shadowRadius = 18
        lineView.layer?.shadowOffset = .zero
        addSubview(lineView)

        // 末端圆点（原型 .drag-dot：10pt 亮金圆 + glow 10px）
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.amberLight).cgColor
        dotView.layer?.cornerRadius = dotDiameter / 2
        dotView.layer?.shadowColor = LingerTheme.nsColor(LingerTheme.Color.amberGlow).cgColor
        dotView.layer?.shadowOpacity = 1
        dotView.layer?.shadowRadius = 10
        dotView.layer?.shadowOffset = .zero
        addSubview(dotView)

        // 双轨分隔线（原型 .dual-separator：1px × 18px）
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        addSubview(separatorView)

        // 双轨标签（原型 .dual-track：label 13pt、value 24pt 等宽 semibold，两轨等大）
        func styleTrack(_ prefix: NSTextField, _ time: NSTextField) {
            prefix.font = LingerTheme.labelFont(size: 13)
            prefix.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
            time.font = LingerTheme.timeFont(size: 24, weight: .semibold)
            time.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
            addSubview(prefix)
            addSubview(time)
        }
        styleTrack(forPrefix, forTime)
        styleTrack(tilPrefix, tilTime)

        // 提示文案（原型 #drag-hint：11pt ink3）
        hintLabel.font = LingerTheme.labelFont(size: 11)
        hintLabel.textColor = LingerTheme.nsColor(LingerTheme.Color.ink3)
        hintLabel.alignment = .center
        hintLabel.maximumNumberOfLines = 1
        addSubview(hintLabel)
    }

    // MARK: - 显示 / 隐藏

    func show(at anchorRect: NSRect) {
        if panelWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: contentWidth,
                                                   height: contentHeight),
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

        // 由 linger_maxDragLinePercent 推导竖线最长长度（25–75%，默认 50）
        let percent = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue)
        let p = (percent >= 25 && percent <= 75) ? percent : LingerTheme.defaultMaxDragLinePercent
        maxLineHeight = DragFeedbackView.kDefaultMaxLineHeight * CGFloat(p / 50)
        let height = contentHeight

        // 水平居中于图标，边界不出主屏幕
        var x = anchorRect.midX - contentWidth / 2
        if let visible = NSScreen.main?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - contentWidth - 4)
        }
        // 窗口顶部对齐菜单栏按钮底边（anchorRect.minY），向下延伸。
        let y = anchorRect.minY - height

        panelWindow?.setFrame(NSRect(x: x, y: y, width: contentWidth, height: height), display: false)
        frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        panelWindow?.alphaValue = 1
        // accessory 应用未激活时 orderFront(nil) 可能不生效，用 Regardless 版本。
        panelWindow?.orderFrontRegardless()
    }

    func hide() {
        panelWindow?.orderOut(nil)
    }

    // MARK: - 每帧更新（30fps 由 MenuBarManager.pollDrag 驱动）

    func update(distance: CGFloat,
                seconds: TimeInterval,
                til: Date,
                mode: DualRailMode,
                highlight: HighlightSide,
                overflow: Bool,
                title: String?) {
        let panelHeight = bounds.height

        // 1) 竖线：从 topY 向下延伸，溢出时线宽变细（弹簧反馈）
        let lineHeight = min(maxLineHeight, max(minLineHeight, distance))
        let width = overflow ? lineWidthOverflow : lineWidthNormal
        let lineX = contentWidth / 2 - width / 2
        let lineY = panelHeight - topY - lineHeight
        lineView.frame = NSRect(x: lineX, y: lineY, width: width, height: lineHeight)
        lineView.layer?.cornerRadius = width / 2

        // 2) 末端圆点
        dotView.frame = NSRect(x: contentWidth / 2 - dotDiameter / 2,
                               y: lineY - dotDiameter,
                               width: dotDiameter,
                               height: dotDiameter)

        // 3) 双轨文本
        let format = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.timeFormat.rawValue)
            ?? LingerTheme.defaultTimeFormat
        forTime.stringValue = TimerEntry.displayString(seconds: seconds, format: format)
        tilTime.stringValue = DragFeedbackView.tilFormatter.string(from: til)

        // 4) 双轨显隐（单轨模式）
        let showFor = (mode == .both || mode == .countdown)
        let showTil = (mode == .both || mode == .endTime)
        forPrefix.isHidden = !showFor
        forTime.isHidden = !showFor
        tilPrefix.isHidden = !showTil
        tilTime.isHidden = !showTil

        // 5) 布局（水平双轨 + 分隔线 + 提示）
        layoutDualTrack(dotMinY: dotView.frame.minY, showFor: showFor, showTil: showTil)

        // 6) 左右半区高亮联动（0.35s 过渡）
        applyHighlight(highlight)
    }

    /// 水平双轨：左组 + 分隔线 + 右组，整体居中于 280pt 窗宽。
    private func layoutDualTrack(dotMinY: CGFloat, showFor: Bool, showTil: Bool) {
        let gapFromDot: CGFloat = 24     // 原型 #time-preview mt-6
        let innerGap: CGFloat = 16       // 原型 gap-4
        let labelGap: CGFloat = 6        // 原型 .dual-track gap 6px
        let separatorHeight: CGFloat = 18

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
            prefix.frame = NSRect(x: x, y: centerY - pSize.height / 2,
                                  width: pSize.width, height: pSize.height)
            x += pSize.width + labelGap
            time.frame = NSRect(x: x, y: centerY - tSize.height / 2,
                                width: tSize.width, height: tSize.height)
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

    /// 悬停高亮：高亮侧琥珀金 + 不透明度 1，对侧 ink3 + 0.3，0.35s 过渡。
    private func applyHighlight(_ side: HighlightSide) {
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
    }
}
