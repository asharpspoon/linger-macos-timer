# Linger 2.5 — 项目接手文档

> 本文件是任何 agent（Codex / WorkBuddy / Trae / 新会话）接手本项目的**第一入口**。
> 动手前先读本文件 + 原型 + PRD；改动后更新本文件"最新进度"。

## 这是什么

macOS 菜单栏计时器 app「Linger」：从菜单栏图标**向下拖拽**设定倒计时（拖拽长度 = 时长，
s=d² 曲线 + 整分钟吸附），松手即开始计时。AppKit 原生、暗色毛玻璃、琥珀金 #F5A623 单主色。
代号 **2.5**（2.0 / 2.1 均已失败存档，勿再回改）。

## 最近交接

> 每次交接/里程碑后在此**顶部**追加一段（最新在上），格式见 `.agents/skills/linger-handoff/`。
> 上次交接见 git 历史；当前状态以「最新进度」为准。

- **2026-08-23 · 设置窗口 3 轮修复 + PRD 全量同步（Codex）**
  - **本次完成（swift build 通过，swift test 21/21 绿）**：
    1. **拖拽线最大长度 → 0-100%**：滑块从 25-75% 改为 0-100%，映射到屏幕可见高度百分比；修复设置后不生效（默认值判定改用 hasSetValue 显式判断）
    2. **双轨显示**：删掉「仅结束时间」选项（只留 倒计时+结束时间 / 仅倒计时）；仅倒计时模式下文字恒亮色（不再高亮切换变灰）
    3. **时间格式 → locale 驱动**：原来 hms/hm/ms（是否显示秒）改为地区习惯（ISO/中国/美国/日本）；拖拽预览结束时刻、完成弹窗时间、记录导出日期随 locale；倒计时统一 MM:SS / HH:MM:SS
    4. **设置 → 通知**：「完成弹窗（强提醒）」→「计时完成时提醒」
    5. **设置 → 日历**：目标日历由下拉改为**文本输入**（用户填日历 app 中已有分类名）；默认标题、快捷键预设 标记 (Beta)
    6. **通用页宽度修复**：hint 长文本可换行 + label 列宽上限 260 + 面板固定宽度 → 切页不再变宽
    7. **关于页宽度统一**：所有 panel 在 selectTab.installPanel 统一 520pt 居中（关于页原来 544 偏宽）
    8. **关于页纸张质感**：三层点阵 + 纤维竖纹（热敏纸粗糙感）
    9. **PRD 全量同步**：linger2_prd.md 更新至 2.5（版本/状态/最近更新/架构图/各模块状态/roadmap），并修正 3 处过时标记（时间格式、双轨模式、HoverListView 拆分）
  - **未完成/卡点**：
    - 实机验收（代码已写好，等你跑）：完成弹窗、日历记录、预约编辑区输入
    - 上线前清单 P0 剩余：关于页内容填充（卡用户提供信息）
    - P1：icon 设计/动画、发起计时动画、初次引导、基础教程、快捷键清单、检查更新、重复日程
    - P2：设置重设计、弹窗菜单、参数设置、md 格式等
    - 拖拽溢出「自动开始最长计时」未实现（弹簧反馈已有）
    - 快捷键预设触发（Fn/Ctrl/Opt 按住拖拽自动填标题）未实现
    - 诊断日志（RIGHTCLICK/buildStamp）建议上线前清理
  - **下一步（按优先级）**：
    1. 你实机验收 3 项（完成弹窗 / 日历记录 / 预约编辑区输入）
    2. 关于页内容填充（等你提供 小红书/IG/邮箱/GitHub/捐赠 信息）
    3. P1 批次（icon 动画 → 发起计时动画 → 初次引导 → 快捷键清单 → 检查更新）
    4. 上线前清诊断日志 + 打包发布
  - **如何验证**：`./script/build_and_run.sh` 启动 → 设置里逐项检查（拖拽线 0-100 生效、双轨仅倒计时恒亮、时间格式切地区看结束时刻、目标日历文本输入、通用页切页不跳宽、关于页纹理+宽度）→ `swift test --disable-sandbox` 21/21 绿
  - **给下一位的提示**：
    - 面板宽度统一在 `SettingsWindow.selectTab → installPanel`（520pt + centerX），**不要再给单个 panel 加宽度约束**（会与外部约束冲突）
    - 时间格式：`linger_timeFormat` 现在存 **locale ID**（sv_SE/zh_CN/en_US/ja_JP），不再是 hms/hm/ms；`TimerEntry.displayString` 忽略 format 参数统一标准格式
    - 拖拽线：`DragFeedbackView.show()` 读 `linger_maxDragLinePercent`（0-100，默认 50），`hasSetValue` 判断是否显式设过
    - 授权铁律不变：`authorizationStatus(for:)` 别信，靠 `grantedByRequest` 持久化
    - 改完设置类 UI 记得先 `swift build`，GUI 需用户实机验收

- **2026-08-06 晚 · ✅ 已授权菜单项灰显修复（Codex，真凶：NSMenu.autoenablesItems）**
  - **结论**：主 bug 已修复并经用户实机确认（右键 → 灰显「已获取授权」不可点）。
  - **根因链（运行时日志实锤）**：
    1. `authorizationStatus(for:)` 在 ad-hoc 签名下恒返回 `notDetermined` → `isAuthorized` 恒 false。授权状态只能靠 `requestFullAccessToEvents` 回调 + `grantedByRequest` 持久化（key=`linger_calendarGrantedByRequest`）兜底。
    2. **真凶**：`NSMenu` 默认 `autoenablesItems=true`，菜单弹出时按「target 是否响应 action」自动重新启用所有菜单项，覆盖手动 `isEnabled=false`。RIGHTCLICK 日志显示 `enabled=0`（确实设了禁用）但弹出瞬间被系统重启用。
  - **修复**：`rightClickMenu.autoenablesItems = false`（手动 isEnabled 成为唯一权威）+ 授权检测加固（启动即初始化、status=notDetermined 且有历史写入记录则补 grantedByRequest=true）+ telemetry 过滤修复 + RIGHTCLICK 诊断日志 + buildStamp（`menu-v3-20260806`）。
  - **给下一位的提示**：
    - 授权状态唯一可靠信号 = `requestFullAccessToEvents` 回调 + `grantedByRequest` 持久化；别信 `authorizationStatus(for:)`，别在它上面加逻辑
    - **菜单项 isEnabled 必须配合 `menu.autoenablesItems=false`**，否则弹出时被系统重启用——"灰显失效"类 bug 的通病
    - 关键文件：`MenuBarManager.swift`（`showRightClickMenu` / init autoenablesItems）、`CalendarManager.swift`（init / hasAccess / requestPermissionIfNeeded / probeAccessOnLaunch）、`AppEntry.swift`（启动触达）

- **2026-08-06 · 上线前设计清单（Codex 整理，未动代码）**
  - 22 项上线前待办，已分类 + 定优先级 + 分批：
  - **P0 上线阻断**：① 粘贴复制 bug（已修✅）② 计时显示 bug（已修✅）③ Intel 转译（🔴 不做了）④ 关于页内容填充（🔴 卡用户提供信息，最后做）
  - **P1 第一印象/核心体验**：⑤ 菜单栏 icon 设计（现自绘 Ring）⑥ icon 计时交互动画 ⑦ 发起计时动画（松手入场仪式感）⑧ 初次使用引导（拖拽教学）⑨ 基础教程 ⑩ 快捷键设计（⏳ 需用户定清单，已有 Fn/Ctrl/Opt 预设标题）⑪ 检查更新（⏳ 需发布渠道）⑫ 重复日程不带入上次时间（⏳ 需澄清语义）
  - **P2 打磨/增强**：⑬ 设置窗口重新设计 ⑭ 提醒框记录日程选择菜单 ⑮ 下拉线条最大值交互打磨 ⑯ 快捷写入方式交互 ⑰ 通知方式交互设计 ⑱ 倒计时提醒阈值设置 ⑲ 计时最大/最小值设置 ⑳ 最小计时单元 ㉑ 强提醒框位置优化 ㉒ md 文档格式检查
  - **建议批次**：批次1=P0 → 批次2=第一印象(⑤⑥⑦⑧⑨) → 批次3=功能(⑩⑪⑫⑱⑲⑳) → 批次4=打磨
  - **如何验证**：`./script/build_and_run.sh`（打包 app 才能测日历/TCC，Xcode 裸跑不可靠）；`swift test --disable-sandbox` 19/19 绿

### 历史里程碑（一行一个，详情见 git 历史）

| 日期 | 能力 | 关键决策 |
|------|------|----------|
| 08-06 | Markdown 记录导出 + 每周清理升级 | RecordExporter 归档到「文稿/Linger 计时记录.md」；僵尸条目随清理清除 |
| 08-06 | 唯一图标 + 空态悬浮窗 + 分隔线统一 | 去掉 Ring/Classic/timer 三选一；无计时也显示 hover 面板 |
| 08-06 | 预约运行态显示修复 | 预约激活后按实际状态渲染；停止运行中预约同步删日历事件 |
| 08-06 | 倒计时完成通知（自绘玻璃横幅） | CompletionBanner 替换系统通知；NotificationManager 仅留提示音；系统通知彻底移除 |
| 08-06 | 预约删除按钮 + 日历同步 | 预约 ✕ 删除 = 删计时 + 同步删日历事件；运行中计时 stop 不删历史 |
| 08-06 | 计时→macOS 日历记录（重要功能） | CalendarRecorder 独立协调器；默认写入方式 auto（已从 manual 迁移）；预约创建即记录，拖拽完成时记录（5 分钟取整）；与通知开关解耦 |
| 08-06 | 弹窗内输入标题写入日历修复 | auto 模式用户输入标题 → 更新已有事件标题（非新建）；编辑时暂停 8s 自动消失 |
| 08-06 | 日历记录实机修复（TCC 归因） | Xcode 裸跑无 bundle → `authorizationStatus` 不可靠，改用 `requestFullAccessToEvents` 回调驱动 |
| 08-06 | 预约编辑区 5 项反馈 | 4 输入框等宽；时间恒 24h；输入框点击加固（sendEvent 强制 key + layoutSubtreeIfNeeded）；日期格式地区设置（默认 ISO sv_SE） |
| 08-05 | 预约计时内联展开 | hover 列表底部内联展开（schedule-timer-expand.html）；胶囊三行编辑区；frame didSet 同步 contentContainer（根治输入失效） |
| 08-04 | 拖拽预览 9 轮迭代 | 发光竖线+光点手绘；Esc 收回三步动画；线长 = `min(40·√maxMinutes, 百分比上限)`；Carbon 全局热键；锚点 = 状态栏按钮底边 |
| 08-04 | 悬停列表对齐 hover-list.html | 300pt 玻璃面板；平铺行；2px 琥珀渐变流动进度条；底栏圆形日历按钮 |
| 08-04 | toast 对齐 | 毛玻璃胶囊；淡入 0.4s → 停留 2.5s → 淡出 0.4s |
| 08-04 | 设置窗口重构（settings-window.html） | 5 tab；Tab 栏贴底琥珀指示线；section/row 范式；关于票据白底面板 |

## 准绳（source of truth）

| 文件 | 作用 |
|---|---|
| `pages/`（HTML 原型，11 页） | **UI 唯一准绳**。布局/配色/字号/文案/交互全以 HTML 为准 |
| `linger2_prd.md` | 功能需求总纲 |
| `phase1-architecture-blueprint.md` | 架构蓝图（设计令牌、模块依赖、NSTrackingArea 铁律） |

**铁律**：原型与旧代码/蓝图冲突时，**以 HTML 原型为准**。

## 最新 PRD 摘要（2026-08-23 同步自 linger2_prd.md，完整版见该文件）

> 全量文档以 `linger2_prd.md` 为准；此处是给接手的 agent 快速掌握「已做什么 / 剩什么」。

**✅ 已实现（架构图全绿）**：菜单栏系统（拖拽/右键/悬停/反馈窗口）、计时引擎（即时/预约/暂停/10 上限/持久化/定时清理）、完成弹窗（自绘玻璃横幅）、日历集成（CalendarRecorder + 预约创建即记录 + 删除同步）、设置窗口（5 tab + 关于票据面板）、记录导出（Markdown 按天归档）、FLIP 动画、右键菜单（设置/系统授权/退出⌘Q）

**🚫 已砍/废弃**：图标三选一（只留 Ring）、系统通知（改自绘横幅）、倒计时浮窗（CountdownPillPanel/Floater 已删）、「仅结束时间」双轨模式、通知权限申请

**⏳ 待做**：拖拽溢出自动开始最长计时；快捷键预设触发拖拽填标题；关于页内容填充（卡用户信息）；P1/P2 打磨清单（见「最近交接」2026-08-06 上线前清单）

**关键决策**：UI 以 `pages/*.html` 原型为准；配色走 LingerTheme；授权状态靠 grantedByRequest 持久化；菜单 isEnabled 配合 autoenablesItems=false

## 目录结构

```
Linger2.5/
├── Package.swift              # SwiftPM 包（macOS 13+，可执行 target Linger）
├── Sources/Linger/            # 全部源码
├── pages/ + 各 .md/.design    # 原型与设计文档
├── script/build_and_run.sh    # 一键 kill + build + 打包 .app + 启动
├── Support/Linger-Info.plist  # 打包用 Info.plist 素材
├── .codex/environments/       # Codex Run 按钮配置
└── HANDOFF.md                 # 本文件
```

## 最新进度

### 已完成
- [x] SwiftPM 工程搭建 + 真编译通过（5,500+ 行 2.0 代码收编修复）
- [x] `build_and_run.sh` 一键构建 + 打包 + 启动
- [x] 拖拽死锁修复（自定义 `LingerStatusItemView` 直接收鼠标事件，绕开 button cell tracking loop 吞 mouseUp）
- [x] 拖拽预览（9 轮迭代稳定：发光竖线/光点手绘、Esc 收回三步、橡皮筋、Carbon 全局热键）
- [x] 悬停列表对齐 hover-list.html（300pt 玻璃 / 平铺行 / 2px 流动进度条 / 底栏圆钮）
- [x] toast 对齐
- [x] 设置窗口重构（5 tab / section-row 范式 / 关于票据面板）
- [x] 预约计时内联展开 + 编辑区输入修复（frame didSet 同步 contentContainer）
- [x] 计时→日历记录（CalendarRecorder / 默认 auto / 预约创建即记录）
- [x] 倒计时完成通知（自绘 CompletionBanner 横幅，替换系统通知）
- [x] 预约删除按钮 + 日历同步删除
- [x] Markdown 记录导出 + 每周清理升级
- [x] 唯一图标 + 空态悬浮窗 + 分隔线统一
- [x] 已授权菜单项灰显修复（`autoenablesItems=false`）
- [x] 纯逻辑单测接入 `swift test`（21/21 绿）
- [x] **拖拽线最大长度 0-100%（屏幕高度百分比）**（2026-08-23）
- [x] **双轨删「仅结束时间」+ 仅倒计时恒亮**（2026-08-23）
- [x] **时间格式改 locale 驱动（ISO/中国/美国/日本）**（2026-08-23）
- [x] **目标日历文本输入 + 默认标题/快捷键预设 (Beta) 标记**（2026-08-23）
- [x] **通用页切页宽度修复 + 关于页宽度统一 520 + 纸张纹理增强**（2026-08-23）
- [x] **PRD 同步至 2.5（全量状态更新）**（2026-08-23）

### 待验收 / 待办
- [ ] **完成弹窗实机验收**：计时归零看右上角横幅（标题行/25:00/内联输入/↻/✓/8s 消失/开关）
- [ ] **日历记录实机验收**：拖拽计时归零 / 创建预约 → 打开日历 app 看「Linger」日历事件（日历记录 12 条已实证工作正常）
- [ ] **预约编辑区输入实机验收**：4 输入框可点击输入
- [ ] **上线前清单 P0 剩余**：关于页内容填充（卡用户提供信息）
- [ ] **上线前清单 P1**：icon 设计/动画、发起计时动画、初次使用引导、基础教程、快捷键、检查更新、重复日程
- [ ] **拖拽溢出自动开始最长计时**（弹簧反馈已有，自动开始未实现）
- [ ] **快捷键预设触发**（Fn/Ctrl/Opt 按住拖拽自动填标题，设置 UI 已有）
- [ ] **上线前清单 P2**：设置重设计、弹窗菜单、参数设置、md 格式等
- [ ] 清理诊断日志（RIGHTCLICK/buildStamp，建议上线前清）

## 构建与运行

```bash
cd /Users/dawang/Downloads/vibecoding/Linger2.5
./script/build_and_run.sh              # kill + build + 打包 + 启动（默认）
./script/build_and_run.sh --verify     # 构建 + 启动 + 进程检查
./script/build_and_run.sh --logs       # 启动 + 流式日志
./script/build_and_run.sh --telemetry  # 启动 + 流式 telemetry 日志
```

- **Xcode**：打开 `Package.swift`，scheme 选 `Linger`，⌘R（需 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`）
- **重要**：日历/TCC 等系统权限功能**必须用 `build_and_run.sh` 打包 app 测**，Xcode 裸跑无 bundle 不可靠

## 架构速览（新 agent 必读）

- **入口**：`main.swift`（无 @main，手写 NSApplication 启动）→ `AppEntry.swift`（AppDelegate，debug `.regular` / release `.accessory`）→ `MenuBarManager`（顶层协调者）
- **引擎（纯 Foundation，勿引 AppKit 视图）**：`TimerEntry`（实体 + s=d² 映射/吸附纯函数）、`TimerManager`（增删/暂停/10 上限/JSON 持久化）
- **设计令牌唯一来源**：`LingerTheme.swift`（琥珀金阶梯、圆角、间距、动画、UserDefaultsKey）——**禁止**硬编码 #F5A623 / 裸 NSColor
- **关键决策（勿轻易回退）**：`LingerStatusItemView.swift` 自定义状态栏视图直接收 mouseDown/mouseUp/rightMouseUp + 内建 hover tracking —— 吞 mouseUp 老 bug 的根治方案
- **拖拽状态机**：idle → pressed（mouseDown）→ dragging（位移 >4px，30fps 轮询）→ mouseUp 松手 → `finishDrag` 创建计时；Esc 取消收敛到 `cleanupDrag`
- **反馈视图**：`DragFeedbackView.swift`（水平双轨、字号设置、橡皮筋）、`DragLineView.swift`（发光竖线/光点手绘）、`DragPhysics.swift`（触顶阻尼纯函数，可单测）
- **浮窗/面板**：`HoverListView.swift`（300pt 毛玻璃列表）、`ScheduleTimerView.swift`（预约内联编辑）、`CompletionBanner.swift`（完成弹窗）、`ToastView.swift`、`SettingsWindow.swift`、`CalendarManager.swift` + `CalendarRecorder.swift`

## 关键铁律速查

### UI 铁律
1. 所有颜色/圆角/字体走 `LingerTheme`，**禁止硬编码** `#F5A623` / 裸 NSColor
2. Switch 必须自定义绘制胶囊（36×20），禁止 `NSButton(.switch)` 复选框
3. Select 必须自定义外观（`.inline` + `isBordered=false` + layer 自绘），禁止 NSPopUpButton 默认 bezel
4. 设置窗口标题栏保持系统原生（`.titled + .closable`），勿回退透明（关闭按钮会消失）
5. 间距用 `LingerTheme.space1~6`（4/8/12/16/24/32），字号用 `labelFont(size:)` / `timeFont(size:)`
6. **菜单项 isEnabled 必须配合 `menu.autoenablesItems=false`**，否则弹出时被系统重启用

### 日历授权铁律
1. 授权状态唯一可靠信号 = `requestFullAccessToEvents` 回调 + `grantedByRequest` 持久化（key=`linger_calendarGrantedByRequest`）
2. `authorizationStatus(for:)` 在 ad-hoc 签名下恒 notDetermined，**别信它、别在它上面加逻辑**
3. 日历/通知等系统权限功能测试一律用 `build_and_run.sh` 打包 app，Xcode 裸跑 TCC 不可靠

### 输入框铁律（.accessory app）
1. 无边框 statusBar 窗口点文本控件不自动成 key → 在 `HoverListWindow.sendEvent` 里 `NSApp.activate` + `makeKeyAndOrderFront` 强制
2. 手动 timer 动画改 frame 后必须 `layoutSubtreeIfNeeded()` 再允许交互，否则 autolayout frame 未解析导致 hitTest nil
3. ScheduleTimerView `frame didSet` 必须同步 `contentContainer.frame = bounds`

### 易踩坑
- `statusItem.view` deprecation 警告是刻意为之（绕开 button cell tracking loop 吞 mouseUp），勿改
- Esc 取消拖拽用 Carbon `RegisterEventHotKey` 全局热键（localMonitor keyDown 在 app 未激活时收不到）
- NSDatePicker `.yearMonthDay` 渲染跟随 locale 数值模板（sv_SE=ISO `2026-08-01`）；要零填充 ISO 用 sv_SE，别用 en_US_POSIX
- 完成项记得回填「最新进度」并 commit；进度与代码分开 commit

## 接手协议

0. **接力工具**：使用 `.agents/skills/linger-handoff/` skill
1. 先读：本文件 → `pages/` 相关页 → `linger2_prd.md` 对应章节
2. UI 改动以 HTML 原型为准；引擎改动保持叶子模块纯净（可单测）
3. 改完必须能 `swift build`（`--disable-sandbox` + `DEVELOPER_DIR`），GUI 改动需实机验收
4. 每完成一个可验收里程碑：更新本文件"最新进度" + git commit
5. 不擅自改动 2.0 / 2.1 存档目录；有疑问标「待确认」，不臆造

## 已知问题

- `statusItem.view` 有 deprecation 警告（刻意为之），功能正常
- 沙箱内无法 `open` GUI app，启动验收需用户在终端执行
- 诊断日志（RIGHTCLICK/buildStamp）建议上线前清理
