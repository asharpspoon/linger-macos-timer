# Linger 2.5 — 项目接手文档

> 本文件是任何 agent（Codex / WorkBuddy / Trae / 新会话）接手本项目的**第一入口**。
> 动手前先读本文件 + 原型 + PRD；改动后更新本文件"最新进度"。

## 这是什么

macOS 菜单栏计时器 app「Linger」：从菜单栏图标**向下拖拽**设定倒计时（拖拽长度 = 时长，
s=d² 曲线 + 整分钟吸附），松手即开始计时。AppKit 原生、暗色毛玻璃、琥珀金 #F5A623 单主色。
代号 **2.5**（2.0 / 2.1 均已失败存档，勿再回改）。

## 准绳（source of truth）

| 文件 | 作用 |
|---|---|
| `pages/`（HTML 原型，11 页） | **UI 唯一准绳**。布局/配色/字号/文案/交互全以 HTML 为准 |
| `linger2_prd.md` | 功能需求总纲 |
| `phase1-architecture-blueprint.md` | 架构蓝图（设计令牌、模块依赖、NSTrackingArea 铁律） |

**铁律**：原型与旧代码/蓝图冲突时，**以 HTML 原型为准**（例：拖拽双轨两轨等大 24pt，
蓝图里写 30/21，按原型做）。

## 目录结构

```
Linger2.5/
├── Package.swift              # SwiftPM 包（macOS 13+，可执行 target Linger）
├── Sources/Linger/            # 全部源码（16 个 Swift 文件）
├── pages/ + 各 .md/.design    # 原型与设计文档
├── script/build_and_run.sh    # 一键 kill + build + 打包 .app + 启动
├── Support/Linger-Info.plist  # 打包用 Info.plist 素材
├── .codex/environments/       # Codex Run 按钮配置
└── HANDOFF.md                 # 本文件
```

## 最新进度（2026-08-04）

- [x] SwiftPM 工程搭建，**真编译通过**（5,500+ 行 2.0 代码收编 + 修复，首次真正 build 成功）
- [x] `script/build_and_run.sh` 一键构建 + 打 `dist/Linger.app`（ad-hoc 签名）+ 启动
- [x] **拖拽死锁修复**（根因：NSStatusBarButton cell tracking loop 吞 mouseUp →
      状态机卡死、松手不计时。方案：自定义 `LingerStatusItemView` 直接在视图层收鼠标事件）
- [x] **拖拽预览按 menubar-drag.html 重写**（4pt 渐变竖线 + 10pt 圆点 + 水平双轨
      for/til 均 24pt + 悬停高亮 + 提示文案）
- [ ] **待真机验收**：菜单栏图标 → 拖拽 → 松手计时 → 悬停列表（用户实机确认中）
- [ ] 按原型逐页对齐：hover-list（悬停列表）、toast、settings×4、about、schedule-timer、notification
- [ ] 纯逻辑单测（TimerEntry/TimerManager）接入 `swift test`
- [ ] 通知/日历权限、预约计时、图标三风格（Ring/Classic/timer）

## 构建与运行

```bash
cd /Users/dawang/Downloads/vibecoding/Linger2.5
./script/build_and_run.sh          # kill + build + 打包 + 启动（默认）
./script/build_and_run.sh --verify # 构建 + 启动 + 进程检查
./script/build_and_run.sh --logs   # 启动 + 流式日志
```

- **Xcode**：打开 `Package.swift`，scheme 选 `Linger`，⌘R（本机 Xcode 26.6 已验证可用；
  `xcode-select` 若指向 CommandLineTools，需 `sudo xcode-select -s /Applications/Xcode.app`
  或在命令前加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`）
- **Run 按钮**：把本文件夹作为 Codex 工作区打开后可用（`.codex/environments/environment.toml`）

## 架构速览（新 agent 必读）

- **入口**：`main.swift`（无 @main，手写 NSApplication 启动）→ `AppEntry.swift`（AppDelegate，
  debug `.regular` / release `.accessory`）→ `MenuBarManager`（顶层协调者）
- **引擎（纯 Foundation，勿引 AppKit 视图）**：`TimerEntry`（实体 + s=d² 映射/吸附纯函数）、
  `TimerManager`（增删/暂停/10 上限/JSON 持久化）
- **设计令牌唯一来源**：`LingerTheme.swift`（琥珀金阶梯、圆角、间距、动画、UserDefaultsKey）——
  **禁止**在视图里硬编码 #F5A623 / 裸 NSColor
- **关键决策（勿轻易回退）**：`LingerStatusItemView.swift` 自定义状态栏视图，直接收
  mouseDown/mouseUp/rightMouseUp + 内建 hover tracking —— 这是吞 mouseUp 老 bug 的根治方案
- **拖拽状态机**：idle → pressed（mouseDown）→ dragging（位移 >4px，30fps 轮询算距离）
  → mouseUp 松手 → `finishDrag` 创建计时；Command 取消；所有出口收敛到 `cleanupDrag`
- **反馈视图**：`DragFeedbackView.swift`（按 menubar-drag.html 实现，水平双轨）
- **浮窗**：`HoverListView.swift`（300pt 毛玻璃列表，三组排序）、`ScheduleTimerView.swift`（预约）、
  `ToastView.swift`（居中提示）、`NotificationManager.swift`（横幅）、`SettingsWindow/AboutWindow/CalendarManager`

## 接手协议

1. 先读：本文件 → `pages/` 相关页 → `linger2_prd.md` 对应章节
2. UI 改动以 HTML 原型为准；引擎改动保持叶子模块纯净（可单测）
3. 改完必须能 `swift build`（`--disable-sandbox` + `DEVELOPER_DIR`），GUI 改动需实机验收
4. 每完成一个可验收里程碑：更新本文件"最新进度" + git commit（信息写清楚改了什么/为什么）
5. 不擅自改动 2.0 / 2.1 存档目录；有疑问标「待确认」，不臆造专有名词

## 已知问题

- `statusItem.view` 有 deprecation 警告（刻意为之：绕开 button 的 cell tracking loop），功能正常
- 沙箱内无法 `open` GUI app，启动验收需用户在 Codex Run 按钮 / 终端执行
