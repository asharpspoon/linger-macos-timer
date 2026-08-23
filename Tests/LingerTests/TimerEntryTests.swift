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

    // MARK: - 拖拽距离 → 时长（s=d² 曲线）

    func testDurationFromDragDistance() {
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 40), 60)
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 80), 240)
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 120), 540)
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 10), 60)   // 最小 40px
        XCTAssertEqual(TimerEntry.duration(fromDragDistance: 2000, maxSeconds: 1800), 1800) // 钳制
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
