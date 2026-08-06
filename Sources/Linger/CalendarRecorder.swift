//  CalendarRecorder.swift
//  计时 → 日历记录协调器（2026-08-06 新增，用户「重要功能」）
//
//  职责：
//  1. 拖拽发起的计时：归零（完成）时按「写入方式」记录到 macOS 日历
//     - auto  ：自动写入（默认标题兜底，5 分钟向上取整）
//     - ask   ：通知横幅可用时由横幅的 ✓/✎ 承担询问；横幅不可用（通知关闭/无 bundle/
//               权限被拒）时用应用内弹窗询问，保证「每次询问」一定发生
//     - manual：不动（用户通过 hover 标题编辑 / 横幅动作手动记录）
//  2. 预约发起的计时：确认创建时按「记录的日期-时间-时长」立即写入日历
//     （预约本身就是用户明确安排的日程，创建即记录；已记录的在完成时不再重复写）
//
//  与 NotificationManager 解耦：日历记录不依赖「计时完成时通知」开关，也不依赖通知权限。

import AppKit
import os.log

final class CalendarRecorder {

    static let shared = CalendarRecorder()

    private let log = OSLog(subsystem: "com.linger.timer", category: "CalendarRecorder")

    private init() {
        NotificationCenter.default.addObserver(
            forName: timerDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleTimerDidFinish(note)
        }
    }

    // MARK: - 归零完成

    private func handleTimerDidFinish(_ note: Notification) {
        guard let entry = note.object as? TimerEntry else {
            os_log("timerDidFinish: object is not TimerEntry, skip", log: log, type: .error)
            return
        }
        recordCompletion(entry)
    }

    /// 完成时按写入模式记录（已记录过的条目跳过，避免重复）
    func recordCompletion(_ entry: TimerEntry) {
        guard !entry.hasRecorded else {
            os_log("Entry %{public}@ already recorded, skip completion record", log: log, type: .debug, entry.id.uuidString)
            return
        }
        switch CalendarManager.shared.writeMode {
        case .auto:
            writeCompletion(entry)
        case .ask:
            presentAskIfBannerUnavailable(entry)
        case .manual:
            // 手动：由 hover 标题编辑 / 横幅 Confirm/✎ 动作写入
            os_log("Manual write mode: completion record skipped (user records manually)", log: log, type: .debug)
        }
    }

    /// auto：完成即写入（未授权时按需发起系统授权，PRD §3.5.1「首次尝试写入时请求权限」；
    /// 已授权/已请求过则直接写）
    private func writeCompletion(_ entry: TimerEntry) {
        let manager = CalendarManager.shared
        manager.ensureFullAccess { [weak self] granted in
            guard granted else {
                os_log("Auto record skipped: calendar not authorized", log: self?.log ?? OSLog(subsystem: "com.linger.timer", category: "CalendarRecorder"), type: .info)
                return
            }
            guard let self else { return }
            let title = entry.predefinedTitle ?? ""
            let start = self.resolveStart(entry)
            let end = self.resolveEnd(entry, start: start)
            if let eventId = manager.writeEventOnFinish(title: title, start: start, end: end) {
                self.markRecorded(entry, eventId: eventId)
                os_log("Auto record written: %{public}@", log: self.log, type: .info, title.isEmpty ? "(default)" : title)
            }
        }
    }

    /// ask：通知横幅可用时由横幅承担询问（✓/✎ 写），横幅不可用时应用内弹窗，保证询问一定发生
    private func presentAskIfBannerUnavailable(_ entry: TimerEntry) {
        let notifyKey = LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue
        let notifyOn = UserDefaults.standard.object(forKey: notifyKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: notifyKey)
        // 通知已关 / 无 bundle → 横幅必然不出现 → 直接应用内询问
        guard notifyOn, NotificationManager.shared.bannerAvailable else {
            presentAskPrompt(entry)
            return
        }
        // 通知开着但权限可能被拒 → 异步查一次，被拒则应用内询问
        NotificationManager.shared.fetchAuthorizationStatus { [weak self] status in
            let ok = (status == .authorized || status == .provisional)
            if !ok {
                self?.presentAskPrompt(entry)
            }
        }
    }

    /// 应用内「每次询问」弹窗：可编辑标题，确认后写入
    private func presentAskPrompt(_ entry: TimerEntry) {
        guard CalendarManager.shared.isAuthorized else {
            CalendarManager.shared.requestPermissionIfNeeded { [weak self] granted in
                if granted { self?.writeCompletion(entry) }
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = "计时完成"
        alert.informativeText = "是否将这段计时记录到日历？"
        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        titleField.stringValue = entry.predefinedTitle ?? CalendarManager.shared.defaultTitle
        titleField.placeholderString = "日程"
        alert.accessoryView = titleField
        alert.addButton(withTitle: "记录")
        alert.addButton(withTitle: "不记录")
        alert.alertStyle = .informational
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            os_log("Ask prompt declined, skip record", log: log, type: .info)
            return
        }
        let typed = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = resolveStart(entry)
        let end = resolveEnd(entry, start: start)
        if let eventId = CalendarManager.shared.writeEventOnFinish(
            title: typed.isEmpty ? CalendarManager.shared.defaultTitle : typed,
            start: start, end: end
        ) {
            markRecorded(entry, eventId: eventId)
            os_log("Ask record written: %{public}@", log: log, type: .info, typed)
        }
    }

    // MARK: - 预约创建即记录（Req 2）

    /// 预约计时确认创建时调用：按记录的日期-时间-时长写入日历（精确时间，不 5 分钟取整）
    func recordScheduled(_ entry: TimerEntry) {
        guard !entry.hasRecorded else { return }
        guard let start = entry.scheduledStartTime, let end = entry.scheduledEndTime else {
            os_log("Scheduled record skipped: missing start/end", log: log, type: .error)
            return
        }
        guard CalendarManager.shared.isAuthorized else {
            // 按需授权：引导用户开启日历权限（与 hover 标题写入一致）
            CalendarManager.shared.requestPermissionIfNeeded { [weak self] granted in
                guard granted else { return }
                self?.writeScheduled(entry, start: start, end: end)
            }
            return
        }
        writeScheduled(entry, start: start, end: end)
    }

    private func writeScheduled(_ entry: TimerEntry, start: Date, end: Date) {
        let title = (entry.scheduledTitle?.isEmpty == false)
            ? entry.scheduledTitle!
            : CalendarManager.shared.defaultTitle
        if let eventId = CalendarManager.shared.writeEvent(title: title, startDate: start, endDate: end) {
            markRecorded(entry, eventId: eventId)
            os_log("Scheduled record written: %{public}@ (%{public}@ → %{public}@)",
                   log: log, type: .info, title, start.description, end.description)
        } else {
            os_log("Scheduled record failed (not authorized or error)", log: log, type: .error)
        }
    }

    // MARK: - 删除预约（同步清理日历事件）

    /// 删除预约计时时调用：若已写入日历则同步删除对应事件，并清除「已记录」标记
    func deleteRecorded(_ entry: TimerEntry) {
        if let eventId = entry.calendarEventId {
            if CalendarManager.shared.deleteEvent(eventIdentifier: eventId) {
                os_log("Scheduled delete: calendar event removed %{public}@", log: log, type: .info, eventId)
            } else {
                os_log("Scheduled delete: calendar event not removed (no auth/not found)", log: log, type: .info)
            }
        }
        entry.calendarEventId = nil
        entry.hasRecorded = false
        CalendarManager.shared.unmarkRecorded(entry.id)
    }

    // MARK: - 辅助

    private func resolveStart(_ entry: TimerEntry) -> Date {
        if let s = entry.originalStartTime ?? entry.startTime { return s }
        if let s = entry.scheduledStartTime { return s }
        return Date()
    }

    private func resolveEnd(_ entry: TimerEntry, start: Date) -> Date {
        if let e = entry.originalEndTime { return e }
        if let e = entry.scheduledEndTime { return e }
        return start.addingTimeInterval(entry.duration)
    }

    private func markRecorded(_ entry: TimerEntry, eventId: String) {
        entry.hasRecorded = true
        entry.calendarEventId = eventId
        CalendarManager.shared.markRecorded(entry.id)
    }
}
