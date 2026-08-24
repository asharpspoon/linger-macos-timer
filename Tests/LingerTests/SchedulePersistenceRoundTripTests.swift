import XCTest
@testable import Linger

/// 2026-08-24 bug 探针：预约计时 JSON 落盘/恢复往返完整性。
/// 真实 App 重启走 loadFromDisk（JSONEncoder/Decoder），此前探针只测了内存 DTO。
final class SchedulePersistenceRoundTripTests: XCTestCase {

    func testPendingScheduleSurvivesJSONRoundTrip() throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(1500)
        let dto = TimerEntryDTO(
            id: UUID(), duration: 1500, remainingTime: 1500,
            isRunning: false, isPaused: false,
            startTime: nil, originalStartTime: nil, originalEndTime: nil,
            hasRecorded: false, isScheduled: true,
            scheduledStartTime: start, scheduledEndTime: end,
            scheduledTitle: "写作", predefinedTitle: "写作", calendarEventId: nil
        )

        let data = try JSONEncoder().encode([dto])
        let decoded = try JSONDecoder().decode([TimerEntryDTO].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        let d = decoded[0]
        XCTAssertTrue(d.isScheduled)
        XCTAssertEqual(d.scheduledStartTime!.timeIntervalSince1970,
                       start.timeIntervalSince1970, accuracy: 1.0,
                       "预约开始时间往返后必须保真（误差<1s），否则重启后预约丢失/错时")
        XCTAssertEqual(d.scheduledEndTime!.timeIntervalSince1970,
                       end.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(d.scheduledTitle, "写作")

        // 恢复的条目在开始时间未到时应仍能激活（复用 restore init + 短窗口）
        let start2 = Date().addingTimeInterval(0.3)
        let end2 = start2.addingTimeInterval(1.0)
        let dto2 = TimerEntryDTO(
            id: UUID(), duration: 1.0, remainingTime: 1.0,
            isRunning: false, isPaused: false,
            startTime: nil, originalStartTime: nil, originalEndTime: nil,
            hasRecorded: false, isScheduled: true,
            scheduledStartTime: start2, scheduledEndTime: end2,
            scheduledTitle: nil, predefinedTitle: nil, calendarEventId: nil
        )
        let data2 = try JSONEncoder().encode([dto2])
        let decoded2 = try JSONDecoder().decode([TimerEntryDTO].self, from: data2)
        let entry = TimerEntry(restoredFrom: decoded2[0])
        let exp = expectation(description: "activated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertTrue(entry.isRunning, "JSON 往返恢复的预约到点必须激活")
        entry.stop()
    }
}
