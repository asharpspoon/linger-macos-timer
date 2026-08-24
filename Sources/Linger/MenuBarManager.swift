import Cocoa
import os.log
import Carbon.HIToolbox   // RegisterEventHotKey：拖拽期全局捕获 Esc（无需辅助功能权限）

/// 菜单栏图标风格（设置-通用下拉可选，`linger_iconStyle`）。
/// 2026-08-23：4 个风格全部用用户提供的 template 矢量 PDF（36×36 画板，渲染 18pt Retina 无损；
/// Sources/Linger/Resources/MenuBarIcons/，随 Linger_Linger.bundle 打进 app），
/// isTemplate=true → 深浅色模式自动适配；资源缺失时回退自绘 Ring。
enum MenuBarIconStyle: String, CaseIterable {
    case jump                            // Jump_time_fill（默认）
    case ring                            // Ring
    case desk                            // Desk_fill
    case importIcon = "import"           // Import_fill（import 是 Swift 关键字）

    /// 设置下拉显示名（2026-08-23 用户要求：显示英文）
    var displayName: String {
        switch self {
        case .jump: return "Jump"
        case .ring: return "Ring"
        case .desk: return "Desk"
        case .importIcon: return "Import"
        }
    }

    /// 资源文件名（不含 .png 扩展）
    var resourceName: String {
        switch self {
        case .jump: return "Jump_time_fill"
        case .ring: return "Ring"
        case .desk: return "Desk_fill"
        case .importIcon: return "Import_fill"
        }
    }

    /// 当前用户选择（未设置/非法值回退 .jump —— 2026-08-23 用户指定默认图标）
    static var current: MenuBarIconStyle {
        let raw = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.iconStyle.rawValue) ?? ""
        return MenuBarIconStyle(rawValue: raw) ?? .jump
    }

    /// 加载 18×18 template 矢量图标（PDF，Retina 无损；对齐微信/企业微信菜单栏规格）；
    /// bundle 里找不到返回 nil（调用方回退自绘 Ring）
    func loadImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "pdf",
                                          subdirectory: "MenuBarIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

/// 设置页切换菜单栏图标后的广播（MenuBarManager 监听并热更新，无需重启）
extension Notification.Name {
    static let lingerMenuBarIconDidChange = Notification.Name("lingerMenuBarIconDidChange")
}


// MARK: - MenuBarManager（菜单栏入口）

final class MenuBarManager: NSObject {

    /// 诊断用构建标记：每次改右键/授权逻辑时递增，日志一眼确认跑的是哪次构建
    static let buildStamp = "menu-v3-20260806"

    private let statusItem: NSStatusItem
    private let statusItemView = LingerStatusItemView()
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
    private enum DragState { case idle, pressed, dragging, cancelling, finishing }
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
    /// 上一帧是否已触顶（用于触顶时只触发一次轻触反馈）
    private var wasOverflowing = false

    // MARK: - Esc 全局热键（Carbon，无需辅助功能权限）

    /// 拖拽期间注册的 Esc 全局热键。keyDown 在 app 未激活时不会派发到 localMonitor，
    /// 因此用 RegisterEventHotKey 兜底：拖拽开始注册、结束注销。
    private static var escHotKeyRef: EventHotKeyRef?
    private static var escEventHandlerRef: EventHandlerRef?
    /// 当前持有拖拽的 MenuBarManager（Carbon 回调无法捕获 Swift 对象，用 weak 转发）
    private static weak var escDragOwner: MenuBarManager?

    // MARK: - 常驻全局热键（Carbon，2026-08-24 用户需求）
    // ⌘, → 打开设置；⌘⌥L → 预约日程。菜单栏 app 常年在后台，
    // mainMenu keyEquivalent 只在本 app 激活时生效 → 必须用 Carbon 全局热键。
    // 右键菜单里同步显示快捷键（纯展示，见 showRightClickMenu）。

    private static weak var hotKeyOwner: MenuBarManager?
    private static var settingsHotKeyRef: EventHotKeyRef?
    private static var scheduleHotKeyRef: EventHotKeyRef?
    private static var globalHotKeyHandlerRef: EventHandlerRef?
    /// 热键 id（EventHotKeyID.id 区分，signature 统一 "LNGR"）
    private static let hotKeyIDSettings: UInt32 = 2
    private static let hotKeyIDSchedule: UInt32 = 3
    /// 触顶瞬间冻结的结束时刻（触顶后数字不再变化，直到退出溢出）
    private var overflowTil: Date?

    // T3: 倒计时面板（CountdownPillPanel / CountdownFloater）已移除；计时归零改用 Toast 占位。

    // T7–T11: 设置窗口与关于窗口（复用实例，避免重复创建）
    private var settingsWindow: SettingsWindow?

    // Step 5: 悬停面板
    private var hoverListWindow: HoverListWindow?
    private var hoverListView: HoverListView?
    /// 窗口顶部锚点 Y（屏幕坐标，动画中保持不变，底部随高度变化）
    private var hoverListTopAnchorY: CGFloat = 0
    /// 鼠标移到面板上时 0.3s 延迟关闭 —— 防止误关
    private var hoverHideWorkItem: DispatchWorkItem?
    /// 鼠标真的进入过面板区域（延迟 0.3s 后判定）→ 用这个标志让面板一直保持打开直到真离开
    private var hoverIsLockedOpen: Bool = false

    /// 2026-08-24 鼠标看门狗：面板显示期间 0.5s 轮询鼠标位置。
    /// 根因：关闭链路依赖 trackingArea exit 事件，但两类场景会丢事件——
    /// ① NSMenu.popUp tracking session 吞掉 icon 侧 mouseExited（右键路径）；
    /// ② 面板 frame 动画缩小把鼠标「甩出」rect，AppKit 不保证补发 exit（取消预约后）。
    /// 看门狗不依赖事件：鼠标既不在面板也不在图标附近 → 走标准延迟关闭判定。
    /// isScheduling 展开期间豁免（NSDatePicker 的系统日历弹层在面板外，防误杀）。
    private var hoverWatchdogTimer: Timer?

    // 右键菜单（不绑定到 statusItem.menu，手动弹出）
    private let rightClickMenu: NSMenu

    // 当前按钮尺寸 — Step 2 恢复 .variableLength，由系统根据内容自适应
    private var statusItemObserver: NSObjectProtocol?
    /// 设置页切换菜单栏图标的通知监听（2026-08-23）
    private var iconChangeObserver: NSObjectProtocol?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rightClickMenu = NSMenu()
        // 2026-08-06 关键修复：NSMenu 默认 autoenablesItems=true，弹出时会按
        // "target 是否响应 action" 自动重新启用所有菜单项——覆盖我们手动设置的
        // isEnabled=false，导致「已获取授权」标题正确但依然可点（前 3 轮未根治的真凶）。
        // 关掉自动启用，让手动 isEnabled 成为唯一权威。
        rightClickMenu.autoenablesItems = false
        super.init()
        statusItem.view = statusItemView
        configureStatusItemStep2()
        // 右键菜单在 showRightClickMenu 中每次重建（实时更新日历权限状态）
        // Step 3 修正：接入 timerStateChangedNotification 监听 — 菜单栏实时同步倒计时
        startObserving()
        NSLog("[Linger] MenuBarManager initialized build=%@ (Step 5: hover list + Step 4 spring/floater)", Self.buildStamp)
        // Step 4 v3: 在 init 之外启动 watch —— 用 DispatchQueue.main.async 推迟到
        //   applicationDidFinishLaunching 返回后由主 RunLoop 处理。
        //   此时 AppEntry 已提前访问过 TimerManager.shared，不会再触发 .shared 初始化。
        DispatchQueue.main.async { [weak self] in
            self?.installHoverTracking()
        }
        // 2026-08-24：常驻全局热键（⌘, 设置 / ⌘⌥L 预约日程）
        installGlobalHotKeys()
    }

    deinit {
        if let obs = statusItemObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = iconChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        // 拖拽期资源：轮询 timer / 点击提示 timer / 局部事件监视器
        pollTimer?.invalidate()
        clickHintTimer?.invalidate()
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        hoverHideWorkItem?.cancel()
        hoverListWindow?.orderOut(nil)
    }

    // MARK: - 图标（SF Symbol + 降级为 Linger 文字）

    /// T12: 菜单栏图标 —— 按用户选择（设置-通用「菜单栏图标」）加载 template PNG；
    /// 资源缺失时回退自绘 Ring。app 图标由 build_and_run.sh 生成 icns 打进 bundle。
    private func buildMenuBarIcon() -> NSImage? {
        return MenuBarIconStyle.current.loadImage() ?? buildRingIcon()
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

    // MARK: - 配置

    /// 自定义 statusItem.view 装配：事件直接在视图层处理，
    /// 不再经过 NSStatusBarButton 的 cell tracking loop ——
    /// 这是「按钮吞 mouseUp → 拖拽状态机卡死 → 松手不计时」老 bug 的根治方案。
    private func configureStatusItemStep2() {
        // 2026-08-23：宽度手动同步 —— AppKit 的 variableLength + custom view
        // 只在内容变宽时自动跟随 intrinsicContentSize，变窄不缩回（倒计时结束
        // 切回纯图标会在菜单栏留大片空白的根因）。每次内容变化手动设 length。
        statusItemView.onContentWidthChanged = { [weak self] width in
            guard let self, abs(self.statusItem.length - width) > 0.5 else { return }
            self.statusItem.length = width
        }
        if let icon = buildMenuBarIcon() {
            statusItemView.setIcon(icon)
        }
        statusItemView.setTitle("")
        // 初次装配也同步一次宽度（图标态 ~26pt）
        statusItem.length = statusItemView.intrinsicContentSize.width

        statusItemView.onMouseDown = { [weak self] in
            self?.beginDrag()
        }
        statusItemView.onMouseUp = { [weak self] in
            self?.finishDrag()
        }
        statusItemView.onRightMouseUp = { [weak self] in
            self?.showRightClickMenu()
        }
        statusItemView.onMouseEntered = { [weak self] in
            self?.handleHoverEntered()
        }
        statusItemView.onMouseExited = { [weak self] in
            self?.handleHoverExited()
        }

        NSLog("[Linger] status item configured (custom view, direct mouseUp)")

    }

    // 右键菜单在 showRightClickMenu 中每次重建（实时更新日历权限状态）
    // NSMenu 声明见 init

    // MARK: - 菜单动作

    @objc private func showAbout(_ sender: Any?) {
        // 2026-08-05：关于已集成进设置窗口第 5 tab（统一原型），不再用独立 AboutWindow
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.showTab(4)   // 关于 tab
        settingsWindow?.refreshPermissionStatuses()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.refreshPermissionStatuses()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openCalendarSettings(_ sender: Any?) {
        // 2026-08-06 修复"点日历授权不主动授权"bug：
        // 旧版未授权时只弹 NSAlert 引导去系统设置，但 macOS TCC 机制要求 app 首次调
        // requestFullAccessToEvents 才会登记到 TCC 并弹系统对话框；不调这个 API，
        // 用户去系统设置也找不到 Linger 开关。新版先主动触发系统对话框，denied 再 fallback。
        // 用 hasAccess（isAuthorized || grantedByRequest）兜底裸 bundle 场景。
        if CalendarManager.shared.hasAccess {
            let alert = NSAlert()
            alert.messageText = "日历权限已开启"
            alert.informativeText = "Linger 已获得日历访问权限，计时标题会实时写入 Linger 日历。"
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        // 未授权 → 走统一入口（notDetermined 触发系统对话框；denied 弹 NSAlert 引导去系统设置）
        CalendarManager.shared.requestPermissionIfNeeded { [weak self] granted in
            guard let self = self else { return }
            if granted {
                // 授权成功 → 刷新设置窗口状态（若已打开）+ 提示
                self.settingsWindow?.refreshPermissionStatuses()
                let alert = NSAlert()
                alert.messageText = "日历权限已开启"
                alert.informativeText = "现在 Linger 会把计时记录自动写入 Linger 日历。"
                alert.addButton(withTitle: "好的")
                alert.runModal()
            }
            // denied/restricted 路径 requestPermissionIfNeeded 内部已弹 NSAlert 引导，这里不再重复
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

        // 2026-08-23：设置页切换「菜单栏图标」→ 热更新，无需重启
        iconChangeObserver = NotificationCenter.default.addObserver(
            forName: .lingerMenuBarIconDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.statusItemView.setIcon(self.buildMenuBarIcon())
        }

        // T6: 计时归零的 UI 反馈改由 CompletionBanner（自绘玻璃横幅）+ 提示音呈现，
        //     此处不再弹出 Toast，避免与完成弹窗重复。
    }

    // MARK: - 菜单栏显示同步

    /// Step 3 阶段：监听 timerStateChangedNotification —— 有计时时显示倒计时文字，无计时时清空
    private func refreshStatusItemTitle() {
        // 拖拽中菜单栏文字由 refreshStatusTextDuringDrag 独占，
        // 否则每秒的 timerTick 通知会把预览读数闪回成运行态读数。
        // （cleanupDrag 会在松手后主动调用本方法复位）
        if dragState == .dragging { return }
        if let earliest = TimerManager.shared.earliestEntry, earliest.remainingTime > 0 {
            statusItemView.setTitle(" " + earliest.displayTime)
        } else {
            statusItemView.setTitle("")
        }
        // 最后 10s：菜单栏倒计时预览闪烁提醒
        updateStatusUrgentBlink()
    }

    /// 拖拽过程中把菜单栏文字替换成实时预览时长（松手后由 refreshStatusItemTitle 复位）。
    /// 与运行态共用 TimerEntry.displayString，保证松手瞬间读数不跳格式。
    /// 最后 10s：菜单栏倒计时预览琥珀闪烁提醒（与悬停列表同节奏 0.5s）
    private var statusUrgentBlinkOn = false
    private var statusUrgentTimer: Timer?

    private func updateStatusUrgentBlink() {
        let urgent = TimerManager.shared.allDisplayEntries.contains { $0.isRunning && $0.remainingTime <= 10 }
        if urgent {
            guard statusUrgentTimer == nil else { return }
            statusUrgentBlinkOn = true
            applyStatusUrgentColor()
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.statusUrgentBlinkOn.toggle()
                self.applyStatusUrgentColor()
            }
            RunLoop.main.add(t, forMode: .common)
            statusUrgentTimer = t
        } else {
            statusUrgentTimer?.invalidate()
            statusUrgentTimer = nil
            statusUrgentBlinkOn = false
            statusItemView.setTitleColor(nil)
        }
    }

    private func applyStatusUrgentColor() {
        statusItemView.setTitleColor(statusUrgentBlinkOn ? LingerTheme.amberGold : .secondaryLabelColor)
    }

    private func refreshStatusTextDuringDrag(seconds: TimeInterval) {
        statusItemView.setTitle(" " + TimerEntry.displayString(seconds: seconds,
                                                               format: TimerEntry.currentTimeFormat))
    }

    private func showRightClickMenu() {

        // 每次右键时重建菜单，确保日历权限状态实时更新
        rightClickMenu.removeAllItems()

        // 2026-08-24：设置移到最上方（用户要求），快捷键显示 ⌘,（实际触发力：Carbon 全局热键）
        let settingsItem = NSMenuItem(title: "设置…",
                                     action: #selector(showSettings(_:)),
                                     keyEquivalent: ",")
        settingsItem.target = self
        rightClickMenu.addItem(settingsItem)

        // 2026-08-24 用户需求：右键直达预约录入（弹悬停面板 + 直接展开编辑区）
        // 快捷键显示 ⌘⌥L（实际触发力：Carbon 全局热键，见 installGlobalHotKeys）
        let scheduleItem = NSMenuItem(title: "预约日程…",
                                      action: #selector(openScheduleEntry(_:)),
                                      keyEquivalent: "l")
        scheduleItem.keyEquivalentModifierMask = [.command, .option]
        scheduleItem.target = self
        rightClickMenu.addItem(scheduleItem)

        let calAuth = CalendarManager.shared.hasAccess
        // 用 hasAccess（isAuthorized || grantedByRequest）兜底裸 bundle 场景：
        // isAuthorized 在无 bundle 裸跑时恒 false，grantedByRequest 才是真实状态（已持久化）
        // 诊断日志：右键一次即可确认运行构建 + 授权状态 + 菜单项最终状态
        let statusRaw = CalendarManager.shared.currentAuthorizationStatus().rawValue
        let grantedRaw = UserDefaults.standard.bool(
            forKey: "linger_calendarGrantedByRequest") ? 1 : 0
        os_log("RIGHTCLICK build=%{public}@ bundleID=%{public}@ status=%d granted=%d hasAccess=%d title=%{public}@ enabled=%d",
               log: log, type: .info,
               Self.buildStamp,
               Bundle.main.bundleIdentifier ?? "nil",
               statusRaw, grantedRaw, calAuth ? 1 : 0,
               calAuth ? "已获取授权" : "系统授权",
               calAuth ? 0 : 1)
        let calItem = NSMenuItem(title: calAuth ? "已获取授权" : "系统授权",
                                 action: #selector(openCalendarSettings(_:)),
                                 keyEquivalent: "")
        calItem.target = self
        calItem.isEnabled = !calAuth
        rightClickMenu.addItem(calItem)

        // 上线规范（2026-08-06 用户补充）：保留「退出」入口，快捷键 Command+Q
        rightClickMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出",
                                  action: #selector(quitApp(_:)),
                                  keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)

        let location = NSPoint(x: 0, y: statusItemView.bounds.height)
        rightClickMenu.popUp(positioning: nil, at: location, in: statusItemView)
    }

    /// 2026-08-24：右键「预约日程…」——模拟「hover 进入 + 点击日历按钮」的自然路径，
    /// 不再直接 showHoverList 死板呼出：
    /// 1. handleHoverEntered：与鼠标悬停完全同一入口/状态（面板已开则只刷新）
    /// 2. expandScheduleDirectly：等效点击底栏日历按钮展开编辑区
    /// 关闭判定由 hoverWatchdog 兜底（见 showHoverList），鼠标离开面板+图标即收起。
    @objc private func openScheduleEntry(_ sender: Any?) {
        handleHoverEntered()
        hoverListView?.expandScheduleDirectly()
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

    private func installEscHotKey() {
        guard Self.escHotKeyRef == nil else { return }
        Self.escDragOwner = self

        if Self.escEventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let handler: EventHandlerUPP = { _, _, _ in
                // Carbon 事件循环线程 → 回主线程执行取消
                DispatchQueue.main.async {
                    MenuBarManager.escDragOwner?.cancelDrag(animated: true)
                }
                return noErr
            }
            InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, &Self.escEventHandlerRef)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4752), id: 1)   // "LNGR"
        RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID,
                            GetEventDispatcherTarget(), 0, &Self.escHotKeyRef)
    }

    private func uninstallEscHotKey() {
        if let ref = Self.escHotKeyRef {
            UnregisterEventHotKey(ref)
            Self.escHotKeyRef = nil
        }
        Self.escDragOwner = nil
    }

    // MARK: - 常驻全局热键（⌘, / ⌘⌥L）

    /// 注册即永久生效（MenuBarManager 是 app 生命周期单实例，无需注销）。
    /// Carbon 热键在 app 后台时也能触发 —— 菜单栏 app 的唯一系统级快捷键方案。
    private func installGlobalHotKeys() {
        Self.hotKeyOwner = self

        // 一个 handler 按 EventHotKeyID.id 分发两个热键
        if Self.globalHotKeyHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let handler: EventHandlerUPP = { _, event, _ in
                var hkID = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkID)
                // Carbon 事件线程 → 主线程执行 UI 动作
                DispatchQueue.main.async {
                    guard let owner = MenuBarManager.hotKeyOwner else { return }
                    switch hkID.id {
                    case MenuBarManager.hotKeyIDSettings:
                        owner.openSettingsFromHotKey()
                    case MenuBarManager.hotKeyIDSchedule:
                        owner.openScheduleEntry(nil)
                    default:
                        break
                    }
                }
                return noErr
            }
            InstallEventHandler(GetEventDispatcherTarget(), handler, 1,
                                &eventType, nil, &Self.globalHotKeyHandlerRef)
        }

        let sig = OSType(0x4C4E4752)   // "LNGR"，与 Esc 热键同 signature 不同 id
        if Self.settingsHotKeyRef == nil {
            RegisterEventHotKey(UInt32(kVK_ANSI_Comma), UInt32(cmdKey),
                                EventHotKeyID(signature: sig, id: Self.hotKeyIDSettings),
                                GetEventDispatcherTarget(), 0, &Self.settingsHotKeyRef)
        }
        if Self.scheduleHotKeyRef == nil {
            RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey),
                                EventHotKeyID(signature: sig, id: Self.hotKeyIDSchedule),
                                GetEventDispatcherTarget(), 0, &Self.scheduleHotKeyRef)
        }
        os_log("Global hotkeys installed: Cmd+, (settings) / Cmd+Opt+L (schedule)",
               log: log, type: .info)
    }

    /// 热键路径打开设置：从后台 app 触发时需要激活本 app 才能把窗口带到前台
    private func openSettingsFromHotKey() {
        NSApp.activate(ignoringOtherApps: true)
        showSettings(nil)
    }

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
        installEscHotKey()

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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .flagsChanged, .keyDown]) { [weak self] event in
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
        let rawSeconds = TimerEntry.duration(fromDragDistance: Double(distance),
                                             lineMaxLength: Double(currentDragLineMaxLength()),
                                             maxSeconds: maxSeconds,
                                             granularity: timerGranularitySeconds())
        let seconds = TimerEntry.snapToMinuteIfClose(rawSeconds)
        let til = Date().addingTimeInterval(seconds)
        let overflow = rawSeconds >= maxSeconds - 0.5

        // 刚触顶：trackpad 轻触反馈（类似 iPhone 拉到页面最下方）
        if overflow && !wasOverflowing {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        wasOverflowing = overflow

        // 触顶后冻结结束时刻：for/til 两侧数字都不再变化（WYSIWYG）
        if overflow {
            if overflowTil == nil { overflowTil = til }
        } else {
            overflowTil = nil
        }
        let displayTil = overflowTil ?? til

        dragFeedback?.update(distance: distance,
                             seconds: seconds,
                             til: displayTil,
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
        case .keyDown:
            // Esc 取消拖拽：断线动画（keyCode 53 = Esc）
            if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
                os_log("Drag cancelled by Esc", log: log, type: .debug)
                cancelDrag(animated: true)
            }
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
        // 入口立即拆监听器 + 改状态，防止动画期间第二次 mouseUp reentry（创建重复计时）。
        detachDragInput()
        guard dragState == .dragging || dragState == .pressed else {
            // 已被 Esc/前一次 finishDrag 收尾，不再处理
            os_log("finishDrag: skipped (state=%{public}@)",
                   log: log, type: .debug, String(describing: dragState))
            return
        }

        let current = NSEvent.mouseLocation
        let distance = max(0, dragStartLocation.y - current.y)

        // 只要位移超过阈值即视为拖拽 —— 即使 30fps 轮询还没来得及把
        // .pressed 升级成 .dragging，松手也要按当前距离创建计时（WYSIWYG）。
        let isDrag = dragState == .dragging || (dragState == .pressed && distance > 4)
        guard isDrag else {
            os_log("finishDrag: click only (state=%{public}@)",
                   log: log, type: .debug, String(describing: dragState))
            cleanupDrag()
            return
        }

        let maxSeconds = maxDragDurationSeconds()
        let rawSeconds = TimerEntry.duration(fromDragDistance: Double(distance),
                                             lineMaxLength: Double(currentDragLineMaxLength()),
                                             maxSeconds: maxSeconds,
                                             granularity: timerGranularitySeconds())
        // 与 pollDrag 用同一套曲线 + 同一次吸附 → 松手所得 == 松手前所见（WYSIWYG）
        let seconds = TimerEntry.snapToMinuteIfClose(rawSeconds)

        let created = finishDrag(with: seconds)
        if created {
            // 成功创建计时 → 播「向下收起 + 圆圈扩散」动画再 cleanupDrag
            // （detachDragInput 已拆 monitor/pollTimer，动画期间不会 reentry）
            dragState = .finishing
            dragFeedback?.animateCreate { [weak self] in
                self?.cleanupDrag()
            }
        } else {
            cleanupDrag()
        }
        os_log("finishDrag: %.1fs (d=%.1f) created=%{public}@",
               log: log, type: .info, seconds, distance, String(describing: created))
    }

    /// 取消拖拽。`animated` 为 true（Esc）时先播断线动画再复位；
    /// 动画期间不再响应鼠标/轮询，松手也不会创建计时。
    private func cancelDrag(animated: Bool = false) {
        guard dragState != .cancelling else { return }
        if animated {
            if let m = localMonitor {
                NSEvent.removeMonitor(m)
                localMonitor = nil
            }
            pollTimer?.invalidate()
            pollTimer = nil
            clickHintTimer?.invalidate()
            clickHintTimer = nil
            dragState = .cancelling
            dragFeedback?.animateBreak { [weak self] in
                self?.cleanupDrag()
            }
            return
        }
        cleanupDrag()
    }

    /// 清理拖拽期资源：移除 monitor、停轮询、关反馈与提示、复位状态与菜单栏文字。
    /// 所有退出路径（松手 / Command 取消 / 纯点击）都收敛到这里，杜绝状态残留。
    /// 拆除拖拽输入监听（monitor + pollTimer + clickHint），不隐藏反馈面板。
    /// 供 finishDrag 入口调用，防止动画期间第二次 mouseUp reentry。
    private func detachDragInput() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        clickHintTimer?.invalidate()
        clickHintTimer = nil
    }

    private func cleanupDrag() {
        detachDragInput()
        dragFeedback?.hide()
        hideClickHint()
        dragState = .idle
        wasOverflowing = false
        overflowTil = nil
        uninstallEscHotKey()
        pendingTitle = nil
        refreshStatusItemTitle()
    }

    /// 真正创建计时：沿用 2.0 的修饰键预设标题 + 并发上限 Toast 语义。
    @discardableResult
    private func finishDrag(with seconds: TimeInterval) -> Bool {
        // 松手瞬间再读一次修饰键，覆盖拖拽期间 flagsChanged 未捕获到的情况
        let title = pendingTitle ?? currentPresetTitle(for: NSEvent.modifierFlags)

        if let entry = TimerManager.shared.addTimer(duration: seconds, predefinedTitle: title) {
            bumpDragHintUsage()
            os_log("Created timer entry %{public}@ for %.1fs",
                   log: log, type: .info, entry.id.uuidString, seconds)
            return true
        } else {
            // 走到这里说明拖拽链路是通的，失败在 TimerManager 并发上限
            //（B2 的 reclaimFinishedEntries 回收逻辑已在 addTimer 内先跑过一轮）
            os_log("finishDrag rejected by TimerManager (limit reached) for %.1fs",
                   log: log, type: .error, seconds)
            showToast(message: "已达 \(TimerManager.maxConcurrentEntries) 个计时上限")
            return false
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

    /// 2026-08-23：当前下拉线最大长度（屏高 × dragLineFraction）。
    /// 与 DragFeedbackView.show() 共用同一纯函数 + 同一 UserDefaults 判定，
    /// 保证「渲染的线长上限」与「时间映射的归一化分母」严格一致（WYSIWYG）。
    private func currentDragLineMaxLength() -> CGFloat {
        let key = LingerTheme.UserDefaultsKey.maxDragLinePercent.rawValue
        let hasSetValue = UserDefaults.standard.object(forKey: key) != nil
        let raw = UserDefaults.standard.double(forKey: key)
        let p = hasSetValue ? raw : 50
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return screenHeight * CGFloat(DragPhysics.dragLineFraction(percent: p))
    }

    /// 2026-08-23：计时粒度（设置-通用，`linger_timerGranularity`，缺省 60s）。
    /// 拖拽读数按该步进吸附（10s → 1:00、1:10、1:20…），松手创建的时长同样吸附。
    private func timerGranularitySeconds() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: LingerTheme.UserDefaultsKey.timerGranularity.rawValue)
        return v > 0 ? v : LingerTheme.defaultTimerGranularity
    }

    /// 拖拽引导提示计数：每次成功创建计时 +1；前 3 次拖拽显示提示文案，之后永久隐藏（见 DragFeedbackView）。
    private func bumpDragHintUsage() {
        let key = LingerTheme.UserDefaultsKey.dragHintUsageCount.rawValue
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
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
        guard let window = statusItemView.window else {
            let y = NSScreen.main?.visibleFrame.maxY ?? 800
            return NSRect(x: 0, y: y, width: 24, height: 24)
        }
        return window.convertToScreen(statusItemView.frame)
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
        // 尺寸内容自适应（对齐 toast.html：px-5 py-3 毛玻璃胶囊）
        let size = ToastView.size(for: message)
        let rect = NSRect(x: screenFrame.midX - size.width / 2,
                          y: screenFrame.midY - size.height / 2,
                          width: size.width, height: size.height)
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

        let view = ToastView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                             message: message)
        win.contentView = view

        // 动画：淡入 0.4s → 停留 2.5s → 淡出 0.4s（对齐原型注释）
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            win.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
            })
        }
    }

    // MARK: - Step 5: 悬停计时列表面板

    /// 悬停追踪由 LingerStatusItemView 内建的 NSTrackingArea 承担
    /// （鼠标进入图标 → 弹面板；离开 → 0.3s 延迟判定）。
    private func installHoverTracking() {
        statusItemView.updateTrackingAreas()
    }

    /// 鼠标进入图标 → 检查是否有计时器，有则弹面板
    private func handleHoverEntered() {
        // 取消之前的延迟关闭（如果鼠标快速进出又进）
        cancelScheduledHoverHide()

        // 2026-08-06: 无计时也弹（空态面板 + 底栏日历按钮），方便直接预约

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
        guard let win = statusItemView.window else { return }

        // 修复 1: 先过滤归零的 entry —— panelH 也要按过滤后的数量算
        //   之前的 bug: allDisplayEntries 包含归零的 entry, setEntries 内部又过滤
        //   导致 panelH 按 2 算, 实际画 1 个卡片, 多出的空间看起来像"空白条目"
        // 2026-08-06: 没有计时也要显示悬浮窗（空态 + 底栏日历按钮），方便用户预约
        let entries = TimerManager.shared.allDisplayEntries.filter { $0.remainingTime > 0 }

        // 计算面板尺寸 & 位置（按三组分：running / paused / scheduled）
        let rCount = entries.filter { !$0.isScheduled && !$0.isPaused }.count
        let pCount = entries.filter { !$0.isScheduled && $0.isPaused }.count
        let scCount = entries.filter { $0.isScheduled }.count
        let panelW = HoverListView.panelWidth
        let panelH = HoverListView.panelHeight3(runningCount: rCount, pausedCount: pCount, scheduledCount: scCount)
        let buttonFrame = statusItemView.frame
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
            guard let self else { return }
            // 停止运行中的预约计时 → 同步删除已写入的日历事件（与「待开始」✕ 删除一致）
            if let entry = TimerManager.shared.allDisplayEntries.first(where: { $0.id == id }),
               entry.isScheduled {
                CalendarRecorder.shared.deleteRecorded(entry)
            }
            TimerManager.shared.stopEntry(id)
            self.refreshHoverList()
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
        // 预约行删除：删计时 + 同步删日历事件
        view.onDeleteScheduled = { [weak self] id in
            self?.deleteScheduledTimer(id)
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
        // 2026-08-05：预约计时改为 hover-list 底部内联展开（原型），
        // 确认后在此创建预约计时；独立浮窗 presentScheduleTimer 已废弃。
        view.onScheduleConfirm = { [weak self] start, duration, title in
            self?.createScheduledTimer(startDate: start, duration: duration, title: title)
        }
        view.onHeightAnimation = { [weak self] height in
            guard let self = self, let win = self.hoverListWindow else { return }
            var frame = win.frame
            frame.size.height = height
            frame.origin.y = self.hoverListTopAnchorY - height
            win.setFrame(frame, display: false)
        }

        // 面板自身加 tracking area：检测鼠标进入/离开面板
        installPanelTracking(on: view)

        // 2026-08-24：看门狗兜底（trackingArea exit 事件在菜单 session / frame 动画下会丢）
        startHoverWatchdog()

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
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = nil
        hoverListWindow?.orderOut(nil)
        hoverListWindow = nil
        hoverListView = nil
        hoverIsLockedOpen = false
    }

    // MARK: - 鼠标看门狗（面板自动关闭兜底）

    private func startHoverWatchdog() {
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.hoverWatchdogTick()
        }
    }

    private func hoverWatchdogTick() {
        guard let win = hoverListWindow else {
            hoverWatchdogTimer?.invalidate()
            hoverWatchdogTimer = nil
            return
        }
        // 预约编辑区展开期间豁免：NSDatePicker 的系统日历弹层出现在面板外，
        // 鼠标在上面选日期时不在面板 frame 内，不能误判离开
        if hoverListView?.isScheduling == true { return }
        let mouse = NSEvent.mouseLocation
        if win.frame.contains(mouse) { return }
        // 鼠标在图标附近（含 8pt 缓冲）→ 视为仍在 hover 语义内
        if let iconWin = statusItemView.window {
            let iconFrame = iconWin.convertToScreen(
                statusItemView.convert(statusItemView.bounds, to: nil))
            if iconFrame.insetBy(dx: -8, dy: -8).contains(mouse) { return }
        }
        // 鼠标既不在面板也不在图标 → 走标准关闭判定（含 0.3s 宽限，期间鼠标滑回可救）
        scheduleHoverHideCheck()
    }

    /// 通知触发时调用：仅在面板已显示时刷新数据
    private func refreshHoverList() {
        guard let view = hoverListView else { return }
        // 修复 1: 同样过滤归零 entry —— 保持与 showHoverList 一致
        // 2026-08-06: 计时清空后保持空态悬浮窗（不再自动隐藏），用户仍可点日历预约
        let active = TimerManager.shared.allDisplayEntries.filter { $0.remainingTime > 0 }
        view.setEntries(active)
    }

    // MARK: - 菜单动作（Step 2 版本见文件上部 showAbout(_:)/showSettings(_:)/quitApp(_:)）

    // MARK: - 日历预约面板（T5: ScheduleTimerView）

    /// 删除预约计时：先同步删除已写入的日历事件，再移除计时条目
    private func deleteScheduledTimer(_ id: UUID) {
        guard let entry = TimerManager.shared.allDisplayEntries.first(where: { $0.id == id }), entry.isScheduled else {
            os_log("Delete scheduled: entry not found / not scheduled", log: log, type: .info)
            return
        }
        CalendarRecorder.shared.deleteRecorded(entry)
        TimerManager.shared.stopEntry(id)
        refreshHoverList()
        os_log("Scheduled timer deleted (calendar synced): %{public}@", log: log, type: .info, id.uuidString)
    }

    /// 弹出内联日历预约面板（ScheduleTimerView），确认后创建预约计时。
    /// 用 ScheduleTimerView 回填的起止时间创建预约计时；
    /// 创建即按「记录的日期-时间-时长」写入 macOS 日历（用户明确安排，无需再等完成）。
    private func createScheduledTimer(startDate: Date, duration: TimeInterval, title: String) {
        let endDate = startDate.addingTimeInterval(duration)
        guard let entry = TimerManager.shared.addScheduledTimer(
            startTime: startDate,
            endTime: endDate,
            title: title.isEmpty ? nil : title
        ) else {
            os_log("Scheduled timer creation failed (slot limit)", log: log, type: .error)
            return
        }
        CalendarRecorder.shared.recordScheduled(entry)
        os_log("Scheduled timer created: %{public}@ → %{public}@",
               log: log, type: .info, startDate.description, endDate.description)
    }
}

