import EventKit
import AppKit
import os.log

/// 日历写入管理器（单例，叶子模块：仅依赖 EventKit / Foundation / AppKit）
///
/// 计时归零且有标题时，按 `writeMode` 策略把计时记录写入名为 "Linger" 的系统日历。
/// T4 扩展：writeMode（manual/auto/ask）、writeEventOnFinish（5 分钟向上取整）、
/// availableCalendars、defaultTitle、历史迁移（🔔Linger / DragTimer → Linger）、
/// Fn/Ctrl/Opt 预设标题。
final class CalendarManager {

    static let shared = CalendarManager()

    private let store = EKEventStore()
    private let log = OSLog(subsystem: "com.linger.timer", category: "CalendarManager")

    /// 目标日历标题（T4：历史 "🔔Linger" / "DragTimer" 统一迁移到 "Linger"）
    private let calendarTitle = "Linger"

    // MARK: - 写入模式

    /// 日历写入策略
    enum WriteMode: String {
        case manual   // 仅手动（用户在 hover 面板输入标题后写入）
        case auto     // 计时归零自动写入
        case ask      // 归零弹窗询问
    }

    /// 当前写入模式（持久化于 UserDefaults）
    var writeMode: WriteMode {
        let raw = UserDefaults.standard.string(
            forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue) ?? WriteMode.manual.rawValue
        return WriteMode(rawValue: raw) ?? .manual
    }

    func setWriteMode(_ mode: WriteMode) {
        UserDefaults.standard.set(mode.rawValue,
                                  forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue)
    }

    /// 默认标题（持久化于 UserDefaults，缺省 "记录一段专注"）
    var defaultTitle: String {
        UserDefaults.standard.string(
            forKey: LingerTheme.UserDefaultsKey.defaultTitle.rawValue) ?? "记录一段专注"
    }

    func setDefaultTitle(_ title: String) {
        UserDefaults.standard.set(title,
                                  forKey: LingerTheme.UserDefaultsKey.defaultTitle.rawValue)
    }

    // MARK: - 预设标题（Fn / Ctrl / Opt）

    /// 快捷键预设标题：Fn = 专注, Ctrl = 休息, Opt = 会议
    enum PresetKey { case fn, control, option }

    func presetTitle(for key: PresetKey) -> String {
        switch key {
        case .fn: return "专注"
        case .control: return "休息"
        case .option: return "会议"
        }
    }

    // 已记录的 entry ID 集合（持久化到 UserDefaults，防止 app 重启后重复写入）
    private var recordedEntryIDs: Set<String> = []

    private init() {
        loadRecordedEntries()
    }

    // MARK: - 已记录追踪

    /// 检查某个 entry 是否已写入日历
    func isRecorded(_ entryID: UUID) -> Bool {
        recordedEntryIDs.contains(entryID.uuidString)
    }

    /// 标记 entry 已写入日历（持久化）
    func markRecorded(_ entryID: UUID) {
        recordedEntryIDs.insert(entryID.uuidString)
        UserDefaults.standard.set(Array(recordedEntryIDs),
                                  forKey: LingerTheme.UserDefaultsKey.recordedCalendarEntries.rawValue)
    }

    private func loadRecordedEntries() {
        if let ids = UserDefaults.standard.array(
            forKey: LingerTheme.UserDefaultsKey.recordedCalendarEntries.rawValue) as? [String] {
            recordedEntryIDs = Set(ids)
        }
    }

    // MARK: - 权限

    /// 实时查询当前日历权限状态（不触发弹窗）
    func currentAuthorizationStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }

    /// 权限是否已授予（基于实时查询，不触发弹窗）
    var isAuthorized: Bool {
        let status = currentAuthorizationStatus()
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        } else {
            return status == .authorized
        }
    }

    /// 请求日历权限并等待回调（.regular + 有窗口时调用，系统会弹权限对话框）
    /// granted=true：用户点了允许，权限已开启
    /// granted=false：用户拒绝或系统不弹对话框（需要引导去系统设置）
    func requestPermissionWithDialog(completion: @escaping (Bool, Error?) -> Void) {
        os_log("requestPermissionWithDialog: calling requestFullAccessToEvents with visible window", log: log, type: .info)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    os_log("requestPermissionWithDialog callback: granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted),
                           error?.localizedDescription ?? "nil")
                    completion(granted, error)
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    os_log("requestPermissionWithDialog callback (legacy): granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted),
                           error?.localizedDescription ?? "nil")
                    completion(granted, error)
                }
            }
        }
    }

    /// 注册 TCC 权限意图（只调 requestFullAccessToEvents，不弹对话框）
    /// 让 TCC 把应用加入隐私列表，之后用户可以在系统设置中开启权限
    func registerTCCIntent() {
        os_log("registerTCCIntent: calling requestFullAccessToEvents to register TCC intent", log: log, type: .info)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                os_log("registerTCCIntent callback: granted=%{public}@ error=%{public}@",
                       log: self.log, type: .info,
                       String(describing: granted),
                       error?.localizedDescription ?? "nil")
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                os_log("registerTCCIntent callback (legacy): granted=%{public}@ error=%{public}@",
                       log: self.log, type: .info,
                       String(describing: granted),
                       error?.localizedDescription ?? "nil")
            }
        }
    }

    /// 启动时请求日历权限（.regular + active 状态下调用，系统会弹权限对话框）
    /// 用户点击允许/拒绝后，TCC 会注册应用，回调在主线程
    func requestPermissionOnLaunch(completion: @escaping (Bool, Error?) -> Void) {
        os_log("requestPermissionOnLaunch: .regular + active, triggering system dialog", log: log, type: .info)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    os_log("requestPermissionOnLaunch callback: granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted),
                           error?.localizedDescription ?? "nil")
                    completion(granted, error)
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    os_log("requestPermissionOnLaunch callback (legacy): granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted),
                           error?.localizedDescription ?? "nil")
                    completion(granted, error)
                }
            }
        }
    }

    /// 请求日历权限：
    /// 1. 已授权 → 直接返回
    /// 2. 调 requestFullAccessToEvents 让 TCC 登记 Linger 的权限需求
    ///    （Info.plist 中 LSUIElement=false，系统启动时视为普通应用，TCC 能正确登记；
    ///     启动后立即切回 .accessory 隐藏 Dock，用户体验无影响）
    /// 3. 弹 NSAlert 引导用户去「系统设置 → 隐私与安全性 → 日历」手动开启
    /// 回调在后台线程，只打 log，不做 UI 操作；不依赖回调结果。
    func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        // 1. 已授权 → 直接返回
        if isAuthorized {
            os_log("Calendar permission already granted", log: log, type: .info)
            completion(true)
            return
        }

        os_log("Calendar permission not granted (status=%d), registering TCC intent + showing NSAlert",
               log: log, type: .info, currentAuthorizationStatus().rawValue)

        // 2. 调 requestFullAccessToEvents 让 TCC 登记 Linger（不依赖回调，回调只打 log）
        //    Info.plist LSUIElement=false 保证 TCC 能正确识别应用并加入隐私列表
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                // 回调在后台线程，只打 log，不做 UI 操作
                if let error = error {
                    os_log("TCC register error: %{public}@",
                           log: self.log, type: .error, error.localizedDescription)
                } else {
                    os_log("TCC register result: granted=%{public}@",
                           log: self.log, type: .info, granted ? "true" : "false")
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                if let error = error {
                    os_log("TCC register error (legacy): %{public}@",
                           log: self.log, type: .error, error.localizedDescription)
                } else {
                    os_log("TCC register result (legacy): granted=%{public}@",
                           log: self.log, type: .info, granted ? "true" : "false")
                }
            }
        }

        // 3. 弹 NSAlert 引导用户去系统设置手动开启（主线程，不依赖上面的回调）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            let alert = NSAlert()
            alert.messageText = "需要开启日历权限"
            alert.informativeText = "Linger 需要日历访问权限来记录计时事件。\n请点击「打开系统设置」，在「隐私与安全性 → 日历」中为 Linger 开启权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // 跳转系统设置 → 隐私与安全性 → 日历（macOS 13+ 格式）
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
                os_log("User chose to open System Settings for calendar permission",
                       log: self.log, type: .info)
            } else {
                os_log("User cancelled calendar permission alert",
                       log: self.log, type: .info)
            }

            // 未授权状态，completion 返回 false（用户去设置开启后，下次操作会重新检查 isAuthorized）
            completion(false)
        }
    }

    // MARK: - 日历查找/创建（含历史迁移）

    /// 查找或创建 "Linger" 本地日历。
    /// 历史迁移：若已存在 "🔔Linger" 或 "DragTimer" 旧标题日历，则重命名为 "Linger"；
    /// 否则查找/创建 "Linger"。
    private func findOrCreateCalendar() -> EKCalendar? {
        let calendars = store.calendars(for: .event)

        // 历史迁移：旧标题 → 新标题
        if let legacy = calendars.first(where: { $0.title == "🔔Linger" || $0.title == "DragTimer" }) {
            legacy.title = calendarTitle
            do {
                try store.saveCalendar(legacy, commit: true)
                os_log("Migrated legacy calendar to %{public}@", log: log, type: .info, calendarTitle)
                return legacy
            } catch {
                os_log("Failed to migrate legacy calendar: %{public}@",
                       log: log, type: .error, error.localizedDescription)
            }
        }

        if let existing = calendars.first(where: { $0.title == calendarTitle }) {
            return existing
        }

        let newCal = EKCalendar(for: .event, eventStore: store)
        newCal.title = calendarTitle

        // 优先使用本地源，其次用默认日历的源
        if let source = store.sources.first(where: { $0.sourceType == .local }) {
            newCal.source = source
        } else if let source = store.defaultCalendarForNewEvents?.source {
            newCal.source = source
        } else {
            os_log("No available calendar source", log: log, type: .error)
            return nil
        }

        do {
            try store.saveCalendar(newCal, commit: true)
            os_log("Created %{public}@ calendar", log: log, type: .info, calendarTitle)
            return newCal
        } catch {
            os_log("Failed to create calendar: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    /// 返回用户可选的可写日历列表（用于设置页选择目标日历）
    func availableCalendars() -> [EKCalendar] {
        return store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    // MARK: - 目标日历解析（T13：闭合"目标日历下拉不生效"偏差）

    /// 读取用户在设置页选择的目标日历标题（linger_targetCalendar）。
    /// - 若未设置或所选日历不存在于可写日历列表中 → 回退默认 "Linger"（calendarTitle）。
    /// - 若选中项有效（存在于可写日历）→ 返回该标题，写事件时写入对应日历。
    private func resolveTargetCalendarTitle() -> String {
        let stored = UserDefaults.standard.string(
            forKey: LingerTheme.UserDefaultsKey.targetCalendar.rawValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = stored, !s.isEmpty,
           availableCalendars().contains(where: { $0.title == s }) {
            return s
        }
        return calendarTitle
    }

    /// 按标题解析实际写入的目标日历：
    /// - 默认 "Linger" → `findOrCreateCalendar()`（含历史迁移 + 创建）。
    /// - 其它标题 → 在可写日历列表中按标题查找；找不到则回退 "Linger"。
    private func calendar(forTitle title: String) -> EKCalendar? {
        if title == calendarTitle {
            return findOrCreateCalendar()
        }
        if let match = availableCalendars().first(where: { $0.title == title }) {
            return match
        }
        os_log("Target calendar '%{public}@' not found, fallback to %{public}@",
               log: log, type: .info, title, calendarTitle)
        return findOrCreateCalendar()
    }

    // MARK: - 5 分钟向上取整

    /// 纯函数：把时间向上取整到最近的 5 分钟边界
    ///   - 例：14:02 → 14:05，14:05 → 14:05，14:59 → 15:00
    func roundUpToFiveMinutes(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        let remainder = minute % 5
        if remainder != 0 {
            components.minute = minute + (5 - remainder)
        }
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    // MARK: - 写入事件（基础）

    /// 写入日历事件
    /// - Parameters:
    ///   - title: 事件标题（用户输入的计时标题）
    ///   - startDate: 计时开始时间
    ///   - endDate: 计时结束时间
    /// - Returns: eventIdentifier（成功）或 nil（失败）
    func writeEvent(title: String, startDate: Date, endDate: Date) -> String? {
        guard isAuthorized else {
            os_log("No calendar permission, skip write", log: log, type: .error)
            return nil
        }

        // T13：写入用户选中的目标日历（linger_targetCalendar），无效时回退 "Linger"
        let targetTitle = resolveTargetCalendarTitle()
        guard let calendar = calendar(forTitle: targetTitle) else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? defaultTitle : title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
            os_log("Calendar event written to '%{public}@': %{public}@",
                   log: log, type: .info, targetTitle, title.isEmpty ? defaultTitle : title)
            return event.eventIdentifier
        } catch {
            os_log("Failed to save event: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    // MARK: - 写入事件（计时归零专用，含 5 分钟向上取整）

    /// 计时归零回调：将 start/end 向上取整到 5 分钟边界后写入日历
    /// - Parameters:
    ///   - title: 事件标题
    ///   - start: 计时开始时间
    ///   - end: 计时结束时间
    /// - Returns: eventIdentifier（成功）或 nil（失败 / 未授权）
    func writeEventOnFinish(title: String, start: Date, end: Date) -> String? {
        let roundedStart = roundUpToFiveMinutes(start)
        let roundedEnd = roundUpToFiveMinutes(end)
        return writeEvent(title: title, startDate: roundedStart, endDate: roundedEnd)
    }
}
