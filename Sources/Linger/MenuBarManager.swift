import Cocoa
import os.log


// MARK: - MenuBarManager（菜单栏入口）

final class MenuBarManager: NSObject {

    private let statusItem: NSStatusItem
    private let log = OSLog(subsystem: "com.linger.menubar", category: "MenuBarManager")

    // MARK: - 拖拽状态机（自 Linger2.1 打磨版移植）
    //
    // 旧版（2.0）在这里堆了 global monitor + eventTracking runloop 模式 +
    // pressedMouseButtons 轮询兜底 + abs(dy) 误判等一系列补丁，反而制造出
    // 「状态栏按钮吞掉 mouseUp → 状态机卡在 .pressed → 之后每次按下都被静默丢弃
    //   → 下拉松手不计时」的死结。
    //
    // 2.1 的正解只有三件事：
    //   1. 按钮只在 leftMouseDown 触发 action（不消费 mouseUp）；
    //   2. 拖拽期挂 **局部** monitor 收 .leftMouseUp / .flagsChanged；
    //   3. 30fps 轮询只负责「算距离 + 刷新反馈」，**不**负责判定松手。
    private enum DragState { case idle, pressed, dragging }
    private var dragState: DragState = .idle
    private var dragStartLocation: NSPoint = .zero
    private var pollTimer: Timer?
    private var localMonitor: Any?
    /// 拖拽期由修饰键决定的预设标题（Fn/Ctrl/Opt）
    private var pendingTitle: String?
    /// 2.0 保留：0.2s 内没拖动就弹「↓ 拖拽开始计时」轻提示
    private var clickHintTimer: Timer?

    // 拖拽反馈视图（复用同一实例 + 同一窗口，show/hide 切换）
    private var dragFeedback: DragFeedbackView?

    // T3: 倒计时面板（CountdownPillPanel / CountdownFloater）已移除；计时归零改用 Toast 占位。
    // T5: 日历预约面板（ScheduleTimerView）承载于独立窗口 schedulePanel。
    private var schedulePanel: NSWindow?

    // T7–T11: 设置窗口与关于窗口（复用实例，避免重复创建）
    private var settingsWindow: SettingsWindow?
    private var aboutWindow: AboutWindow?

    // Step 5: 悬停面板
    private var hoverListWindow: HoverListWindow?
    private var hoverListView: HoverListView?
    /// 窗口顶部锚点 Y（屏幕坐标，动画中保持不变，底部随高度变化）
    private var hoverListTopAnchorY: CGFloat = 0
    private var hoverOverlay: HoverTrackingOverlay?
    /// 鼠标移到面板上时 0.3s 延迟关闭 —— 防止误关
    private var hoverHideWorkItem: DispatchWorkItem?
    /// 鼠标真的进入过面板区域（延迟 0.3s 后判定）→ 用这个标志让面板一直保持打开直到真离开
    private var hoverIsLockedOpen: Bool = false

    // 右键菜单（不绑定到 statusItem.menu，手动弹出）
    private let rightClickMenu: NSMenu

    // 当前按钮尺寸 — Step 2 恢复 .variableLength，由系统根据内容自适应
    private var statusItemObserver: NSObjectProtocol?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rightClickMenu = NSMenu()
        super.init()
        configureStatusItemStep2()
        // 右键菜单在 showRightClickMenu 中每次重建（实时更新日历权限状态）
        // Step 3 修正：接入 timerStateChangedNotification 监听 — 菜单栏实时同步倒计时
        startObserving()
        NSLog("[Linger] MenuBarManager initialized (Step 5: hover list + Step 4 spring/floater)")
        // Step 4 v3: 在 init 之外启动 watch —— 用 DispatchQueue.main.async 推迟到
        //   applicationDidFinishLaunching 返回后由主 RunLoop 处理。
        //   此时 AppEntry 已提前访问过 TimerManager.shared，不会再触发 .shared 初始化。
        DispatchQueue.main.async { [weak self] in
            self?.installHoverTracking()
        }
    }

    deinit {
        if let obs = statusItemObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        // 拖拽期资源：轮询 timer / 点击提示 timer / 局部事件监视器
        pollTimer?.invalidate()
        clickHintTimer?.invalidate()
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        hoverHideWorkItem?.cancel()
        hoverOverlay?.removeFromSuperview()
        hoverListWindow?.orderOut(nil)
    }

    // MARK: - 图标（SF Symbol + 降级为 Linger 文字）

    /// T12: 菜单栏图标装配 —— 由 linger_iconStyle 决定三种风格
    ///   - ring    : 自绘环形 NSImage（template，深浅自适应）—— 默认
    ///   - classic : SF Symbol "clock"（旧样式）
    ///   - timer   : SF Symbol "timer"
    private func buildMenuBarIcon() -> NSImage? {
        switch currentIconStyle() {
        case "ring":
            return buildRingIcon()
        case "classic":
            return buildSFSymbolIcon("clock")
        case "timer":
            return buildSFSymbolIcon("timer")
        default:
            return buildRingIcon()
        }
    }

    /// 当前图标风格（缺省 ring，与 PRD §3.6.5 默认 Ring 一致）
    private func currentIconStyle() -> String {
        UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue) ?? "ring"
    }

    /// 自绘环形图标（template）：外环描边 + 中心实心点，深浅模式自适应
    private func buildRingIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let inset: CGFloat = 2
        let ringRect = NSRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = 2.0
        ringPath.stroke()
        let dotRadius: CGFloat = 2.5
        let dotRect = NSRect(x: size.width / 2 - dotRadius,
                             y: size.height / 2 - dotRadius,
                             width: dotRadius * 2, height: dotRadius * 2)
        NSBezierPath(ovalIn: dotRect).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// SF Symbol 图标（template）
    private func buildSFSymbolIcon(_ name: String) -> NSImage? {
        guard let raw = NSImage(systemSymbolName: name, accessibilityDescription: "Linger") else { return nil }
        raw.isTemplate = true
        return raw
    }

    /// 图标风格切换后由设置窗口通知触发，重建菜单栏图标（T10 / T12）
    private func refreshMenuBarIcon() {
        guard let button = statusItem.button else { return }
        button.image = buildMenuBarIcon()
    }

    // MARK: - 配置

    /// Step 3 修正：加载 SF Symbol 图标 + 拦截 mouseDown；右键菜单不再绑在 statusItem.menu 上
    private func configureStatusItemStep2() {
        guard let button = statusItem.button else {
            NSLog("[Linger] ERROR: statusItem.button is nil")
            return
        }

        button.imagePosition = .imageLeft
        if let icon = buildMenuBarIcon() {
            button.image = icon
            button.title = ""
        } else {
            // 降级：SF Symbol 都加载不到时显示文字
            button.image = nil
            button.title = "Linger"
        }
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        // 关键：解绑 statusItem.menu，让 AppKit 把所有点击交给 button.action
        statusItem.menu = nil

        // 2.1 装配：左键**按下**进拖拽状态机；右键**抬起**弹菜单。
        //   关键点在于 action 只挂 .leftMouseDown —— 按钮不消费 leftMouseUp，
        //   拖拽期的局部 monitor 才能稳定收到松手事件（这是 2.1 能正常计时的根本原因）。
        button.target = self
        button.action = #selector(handleStatusClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])

        NSLog("[Linger] Step 3 fix: status item configured (icon=%@, mouseDown intercept)",
              buildMenuBarIcon() != nil ? "SF Symbol" : "text fallback")

        // T7/T10: 图标风格实时刷新（设置窗口改变 linger_iconStyle 时通知）
        NotificationCenter.default.addObserver(
            forName: Notification.Name("linger.iconStyleChanged"),
            object: nil, queue: .main) { [weak self] _ in
                self?.refreshMenuBarIcon()
            }
    }

    // 右键菜单在 showRightClickMenu 中每次重建（实时更新日历权限状态）
    // NSMenu 声明见 init

    // MARK: - 菜单动作

    @objc private func showAbout(_ sender: Any?) {
        if aboutWindow == nil { aboutWindow = AboutWindow() }
        // AboutWindow.orderFront 覆盖已启动 3 秒权限轮询，无需额外调用
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.refreshPermissionStatuses()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openCalendarSettings(_ sender: Any?) {
        if CalendarManager.shared.isAuthorized {
            let alert = NSAlert()
            alert.messageText = "日历权限已开启"
            alert.informativeText = "Linger 已获得日历访问权限，计时标题会实时写入 Linger 日历。"
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "需要开启日历权限"
        alert.informativeText = "请在「系统设置 → 隐私与安全性 → 日历」中为 Linger 开启权限。\n开启后返回 Linger，编辑计时标题即可自动写入日历。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func startObserving() {
        statusItemObserver = NotificationCenter.default.addObserver(
            forName: timerStateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 收到通知时立即刷新菜单栏标题与悬停面板（替代原 0.25s 轮询检查浮窗）
            self?.refreshStatusItemTitle()
            self?.refreshHoverList()
        }

        // T6: 计时归零的 UI 反馈改由 NotificationManager 通过原生横幅呈现，
        //     此处不再弹出 Toast，避免与通知横幅重复。
    }

    // MARK: - 菜单栏显示同步

    /// Step 3 阶段：监听 timerStateChangedNotification —— 有计时时显示倒计时文字，无计时时清空
    private func refreshStatusItemTitle() {
        guard let button = statusItem.button else { return }
        // 兜底：保证图标永远存在
        if button.image == nil {
            button.image = buildMenuBarIcon()
        }
        // 拖拽中菜单栏文字由 refreshStatusTextDuringDrag 独占，
        // 否则每秒的 timerTick 通知会把预览读数闪回成运行态读数。
        // （cleanupDrag 会在松手后主动调用本方法复位）
        if dragState == .dragging { return }
        if let earliest = TimerManager.shared.earliestEntry, earliest.remainingTime > 0 {
            button.title = " " + earliest.displayTime
        } else {
            button.title = ""
        }
    }

    /// 拖拽过程中把菜单栏文字替换成实时预览时长（松手后由 refreshStatusItemTitle 复位）。
    /// 与运行态共用 TimerEntry.displayString，保证松手瞬间读数不跳格式。
    private func refreshStatusTextDuringDrag(seconds: TimeInterval) {
        guard let button = statusItem.button else { return }
        button.title = " " + TimerEntry.displayString(seconds: seconds,
                                                      format: TimerEntry.currentTimeFormat)
    }

    // MARK: - 点击处理

    /// 状态栏点击分发（2.1）：右键 / Ctrl+左键 → 菜单；左键按下 → 进拖拽状态机。
    @objc private func handleStatusClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showRightClickMenu()
            return
        }
        if event.type == .leftMouseDown {
            beginDrag()
        }
    }

    private func showRightClickMenu() {
        guard let button = statusItem.button else { return }

        // 每次右键时重建菜单，确保日历权限状态实时更新
        rightClickMenu.removeAllItems()

        let aboutItem = NSMenuItem(title: "关于 Linger",
                                   action: #selector(showAbout(_:)),
                                   keyEquivalent: "")
        aboutItem.target = self
        rightClickMenu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "设置…",
                                     action: #selector(showSettings(_:)),
                                     keyEquivalent: "")
        settingsItem.target = self
        rightClickMenu.addItem(settingsItem)

        let calAuth = CalendarManager.shared.isAuthorized
        let calItem = NSMenuItem(title: calAuth ? "✅ 日历已授权" : "日历授权 → 去设置",
                                 action: #selector(openCalendarSettings(_:)),
                                 keyEquivalent: "")
        calItem.target = self
        calItem.isEnabled = !calAuth
        rightClickMenu.addItem(calItem)

        rightClickMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出",
                                  action: #selector(quitApp(_:)),
                                  keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)

        let location = NSPoint(x: 0, y: button.bounds.height)
        rightClickMenu.popUp(positioning: nil, at: location, in: button)
    }

    // MARK: - 拖拽状态机（自 Linger2.1 打磨版移植：idle → pressed → dragging）
    //
    // 与 2.0 旧实现的根本差异：
    //   - 旧版有 4 条松手判定路径（local monitor / global monitor /
    //     NSEvent.pressedMouseButtons 轮询兜底 / pending timer），互相抢跑又互相兜底。
    //     只要按钮把 mouseUp 吞掉一次，dragPhase 就被永久钉在 .pressed，
    //     之后每次按下都被 statusBarButtonPressed 的闸门静默丢弃 →「下拉松手不计时」。
    //   - 新版只有 **一条** 松手路径：局部 monitor 的 .leftMouseUp。
    //     之所以敢只留一条，是因为按钮已改成 sendAction(on: [.leftMouseDown, .rightMouseUp])，
    //     action 只在按下时触发、不再消费 mouseUp，松手事件必然回到 monitor。
    //   - 30fps 轮询只做「算距离 + 刷预览」，**不**参与状态判定，也不做任何松手兜底。
    //
    // 2.0 独有能力在此保留：拖拽前收起悬停面板、0.2s 点击轻提示、
    // 修饰键预设标题（Fn/Ctrl/Opt）、并发上限 Toast。

    private func beginDrag() {
        guard dragState == .idle else {
            os_log("beginDrag ignored: state=%{public}@",
                   log: log, type: .debug, String(describing: dragState))
            return
        }

        // 2.0 保留：开始拖拽立刻收起悬停面板 —— 别挡着细线
        cancelScheduledHoverHide()
        hideHoverListNow()

        dragState = .pressed
        dragStartLocation = NSEvent.mouseLocation
        pendingTitle = currentPresetTitle(for: NSEvent.modifierFlags)

        ensureDragFeedback()

        // 2.0 保留：0.2s 内没往下拖 → 认定为单纯点击，弹「↓ 拖拽开始计时」
        clickHintTimer?.invalidate()
        let hint = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self, self.dragState == .pressed else { return }
            self.showClickHint()
        }
        RunLoop.main.add(hint, forMode: .common)
        // 2.0 保留的加固：按住按钮期间 RunLoop 可能处于事件追踪模式，
        // 各版本 .common 是否真的含 .eventTracking 并不稳定 —— 显式补一次注册。
        // （多模式注册不会让 timer 一个周期触发多次，纯属扩大可触发范围）
        RunLoop.main.add(hint, forMode: .eventTracking)
        clickHintTimer = hint

        // 仅拖拽期挂局部监视器：leftMouseUp 判松手，flagsChanged 判 Command 取消 / 预设标题
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }

        // 30fps 轮询鼠标位置（不阻塞主线程）
        pollTimer?.invalidate()
        let poll = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollDrag()
        }
        RunLoop.main.add(poll, forMode: .common)
        RunLoop.main.add(poll, forMode: .eventTracking)
        pollTimer = poll

        os_log("beginDrag: pressed at (%.1f, %.1f)",
               log: log, type: .debug, dragStartLocation.x, dragStartLocation.y)
    }

    private func pollDrag() {
        let current = NSEvent.mouseLocation
        let distance = max(0, dragStartLocation.y - current.y)   // 向下拖拽 y 减小

        if dragState == .pressed {
            guard distance > 4 else { return }   // 4px 阈值区分「点击」与「拖拽」
            dragState = .dragging
            clickHintTimer?.invalidate()
            clickHintTimer = nil
            hideClickHint()
            dragFeedback?.show(at: buttonScreenRect())
            os_log("pollDrag: upgraded to dragging (d=%.1f)", log: log, type: .debug, distance)
        }

        guard dragState == .dragging else { return }

        let maxSeconds = maxDragDurationSeconds()
        let rawSeconds = TimerEntry.duration(fromDragDistance: Double(distance), maxSeconds: maxSeconds)
        let seconds = TimerEntry.snapToMinuteIfClose(rawSeconds)
        let til = Date().addingTimeInterval(seconds)
        let overflow = rawSeconds >= maxSeconds - 0.5

        dragFeedback?.update(distance: distance,
                             seconds: seconds,
                             til: til,
                             mode: dualRailMode(),
                             highlight: highlightSide(),
                             overflow: overflow,
                             title: pendingTitle)
        refreshStatusTextDuringDrag(seconds: seconds)
    }

    private func handleDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseUp:
            finishDrag()
        case .flagsChanged:
            if event.modifierFlags.contains(.command) {
                os_log("Drag cancelled by Command", log: log, type: .debug)
                cancelDrag()
                return
            }
            // 拖拽中切换 Fn/Ctrl/Opt → 预览区实时显示对应预设标题
            pendingTitle = currentPresetTitle(for: event.modifierFlags)
        default:
            break
        }
    }

    private func finishDrag() {
        // 只按了一下没拖动 → 不建计时，直接收尾（点击提示由 cleanupDrag 关掉）
        guard dragState == .dragging else {
            os_log("finishDrag: click only (state=%{public}@)",
                   log: log, type: .debug, String(describing: dragState))
            cleanupDrag()
            return
        }

        let current = NSEvent.mouseLocation
        let distance = max(0, dragStartLocation.y - current.y)
        let maxSeconds = maxDragDurationSeconds()
        let rawSeconds = TimerEntry.duration(fromDragDistance: Double(distance), maxSeconds: maxSeconds)
        // 与 pollDrag 用同一套曲线 + 同一次吸附 → 松手所得 == 松手前所见（WYSIWYG）
        let seconds = TimerEntry.snapToMinuteIfClose(rawSeconds)

        finishDrag(with: seconds)
        cleanupDrag()
        os_log("finishDrag: %.1fs (d=%.1f)", log: log, type: .info, seconds, distance)
    }

    private func cancelDrag() {
        cleanupDrag()
    }

    /// 清理拖拽期资源：移除 monitor、停轮询、关反馈与提示、复位状态与菜单栏文字。
    /// 所有退出路径（松手 / Command 取消 / 纯点击）都收敛到这里，杜绝状态残留。
    private func cleanupDrag() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        clickHintTimer?.invalidate()
        clickHintTimer = nil
        dragFeedback?.hide()
        hideClickHint()
        dragState = .idle
        pendingTitle = nil
        refreshStatusItemTitle()
    }

    /// 真正创建计时：沿用 2.0 的修饰键预设标题 + 并发上限 Toast 语义。
    private func finishDrag(with seconds: TimeInterval) {
        // 松手瞬间再读一次修饰键，覆盖拖拽期间 flagsChanged 未捕获到的情况
        let title = pendingTitle ?? currentPresetTitle(for: NSEvent.modifierFlags)

        if let entry = TimerManager.shared.addTimer(duration: seconds, predefinedTitle: title) {
            os_log("Created timer entry %{public}@ for %.1fs",
                   log: log, type: .info, entry.id.uuidString, seconds)
        } else {
            // 走到这里说明拖拽链路是通的，失败在 TimerManager 并发上限
            //（B2 的 reclaimFinishedEntries 回收逻辑已在 addTimer 内先跑过一轮）
            os_log("finishDrag rejected by TimerManager (limit reached) for %.1fs",
                   log: log, type: .error, seconds)
            showToast(message: "已达上限 (最多 \(TimerManager.maxConcurrentEntries) 个)")
        }
    }

    /// 修饰键 → 预设标题（T9 设置项，缺省 专注 / 休息 / 写作）。
    /// Ctrl 需排除 Command，避免与「Command 取消拖拽」语义打架。
    private func currentPresetTitle(for flags: NSEvent.ModifierFlags) -> String? {
        if flags.contains(.function) {
            return UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.fnTitle.rawValue) ?? "专注"
        }
        if flags.contains(.option) {
            return UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.optTitle.rawValue) ?? "休息"
        }
        if flags.contains(.control) && !flags.contains(.command) {
            return UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.ctrlTitle.rawValue) ?? "写作"
        }
        return nil
    }

    // MARK: - 拖拽参数与几何

    /// 最大计时时长（T7 `linger_maxDurationMinutes`，缺省 30 分钟）
    private func maxDragDurationSeconds() -> TimeInterval {
        let mins = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.maxDurationMinutes.rawValue)
        let m = mins > 0 ? mins : LingerTheme.defaultMaxDurationMinutes
        return TimeInterval(m) * 60
    }

    /// 双轨模式（T12 `linger_dualRailMode`，缺省 both）
    private func dualRailMode() -> DragFeedbackView.DualRailMode {
        let raw = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.dualRailMode.rawValue)
            ?? LingerTheme.defaultDualRailMode
        return DragFeedbackView.DualRailMode(rawValue: raw) ?? .both
    }

    /// 鼠标偏左 → 高亮 for（时长），偏右 → 高亮 til（结束时刻）。
    /// 反馈窗口已 ignoresMouseEvents，故不再用 NSTrackingArea，改由这里按坐标判定。
    private func highlightSide() -> DragFeedbackView.HighlightSide {
        guard let w = dragFeedback?.panelWindow else { return .forSide }
        return NSEvent.mouseLocation.x < w.frame.midX ? .forSide : .tilSide
    }

    /// 状态栏按钮在屏幕坐标系下的矩形（拖拽反馈 / 点击提示的锚点）。
    private func buttonScreenRect() -> NSRect {
        guard let button = statusItem.button, let window = button.window else {
            let y = NSScreen.main?.visibleFrame.maxY ?? 800
            return NSRect(x: 0, y: y, width: 24, height: 24)
        }
        return window.convertToScreen(button.frame)
    }

    // MARK: - 拖拽反馈视图（单实例复用，show/hide 切换）

    private func ensureDragFeedback() {
        if dragFeedback == nil {
            dragFeedback = DragFeedbackView()
        }
    }

    // MARK: - v3: 单纯点击提示窗口（2.0 独有，保留）

    private var hintWindow: NSWindow?

    private func showClickHint() {
        guard hintWindow == nil else { return }
        let anchor = buttonScreenRect()

        let hintText = "↓ 拖拽开始计时"
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (hintText as NSString).size(withAttributes: attr)
        let padding: CGFloat = 12
        let contentWidth = textSize.width + padding * 2
        let contentHeight = textSize.height + padding
        let originX = anchor.midX - contentWidth / 2
        let originY = anchor.minY - contentHeight - 4

        let contentRect = NSRect(x: originX, y: originY, width: contentWidth, height: contentHeight)
        let win = NSWindow(contentRect: contentRect,
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

        let view = ClickHintView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                                 text: hintText)
        win.contentView = view
        hintWindow = win
        win.orderFrontRegardless()
    }

    private func hideClickHint() {
        hintWindow?.orderOut(nil)
        hintWindow = nil
    }

    // MARK: - Toast

    private func showToast(message: String) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = 260
        let height: CGFloat = 44
        let rect = NSRect(x: screenFrame.midX - width / 2,
                          y: screenFrame.midY - height / 2,
                          width: width, height: height)
        let win = NSWindow(contentRect: rect,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false

        let view = ToastView(frame: rect, message: message)
        win.contentView = view
        win.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            win.orderOut(nil)
        }
    }

    // MARK: - Step 5: 悬停计时列表面板

    /// 安装 NSTrackingArea —— 把透明 overlay 嵌到 statusItem.button 上
    /// 鼠标进入 overlay 区域时弹面板，离开时延迟 0.3s 判定（防止从图标滑到面板时误关）
    private func installHoverTracking() {
        guard let button = statusItem.button else { return }
        // 防御性：清理旧的
        hoverOverlay?.removeFromSuperview()

        let overlay = HoverTrackingOverlay(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onMouseEntered = { [weak self] in
            self?.handleHoverEntered()
        }
        overlay.onMouseExited = { [weak self] in
            self?.handleHoverExited()
        }
        button.addSubview(overlay)
        hoverOverlay = overlay
        os_log("Hover tracking installed on status item", log: log, type: .info)
    }

    /// 鼠标进入图标 → 检查是否有计时器，有则弹面板
    private func handleHoverEntered() {
        // 取消之前的延迟关闭（如果鼠标快速进出又进）
        cancelScheduledHoverHide()

        // 无计时器 → 不弹
        guard TimerManager.shared.hasActiveTimers else {
            return
        }

        // 已有面板 → 仅取消延迟关闭 + 标记锁定
        if hoverListWindow != nil {
            hoverIsLockedOpen = true
            refreshHoverList()
            return
        }

        showHoverList()
        hoverIsLockedOpen = true
    }

    /// 鼠标离开图标 → 0.3s 延迟后再判一次
    private func handleHoverExited() {
        scheduleHoverHideCheck()
    }

    /// 0.3s 后检查鼠标是否在面板区域内 — 在则保持打开，不在则关闭
    private func scheduleHoverHideCheck() {
        cancelScheduledHoverHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let win = self.hoverListWindow else {
                self.hoverIsLockedOpen = false
                return
            }
            // 鼠标当前位置（屏幕坐标）
            let mouse = NSEvent.mouseLocation
            // 面板在屏幕坐标中的 frame
            let panelFrame = win.frame
            if panelFrame.contains(mouse) {
                // 鼠标在面板上 → 锁定打开，菜单栏 overlay 会在面板区域内（不悬停图标时）通过
                // 面板自己的 NSTrackingArea 接管后续 enter/exit
                self.hoverIsLockedOpen = true
            } else {
                // 鼠标真的离开了 → 关闭
                self.hoverIsLockedOpen = false
                self.hideHoverListNow()
            }
        }
        hoverHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelScheduledHoverHide() {
        hoverHideWorkItem?.cancel()
        hoverHideWorkItem = nil
    }

    private func showHoverList() {
        guard let button = statusItem.button,
              let win = button.window else { return }

        // 修复 1: 先过滤归零的 entry —— panelH 也要按过滤后的数量算
        //   之前的 bug: allDisplayEntries 包含归零的 entry, setEntries 内部又过滤
        //   导致 panelH 按 2 算, 实际画 1 个卡片, 多出的空间看起来像"空白条目"
        let entries = TimerManager.shared.allDisplayEntries.filter { $0.remainingTime > 0 }
        guard !entries.isEmpty else { return }

        // 计算面板尺寸 & 位置（按三组分：running / paused / scheduled）
        let rCount = entries.filter { !$0.isScheduled && !$0.isPaused }.count
        let pCount = entries.filter { !$0.isScheduled && $0.isPaused }.count
        let scCount = entries.filter { $0.isScheduled }.count
        let panelW = HoverListView.panelWidth
        let panelH = HoverListView.panelHeight3(runningCount: rCount, pausedCount: pCount, scheduledCount: scCount)
        let buttonFrame = button.frame
        let screenOrigin = win.convertPoint(toScreen: NSPoint(x: NSMinX(buttonFrame), y: NSMinY(buttonFrame)))
        let originX = screenOrigin.x + buttonFrame.width / 2 - panelW / 2
        // 面板从图标下沿向下延伸
        let originY = screenOrigin.y - panelH - 4

        // 边界保护：左右不超出主屏幕
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let clampedX = max(screen.minX + 8, min(screen.maxX - panelW - 8, originX))

        let rect = NSRect(x: clampedX, y: originY, width: panelW, height: panelH)
        let panelWin = HoverListWindow(contentRect: rect)
        let view = HoverListView(frame: NSRect(origin: .zero, size: rect.size))
        view.setEntries(entries)
        panelWin.contentView = view
        panelWin.makeKeyAndOrderFront(nil)

        hoverListTopAnchorY = screenOrigin.y - 4  // 窗口顶部 Y（不变）
        hoverListWindow = panelWin
        hoverListView = view

        // ⑧ 接线: 按钮回调
        view.onPauseToggle = { [weak self] id in
            guard let entry = TimerManager.shared.allDisplayEntries.first(where: { $0.id == id }) else { return }
            entry.togglePause()
            self?.refreshHoverList()
        }
        view.onStop = { [weak self] id in
            TimerManager.shared.stopEntry(id)
            self?.refreshHoverList()
        }
        view.onToggleAllPause = { [weak self] in
            guard let self = self else { return }
            let entries = TimerManager.shared.allDisplayEntries.filter { $0.remainingTime > 0 }
            let hasRunning = entries.contains { !$0.isScheduled && !$0.isPaused }
            for entry in entries {
                if !entry.isScheduled {
                    if hasRunning && !entry.isPaused {
                        entry.togglePause()
                    } else if !hasRunning && entry.isPaused {
                        entry.togglePause()
                    }
                }
            }
            self.refreshHoverList()
        }
        view.onTitleEdit = { [weak self] id, title in
            guard let entry = TimerManager.shared.allDisplayEntries.first(where: { $0.id == id }) else { return }
            entry.predefinedTitle = title.isEmpty ? nil : title
            self?.refreshHoverList()

            // 有标题且未记录 → 立即写入日历
            guard !title.isEmpty, !entry.hasRecorded else { return }

            let startDate = entry.originalStartTime ?? entry.startTime ?? Date()
            let endDate = entry.originalEndTime ?? Date(timeInterval: entry.duration, since: startDate)

            CalendarManager.shared.requestPermissionIfNeeded { [weak self] granted in
                guard let self = self, granted else { return }
                if let eventId = CalendarManager.shared.writeEvent(
                    title: title, startDate: startDate, endDate: endDate
                ) {
                    entry.hasRecorded = true
                    entry.calendarEventId = eventId
                    CalendarManager.shared.markRecorded(entry.id)
                    os_log("Calendar record written: %{public}@", log: self.log, type: .info, title)
                }
            }
        }
        view.onCalendarSchedule = { [weak self] in
            self?.presentScheduleTimer()
        }
        view.onHeightAnimation = { [weak self] height in
            guard let self = self, let win = self.hoverListWindow else { return }
            var frame = win.frame
            frame.size.height = height
            frame.origin.y = self.hoverListTopAnchorY - height
            win.setFrame(frame, display: false)
        }

        // 在面板上挂一个 tracking area：检测鼠标进入/离开面板
        installPanelTracking(on: view)

        os_log("Hover list shown: %d entries", log: log, type: .info, entries.count)
    }

    /// 面板自身加 tracking area —— 鼠标进入面板时锁定打开，离开时延迟关闭
    private func installPanelTracking(on view: HoverListView) {
        view.onPanelMouseEntered = { [weak self] in
            guard let self = self else { return }
            // 鼠标进入面板 → 取消之前排队的关闭 + 锁定
            self.cancelScheduledHoverHide()
            self.hoverIsLockedOpen = true
        }
        view.onPanelMouseExited = { [weak self] in
            // 鼠标离开面板 → 0.3s 延迟后再判定（防止快速滑过）
            self?.scheduleHoverHideCheck()
        }
        view.updateTrackingAreas()  // 触发 addTrackingArea
    }

    private func hideHoverListNow() {
        hoverListWindow?.orderOut(nil)
        hoverListWindow = nil
        hoverListView = nil
        hoverIsLockedOpen = false
    }

    /// 通知触发时调用：仅在面板已显示时刷新数据
    private func refreshHoverList() {
        guard let view = hoverListView else { return }
        // 修复 1: 同样过滤归零 entry —— 保持与 showHoverList 一致
        let active = TimerManager.shared.allDisplayEntries.filter { $0.remainingTime > 0 }
        if active.isEmpty {
            hideHoverListNow()
            return
        }
        view.setEntries(active)
    }

    // MARK: - 菜单动作（Step 2 版本见文件上部 showAbout(_:)/showSettings(_:)/quitApp(_:)）

    // MARK: - 日历预约面板（T5: ScheduleTimerView）

    /// 弹出内联日历预约面板（ScheduleTimerView），确认后创建预约计时。
    private func presentScheduleTimer() {
        guard let hoverWin = self.hoverListWindow else { return }
        let width = ScheduleTimerView.panelWidth
        let height = ScheduleTimerView.preferredHeight()
        let scheduleView = ScheduleTimerView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scheduleView.onConfirm = { [weak self] start, duration, title in
            self?.createScheduledTimer(startDate: start, duration: duration, title: title)
            self?.dismissScheduleTimer()
        }
        scheduleView.onCancel = { [weak self] in
            self?.dismissScheduleTimer()
        }

        let panel = SchedulePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = scheduleView

        // 锚定到 hover 列表窗口正下方居中
        var origin = hoverWin.frame.origin
        origin.y = hoverWin.frame.minY - height - 8
        origin.x = hoverWin.frame.midX - width / 2
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.schedulePanel = panel
    }

    /// 关闭并释放日历预约面板
    private func dismissScheduleTimer() {
        schedulePanel?.orderOut(nil)
        schedulePanel = nil
    }

    /// 用 ScheduleTimerView 回填的起止时间创建预约计时
    private func createScheduledTimer(startDate: Date, duration: TimeInterval, title: String) {
        let endDate = startDate.addingTimeInterval(duration)
        _ = TimerManager.shared.addScheduledTimer(
            startTime: startDate,
            endTime: endDate,
            title: title.isEmpty ? nil : title
        )
        os_log("Scheduled timer created: %{public}@ → %{public}@",
               log: log, type: .info, startDate.description, endDate.description)
    }
}

