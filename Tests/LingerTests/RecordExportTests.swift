import XCTest
@testable import Linger

/// 日历 Markdown 归档导出 + 清理谓词测试（2026-08-06 重新设计）
final class RecordExportTests: XCTestCase {

    private func makeItem(title: String, calendar: String, start: Date, duration: TimeInterval, isLinger: Bool = false) -> RecordExporter.ExportItem {
        return RecordExporter.ExportItem(
            title: title,
            calendarTitle: calendar,
            start: start,
            end: start.addingTimeInterval(duration),
            isLinger: isLinger
        )
    }

    /// 测试：按月分文档 + 按天去重 + Linger 标记
    func testWriteItemsToMonthlyFilesAndDedupesByDay() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("linger-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 10, minute: 0))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 9, minute: 30))!

        // 第一次：8 月两天各一条
        let written1 = RecordExporter.writeItemsToMonthlyFiles(items: [
            makeItem(title: "写代码", calendar: "工作", start: day1, duration: 25 * 60, isLinger: true),
            makeItem(title: "开会", calendar: "工作", start: day2, duration: 60 * 60)
        ], directory: dir)
        XCTAssertEqual(written1, 2)

        let file = dir.appendingPathComponent("Linger-日历归档-2026-08.md")
        let first = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(first.contains("# 日程归档 2026-08"))
        XCTAssertTrue(first.contains("## 2026-08-01"))
        XCTAssertTrue(first.contains("10:00-10:25 | 写代码 | 工作 | Linger"))
        XCTAssertTrue(first.contains("## 2026-08-02"))
        XCTAssertTrue(first.contains("09:30-10:30 | 开会 | 工作"))
        XCTAssertFalse(first.contains("开会 | 工作 | Linger"), "非 Linger 事件不应有 Linger 标记")

        // 第二次：同一天再导出不应重复；新日期应追加
        let day3 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 8, minute: 0))!
        let written2 = RecordExporter.writeItemsToMonthlyFiles(items: [
            makeItem(title: "写代码", calendar: "工作", start: day1, duration: 25 * 60, isLinger: true),
            makeItem(title: "阅读", calendar: "个人", start: day3, duration: 45 * 60)
        ], directory: dir)
        XCTAssertEqual(written2, 1, "同一天去重，只应写入 1 条新日期")

        let second = try String(contentsOf: file, encoding: .utf8)
        let day1Count = second.components(separatedBy: "## 2026-08-01").count - 1
        XCTAssertEqual(day1Count, 1, "同一天不应重复导出")
        XCTAssertTrue(second.contains("## 2026-08-03"))
        XCTAssertTrue(second.contains("08:00-08:45 | 阅读 | 个人"))
    }

    /// 测试：跨月分文档
    func testCrossMonthSeparateFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("linger-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let aug31 = cal.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 22, minute: 0))!
        let sep1 = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 8, minute: 0))!

        let written = RecordExporter.writeItemsToMonthlyFiles(items: [
            makeItem(title: "晚间专注", calendar: "Linger", start: aug31, duration: 90 * 60, isLinger: true),
            makeItem(title: "晨会", calendar: "工作", start: sep1, duration: 30 * 60)
        ], directory: dir)
        XCTAssertEqual(written, 2)

        let augFile = dir.appendingPathComponent("Linger-日历归档-2026-08.md")
        let sepFile = dir.appendingPathComponent("Linger-日历归档-2026-09.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: augFile.path), "8 月应有独立文档")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sepFile.path), "9 月应有独立文档")

        let augContent = try String(contentsOf: augFile, encoding: .utf8)
        XCTAssertTrue(augContent.contains("## 2026-08-31"))
        XCTAssertFalse(augContent.contains("晨会"))

        let sepContent = try String(contentsOf: sepFile, encoding: .utf8)
        XCTAssertTrue(sepContent.contains("## 2026-09-01"))
        XCTAssertFalse(sepContent.contains("晚间专注"))
    }

    /// 测试：hasExportedToday 首次为 false
    func testHasExportedTodayInitiallyFalse() {
        // 清掉可能的历史状态（其他测试可能写过）
        UserDefaults.standard.removeObject(forKey: LingerTheme.UserDefaultsKey.lastExportDate.rawValue)
        XCTAssertFalse(RecordExporter.hasExportedToday())
    }

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
