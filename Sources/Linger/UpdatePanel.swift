import AppKit

/// 检查更新的 UI 面板（三态）：
/// - 发现新版：当前 v → 新 v + 更新说明 + 下载（浏览器）/ 忽略此版本 / 稍后
/// - 已是最新 / 网络失败：轻提示（自动跳合）
///
/// 单例复用一个 NSWindow（不重复创建）；样式走 LingerTheme（琥珀主色、
/// 纸张背景），与设置窗一致。方案依据：docs/update-design.md §3-4。
final class UpdatePanel {

    static let shared = UpdatePanel()

    private var window: NSWindow?
    private var notesBox: NSTextField?
    private var versionLabel: NSTextField?
    private var statusPopup: NSView?      // 已最新/失败 的轻提示层
    private var currentTag: String?
    private var currentURL: URL?

    private init() {}

    // MARK: - 入口

    /// 发现新版（自动检查 / 手动检查共用）
    func present(tag: String, version: String, notes: String?, downloadURL: URL?) {
        currentTag = tag
        currentURL = downloadURL
        buildWindowIfNeeded()

        versionLabel?.stringValue = "Linger \(AppVersion.current) → \(version)"
        if let notes, !notes.isEmpty {
            notesBox?.stringValue = Self.clamp(notes: notes)
            notesBox?.isHidden = false
        } else {
            notesBox?.isHidden = true
        }
        statusPopup?.removeFromSuperview()
        statusPopup = nil

        showWindow()
    }

    /// 手动检查：已是最新
    func presentUpToDate() {
        presentLightStatus(text: "✓ 已是最新版本（\(AppVersion.current)）")
    }

    /// 手动检查：失败
    func presentFailure(_ message: String) {
        presentLightStatus(text: "检查失败：\(message)")
    }

    // MARK: - 轻提示（不弹窗，浮在屏幕右上）

    private func presentLightStatus(text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = LingerTheme.nsColor(LingerTheme.Color.ink)
        label.alignment = .center

        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface).cgColor
        chip.layer?.cornerRadius = 10
        chip.layer?.borderColor = LingerTheme.nsColor(LingerTheme.Color.line).cgColor
        chip.layer?.borderWidth = 1
        chip.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -14)
        ])

        guard let screen = NSScreen.main?.visibleFrame else { return }
        chip.frame.origin = NSPoint(x: screen.maxX - chip.fittingSize.width - 16,
                                    y: screen.maxY - 44)
        chip.setFrameSize(chip.fittingSize)
        if let old = statusPopup { old.removeFromSuperview() }
        statusPopup = chip

        // 无窗口层级容器：临时建一个小 panel 挂载
        let panel = NSPanel(contentRect: chip.frame, styleMask: [.borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = chip
        panel.orderFrontRegardless()
        chip.superview?.wantsLayer = true

        // 2.5s 自动消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.statusPopup === chip { self?.statusPopup = nil }
        }
    }

    // MARK: - 构建主窗

    private func buildWindowIfNeeded() {
        guard window == nil else { return }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "检查更新"
        w.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = LingerTheme.nsColor(LingerTheme.Color.surface).cgColor

        let title = NSTextField(labelWithString: "发现新版本")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = LingerTheme.nsColor(LingerTheme.Color.ink)

        versionLabel = NSTextField(labelWithString: "")
        versionLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        versionLabel?.textColor = LingerTheme.nsColor(LingerTheme.Color.amberLight)

        notesBox = NSTextField(wrappingLabelWithString: "")
        notesBox?.font = .systemFont(ofSize: 11)
        notesBox?.textColor = LingerTheme.nsColor(LingerTheme.Color.ink2)
        notesBox?.maximumNumberOfLines = 8

        let download = makeButton(title: "下载新版", primary: true, action: #selector(openDownload))
        let skip = makeButton(title: "忽略此版本", primary: false, action: #selector(skipVersion))
        let later = makeButton(title: "稍后", primary: false, action: #selector(closePanel))

        [title, versionLabel!, notesBox!, download, skip, later].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),

            versionLabel!.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            versionLabel!.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            notesBox!.topAnchor.constraint(equalTo: versionLabel!.bottomAnchor, constant: 12),
            notesBox!.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            notesBox!.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            later.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            later.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            skip.centerYAnchor.constraint(equalTo: later.centerYAnchor),
            skip.trailingAnchor.constraint(equalTo: later.leadingAnchor, constant: -10),
            download.centerYAnchor.constraint(equalTo: later.centerYAnchor),
            download.trailingAnchor.constraint(equalTo: skip.leadingAnchor, constant: -10),
        ])

        w.contentView = content
        window = w
    }

    private func makeButton(title: String, primary: Bool, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        if primary {
            b.keyEquivalent = "\r"   // 回车触发
            b.contentTintColor = LingerTheme.nsColor(LingerTheme.Color.amber)
        } else {
            b.contentTintColor = LingerTheme.nsColor(LingerTheme.Color.ink2)
        }
        return b
    }

    private func showWindow() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 动作

    @objc private func openDownload() {
        if let url = currentURL { NSWorkspace.shared.open(url) }
        closePanel()
    }

    @objc private func skipVersion() {
        if let tag = currentTag { UpdateChecker.shared.skip(tag: tag) }
        closePanel()
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
    }

    /// 更新说明超长截断（Release body 可能很长，面板最多 8 行）
    private static func clamp(notes: String, limit: Int = 400) -> String {
        notes.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
