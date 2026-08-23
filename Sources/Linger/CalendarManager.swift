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
    /// 默认 .auto：用户「拖拽发起的计时完成时记入 macOS 日程」（2026-08-06 需求）；
    /// 可在设置 → 日历 → 写入方式 改为 每次询问 / 手动。
    var writeMode: WriteMode {
        let raw = UserDefaults.standard.string(
            forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue) ?? WriteMode.auto.rawValue
        return WriteMode(rawValue: raw) ?? .auto
    }

    /// 用户是否显式设置过写入方式（true 后不再做默认值迁移）
    private static let explicitWriteModeKey = "linger_calendarWriteModeExplicit"

    func setWriteMode(_ mode: WriteMode) {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue,
                     forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue)
        defaults.set(true, forKey: Self.explicitWriteModeKey)
    }

    /// 2026-08-06：写入方式默认由 manual 改为 auto（用户需求：拖拽计时完成即记入日程）。
    /// 老版本把默认 manual 持久化进了 UserDefaults，导致新默认不生效（实机日志确认
    /// 「Manual write mode: completion record skipped」）。
    /// 一次性迁移：只要用户从未显式设置过（linger_calendarWriteModeExplicit=false），
    /// 就把残留的 manual 升为 auto；显式选过手动/询问的用户不受影响。
    private func migrateLegacyWriteModeDefault() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.explicitWriteModeKey) else { return }
        let raw = defaults.string(forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue)
        if raw == WriteMode.manual.rawValue {
            defaults.set(WriteMode.auto.rawValue,
                         forKey: LingerTheme.UserDefaultsKey.calendarWriteMode.rawValue)
            os_log("Migrated legacy writeMode manual -> auto (new default)", log: log, type: .info)
        }
        defaults.set(true, forKey: Self.explicitWriteModeKey)
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

    /// 授权标记（持久化于 UserDefaults）。
    /// 2026-08-06 修复"重启后已授权菜单项仍可点"bug：
    /// 旧版是内存变量，app 重启后重置为 false。裸 bundle 下 isAuthorized 恒 false，
    /// 重启后 hasAccess 恒 false → 菜单项永远可点。改为持久化后，只要曾经授权过，
    /// 重启后 hasAccess 仍返回 true。
    /// macOS 对「无 bundle 的裸可执行文件」无法用 authorizationStatus(for:)
    /// 正确归因 TCC 权限（status 恒 notDetermined），但 requestFullAccessToEvents
    /// 的回调会如实返回 granted。用回调结果驱动写入，让 Xcode 裸跑调试也能写日历。
    private static let grantedByRequestKey = "linger_calendarGrantedByRequest"
    private var grantedByRequest: Bool {
        get { UserDefaults.standard.bool(forKey: Self.grantedByRequestKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.grantedByRequestKey)
            // 通知 UI 刷新（右键菜单状态 / 设置页授权状态）
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .lingerCalendarAccessDidRefresh, object: nil)
            }
        }
    }

    private init() {
        loadRecordedEntries()
        migrateLegacyWriteModeDefault()
        // 2026-08-06 加固：TCC 归因漂移时 authorizationStatus(for:) 恒返回 notDetermined
        // （ad-hoc 签名每次重建变化，TCC 可能不再把授权记录归因到新二进制），
        // 但 recordedCalendarEntries 非空 = 本 app 曾成功写入过日历 = 实际已授权。
        // 此时用历史写入证据把 grantedByRequest 补为 true，避免"已授权但菜单仍可点"。
        if currentAuthorizationStatus() == .notDetermined
            && !grantedByRequest && !recordedEntryIDs.isEmpty {
            grantedByRequest = true
            os_log("CalendarManager: inferred granted from %d recorded entries (status notDetermined)",
                   log: log, type: .info, recordedEntryIDs.count)
        }
        os_log("CalendarManager init: bundleID=%{public}@ status=%d grantedByRequest=%d",
               log: log, type: .info,
               Bundle.main.bundleIdentifier ?? "nil",
               currentAuthorizationStatus().rawValue,
               grantedByRequest ? 1 : 0)
        // 启动时静默探测真实权限状态（已授权/已拒绝不弹窗），更新 grantedByRequest
        probeAccessOnLaunch()
    }

    /// 启动时静默探测权限：只在 authorizationStatus != notDetermined 时调
    /// requestFullAccessToEvents（已授权/已拒绝时不弹窗，直接回调真实状态）。
    /// notDetermined 时不调（避免启动弹窗），grantedByRequest 用持久化值。
    /// 回调更新 grantedByRequest + 发通知让 UI 刷新。
    private func probeAccessOnLaunch() {
        let status = currentAuthorizationStatus()
        os_log("probeAccessOnLaunch: status=%d", log: log, type: .info, status.rawValue)
        guard status != .notDetermined else { return }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.grantedByRequest = granted
                    os_log("probeAccessOnLaunch result: granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted), error?.localizedDescription ?? "nil")
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.grantedByRequest = granted
                    os_log("probeAccessOnLaunch result (legacy): granted=%{public}@",
                           log: self.log, type: .info, String(describing: granted))
                }
            }
        }
    }

    /// 确保完全访问：已授权/已请求过 → 直接 true；notDetermined → 发起系统授权；
    /// denied/restricted → false（不弹窗）。回调主线程。
    func ensureFullAccess(completion: @escaping (Bool) -> Void) {
        if isAuthorized || grantedByRequest {
            completion(true)
            return
        }
        let status = currentAuthorizationStatus()
        let canRequest: Bool = {
            if status == .notDetermined || status == .authorized { return true }
            if #available(macOS 14.0, *), status == .fullAccess { return true }
            return false
        }()
        guard canRequest else {
            os_log("Calendar access denied/restricted (status=%d), skip request",
                   log: log, type: .info, status.rawValue)
            completion(false)
            return
        }
        os_log("ensureFullAccess: requesting full access (status=%d)", log: log, type: .info, status.rawValue)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    self.grantedByRequest = granted
                    os_log("ensureFullAccess result: granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted), error?.localizedDescription ?? "nil")
                    completion(granted)
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    self.grantedByRequest = granted
                    os_log("ensureFullAccess result (legacy): granted=%{public}@ error=%{public}@",
                           log: self.log, type: .info,
                           String(describing: granted), error?.localizedDescription ?? "nil")
                    completion(granted)
                }
            }
        }
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

    /// 取消「已记录」标记（删除预约时同步移除日历事件后调用）
    func unmarkRecorded(_ entryID: UUID) {
        recordedEntryIDs.remove(entryID.uuidString)
        UserDefaults.standard.set(Array(recordedEntryIDs),
                                  forKey: LingerTheme.UserDefaultsKey.recordedCalendarEntries.rawValue)
    }

    /// 更新已写入日历事件的标题（完成弹窗内输入日程标题时，覆盖 auto 写入的默认标题）
    func updateEventTitle(eventIdentifier: String, newTitle: String) -> Bool {
        guard isAuthorized || grantedByRequest else {
            os_log("Update event title skipped: calendar not authorized", log: log, type: .error)
            return false
        }
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            os_log("Update event title: event %{public}@ not found", log: log, type: .info, eventIdentifier)
            return false
        }
        event.title = newTitle
        do {
            try store.save(event, span: .thisEvent, commit: true)
            os_log("Calendar event title updated → %{public}@", log: log, type: .info, newTitle)
            return true
        } catch {
            os_log("Failed to update event title: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return false
        }
    }

    /// 按 eventIdentifier 删除日历事件（预约删除时同步清理；未授权/找不到返回 false）
    func deleteEvent(eventIdentifier: String) -> Bool {
        guard isAuthorized || grantedByRequest else {
            os_log("Delete event skipped: calendar not authorized", log: log, type: .error)
            return false
        }
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            os_log("Delete event: event %{public}@ not found (maybe already removed)", log: log, type: .info, eventIdentifier)
            return false
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            os_log("Calendar event deleted: %{public}@", log: log, type: .info, eventIdentifier)
            return true
        } catch {
            os_log("Failed to delete event %{public}@: %{public}@",
                   log: log, type: .error, eventIdentifier, error.localizedDescription)
            return false
        }
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

    /// 统一授权状态查询（实时查询 OR 内存回调标记）。
    /// 2026-08-06 修复"已授权菜单项仍可点"bug：裸 bundle 下 isAuthorized 恒 false，
    /// UI 层直接读 isAuthorized 会误判为未授权。所有外部调用方应使用 hasAccess，
    /// 而非 isAuthorized（后者仅供内部与 ensureFullAccess 等已做 OR 兜底的路径使用）。
    var hasAccess: Bool {
        return isAuthorized || grantedByRequest
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

    /// 请求日历权限（统一入口，去重弹窗）：
    /// - 已授权 → completion(true) 直接返回
    /// - notDetermined → 调 requestFullAccessToEvents 触发**一次**系统对话框；granted=true → completion(true)；granted=false → completion(false)
    /// - denied/restricted → 弹一次 NSAlert 引导去「系统设置 → 隐私与安全性 → 日历」手动开启 → completion(false)
    ///
    /// 2026-08-06 修复"首次写入弹三次授权两次重复"bug：
    /// 旧版无论 status 如何都无条件调 requestFullAccessToEvents + 弹 NSAlert，导致 notDetermined
    /// 状态下系统对话框 + 应用内 NSAlert 同时出现；叠加 ensureFullAccess 的系统弹窗就是三次。
    /// 新版按 status 分流，每个状态只触发一条 UI 路径。
    func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        // 1. 已授权 → 直接返回
        if isAuthorized {
            os_log("Calendar permission already granted", log: log, type: .info)
            completion(true)
            return
        }

        let status = currentAuthorizationStatus()
        os_log("Calendar permission not granted (status=%d), routing by status",
               log: log, type: .info, status.rawValue)

        // 2. notDetermined → 调一次系统对话框（TCC 登记 + 用户选择）
        if status == .notDetermined {
            os_log("requestPermissionIfNeeded: notDetermined, triggering system dialog", log: log, type: .info)
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { [weak self] granted, error in
                    DispatchQueue.main.async {
                        self?.grantedByRequest = granted
                        os_log("requestPermissionIfNeeded system dialog: granted=%{public}@ error=%{public}@",
                               log: self?.log ?? OSLog.default, type: .info,
                               String(describing: granted), error?.localizedDescription ?? "nil")
                        completion(granted)
                    }
                }
            } else {
                store.requestAccess(to: .event) { [weak self] granted, error in
                    DispatchQueue.main.async {
                        self?.grantedByRequest = granted
                        os_log("requestPermissionIfNeeded system dialog (legacy): granted=%{public}@",
                               log: self?.log ?? OSLog.default, type: .info, String(describing: granted))
                        completion(granted)
                    }
                }
            }
            return
        }

        // 3. denied/restricted → 弹 NSAlert 引导去系统设置（不再调 requestFullAccessToEvents，系统不会弹对话框）
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

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
                os_log("User chose to open System Settings for calendar permission", log: self.log, type: .info)
            } else {
                os_log("User cancelled calendar permission alert", log: self.log, type: .info)
            }
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
        guard isAuthorized || grantedByRequest else {
            os_log("No calendar permission (status=%d), skip write", log: log, type: .error,
                   currentAuthorizationStatus().rawValue)
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
        // 2026-08-06：notes 加 [Linger 计时] 标记，供 Markdown 导出识别哪些事件是 Linger 写的
        event.notes = "[Linger 计时]"

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

    // MARK: - 查询事件（Markdown 导出用，2026-08-06）

    /// 查询指定时间范围内的所有日历事件（用于 Markdown 导出）。
    /// - Parameters:
    ///   - from: 起始时间（含）
    ///   - to: 结束时间（含）
    /// - Returns: 事件数组（按开始时间升序）；授权失败返回空数组
    func fetchEvents(from: Date, to: Date) -> [EKEvent] {
        guard isAuthorized || grantedByRequest else {
            os_log("fetchEvents skipped: calendar not authorized", log: log, type: .error)
            return []
        }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        os_log("fetchEvents: %d events from %@ to %@", log: log, type: .info,
               events.count, from.description, to.description)
        return events
    }

    /// 判断事件是否由 Linger 写入（notes 含 "[Linger 计时]" 标记）
    func isLingerEvent(_ event: EKEvent) -> Bool {
        return event.notes?.contains("[Linger 计时]") == true
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

/// 日历授权状态变更通知（CalendarManager.grantedByRequest 更新时发出）。
extension Notification.Name {
    static let lingerCalendarAccessDidRefresh = Notification.Name("LingerCalendarAccessDidRefresh")
}
