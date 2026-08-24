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
            // 完成弹窗开启时由横幅 ✓/输入承担「每次询问」；弹窗关闭则不打扰、静默跳过
            let key = LingerTheme.UserDefaultsKey.notifyOnComplete.rawValue
            let bannerOn = UserDefaults.standard.object(forKey: key) == nil
                ? true
                : UserDefaults.standard.bool(forKey: key)
            os_log("Ask mode: banner handles ask (bannerOn=%d)", log: log, type: .debug, bannerOn ? 1 : 0)
        case .manual:
            // 手动：由 hover 标题编辑 / 横幅 Confirm/✎ 动作写入
            os_log("Manual write mode: completion record skipped (user records manually)", log: log, type: .debug)
        }
    }

    /// auto：完成即写入（未授权时按需发起系统授权，PRD §3.5.1「首次尝试写入时请求权限」；
    /// 已授权/已请求过则直接写）。
    /// 2026-08-23：首次授权回调可能早于 EventKit 数据库就绪（calendars/sources 仍为空
    /// → 找不到日历 source 写入失败），失败时延迟 1.5s 重试一次。
    private func writeCompletion(_ entry: TimerEntry, retryOnFailure: Bool = true) {
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
            } else if retryOnFailure {
                os_log("Auto record failed (store may not be ready), retrying in 1.5s",
                       log: self.log, type: .info)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.writeCompletion(entry, retryOnFailure: false)
                }
            }
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
        guard CalendarManager.shared.hasAccess else {
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

    // MARK: - 横幅确认写入

    /// 完成弹窗的「确认/输入日程」调用：auto 已自动写则跳过；ask/manual 写并标记。
    /// title 传 nil 表示用条目自带标题（或默认标题）。
    func recordFromBanner(_ entry: TimerEntry, title: String?) {
        let manager = CalendarManager.shared
        let typed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 用户显式输入了标题 → 无论 auto/ask/manual 都保证日历里用的是这个标题：
        // auto 已完成写入（默认标题）→ 更新已有事件的标题；否则按需写入。
        if !typed.isEmpty {
            entry.predefinedTitle = typed
            if let eventId = entry.calendarEventId {
                if manager.updateEventTitle(eventIdentifier: eventId, newTitle: typed) {
                    os_log("Banner typed title applied to existing event: %{public}@", log: log, type: .info, typed)
                } else {
                    os_log("Banner typed title update failed (event not found / no auth)", log: log, type: .info)
                }
                return
            }
            // 没有已有事件（ask/manual 尚未写）→ 走正常写入
        }

        guard !entry.hasRecorded else {
            os_log("Banner confirm: already recorded, skip", log: log, type: .debug)
            return
        }
        if manager.writeMode == .auto {
            os_log("Banner confirm in auto mode: already auto-written, skip", log: log, type: .info)
            return
        }
        let resolved: String
        if !typed.isEmpty {
            resolved = typed
        } else if let t = entry.predefinedTitle, !t.isEmpty {
            resolved = t
        } else {
            resolved = manager.defaultTitle
        }
        let start = resolveStart(entry)
        let end = resolveEnd(entry, start: start)
        if let eventId = manager.writeEventOnFinish(title: resolved, start: start, end: end) {
            markRecorded(entry, eventId: eventId)
            os_log("Banner confirm record written: %{public}@", log: log, type: .info, resolved)
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
