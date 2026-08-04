//  ToastView.swift
//  Toast 轻提示（非模态）—— 对齐 toast.html 原型：
//    - 毛玻璃胶囊（NSVisualEffectView hudWindow）+ 1px 边框 + 圆角 10
//    - 文案 13px ink；内边距 px-5(20) / py-3(12)，尺寸内容自适应
//    - 淡入 0.4s → 停留 2.5s → 淡出 0.4s（由 MenuBarManager.showToast 驱动）
//  铁律：无硬编码 #F5A623，颜色走 LingerTheme。

import Cocoa

final class ToastView: NSView {

    private let message: String
    private let effectView = NSVisualEffectView()

    static let cornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = 20   // px-5
    static let verticalPadding: CGFloat = 12     // py-3

    init(frame frameRect: NSRect, message: String) {
        self.message = message
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        self.message = ""
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = ToastView.cornerRadius
        layer?.masksToBounds = true
        layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        layer?.borderWidth = 1

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)
    }

    /// 按文案计算自适应尺寸（文字 + 内边距）
    static func size(for message: String) -> NSSize {
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        let textSize = (message as NSString).size(withAttributes: attr)
        return NSSize(width: textSize.width + horizontalPadding * 2,
                      height: textSize.height + verticalPadding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: LingerTheme.nsColor(LingerTheme.Color.ink)
        ]
        let size = (message as NSString).size(withAttributes: attr)
        let textRect = NSRect(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2,
                              width: size.width,
                              height: size.height)
        (message as NSString).draw(in: textRect, withAttributes: attr)
    }
}
