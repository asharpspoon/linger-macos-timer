//  NotificationManager.swift
//  完成提示音管理器（2026-08-06 重构：通知横幅已由 CompletionBanner 自绘承担）
//
//  历史职责拆分：
//   - 完成弹窗（强提醒）→ CompletionBannerManager（自绘玻璃横幅，尊重 linger_notifyOnComplete 开关）
//   - 日历记录 → CalendarRecorder（auto/ask/manual，与弹窗解耦）
//   - 本类只负责完成提示音（linger_playSound / linger_soundName，关时静默；
//     系统通知权限不再需要 —— 自绘横幅 + NSSound 均不依赖通知权限）

import AppKit
import os.log

final class NotificationManager {

    static let shared = NotificationManager()

    private let log = OSLog(subsystem: "com.linger.notification", category: "NotificationManager")

    private init() {
        startObservingFinish()
    }

    // MARK: - 订阅计时归零

    private func startObservingFinish() {
        NotificationCenter.default.addObserver(
            forName: timerDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleTimerDidFinish(note)
        }
    }

    private func handleTimerDidFinish(_ note: Notification) {
        playFinishSoundIfEnabled()
    }

    // MARK: - 完成提示音（NSSound，无需通知权限）

    private func playFinishSoundIfEnabled() {
        let play = UserDefaults.standard.object(forKey: LingerTheme.UserDefaultsKey.playSound.rawValue) as? Bool ?? true
        guard play else { return }
        let name = UserDefaults.standard.string(forKey: LingerTheme.UserDefaultsKey.soundName.rawValue) ?? "Glass"
        if let sound = NSSound(named: name) {
            sound.play()
        } else if let fallback = NSSound(named: "Glass") {
            fallback.play()
        }
    }
}
