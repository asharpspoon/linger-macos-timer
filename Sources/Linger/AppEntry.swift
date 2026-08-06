import Cocoa

// ⚠️ 不要 @main — main 入口在 main.swift 里
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarManager: MenuBarManager!

    /// Linger 1.0 已验证：Debug 检测决定激活策略
    /// Xcode 调试时 .regular → 能弹出系统 TCC 权限对话框
    /// Release 时 .accessory → 菜单栏应用，无 Dock 图标
    static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Linger] applicationDidFinishLaunching entered")

        if Self.isDebuggerAttached {
            NSLog("[Linger] DEBUGGER DETECTED — using .regular to allow TCC dialogs")
            NSApp.setActivationPolicy(.regular)
        } else {
            NSLog("[Linger] Release mode — using .accessory (menu bar app)")
            NSApp.setActivationPolicy(.accessory)
        }

        // 提前初始化 TimerManager（避免首次 addTimer 时 .shared init 阻塞主线程）
        _ = TimerManager.shared

        // T6: 初始化完成反馈（提示音）+ 完成弹窗（强提醒，自绘玻璃横幅）+ 日历记录协调器
        _ = NotificationManager.shared
        _ = CompletionBannerManager.shared
        _ = CalendarRecorder.shared

        menuBarManager = MenuBarManager()
        NSLog("[Linger] MenuBarManager created")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
