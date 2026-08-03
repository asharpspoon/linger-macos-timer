import Cocoa

// 立即在 main 阶段打印 — 证明二进制真的跑到了这里
let logFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Linger_debug.log")
try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
func dbg(_ s: String) {
    let line = "[Linger \(Date())] \(s)\n"
    if let h = try? FileHandle(forWritingTo: logFile) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8) ?? Data())
        try? h.close()
    }
    NSLog("%@", line)
}
dbg("main.swift entered")

// 标准 AppKit 启动
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
dbg("delegate assigned")
// 启动策略：applicationDidFinishLaunching 中立即设为 .accessory（菜单栏应用，无 Dock 图标）
// 日历授权改为用户通过右键菜单「日历授权」手动发起
dbg("app.run() starting")
app.run()
dbg("app.run() returned (should never reach here)")
