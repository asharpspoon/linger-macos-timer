import Foundation
import os.log

let timerStateChangedNotification = Notification.Name("timerStateChanged")

/// 计时归零（完成）通知。由 TimerEntry.fireFinish 在计时结束时广播，供 UI 层（如 Toast 占位）监听。
let timerDidFinishNotification = Notification.Name("timerDidFinish")

// MARK: - TimerEntryDTO（持久化 DTO）

struct TimerEntryDTO: Codable {
    let id: UUID
    let duration: TimeInterval
    let remainingTime: TimeInterval
    let isRunning: Bool
    let isPaused: Bool
    let startTime: Date?
    let originalStartTime: Date?
    let originalEndTime: Date?
    let hasRecorded: Bool
    let isScheduled: Bool
    let scheduledStartTime: Date?
    let scheduledEndTime: Date?
    let scheduledTitle: String?
    let predefinedTitle: String?
    let calendarEventId: String?
}

// MARK: - TimerEntry（计时器实体 + 状态机）

final class TimerEntry {

    // MARK: - 数据字段

    let id: UUID
    var duration: TimeInterval
    var remainingTime: TimeInterval
    var isRunning: Bool
    var isPaused: Bool
    var startTime: Date?
    var originalStartTime: Date?
    var originalEndTime: Date?
    var hasRecorded: Bool
    let isScheduled: Bool
    let scheduledStartTime: Date?
    let scheduledEndTime: Date?
    let scheduledTitle: String?
    var predefinedTitle: String?
    var calendarEventId: String?

    // MARK: - 运行时

    private var timer: Timer?
    private var scheduledTimer: Timer?
    private var onTick: ((TimerEntry) -> Void)?
    private var onFinish: ((TimerEntry) -> Void)?

    private let log = OSLog(subsystem: "com.linger.timer", category: "TimerEntry")

    // MARK: - 即时计时

    init(duration: TimeInterval, predefinedTitle: String? = nil, onTick: ((TimerEntry) -> Void)? = nil, onFinish: ((TimerEntry) -> Void)? = nil) {
        self.id = UUID()
        self.duration = duration
        self.remainingTime = duration
        self.isRunning = true
        self.isPaused = false
        self.startTime = Date()
        self.originalStartTime = Date()
        self.originalEndTime = Date().addingTimeInterval(duration)
        self.hasRecorded = false
        self.isScheduled = false
        self.scheduledStartTime = nil
        self.scheduledEndTime = nil
        self.scheduledTitle = nil
        self.predefinedTitle = predefinedTitle
        self.calendarEventId = nil
        self.onTick = onTick
        self.onFinish = onFinish
        startTicking()
    }

    // MARK: - 预约计时

    init(scheduledStartTime: Date, scheduledEndTime: Date, title: String? = nil, onTick: ((TimerEntry) -> Void)? = nil, onFinish: ((TimerEntry) -> Void)? = nil) {
        self.id = UUID()
        let scheduledDuration = max(1, scheduledEndTime.timeIntervalSince(scheduledStartTime))
        self.duration = scheduledDuration
        self.remainingTime = scheduledDuration
        self.isRunning = false
        self.isPaused = false
        self.startTime = nil
        self.originalStartTime = nil
        self.originalEndTime = nil
        self.hasRecorded = false
        self.isScheduled = true
        self.scheduledStartTime = scheduledStartTime
        self.scheduledEndTime = scheduledEndTime
        self.scheduledTitle = title
        self.predefinedTitle = title
        self.calendarEventId = nil
        self.onTick = onTick
        self.onFinish = onFinish
        scheduleActivation(at: scheduledStartTime, duration: scheduledDuration)
    }

    // MARK: - 从 DTO 恢复

    init(restoredFrom dto: TimerEntryDTO, onTick: ((TimerEntry) -> Void)? = nil, onFinish: ((TimerEntry) -> Void)? = nil) {
        self.id = dto.id
        self.duration = dto.duration
        self.remainingTime = dto.remainingTime
        self.isRunning = dto.isRunning
        self.isPaused = dto.isPaused
        self.startTime = dto.startTime
        self.originalStartTime = dto.originalStartTime
        self.originalEndTime = dto.originalEndTime
        self.hasRecorded = dto.hasRecorded
        self.isScheduled = dto.isScheduled
        self.scheduledStartTime = dto.scheduledStartTime
        self.scheduledEndTime = dto.scheduledEndTime
        self.scheduledTitle = dto.scheduledTitle
        self.predefinedTitle = dto.predefinedTitle
        self.calendarEventId = dto.calendarEventId
        self.onTick = onTick
        self.onFinish = onFinish

        if isScheduled, let start = dto.scheduledStartTime, start.timeIntervalSinceNow > 0 {
            let dur = max(1, (dto.scheduledEndTime?.timeIntervalSince(start) ?? duration))
            scheduleActivation(at: start, duration: dur)
            return
        }

        if isRunning {
            if let start = dto.startTime {
                let elapsed = Date().timeIntervalSince(start)
                self.remainingTime = max(0, dto.duration - elapsed)
                if self.remainingTime <= 0 {
                    self.isRunning = false
                    fireFinish()
                    return
                }
            } else {
                // v5 修复: 旧版本落盘的 JSON 里没有 startTime（Optional 为 nil 时被 JSONEncoder 省略）。
                //   tick() 的 `guard let start = startTime else { return }` 会让这类条目永远不递减、
                //   永远不 finish —— 变成占着并发名额的僵尸，还会把菜单栏读数钉死在它的 remainingTime 上。
                //   这里按 remainingTime 重建一个 startTime，让它从当前剩余时间继续正常倒计时。
                self.startTime = Date()
                self.durationForResume = max(0, dto.remainingTime)
                if self.remainingTime <= 0 {
                    self.isRunning = false
                    fireFinish()
                    return
                }
            }
            self.isPaused = false
            startTicking()
        }
    }

    // MARK: - 计时器控制

    private func startTicking() {
        timer?.invalidate()
        // v5 修复: 1.0s → 0.1s —— hover 面板进度条需要更细粒度更新，0.1s 一次 tick 让 CALayer 动画帧更密不会跳
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        remainingTime = max(0, tickDuration - elapsed)
        onTick?(self)
        NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
        if remainingTime <= 0 {
            stop()
            fireFinish()
        }
    }

    private func fireFinish() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        onFinish?(self)
        NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
        // T3: 广播归零通知，供 UI 层（如 MenuBarManager 的 Toast 占位）监听
        NotificationCenter.default.post(name: timerDidFinishNotification, object: self)
    }

    func togglePause() {
        if isRunning && !isPaused {
            timer?.invalidate()
            timer = nil
            isPaused = true
            isRunning = false
            os_log("Timer %{public}@ paused", log: log, type: .debug, id.uuidString)
            NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
        } else if isPaused {
            startTime = Date()
            durationForResume = remainingTime
            isPaused = false
            isRunning = true
            startTicking()
            os_log("Timer %{public}@ resumed", log: log, type: .debug, id.uuidString)
            NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
        }
    }

    // 用于 resume 场景：替换 duration 逻辑，用 remainingTime 作为新的总时长进行 tick 计算
    private var durationForResume: TimeInterval?

    func stop() {
        timer?.invalidate()
        timer = nil
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        isRunning = false
        isPaused = false
        NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
    }

    private func scheduleActivation(at fireDate: Date, duration: TimeInterval) {
        scheduledTimer?.invalidate()
        let t = Timer(fireAt: fireDate, interval: 0, target: self, selector: #selector(activateScheduled), userInfo: nil, repeats: false)
        RunLoop.current.add(t, forMode: .common)
        scheduledTimer = t
        os_log("Timer %{public}@ scheduled at %{public}@", log: log, type: .debug, id.uuidString, fireDate.description)
    }

    @objc private func activateScheduled() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        self.duration = effectiveDuration
        self.remainingTime = effectiveDuration
        self.startTime = Date()
        self.originalStartTime = Date()
        self.originalEndTime = Date().addingTimeInterval(effectiveDuration)
        self.isRunning = true
        self.isPaused = false
        startTicking()
        NotificationCenter.default.post(name: timerStateChangedNotification, object: self)
    }

    // effectiveDuration 供预约计时使用
    private var effectiveDuration: TimeInterval {
        if let end = scheduledEndTime, let start = scheduledStartTime {
            return max(1, end.timeIntervalSince(start))
        }
        return duration
    }

    // 辅助: resume 时的 tick 计算需要的有效总时长
    private var tickDuration: TimeInterval {
        return durationForResume ?? duration
    }

    // MARK: - 展示

    /// 纯函数：把「秒数 + 格式串」渲染成显示文本。
    ///
    /// 抽成 static 是为了让**拖拽预览**（还没有 TimerEntry 实例）与**运行态菜单栏**
    /// 共用同一套格式规则 —— 否则松手瞬间读数会从 "00:05:00" 跳成 "05:00"。
    /// 规则保持 2.0 既有行为不变：
    ///   - "hm"  → HH:MM（不足 1 小时补 00）
    ///   - "ms"  → MM:SS
    ///   - 其它  → 有小时 HH:MM:SS，无小时 MM:SS
    /// 2026-08-23 用户确认：时间格式不是是否显示秒，秒固定显示。
    /// 倒计时统一格式：超过 1h 显示 HH:MM:SS，不足 1h 显示 MM:SS。
    /// 地区习惯走 linger_timeFormat locale（影响结束时刻和日期格式）。
    static func displayString(seconds: TimeInterval, format: String = "hms") -> String {
        let total = max(0, Int(ceil(seconds)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 当前地区格式（UserDefaults `linger_timeFormat`，缺省 sv_SE=ISO；影响结束时刻/日期格式）。
    static var currentTimeFormat: String {
        return UserDefaults.standard.string(forKey: "linger_timeFormat") ?? "sv_SE"
    }

    var displayTime: String {
        return TimerEntry.displayString(seconds: remainingTime, format: TimerEntry.currentTimeFormat)
    }

    /// 注入格式串的显示文本（自 Linger2.1 移植的 API 形态，便于测试 / 拖拽预览复用）。
    func displayTime(format: String) -> String {
        return TimerEntry.displayString(seconds: remainingTime, format: format)
    }

    // MARK: - 拖拽映射纯函数（自 Linger2.1 移植）

    /// 拖拽距离 → 计时秒数（非线性 s = d² 曲线）。
    ///
    /// 规则（对齐 Linger2.1 / 原型 JS）：
    /// - 最小拖拽距离 40px（不足按 40 计）
    /// - `units = px / 40`
    /// - `minutes = max(1, round(units * units))`
    /// - `seconds = minutes * 60`，最终受 `maxSeconds` 钳制
    ///
    /// 示例：40px→60s、80px→240s、120px→540s、<40px→60s。
    static func duration(fromDragDistance dragDistance: Double,
                         maxSeconds: TimeInterval = 30 * 60) -> TimeInterval {
        let effectiveDistance = max(dragDistance, 40.0)
        let units = effectiveDistance / 40.0
        let minutes = max(1, Int((units * units).rounded()))
        let seconds = Double(minutes) * 60.0
        return min(TimeInterval(seconds), maxSeconds)
    }

    /// 整分钟吸附：秒数距某个整分钟不足 5 秒时吸附到该整分钟，否则原样返回。
    static func snapToMinuteIfClose(_ seconds: TimeInterval) -> TimeInterval {
        let threshold: TimeInterval = 5.0
        let rounded = (seconds / 60.0).rounded() * 60.0
        if abs(rounded - seconds) < threshold {
            return rounded
        }
        return seconds
    }

    // MARK: - DTO

    func toDTO() -> TimerEntryDTO {
        return TimerEntryDTO(
            id: id,
            duration: tickDuration,
            remainingTime: remainingTime,
            isRunning: isRunning,
            isPaused: isPaused,
            startTime: startTime,
            originalStartTime: originalStartTime,
            originalEndTime: originalEndTime,
            hasRecorded: hasRecorded,
            isScheduled: isScheduled,
            scheduledStartTime: scheduledStartTime,
            scheduledEndTime: scheduledEndTime,
            scheduledTitle: scheduledTitle,
            predefinedTitle: predefinedTitle,
            calendarEventId: calendarEventId
        )
    }

    static func fromDTO(_ dto: TimerEntryDTO, onTick: ((TimerEntry) -> Void)? = nil, onFinish: ((TimerEntry) -> Void)? = nil) -> TimerEntry {
        return TimerEntry(restoredFrom: dto, onTick: onTick, onFinish: onFinish)
    }
}

// MARK: - 用于恢复时判断剩余 & tick 计算逻辑

private var _durationKey: UInt8 = 0

extension TimerEntry {
    // tick 时基于 startTime 计算已流逝时间 -> remaining = duration - elapsed
    // 但 resume 场景下 duration 应为 remainingTime。通过 tickDuration 统一处理。
    func _recomputeTickDuration() {
        // 空实现，保留扩展点
    }
}
