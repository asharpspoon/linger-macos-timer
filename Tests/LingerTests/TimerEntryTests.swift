import XCTest
@testable import Linger

final class TimerEntryTests: XCTestCase {

    // MARK: - displayString（时间格式）

    func testDisplayStringHMS() {
        XCTAssertEqual(TimerEntry.displayString(seconds: 3725, format: "hms"), "01:02:05")
        XCTAssertEqual(TimerEntry.displayString(seconds: 60, format: "hms"), "01:00")
        XCTAssertEqual(TimerEntry.displayString(seconds: 59, format: "hms"), "00:59")
        XCTAssertEqual(TimerEntry.displayString(seconds: 0, format: "hms"), "00:00")
    }

    /// 2026-08-23：displayString 不再支持 hm/ms 格式参数（统一标准格式 HH:MM:SS / MM:SS）
    func testDisplayStringHM() {
        XCTAssertEqual(TimerEntry.displayString(seconds: 3725, format: "hms"), "01:02:05")
        XCTAssertEqual(TimerEntry.displayString(seconds: 60, format: "hms"), "01:00")
        XCTAssertEqual(TimerEntry.displayString(seconds: 59, format: "hms"), "00:59")
        XCTAssertEqual(TimerEntry.displayString(seconds: 0, format: "hms"), "00:00")
    }

    /// 2026-08-23：displayString 不再支持 ms 格式（统一格式，>1h 显示 HH:MM:SS）
    func testDisplayStringMS() {
        XCTAssertEqual(TimerEntry.displayString(seconds: 65, format: "hms"), "01:05")
        XCTAssertEqual(TimerEntry.displayString(seconds: 3600, format: "hms"), "01:00:00")
    }

    // MARK: - 拖拽距离 → 时长（s=d² 归一化曲线，2026-08-23 与线长挂钩）

    /// 新语义：p = px/lineMaxLength，minutes = round(p² × maxMinutes)，拉满线 = 最大时长
    func testDurationFromDragDistance() {
        // lineMaxLength=400、maxSeconds=1800（30 分钟）
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 400, lineMaxLength: 400, maxSeconds: 1800), 1800) // 拉满线=最大
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 200, lineMaxLength: 400, maxSeconds: 1800), 480)  // 半程 p²=0.25 → 7.5min → 8min
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 100, lineMaxLength: 400, maxSeconds: 1800), 120)  // p=0.25 → 1.875min → 2min
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 10, lineMaxLength: 400, maxSeconds: 1800), 60)    // 最小 1 分钟兜底
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 2000, lineMaxLength: 400, maxSeconds: 1800), 1800) // 超线钳制
        // 线更长 → 同一物理距离时间更短（时间跟随线长变化）
        let short = TimerEntry.duration(fromDragDistance: 200, lineMaxLength: 400, maxSeconds: 1800)
        let long = TimerEntry.duration(fromDragDistance: 200, lineMaxLength: 800, maxSeconds: 1800)
        XCTAssertLessThan(long, short)
        // 拉满不同长度的线都等于最大时长
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 800, lineMaxLength: 800, maxSeconds: 1800), 1800)
    }

    /// 线长下限 40：极短线也不至于时间映射分母过小
    func testDurationLineMaxLengthFloor() {
        // limit = max(40, 10) = 40
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 40, lineMaxLength: 10, maxSeconds: 1800), 1800) // p=1 → 30min
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 20, lineMaxLength: 10, maxSeconds: 1800), 480)  // p=0.5 → 7.5min → round=8
    }

    /// 计时粒度（2026-08-23）：读数按 granularity 步进吸附，最小仍 1 分钟
    func testDurationGranularity() {
        // p=0.25 → raw 112.5s：g=10 吸附到 110（1:50）；g=60（默认）吸附到 120（2:00）
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 100, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 10), 110)
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 100, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 60), 120)
        // p=0.5 → raw 450s：g=30 整粒不变；g=20 吸附到 460（round(22.5)=23）
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 200, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 30), 450)
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 200, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 20), 460)
        // 最小 1 分钟兜底（与粒度无关）
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 10, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 10), 60)
        // 拉满线钳制到最大时长（仍是粒度倍数：1800 = 10 的倍数）
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 400, lineMaxLength: 400,
                                           maxSeconds: 1800, granularity: 10), 1800)
    }

    // MARK: - 整分钟吸附

    func testSnapToMinuteIfClose() {
        XCTAssertEqual(TimerEntry.snapToMinuteIfClose(118), 120)
        XCTAssertEqual(TimerEntry.snapToMinuteIfClose(123), 120)
        XCTAssertEqual(TimerEntry.snapToMinuteIfClose(124), 120)
        XCTAssertEqual(TimerEntry.snapToMinuteIfClose(126), 126) // 差 6s，不吸附
        XCTAssertEqual(TimerEntry.snapToMinuteIfClose(1800), 1800)
    }
}
