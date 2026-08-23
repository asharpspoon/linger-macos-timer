//  RecordExporter.swift
//  日历 Markdown 归档导出（2026-08-06 重新设计）
//
//  数据源：日历事件（EKEvent），通过 CalendarManager.fetchEvents 拉取
//  触发：每天首次运行 app 时，导出从「上次导出时间」到「现在」的所有日历事件
//  分文档：按自然月分（2026-08.md、2026-09.md），存在用户选择的目录下
//  内容：日程标题、日历分类、开始-结束时间、是否由 Linger 标记
//  目的：用户把 md 喂给 AI 做周报/日报/复盘
//
//  Foundation-only（可单测），不依赖 AppKit（目录选择由设置页处理）。

import Foundation
import EventKit
import os.log

enum RecordExporter {

    private static let log = OSLog(subsystem: "com.linger.timer", category: "RecordExporter")

    /// 文档文件名前缀（按月分文档：Linger-日历归档-2026-08.md）
    static let filePrefix = "Linger-日历归档"

    // MARK: - 导出入口

    /// 增量导出：从「上次导出时间」到「现在」的日历事件，按自然月分文档追加。
    /// 首次运行（无 lastExportDate）时导出「现在往前 30 天」。
    /// - Parameters:
    ///   - directory: 导出目录（nil 时用 UserDefaults 存的目录）
    ///   - now: 当前时间（测试可注入）
    /// - Returns: 实际写入了多少条事件
    @discardableResult
    static func exportIncremental(directory: URL? = nil, now: Date = Date()) -> Int {
        let dir = directory ?? savedDirectory() ?? defaultDirectory()
        guard let url = ensureDirectory(dir) else {
            os_log("Export: directory not accessible %@", log: log, type: .error, dir.path)
            return 0
        }

        // 时间范围：上次导出时间 → 现在；首次回溯 30 天
        let last = lastExportDate() ?? now.addingTimeInterval(-30 * 24 * 3600)
        let events = CalendarManager.shared.fetchEvents(from: last, to: now)
        guard !events.isEmpty else {
            os_log("Export: no events since %@", log: log, type: .debug, last.description)
            markExported(now: now)
            return 0
        }

        let written = writeToMonthlyFiles(events: events, directory: url)
        markExported(now: now)
        os_log("Export: %d events written to %@", log: log, type: .info, written, url.path)
        return written
    }

    /// 全量导出：指定时间范围的所有事件（设置页「立即导出」用）
    /// - Parameters:
    ///   - from: 起始时间
    ///   - to: 结束时间
    ///   - directory: 导出目录
    /// - Returns: 写入的事件数
    @discardableResult
    static func exportRange(from: Date, to: Date, directory: URL? = nil) -> Int {
        let dir = directory ?? savedDirectory() ?? defaultDirectory()
        guard let url = ensureDirectory(dir) else { return 0 }
        let events = CalendarManager.shared.fetchEvents(from: from, to: to)
        guard !events.isEmpty else {
            os_log("Export range: no events", log: log, type: .debug)
            return 0
        }
        let written = writeToMonthlyFiles(events: events, directory: url)
        os_log("Export range: %d events written to %@", log: log, type: .info, written, url.path)
        return written
    }

    // MARK: - 按月分文档写入

    /// 导出项（轻量数据结构，供纯逻辑测试，不依赖 EKEvent）
    struct ExportItem {
        let title: String
        let calendarTitle: String
        let start: Date
        let end: Date
        let isLinger: Bool
    }

    /// 把事件按自然月分组，每组建/追加到一个月度文档
    private static func writeToMonthlyFiles(events: [EKEvent], directory: URL) -> Int {
        let items = events.map { e in
            ExportItem(title: e.title ?? "（无标题）",
                       calendarTitle: e.calendar?.title ?? "未知日历",
                       start: e.startDate,
                       end: e.endDate,
                       isLinger: CalendarManager.shared.isLingerEvent(e))
        }
        return writeItemsToMonthlyFiles(items: items, directory: directory)
    }

    /// 纯逻辑：把 ExportItem 按月分组写入文档（internal 供测试）
    static func writeItemsToMonthlyFiles(items: [ExportItem], directory: URL) -> Int {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"

        // 按月分组（按事件开始时间所在月）
        var byMonth: [String: [ExportItem]] = [:]
        for item in items {
            let key = monthFormatter.string(from: item.start)
            byMonth[key, default: []].append(item)
        }

        var total = 0
        for (month, monthItems) in byMonth.sorted(by: { $0.key < $1.key }) {
            let fileURL = directory.appendingPathComponent("\(filePrefix)-\(month).md")
            let added = appendMonth(month: month, items: monthItems, to: fileURL)
            total += added
        }
        return total
    }

    /// 把一个月的事件追加到文档（按天去重：已存在的日期跳过）
    private static func appendMonth(month: String, items: [ExportItem], to url: URL) -> Int {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        // 按天分组
        var byDay: [String: [ExportItem]] = [:]
        for item in items {
            let day = dayFormatter.string(from: item.start)
            byDay[day, default: []].append(item)
        }

        // 读已有内容（去重：已存在的日期不再追加）
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var blocks: [String] = []
        var added = 0
        for day in byDay.keys.sorted() {
            guard !existing.contains("## \(day)") else { continue }   // 该日已导出过
            let dayItems = byDay[day]!
            let body = dayItems.map { item in
                let start = timeFormatter.string(from: item.start)
                let end = timeFormatter.string(from: item.end)
                let lingerTag = item.isLinger ? " | Linger" : ""
                return "- \(start)-\(end) | \(item.title) | \(item.calendarTitle)\(lingerTag)"
            }.joined(separator: "\n")
            blocks.append("## \(day)\n\n\(body)")
            added += dayItems.count
        }

        guard !blocks.isEmpty else { return 0 }

        let addition = blocks.joined(separator: "\n\n") + "\n"
        let combined: String
        if existing.isEmpty {
            combined = "# 日程归档 \(month)\n\n> 由 Linger 自动导出。标注 Linger 的事件为 Linger 计时记录。\n\n" + addition
        } else {
            combined = existing + "\n" + addition
        }
        do {
            try combined.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            os_log("Export write failed: %@", log: log, type: .error, error.localizedDescription)
        }
        return added
    }

    // MARK: - 目录与状态管理

    /// 默认目录：~/Documents/Linger 日程归档/
    static func defaultDirectory() -> URL {
        let docs = (try? FileManager.default.url(for: .documentDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("Linger 日程归档")
    }

    /// 用户选择的导出目录（存 UserDefaults）
    static func savedDirectory() -> URL? {
        guard let path = UserDefaults.standard.string(
            forKey: LingerTheme.UserDefaultsKey.exportDirectory.rawValue),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func setSavedDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path,
                                  forKey: LingerTheme.UserDefaultsKey.exportDirectory.rawValue)
    }

    /// 确保目录存在且可写，返回目录 URL 或 nil
    private static func ensureDirectory(_ url: URL) -> URL? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return url
    }

    /// 上次导出时间（nil = 从未导出过）
    static func lastExportDate() -> Date? {
        return UserDefaults.standard.object(
            forKey: LingerTheme.UserDefaultsKey.lastExportDate.rawValue) as? Date
    }

    /// 记录本次导出时间
    private static func markExported(now: Date) {
        UserDefaults.standard.set(now,
                                  forKey: LingerTheme.UserDefaultsKey.lastExportDate.rawValue)
    }

    /// 判断今天是否已导出过（每天首次运行触发用）
    static func hasExportedToday(now: Date = Date()) -> Bool {
        guard let last = lastExportDate() else { return false }
        return Calendar.current.isDateInToday(last)
    }
}
