# Linger 2.5 工程上下文（接手必读的细节）

## 构建与运行

```bash
cd /Users/dawang/Downloads/vibecoding/Linger2.5
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./script/build_and_run.sh            # kill + build + 打 dist/Linger.app + 启动
./script/build_and_run.sh --verify   # 构建 + 启动 + 进程检查
./script/build_and_run.sh --logs     # 启动 + 流式日志
```

- 纯编译：`swift build --disable-sandbox`（沙箱环境必须加 `--disable-sandbox`）
- 纯逻辑测试（未接入，待做）：`swift test`
- 沙箱限制：本机 Codex 沙箱内无法 `open` GUI app，启动/交互验收必须在
  Codex Run 按钮或用户终端执行。

## 目录结构

```
Linger2.5/
├── Package.swift              # SwiftPM（macOS 13+，可执行 target Linger）
├── Sources/Linger/            # 16 个 Swift 源文件
├── pages/ + *.md/.design      # HTML 原型（UI 准绳）与设计文档
├── script/build_and_run.sh    # 一键构建脚本
├── Support/Linger-Info.plist  # 打包用 Info.plist 素材
├── .codex/environments/       # Codex Run 按钮配置
└── HANDOFF.md                 # 状态权威 + 交接记录
```

## 架构速览

- **入口**：`main.swift`（手写 NSApplication，无 @main）→ `AppEntry.swift`（AppDelegate；
  debug `.regular` / release `.accessory`）→ `MenuBarManager`（顶层协调者）
- **引擎（Foundation-only）**：`TimerEntry`（s=d² 时长映射、整分钟吸附、displayTime）、
  `TimerManager`（增删/暂停/10 上限/JSON 持久化）
- **设计令牌唯一来源**：`LingerTheme.swift`（琥珀金阶梯、圆角、间距、动画、UserDefaultsKey）
- **关键决策（勿回退）**：`LingerStatusItemView.swift` —— 自定义状态栏视图，直接收
  mouseDown/mouseUp/rightMouseUp + 内建 hover tracking。原因：`NSStatusBarButton` 的
  cell tracking loop 会吞掉 mouseUp → 拖拽状态机卡死 → 松手不计时（老 bug 根因）。
- **拖拽状态机**：idle → pressed（mouseDown）→ dragging（位移 >4px，30fps 轮询算距离）
  → mouseUp 松手 → `finishDrag` 创建计时；Command 取消；所有出口收敛 `cleanupDrag`。
- **拖拽预览**：`DragFeedbackView.swift` —— 按 `menubar-drag.html` 实现：
  4pt 渐变竖线 + 10pt 圆点 + **水平双轨** `for 25:00 │ til 11:49`（两轨等大 24pt）+ 提示文案。
- **浮窗/其他**：`HoverListView.swift`（300pt 毛玻璃列表，三组排序/暂停/标题编辑）、
  `ScheduleTimerView.swift`（预约）、`ToastView.swift`、`NotificationManager.swift`、
  `SettingsWindow.swift`、`AboutWindow.swift`、`CalendarManager.swift`、`ClickHintView.swift`

## 已知问题

- `statusItem.view` 有 deprecation 警告：刻意为之（绕开 button 的 cell tracking loop），功能正常。
- 拖拽修复已编译通过，**等待实机验收**（见 HANDOFF.md 最新进度）。
- 设置/关于/预约/通知界面代码存在但未按最新原型逐页核对（待做）。
