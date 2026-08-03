import Cocoa

// MARK: - ToastView（内联）
//
// 从 MenuBarManager.swift 逐字抽取（逻辑不变）。
// 计时归零时的轻提示占位（T3 用 Toast 替代原 CountdownFloater "zero expression"）。

final class ToastView: NSView {

    private let message: String

    init(frame frameRect: NSRect, message: String) {
        self.message = message
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.message = ""
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bg.fill()

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (message as NSString).size(withAttributes: attr)
        let textRect = NSRect(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2,
                              width: size.width,
                              height: size.height)
        (message as NSString).draw(in: textRect, withAttributes: attr)
    }
}
