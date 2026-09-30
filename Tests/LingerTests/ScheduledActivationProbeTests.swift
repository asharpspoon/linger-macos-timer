import XCTest
@testable import Linger

/// 2026-08-24 bug 探针：预约日程提交后无法在预约时间开始计时。
/// 验证引擎层：到点激活 → isRunning 翻转 → 剩余时间正确递减。
/// 运行时证据（Rule 8）：不靠读代码猜，直接跑真实 RunLoop。
final class ScheduledActivationProbeTests: XCTestCase {

    /// 预约 0.3s 后开始、时长 2s → 0.8s 时应已激活且在计时
    func testScheduledEntryActivatesAtFireDate() {
        let start = Date().addingTimeInterval(0.3)
        let end = start.addingTimeInterval(2.0)
        let entry = TimerEntry(scheduledStartTime: start, scheduledEndTime: end, title: "probe")

        XCTAssertFalse(entry.isRunning, "预约等待期不应处于运行态")

        let exp = expectation(description: "activated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(entry.isRunning, "到点后应自动激活为运行态（scheduledTimer 未触发？）")
        XCTAssertNotNil(entry.startTime, "激活后 startTime 应被记录")
        // 激活时刻 ≈ 预约开始时刻，剩余时间应接近时长（2s）而非 0
        XCTAssertEqual(entry.remainingTime, 2.0, accuracy: 1.5,
                       "激活后剩余时间应≈预约时长")
        entry.stop()
    }

    /// 激活后应正常走完倒计时并回调 onFinish
    func testScheduledEntryRunsToFinish() {
        let start = Date().addingTimeInterval(0.2)
        let end = start.addingTimeInterval(1.0)
        var finished = false
        let entry = TimerEntry(scheduledStartTime: start, scheduledEndTime: end, title: "probe") {
            _ in finished = true
        }
        let exp = expectation(description: "finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 4)
        XCTAssertTrue(finished, "预约计时到点激活后应能正常完成")
        entry.stop()
    }

    /// 恢复路径：等待中的预约落盘恢复后仍应在到点激活
    func testRestoredPendingScheduleStillActivates() {
        let dto = TimerEntryDTO(
            id: UUID(),
            duration: 1.0,
            remainingTime: 1.0,
            isRunning: false,
            isPaused: false,
            startTime: nil,
            originalStartTime: nil,
            originalEndTime: nil,
            hasRecorded: false,
            isScheduled: true,
            scheduledStartTime: Date().addingTimeInterval(0.3),
            scheduledEndTime: Date().addingTimeInterval(1.3),
            scheduledTitle: "probe",
            predefinedTitle: nil,
            calendarEventId: nil
        )
        let entry = TimerEntry(restoredFrom: dto)
        XCTAssertFalse(entry.isRunning)
        let exp = expectation(description: "activated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
        XCTAssertTrue(entry.isRunning, "恢复的等待期预约到点应激活")
        entry.stop()
    }

    // MARK: - 2026-08-24 僵尸预约修复（真实数据：timers.json「发 ppt」挂起一整天）

    private func makeDTO(start: Date, end: Date) -> TimerEntryDTO {
        TimerEntryDTO(
            id: UUID(),
            duration: end.timeIntervalSince(start),
            remainingTime: end.timeIntervalSince(start),
            isRunning: false, isPaused: false,
            startTime: nil, originalStartTime: nil, originalEndTime: nil,
            hasRecorded: false, isScheduled: true,
            scheduledStartTime: start, scheduledEndTime: end,
            scheduledTitle: "probe", predefinedTitle: nil, calendarEventId: nil
        )
    }

    /// App 在预约开始后、结束前启动 → 立即补激活按剩余跨度倒计时（不再永远挂起）
    func testRestoredMidSpanScheduleActivatesImmediately() {
        let start = Date().addingTimeInterval(-30)   // 30s 前开始
        let end = Date().addingTimeInterval(2.0)     // 2s 后结束
        let entry = TimerEntry(restoredFrom: makeDTO(start: start, end: end))
        XCTAssertTrue(entry.isRunning, "跨中段恢复的预约应立即激活（修复前永远挂起）")
        XCTAssertEqual(entry.remainingTime, 2.0, accuracy: 1.0,
                       "剩余时间应为剩余跨度而非完整时长")
        entry.stop()
    }

    /// App 在预约结束后才启动 → 视为已结束（remainingTime=0，不再显示「等待中」）
    func testRestoredExpiredScheduleIsFinishedNotZombie() {
        let start = Date().addingTimeInterval(-3600)
        let end = Date().addingTimeInterval(-3500)
        let entry = TimerEntry(restoredFrom: makeDTO(start: start, end: end))
        XCTAssertFalse(entry.isRunning, "过期预约不应运行")
        XCTAssertFalse(entry.isPaused)
        XCTAssertEqual(entry.remainingTime, 0, "过期预约剩余时间应为 0（不显示、可被清理）")
    }

    // MARK: - 2026-09-30「关掉软件后预约/计时乱掉」修复

    /// 跨中段恢复必须保留「原始计划时长 + 真实时间轴」。
    /// 旧逻辑把 duration 改成剩余跨度、startTime 重置为 now →
    ///   ① 进度条重新从 0 跑；
    ///   ② toDTO() 把变短的 duration 写回磁盘，每重启一次时长就短一截。
    func testRestoredMidSpanScheduleKeepsFullDurationAndTimeline() {
        let start = Date().addingTimeInterval(-30)   // 已开始 30s
        let end = Date().addingTimeInterval(90)      // 还有 90s 结束（总跨度 120s）
        let entry = TimerEntry(restoredFrom: makeDTO(start: start, end: end))

        XCTAssertTrue(entry.isRunning, "跨中段恢复应立即激活")
        XCTAssertEqual(entry.duration, 120, accuracy: 0.5,
                       "必须保留完整计划时长，不能被改写成剩余跨度")
        XCTAssertEqual(entry.startTime?.timeIntervalSince1970 ?? 0,
                       start.timeIntervalSince1970, accuracy: 0.5,
                       "startTime 必须锚在真实预约开始时刻，否则进度条会被清零")
        XCTAssertEqual(entry.remainingTime, 90, accuracy: 1.5,
                       "剩余时间 = 结束时刻 - 现在，与重启次数无关")

        // 进度 = 1 - remaining/duration → 已过 30/120 = 25%，不能回到 0%
        let progress = 1 - entry.remainingTime / entry.duration
        XCTAssertEqual(progress, 0.25, accuracy: 0.02, "恢复后进度不得归零")

        // 落盘往返后时长必须仍是完整值（否则每次重启都被改短）
        let dto = entry.toDTO()
        XCTAssertEqual(dto.duration, 120, accuracy: 0.5, "toDTO 必须写回完整计划时长")
        XCTAssertEqual(dto.scheduledEndTime?.timeIntervalSince1970 ?? 0,
                       end.timeIntervalSince1970, accuracy: 0.5,
                       "预约结束时刻不能被改写")

        entry.stop()
    }

    /// 预约「到点激活」也必须锚定预约时间轴：Mac 睡眠 / RunLoop 阻塞会让 Timer 晚触发，
    /// 旧逻辑从触发时刻重新跑满整段时长 → 结束时间被整体推后，且与重启恢复口径不一致。
    func testLateScheduledActivationAnchorsToScheduledTimeline() {
        let start = Date().addingTimeInterval(-30)   // 已到点 → 定时器会立即触发
        let end = Date().addingTimeInterval(60)
        let entry = TimerEntry(scheduledStartTime: start, scheduledEndTime: end, title: "probe")

        let exp = expectation(description: "activated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(entry.isRunning, "已到点的预约应立即激活")
        XCTAssertEqual(entry.duration, 90, accuracy: 0.5,
                       "时长应为完整预约跨度，而不是从触发时刻重算")
        XCTAssertEqual(entry.startTime?.timeIntervalSince1970 ?? 0,
                       start.timeIntervalSince1970, accuracy: 0.5,
                       "startTime 必须锚在预约开始时刻，结束时间才不会被推后")
        XCTAssertEqual(entry.remainingTime, 60, accuracy: 1.5,
                       "剩余时间 = 结束时刻 - 现在（≈60s），不是完整 90s")
        XCTAssertEqual(entry.originalEndTime?.timeIntervalSince1970 ?? 0,
                       end.timeIntervalSince1970, accuracy: 0.5,
                       "结束时刻必须等于预约结束时刻")
        entry.stop()
    }

    /// 过期预约应能被定期清理回收（修复前 !isScheduled 永久挡清理，攒满 10 个堵死新建）
    func testExpiredScheduleIsPrunable() {
        let start = Date().addingTimeInterval(-3600)
        let end = Date().addingTimeInterval(-3500)
        let entry = TimerEntry(restoredFrom: makeDTO(start: start, end: end))
        let pruned = TimerManager.entriesToPrune([entry], interval: "weekly")
        XCTAssertEqual(pruned.count, 1, "过期预约应可被清理回收槽位")
    }
}
