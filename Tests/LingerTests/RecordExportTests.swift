import XCTest
@testable import Linger

/// Markdown 导出 + 清理谓词测试（2026-08-06）
final class RecordExportTests: XCTestCase {

    private func makeRecordedEntry(title: String, start: Date, duration: TimeInterval) -> TimerEntry {
        let dto = TimerEntryDTO(
            id: UUID(), duration: duration, remainingTime: 0,
            isRunning: false, isPaused: false,
            startTime: start, originalStartTime: start,
            originalEndTime: start.addingTimeInterval(duration),
            hasRecorded: true, isScheduled: false,
            scheduledStartTime: nil, scheduledEndTime: nil,
            scheduledTitle: nil, predefinedTitle: title,
            calendarEventId: "event-\(UUID().uuidString)"
        )
        return TimerEntry(restoredFrom: dto, onTick: nil, onFinish: nil)
    }

    func testExportWritesMarkdownAndDedupesByDay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linger-export-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 10, minute: 0))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 9, minute: 30))!

        // 第一次：两天各一条
        RecordExporter.export([
            makeRecordedEntry(title: "写代码", start: day, duration: 25 * 60),
            makeRecordedEntry(title: "开会", start: day2, duration: 60 * 60)
        ], to: url)

        let first = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(first.contains("## 2026-08-01"))
        XCTAssertTrue(first.contains("写代码（25 分钟）"))
        XCTAssertTrue(first.contains("## 2026-08-02"))
        XCTAssertTrue(first.contains("开会（60 分钟）"))

        // 第二次：同一天再导出不应重复；新日期应追加
        let day3 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 8, minute: 0))!
        RecordExporter.export([
            makeRecordedEntry(title: "写代码", start: day, duration: 25 * 60),
            makeRecordedEntry(title: "阅读", start: day3, duration: 45 * 60)
        ], to: url)

        let second = try String(contentsOf: url, encoding: .utf8)
        let day1Count = second.components(separatedBy: "## 2026-08-01").count - 1
        XCTAssertEqual(day1Count, 1, "同一天不应重复导出")
        XCTAssertTrue(second.contains("## 2026-08-03"))
        XCTAssertTrue(second.contains("阅读（45 分钟）"))
    }

    func testEntriesToPruneIncludesUnrecordedFinished() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let finishedRecorded = makeRecordedEntry(title: "已记录", start: now.addingTimeInterval(-3600), duration: 600)
        let finishedUnrecorded = TimerEntryDTO(
            id: UUID(), duration: 600, remainingTime: 0,
            isRunning: false, isPaused: false,
            startTime: now.addingTimeInterval(-3600), originalStartTime: nil,
            originalEndTime: nil, hasRecorded: false, isScheduled: false,
            scheduledStartTime: nil, scheduledEndTime: nil,
            scheduledTitle: nil, predefinedTitle: nil, calendarEventId: nil
        )
        let running = TimerEntry(duration: 600)   // 运行中，不应清理
        let pruned = TimerManager.entriesToPrune([finishedRecorded, TimerEntry(restoredFrom: finishedUnrecorded), running],
                                                 interval: "weekly")
        XCTAssertEqual(pruned.count, 2, "已记录 + 未记录的已完成条目都应清理，运行中不清")
        XCTAssertFalse(pruned.contains { $0.id == running.id })
        XCTAssertEqual(TimerManager.entriesToPrune([finishedRecorded], interval: "never").count, 0)
    }
}
