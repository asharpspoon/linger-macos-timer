import Cocoa

// MARK: - ClickHintView（v3: 单纯点击时图标下方的轻提示）
//
// 从 MenuBarManager.swift 逐字抽取（逻辑不变）。

/// v3: 完全无背景，只画一行白字"↓ 拖拽开始计时"
final class ClickHintView: NSView {

    private let text: String

    init(frame frameRect: NSRect, text: String) {
        self.text = text
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.text = ""
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 强制清成完全透明，不留任何底色
        ctx.clear(bounds)

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attr)
        let rect = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attr)
    }
}
