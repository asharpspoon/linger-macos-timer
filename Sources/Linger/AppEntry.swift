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

        // 必须建立应用主菜单（含 Edit 菜单的标准编辑命令）。
        // macOS 的 Cmd+X/C/V/Z/Y/A 派发依赖 mainMenu 中的 Edit 菜单项 → responder chain。
        // .accessory app 不显示菜单栏，但菜单项必须存在，否则 NSTextField 即使是
        // firstResponder 也收不到 paste: 等 action（Cmd+V 失效）。
        // 这是菜单栏 app 的经典坑，影响 hover 列表标题编辑、预约编辑区日程名称等所有输入框。
        setUpMainMenu()

        // 提前初始化 TimerManager（避免首次 addTimer 时 .shared init 阻塞主线程）
        _ = TimerManager.shared

        // T6: 初始化完成反馈（提示音）+ 完成弹窗（强提醒，自绘玻璃横幅）+ 日历记录协调器
        _ = NotificationManager.shared
        _ = CompletionBannerManager.shared
        _ = CalendarRecorder.shared
        // 启动即初始化 CalendarManager：让授权状态（init 日志 + probe + 历史写入证据迁移）
        // 在第一次右键前就绪，右键菜单直接读到正确状态
        _ = CalendarManager.shared

        menuBarManager = MenuBarManager()
        NSLog("[Linger] MenuBarManager created")

        // 2026-08-24 B 组：启动静默检查更新（内部 24h 节流 + 忽略版本 + 失败静默）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UpdateChecker.shared.checkSilentlyOnLaunch()
        }

        // 2026-08-06：日历归档导出 — 每天首次运行时增量导出日历事件到 Markdown
        // 异步执行，不阻塞启动；需用户在设置里开启开关
        DispatchQueue.global(qos: .utility).async {
            let exportOn = UserDefaults.standard.bool(
                forKey: LingerTheme.UserDefaultsKey.exportMarkdown.rawValue)
            guard exportOn else { return }
            guard !RecordExporter.hasExportedToday() else { return }
            // 等日历授权探测完成（CalendarManager.init 已启动异步 probe，给它 2s）
            Thread.sleep(forTimeInterval: 2)
            DispatchQueue.main.async {
                _ = RecordExporter.exportIncremental()
            }
        }
    }

    /// 建立最小主菜单（含 Edit 菜单标准编辑命令），让 .accessory app 的 NSTextField
    /// 能响应 Cmd+X/C/V/Z/Y/A。菜单栏不显示但菜单项必须存在以驱动系统快捷键派发。
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        // Edit 菜单（关键）：cut/copy/paste/selectAll/undo/redo
        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
        NSLog("[Linger] mainMenu set up with Edit menu (Cmd+X/C/V/Z/Y/A enabled)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
