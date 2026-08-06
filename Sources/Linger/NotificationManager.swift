import AppKit
import UserNotifications
import os.log

/// 通知系统管理器（单例，叶子模块的协调者）
///
/// 职责（对应 PRD §3.4 / 关联描述 §二 06R / 原型 notification-inline.html）：
/// 1. 首次启动请求 `UNUserNotificationCenter` 授权；用户拒绝时回退 `NSSound` 提示音。
/// 2. 订阅 `timerDidFinishNotification`（TimerEntry 计时归零广播），归零即弹原生横幅，不唤醒任何窗口。
/// 3. 横幅：无标题、✓ 完成标记 + 模块化单行（日程模块 + 记录时间 mm:ss + 重复 + 确认）。
///    - 有日程内容 → 日程模块直接显名
///    - 无内容 → 提供内联输入框（`UNTextInputNotificationAction`, placeholder="日程"）
/// 4. 两个 Category：
///    - `dragTimer`：Repeat(↻) + Confirm(✓) 两个纯图标 Action + 日程内联输入(✎)
///    - `scheduledTimer`：无 Action
/// 5. Action 回调（主线程、App 不被唤醒）：
///    - Repeat → `TimerManager.addTimer(duration:)` 同长新计时
///    - Confirm → 按 `writeMode` 编排（auto 已完成即自动写；manual/ask 触发 `CalendarManager.writeEventOnFinish`）
///    - 日程内联输入 → 取用户输入标题后写入
/// 6. 完成提示音：读 `linger_playSound` / `linger_soundName`，关时静默。
///
/// 依赖：`CalendarManager` + `TimerManager`（均为叶子模块），不被其他模块依赖，无循环依赖。
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - 单例

    static let shared = NotificationManager()

    private let log = OSLog(subsystem: "com.linger.notification", category: "NotificationManager")
    /// 通知中心（lazy + bundle 兜底）：Xcode 直接跑可执行文件（无 .app bundle）时
    /// `UNUserNotificationCenter.current()` 会抛异常崩溃，此处无 bundle 返回 nil 禁用通知。
    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil else {
            os_log("No app bundle (raw executable) - notifications disabled", log: log, type: .debug)
            return nil
        }
        return UNUserNotificationCenter.current()
    }()

    /// 横幅是否可用（CalendarRecorder 判断「每次询问」是否改由应用内弹窗承担）
    var bannerAvailable: Bool { center != nil }

    // MARK: - Category / Action 标识

    static let categoryDragTimer = "linger.category.dragTimer"
    static let categoryScheduledTimer = "linger.category.scheduledTimer"
    static let actionRepeat = "linger.action.repeat"
    static let actionConfirm = "linger.action.confirm"
    static let actionScheduleInput = "linger.action.scheduleInput"

    // MARK: - userInfo 键

    private let keyDuration = "duration"
    private let keyStart = "start"
    private let keyEnd = "end"
    private let keyPresetTitle = "presetTitle"
    private let keyHadTitle = "hadTitle"
    private let keyEntryID = "entryID"

    // MARK: - 初始化

    override init() {
        super.init()
        center?.delegate = self
        registerCategories()
        startObservingFinish()
    }

    // MARK: - 授权（首次启动）

    /// 首次启动请求通知授权。
    /// - 仅当状态为 `.notDetermined` 时弹窗；其余状态（含 `.denied`）不重复弹窗。
    /// - 拒绝场景下由 `playFinishSoundIfEnabled()` 的 `NSSound` 回退提示音（不依赖系统通知权限）。
    func requestAuthorizationIfNeeded() {
        center?.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center?.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    os_log("Notification auth result granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted), error?.localizedDescription ?? "nil")
                }
            case .denied, .authorized, .provisional, .ephemeral:
                // 已确定：不重复弹窗；denied 时由 NSSound 回退提示音
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - Category 注册

    private func registerCategories() {
        // dragTimer：日程内联输入(✎) + 重复(↻, 纯图标) + 确认(✓, 纯图标)
        let scheduleInputAction = UNTextInputNotificationAction(
            identifier: Self.actionScheduleInput,
            title: "✎",
            options: [],
            textInputButtonTitle: "确认",
            textInputPlaceholder: "日程")
        let repeatAction = UNNotificationAction(
            identifier: Self.actionRepeat,
            title: "↻",
            options: [])
        let confirmAction = UNNotificationAction(
            identifier: Self.actionConfirm,
            title: "✓",
            options: [])
        let dragCategory = UNNotificationCategory(
            identifier: Self.categoryDragTimer,
            actions: [scheduleInputAction, repeatAction, confirmAction],
            intentIdentifiers: [],
            options: [.customDismissAction])

        // scheduledTimer：无 Action
        let scheduledCategory = UNNotificationCategory(
            identifier: Self.categoryScheduledTimer,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction])

        center?.setNotificationCategories([dragCategory, scheduledCategory])
    }

    // MARK: - 订阅计时归零

    private func startObservingFinish() {
        NotificationCenter.default.addObserver(
            forName: timerDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleTimerDidFinish(note)
        }
    }

    // MARK: - 计时归零处理

    private func handleTimerDidFinish(_ note: Notification) {
        guard let entry = note.object as? TimerEntry else {
            os_log("timerDidFinish: object is not TimerEntry, skip", log: log, type: .error)
            return
        }

        // 完成提示音（读 playSound / soundName，关时静默；拒绝通知权限也照常播放）
        playFinishSoundIfEnabled()

        // 计时完成时通知总开关（设置 → 通知面板；默认开，未设置视为开）
        let notifyKey = LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue
        let notifyOnComplete = UserDefaults.standard.object(forKey: notifyKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: notifyKey)
        guard notifyOnComplete else {
            os_log("notifyOnComplete disabled, skip finish banner", log: log, type: .debug)
            return
        }

        let hadTitle = !(entry.predefinedTitle ?? "").isEmpty
        let presetTitle = entry.predefinedTitle ?? ""
        let duration = entry.duration

        let start = resolveStart(entry: entry, duration: duration)
        let end = resolveEnd(entry: entry, start: start, duration: duration)

        // 归零即弹横幅，不唤醒任何窗口
        let content = UNMutableNotificationContent()
        content.title = ""   // 无标题（PRD/原型一致：用 ✓ 表示完成）
        let scheduleDisplay = hadTitle ? presetTitle : "日程"
        content.body = "✓ \(scheduleDisplay) · \(formatMMSS(duration))"
        content.userInfo = [
            keyDuration: duration,
            keyStart: start.timeIntervalSince1970,
            keyEnd: end.timeIntervalSince1970,
            keyPresetTitle: presetTitle,
            keyHadTitle: hadTitle,
            keyEntryID: entry.id.uuidString
        ]
        content.categoryIdentifier = entry.isScheduled ? Self.categoryScheduledTimer : Self.categoryDragTimer
        content.sound = nil   // 提示音由 NSSound 手动播放，避免与系统通知音叠加

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center?.add(request) { error in
            if let error = error {
                os_log("Failed to deliver finish notification: %{public}@",
                       log: self.log, type: .error, error.localizedDescription)
            }
        }

        // 日历记录由 CalendarRecorder 独立处理（不依赖通知开关/通知权限），此处不再写日历。
    }

    // MARK: - 起始 / 结束时间解析

    private func resolveStart(entry: TimerEntry, duration: TimeInterval) -> Date {
        if let s = entry.originalStartTime ?? entry.startTime { return s }
        if let s = entry.scheduledStartTime { return s }
        return Date()
    }

    private func resolveEnd(entry: TimerEntry, start: Date, duration: TimeInterval) -> Date {
        if let e = entry.originalEndTime { return e }
        if let e = entry.scheduledEndTime { return e }
        return start.addingTimeInterval(duration)
    }

    // MARK: - 日历写入

    private func writeToCalendar(title: String, start: Date, end: Date) -> String? {
        // CalendarManager.writeEventOnFinish 内部已做 isAuthorized 守卫；未授权时返回 nil。
        let eventId = CalendarManager.shared.writeEventOnFinish(title: title, start: start, end: end)
        if eventId != nil {
            os_log("Calendar record written from notification: %{public}@", log: log, type: .info, title)
        } else {
            os_log("Calendar write skipped (not authorized or failed): %{public}@", log: log, type: .info, title)
        }
        return eventId
    }

    /// 按写入模式编排确认逻辑
    private func confirmWrite(title: String, start: Date, end: Date) -> String? {
        let mode = CalendarManager.shared.writeMode
        // auto 模式：归零时已自动写入，Confirm 不再重复写（避免重复事件）
        guard mode != .auto else {
            os_log("Confirm in auto mode → already auto-written, skip", log: log, type: .info)
            return nil
        }
        return writeToCalendar(title: title, start: start, end: end)
    }

    /// 横幅 Confirm/✎：防重复（完成时已被 CalendarRecorder 记录则跳过），写入成功标记条目
    private func confirmAndMark(userInfo: [AnyHashable: Any], title: String, start: Date, end: Date) {
        let entry = lookupEntry(from: userInfo)
        if let entry, entry.hasRecorded {
            os_log("Entry already recorded, skip banner confirm write", log: log, type: .info)
            return
        }
        let eventId = confirmWrite(title: title, start: start, end: end)
        if let eventId, let entry {
            entry.hasRecorded = true
            entry.calendarEventId = eventId
            CalendarManager.shared.markRecorded(entry.id)
        }
    }

    private func lookupEntry(from userInfo: [AnyHashable: Any]) -> TimerEntry? {
        guard let idString = userInfo[keyEntryID] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        return TimerManager.shared.allDisplayEntries.first { $0.id == id }
    }

    // MARK: - 完成提示音（NSSound 回退）

    private func playFinishSoundIfEnabled() {
        let play = UserDefaults.standard.object(forKey: LingerTheme.UserDefaultsKey.playSound.rawValue) as? Bool ?? true
        guard play else { return }
        let name = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.soundName.rawValue) ?? "Glass"
        if let sound = NSSound(named: name) {
            sound.play()
        } else if let fallback = NSSound(named: "Glass") {
            fallback.play()
        }
    }

    // MARK: - 时间格式

    /// 记录时间 mm:ss（分钟可超过 59，如 90:00）
    private func formatMMSS(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - 设置/关于窗口辅助（不改现有通知行为）

    /// 异步返回当前通知授权状态（主线程回调）
    func fetchAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center?.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    /// 打开系统「通知」设置面板（macOS 13+）
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Notification") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 应用在前台（菜单栏 accessory 应用）时仍以横幅呈现
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// Action 回调（App 不被唤醒）。所有 UI/数据操作派发到主线程。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { completionHandler(); return }
            self.handleAction(identifier: identifier, response: response, userInfo: userInfo)
            completionHandler()
        }
    }

    // MARK: - Action 分发

    private func handleAction(identifier: String,
                              response: UNNotificationResponse,
                              userInfo: [AnyHashable: Any]) {
        let duration = (userInfo[keyDuration] as? Double) ?? 0
        let start = Date(timeIntervalSince1970: (userInfo[keyStart] as? Double) ?? Date().timeIntervalSince1970)
        let end = Date(timeIntervalSince1970: (userInfo[keyEnd] as? Double)
                       ?? Date().addingTimeInterval(duration).timeIntervalSince1970)
        let presetTitle = (userInfo[keyPresetTitle] as? String) ?? ""

        switch identifier {
        case Self.actionRepeat:
            // 重复：同长新计时
            _ = TimerManager.shared.addTimer(duration: duration, predefinedTitle: nil)
            os_log("Repeat → new timer %.1fs", log: log, type: .info, duration)

        case Self.actionConfirm:
            // 确认：按写入模式编排（完成时已被 CalendarRecorder 记录则跳过）
            confirmAndMark(userInfo: userInfo, title: presetTitle, start: start, end: end)

        case Self.actionScheduleInput:
            // 日程内联输入：取用户输入标题后写入（无内容时回退 presetTitle）
            if let textResponse = response as? UNTextInputNotificationResponse {
                let typed = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
                confirmAndMark(userInfo: userInfo, title: typed.isEmpty ? presetTitle : typed, start: start, end: end)
            } else {
                confirmAndMark(userInfo: userInfo, title: presetTitle, start: start, end: end)
            }

        case UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier:
            // 默认点击 / 手动关闭：不操作（横幅可手动关闭由系统处理）
            break

        default:
            break
        }
    }
}
