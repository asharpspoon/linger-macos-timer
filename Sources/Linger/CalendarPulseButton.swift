//  CalendarPulseButton.swift
//  hover 列表底栏的日历预约按钮（按 schedule-timer-expand.html）：
//    - 收起态：琥珀软底脉动提示（1.8s 循环）
//    - 点击：scale 1→1.2→1.05（240ms）+ 停止脉动
//    - 展开态：is-active（琥珀软底 + scale 1.05）
//  铁律：颜色走 LingerTheme。

import Cocoa

final class CalendarPulseButton: NSView {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private var active = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14

        iconView.image = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "预约计时")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        iconView.contentTintColor = LingerTheme.amberGold
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 收起态脉动提示（1.8s 循环；is-hint）
    func startHintPulse() {
        guard !active else { return }
        if layer?.animation(forKey: "hintPulse") != nil { return }
        let pulse = CABasicAnimation(keyPath: "backgroundColor")
        pulse.fromValue = NSColor.clear.cgColor
        pulse.toValue = LingerTheme.amberGold.withAlphaComponent(0.14).cgColor
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "hintPulse")
    }

    func stopHintPulse() {
        layer?.removeAnimation(forKey: "hintPulse")
        if !active {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    /// 展开态：琥珀软底 + scale 1.05
    func setActive(_ on: Bool) {
        active = on
        if on {
            stopHintPulse()
            layer?.backgroundColor = LingerTheme.amberGold.withAlphaComponent(0.14).cgColor
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 1.05
            scale.duration = 0.2
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            layer?.add(scale, forKey: "activeScale")
            layer?.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))
        } else {
            layer?.removeAnimation(forKey: "activeScale")
            layer?.setAffineTransform(.identity)
            layer?.backgroundColor = NSColor.clear.cgColor
            startHintPulse()
        }
    }

    /// 点击反馈：scale 1→1.2→1.05（240ms）
    func playTap() {
        let tap = CAKeyframeAnimation(keyPath: "transform.scale")
        tap.values = [1.0, 1.2, 1.05]
        tap.keyTimes = [0, 0.4, 1]
        tap.duration = 0.24
        tap.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        layer?.add(tap, forKey: "tapFeedback")
    }

    override func mouseDown(with event: NSEvent) {
        playTap()
        // 点击判定由 HoverListView.mouseDown 统一处理（更可靠，避免本类 mouseDown 未送达时失效）
        onClick?()
    }
}
