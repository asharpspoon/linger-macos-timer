//  RecordExporter.swift
//  Markdown 记录导出（2026-08-06 用户需求）
//
//  把「已记录到日历的计时」整理成 Markdown 存档（~/Documents/Linger 计时记录.md）：
//  按日期分节，每条 = 开始–结束 · 标题（时长）。同一天只导出一次（追加去重）。
//  用户开启「导出记录（Markdown）」开关后，每周清理时自动导出；也可设置里「立即导出」。
//  Foundation-only（可单测），不依赖 AppKit（Finder 展示由设置页调用 fileURL() 处理）。

import Foundation
import os.log

enum RecordExporter {

    private static let log = OSLog(subsystem: "com.linger.timer", category: "RecordExporter")
    static let fileName = "Linger 计时记录.md"

    /// 生成 Markdown 并追加到文件（按天去重）。destination 缺省为 ~/Documents/Linger 计时记录.md
    static func export(_ entries: [TimerEntry], to destination: URL? = nil) {
        let recorded = entries.filter { $0.hasRecorded }
        guard !recorded.isEmpty else {
            os_log("Export: no recorded entries", log: log, type: .debug)
            return
        }

        // 按日期分组
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var byDay: [String: [String]] = [:]
        for e in recorded {
            guard let start = e.originalStartTime ?? e.startTime ?? e.scheduledStartTime else { continue }
            let day = dayFormatter.string(from: start)
            let end = start.addingTimeInterval(e.duration)
            let title = e.predefinedTitle ?? e.scheduledTitle ?? "专注"
            let minutes = Int((e.duration / 60).rounded())
            let line = "- \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end)) · \(title)（\(minutes) 分钟）"
            byDay[day, default: []].append(line)
        }
        guard !byDay.isEmpty else { return }

        guard let url = destination ?? fileURL() else { return }

        // 读已有内容（去重：已存在的日期不再追加）
        var existing = ""
        if let old = try? String(contentsOf: url, encoding: .utf8) {
            existing = old
        }
        var blocks: [String] = []
        for day in byDay.keys.sorted() {
            guard !existing.contains("## \(day)") else { continue }   // 该日已导出过
            let body = byDay[day]!.joined(separator: "\n")
            blocks.append("## \(day)\n\n\(body)")
        }
        guard !blocks.isEmpty else {
            os_log("Export: all days already exported, skip", log: log, type: .debug)
            return
        }

        let addition = blocks.joined(separator: "\n\n") + "\n"
        let combined = existing.isEmpty ? "# Linger 计时记录\n\n" + addition : existing + "\n" + addition
        do {
            try combined.write(to: url, atomically: true, encoding: .utf8)
            os_log("Export appended %d day(s) → %@", log: log, type: .info, blocks.count, url.path)
        } catch {
            os_log("Export write failed: %@", log: log, type: .error, error.localizedDescription)
        }
    }

    /// 导出的文件 URL（~/Documents/Linger 计时记录.md）
    static func fileURL() -> URL? {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true) else { return nil }
        return docs.appendingPathComponent(fileName)
    }

}
