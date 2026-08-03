import Foundation
import os.log

final class TimerManager {

    static let shared = TimerManager()

    private var entries: [TimerEntry] = []
    private let queue = DispatchQueue(label: "com.linger.timer-manager", qos: .userInitiated)
    private let log = OSLog(subsystem: "com.linger.timer", category: "TimerManager")

    /// 并发计时上限。改为 `static` 供 UI 层（Toast 文案）引用，避免上限值散落成硬编码 10。
    /// 注意：这里只改可见性，B2「触顶回收僵尸条目」的逻辑保持原样。
    static let maxConcurrentEntries = 10

    private var appSupportURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.homeDirectoryForCurrentUser
        let lingerDir = base.appendingPathComponent("Linger", isDirectory: true)
        if !fm.fileExists(atPath: lingerDir.path) {
            try? fm.createDirectory(at: lingerDir, withIntermediateDirectories: true)
        }
        return lingerDir
    }

    private var storageURL: URL {
        return appSupportURL.appendingPathComponent("timers.json")
    }

    private init() {
        loadFromDisk()
        performWeeklyCleanup()
    }

    // MARK: - 公共 API

    var hasActiveTimers: Bool {
        return entries.contains { $0.isRunning || $0.isPaused || $0.isScheduled }
    }

    var hasRunningTimers: Bool {
        return entries.contains { $0.isRunning }
    }

    var hasPausedTimers: Bool {
        return entries.contains { $0.isPaused }
    }

    var allDisplayEntries: [TimerEntry] {
        return entries.sorted { ($0.remainingTime) < ($1.remainingTime) }
    }

    var earliestEntry: TimerEntry? {
        return entries
            .filter { $0.isRunning || $0.isPaused }
            .min { $0.remainingTime < $1.remainingTime }
    }

    var runningEntries: [TimerEntry] {
        return entries.filter { $0.isRunning }
    }

    func addTimer(duration: TimeInterval, predefinedTitle: String? = nil) -> TimerEntry? {
        // v5 修复: 触顶时先回收「已结束且 UI 上不可见」的条目。
        //   entriesToPrune 要求 hasRecorded == true，而 hasRecorded 只有在
        //   「用户填了标题 + 日历写入成功」时才为 true —— 没写日历的已完成计时会永久占坑。
        //   累计约 10 次拖拽后 addTimer 恒返回 nil，表现为「松手不创建计时」。
        //   悬停面板本来就用 remainingTime > 0 过滤，这些条目对用户不可见，回收无副作用。
        if entries.count >= Self.maxConcurrentEntries {
            reclaimFinishedEntries()
        }
        guard entries.count < Self.maxConcurrentEntries else {
            os_log("Max concurrent entries reached (%d)", log: log, type: .info, Self.maxConcurrentEntries)
            return nil
        }
        let entry = TimerEntry(duration: duration, predefinedTitle: predefinedTitle,
                               onTick: { [weak self] _ in
                                   self?.notifyStateChanged()
                                   self?.saveToDisk()
                               },
                               onFinish: { [weak self] _ in
                                   self?.notifyStateChanged()
                                   self?.saveToDisk()
                               })
        entries.append(entry)
        notifyStateChanged()
        saveToDisk()
        return entry
    }

    func addScheduledTimer(startTime: Date, endTime: Date, title: String? = nil) -> TimerEntry? {
        guard entries.count < Self.maxConcurrentEntries else { return nil }
        let entry = TimerEntry(scheduledStartTime: startTime, scheduledEndTime: endTime, title: title,
                               onTick: { [weak self] _ in
                                   self?.notifyStateChanged()
                                   self?.saveToDisk()
                               },
                               onFinish: { [weak self] _ in
                                   self?.notifyStateChanged()
                                   self?.saveToDisk()
                               })
        entries.append(entry)
        notifyStateChanged()
        saveToDisk()
        return entry
    }

    func togglePause(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.togglePause()
        notifyStateChanged()
        saveToDisk()
    }

    func pauseAll() {
        entries.forEach { if $0.isRunning { $0.togglePause() } }
        notifyStateChanged()
        saveToDisk()
    }

    func resumeAll() {
        entries.forEach { if $0.isPaused { $0.togglePause() } }
        notifyStateChanged()
        saveToDisk()
    }

    func stopEntry(_ id: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries.remove(at: idx)
            entry.stop()
        }
        notifyStateChanged()
        saveToDisk()
    }

    func stopAll() {
        entries.forEach { $0.stop() }
        entries.removeAll()
        notifyStateChanged()
        saveToDisk()
    }

    // MARK: - 持久化

    private func saveToDisk() {
        let dtos = entries.map { $0.toDTO() }
        queue.async { [storageURL] in
            do {
                let data = try JSONEncoder().encode(dtos)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                os_log("Failed to save timers: %{public}@", log: self.log, type: .error, error.localizedDescription)
            }
        }
    }

    private func loadFromDisk() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([TimerEntryDTO].self, from: data)
            for dto in dtos {
                let entry = TimerEntry(restoredFrom: dto,
                                       onTick: { [weak self] _ in
                                           self?.notifyStateChanged()
                                           self?.saveToDisk()
                                       },
                                       onFinish: { [weak self] _ in
                                           self?.notifyStateChanged()
                                           self?.saveToDisk()
                                       })
                entries.append(entry)
            }
            os_log("Loaded %d timer entries from disk", log: log, type: .info, entries.count)
        } catch {
            os_log("Failed to load timers: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }

    // MARK: - 定时清理

    /// 纯函数（无副作用，便于单元测试）：按清理区间策略返回应被移除的已完成条目。
    /// 策略：remainingTime<=0 且非运行 / 非暂停 / 非预约的条目即视为可清理；
    /// 仅 `weekly` / `monthly` 执行清理，`never` 或未知值返回空（不清理）。
    static func entriesToPrune(_ entries: [TimerEntry], interval: String) -> [TimerEntry] {
        guard interval == "weekly" || interval == "monthly" else { return [] }
        return entries.filter { $0.remainingTime <= 0 && !$0.isRunning && !$0.isPaused && !$0.isScheduled && $0.hasRecorded }
    }

    /// v5 修复: 回收「已结束、未运行、未暂停」的僵尸条目 —— 它们在悬停面板里被
    ///   `remainingTime > 0` 过滤掉，用户看不见，却一直占用 maxConcurrentEntries 名额。
    ///   与 entriesToPrune 的区别: 这里不要求 hasRecorded，只在触顶时调用。
    ///
    /// v5 修复 (QA 回归 BUG-2): 谓词去掉 `!$0.isScheduled`。
    ///   `TimerEntry.isScheduled` 是 `let`，预约跑完后依旧为 true（activateScheduled 不会清它），
    ///   带上该条件会让「已完成的预约」永久占坑，攒满 10 个后 addTimer 恒返回 nil —— Bug 1 原样复发。
    ///   未触发的预约 remainingTime 恒为完整时长 > 0、已激活的预约 isRunning == true，
    ///   两者都会被前两个条件挡住，不存在误删未来预约的风险。
    private func reclaimFinishedEntries() {
        let before = entries.count
        entries.removeAll { $0.remainingTime <= 0 && !$0.isRunning && !$0.isPaused }
        let reclaimed = before - entries.count
        if reclaimed > 0 {
            os_log("Reclaimed %d finished entries (slot limit hit)", log: log, type: .info, reclaimed)
            saveToDisk()
        }
    }

    private func performWeeklyCleanup() {
        let intervalKey = "linger_cleanupInterval"
        let interval = UserDefaults.standard.string(forKey: intervalKey) ?? "weekly"
        // "never" 不清理，直接跳过（与原逻辑一致），避免无谓的后台派发
        guard interval != "never" else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.sync {
                let before = self.entries.count
                let pruned = TimerManager.entriesToPrune(self.entries, interval: interval)
                let ids = Set(pruned.map { $0.id })
                self.entries.removeAll { ids.contains($0.id) }
                if self.entries.count != before {
                    self.saveToDisk()
                }
            }
        }
    }

    // MARK: - 通知

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: timerStateChangedNotification, object: nil)
        }
    }
}
