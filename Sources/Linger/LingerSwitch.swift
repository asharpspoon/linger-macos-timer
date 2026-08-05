//  LingerSwitch.swift
//  自定义胶囊开关（铁律：禁止 NSButton(.switch) 复选框）。
//    36×20pt 胶囊，圆角 full；关态 rgba(255,255,255,0.16)，开态 LingerTheme.amberGold；
//    滑块 16pt 白，切换 0.2s easeInOut。NSControl 子类，走 target/action。

import Cocoa

final class LingerSwitch: NSControl {

    /// 开/关状态（外部可读写，didSet 触发重绘/动画）
    var isOn: Bool = false {
        didSet {
            updateAppearance(animated: true)
        }
    }

    private let knob = NSView()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10

        knob.wantsLayer = true
        knob.layer?.cornerRadius = 8
        knob.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(knob)
        positionKnob(animated: false)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 36, height: 20)
    }

    override func layout() {
        super.layout()
        positionKnob(animated: false)
    }

    // MARK: - 外观

    private func updateAppearance(animated: Bool) {
        layer?.backgroundColor = (isOn
            ? LingerTheme.amberGold
            : LingerTheme.nsColor(LingerTheme.Color.switchTrackOff)).cgColor
        positionKnob(animated: animated)
    }

    private func positionKnob(animated: Bool) {
        let x = isOn ? bounds.width - 18 : 2
        let frame = NSRect(x: x, y: 2, width: 16, height: 16)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                knob.animator().frame = frame
            }
        } else {
            knob.frame = frame
        }
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }
}
