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

- **2026-08-06 · 弹窗内输入的日程标题未写入日历（Codex 修复）**
  - 现象：auto 写入方式下，用户在完成弹窗输入标题后，日历里没有这个标题
  - 根因：`CalendarRecorder.recordFromBanner` 对 auto 模式直接跳过（以为已完成自动写入）—— 实际 auto 在归零时用**默认标题**写了事件，用户输入的新标题被丢弃
  - 修复：
    1. `CalendarManager.updateEventTitle(eventIdentifier:newTitle:)`：更新已有事件的标题
    2. `recordFromBanner`：用户显式输入标题 → 有已有事件则**更新标题**（覆盖 auto 默认标题）；无事件（ask/manual）才新建；并同步 `entry.predefinedTitle`
    3. 完成弹窗输入框开始编辑时**暂停 8s 自动消失**，结束编辑重新计时（避免打字被打断丢输入）
  - 编译 17/17 绿；bundle 已重建
  - 待验收：auto 模式下跑一个计时 → 弹窗里输入标题 → 日历事件标题应变成输入的标题

- **2026-08-06 · 倒计时完成通知：自绘玻璃横幅（Codex）**
  - 本次完成（`swift build` 通过，`swift test` 17/17 绿）：
    1. **新增 `CompletionBanner.swift`**：完成弹窗（强提醒）—— 300pt 右上角毛玻璃横幅，替换系统通知
       - 标题行：Ring 图标 + Linger + ✓ 绿 + 「现在」+ ✕ 关闭
       - 内容行：日程模块（有标题显名 / 无标题铅笔+内联输入 placeholder=日程 + ↩ 提交）+ 记录时间 mm:ss 琥珀等宽 + 重复 ↻ + 确认 ✓（圆钮 hover 琥珀）
       - 交互全程横幅内完成；8s 无交互自动淡出；多条右上角堆叠；无边框 statusBar 窗口 + sendEvent 强制 key（复用 hover 列表经验，点击输入不抢焦点）
    2. **NotificationManager 重构为仅提示音**：删掉 UNUserNotificationCenter（categories/actions/授权/横幅）；系统通知权限不再申请
    3. **设置 → 通知**：删「通知授权」区（不再需要）；「计时完成时通知」开关改名为 **「完成弹窗（强提醒）」** + hint（关闭后仅保留菜单栏倒计时与提示音）；仍写 `linger_notifyOnComplete`（默认开，无需迁移）
    4. **CalendarRecorder**：ask 模式改由横幅 ✓/输入承担（不再弹 NSAlert）；新增 `recordFromBanner(entry, title:)`（auto 已写跳过 / ask/manual 写 + 标记）
    5. AppEntry 初始化 CompletionBannerManager
    6. 新增 CompletionBannerTests 2 个（有/无标题构建+布局）；OCR 验证标题行/内容行渲染正确
  - 未完成/卡点：**实机验收**（build_and_run.sh）—— 拖一个计时跑完看右上角弹窗：标题行、mm:ss、无标题时内联输入、↻ 同长重开、✓ 写入日历、8s 自动消失、设置开关关闭后不再弹
  - 下一步：验收 → 之后可做 toast.html 视觉统一 / UI 整体打磨
  - 给下一位：
    - **关键决策**：完成反馈三层 = 菜单栏倒计时（常驻）+ 提示音（开关）+ 完成弹窗（开关，默认开）；弹窗与日历记录解耦（CalendarRecorder 独立）
    - **关键决策**：系统通知彻底移除（自绘横幅 + NSSound 都不需要通知权限），设置「通知授权」区已删
    - 弹窗开关复用 `linger_notifyOnComplete`（旧「计时完成时通知」键，默认开）；`NotificationManager.bannerAvailable` 等旧 API 已删
    - 弹窗 UI 在 `CompletionBanner.swift`；显示入口 CompletionBannerManager.handleTimerDidFinish；确认写入 CalendarRecorder.recordFromBanner

- **2026-08-06 · 预约删除按钮 + 日历同步（Codex）**
  - 本次完成：hover 列表预约行右侧新增 ✕ 删除按钮；点击 = 删计时 + 同步删除已写入的日历事件
    1. `CalendarManager.deleteEvent(eventIdentifier:)`（按 eventIdentifier 删事件，未授权/找不到返回 false）+ `unmarkRecorded`
    2. `CalendarRecorder.deleteRecorded(entry)`：有 calendarEventId 先删日历事件，再清标记
    3. `HoverListView`：预约行画 ✕（右缘）+「待开始」徽标左移；`onDeleteScheduled` 回调 + hit rect
    4. `MenuBarManager.deleteScheduledTimer(id)`：CalendarRecorder.deleteRecorded → stopEntry → refresh
  - 编译 15/15 绿
  - 待验收：hover 列表创建预约 → 日历出现事件 → 点 ✕ → 计时消失 + 日历事件同步删除
  - 给下一位：只有预约走「删除同步删日历」；运行中/暂停的拖拽计时 stop 按钮保持原语义（不删历史事件）

- **2026-08-06 · 日历记录实机修复 2（仍无事件：calendar not authorized）**
  - 现象：迁移生效（`Migrated legacy writeMode manual -> auto`），记录路径跑到，但 `Auto record skipped: calendar not authorized`
  - 根因（TCC 实测确认）：**Xcode/SwiftPM 裸跑的可执行文件没有 bundle identifier**（日志 `No app bundle (raw executable)`），macOS 的 `EKEventStore.authorizationStatus(for:)` 无法为无 bundle 进程归因 TCC 权限 → status 恒 notDetermined，即使 TCC 里已有该路径条目（TCC.db 显示 debug 二进制 auth_value=2、01:53 已授权）也读不到
  - 修复：
    1. **请求回调驱动授权**：`CalendarManager.ensureFullAccess` —— 已授权/已请求过直接 true；notDetermined 时调 `requestFullAccessToEvents` 并**用回调 granted 结果**（该回调对无 bundle 进程也如实返回，01:53 实测 granted=true），不再只看 status API；`writeEvent` 守卫改为 `isAuthorized || grantedByRequest`
    2. `CalendarRecorder.writeCompletion`（auto）改用 `ensureFullAccess`（PRD §3.5.1 按需授权），不再静默跳过
    3. CalendarManager.init 打诊断：bundleID + status（一眼看出是哪种运行方式）
    4. **重新打包 dist/Linger.app（com.linger.app，TCC 08-05 已授权）** —— 正式包走 bundle ID 正常路径，日历记录最稳
  - 编译 15/15 绿
  - 给下一位：macOS TCC 对无 bundle 裸可执行文件不可靠，日历/通知等系统权限功能测试一律用 `./script/build_and_run.sh` 打包 app；Xcode 裸跑靠 grantedByRequest 兜底（写 EventKit 是否真成功待实机确认）

- **2026-08-06 · 日历记录实机修复（用户实测：1 分钟计时无事件）**
  - 现象：日志 `Manual write mode: completion record skipped (user records manually)` —— 记录逻辑已跑，但写入方式还是老的 manual
  - 根因：老版本把默认 `manual` 持久化进 `linger_calendarWriteMode`，新默认 auto 对老用户不生效
  - 修复：`CalendarManager` 一次性迁移 —— 只要用户从未显式设置过（`linger_calendarWriteModeExplicit=false`），残留 manual → auto；`setWriteMode`（设置下拉）置 explicit=true 后不再迁移
  - 顺手修：`animateScheduleViewHeight` 完成处 `layoutSubtreeIfNeeded` 直接调用触发 "already being laid out" 警告 → 改 `DispatchQueue.main.async` 延迟到 layout pass 结束后
  - 编译 15/15 绿；下次启动即迁移

- **2026-08-06 · 计时→macOS 日历记录（用户「重要功能」）**
  - 本次完成（`swift build` 通过，`swift test` 15/15 绿）：
    1. **拖拽发起的计时完成时记入日程**：新增 `CalendarRecorder`（独立协调器，订阅 `timerDidFinishNotification`），按「写入方式」编排：
       - auto（**默认已从 manual 改为 auto**）：完成即自动写入（无标题用默认标题，5 分钟向上取整）
       - ask：通知横幅可用时由横幅 ✓/✎ 承担询问；横幅不可用（通知关 / 无 bundle / 权限被拒）时应用内弹窗询问（可编辑标题）
       - manual：保持既有手动路径（hover 标题编辑 / 横幅动作）
       - 与通知开关解耦：日历记录不再被「计时完成时通知」关闭 / 通知权限影响（原实现把 auto 写入放在 NotificationManager 且被 notifyOnComplete guard 挡住，是 bug）
    2. **预约计时创建即记入日程**：`createScheduledTimer` 确认后按「记录的日期-时间-时长」精确写入（不 5 分钟取整），标题用日程名称或默认标题；未授权时引导开权限；已记录的完成时不再重复写
    3. **防重复**：横幅 userInfo 增加 entryID，Confirm/✎ 写入前查 `entry.hasRecorded` 跳过；CalendarRecorder 各处先查 hasRecorded
  - 未完成/卡点：**实机验收**（需真机 EventKit）：拖一个计时跑完 → 看「Linger」日历有没有事件；预约一个未来时间 → 立即出现在日历；设置切换写入方式再验证
  - 下一步：验收 → 拍板通知横幅方向（自定义玻璃 vs 系统，现仍系统通知）
  - 如何验证：`./script/build_and_run.sh` → 拖拽计时到归零 → 打开「日历」app 看 Linger 日历事件（标题=预设/默认标题，时间=起止 5 分钟取整）；hover 列表点日历 → 创建预约 → 日历立即出现未来事件；设置 → 日历 → 写入方式切「每次询问」→ 再完成一个计时应弹询问
  - 给下一位：
    - **关键决策**：日历记录独立成 `CalendarRecorder`（不塞进 NotificationManager），避免与通知开关/通知权限耦合
    - **关键决策**：预约 = 用户明确安排 → 创建即记录（精确时间）；拖拽 = 完成时记录（5 分钟取整，PRD §3.5.3）
    - **关键决策**：ask 模式优先用系统横幅承担询问；仅横幅不可用时应用内 NSAlert（accessory 应用 runModal 可用）
    - 默认写入方式改为 auto（`CalendarManager.writeMode`），设置页可切回每次询问/手动
    - `requestPermissionIfNeeded` 会弹「打开系统设置」引导；.accessory 模式下 TCC 弹窗不可靠，这是既有模式

- **2026-08-06 上午 · 预约编辑区 5 项反馈（Codex）**
  - 本次完成（`swift build` 通过，`swift test` 15/15 绿）：
    1. **4 个输入框等宽**：行1/行2 改 `distribution = .fillEqually`（日期/时间/时长/日程宽度一致）
    2. **时间恒 24 小时制**：`timePicker.locale = en_US_POSIX`（HH:mm）+ 预计结束 `HH:mm`，不受系统 12/24h 影响
    3. **日程/时长输入框无法输入 — 多项加固 + 诊断**（上一轮 frame didSet 未根治）：
       - `HoverListWindow.sendEvent`：任意 leftMouseDown 若窗口非 key → `NSApp.activate` + `makeKeyAndOrderFront`（.accessory 无边框 statusBar 窗口点击文本控件不自动 key 的根治）
       - 高度动画完成时 `sv.layoutSubtreeIfNeeded()` + `contentView.layoutSubtreeIfNeeded()`（强制解析子树 autolayout，杜绝 frame 未解析导致 hitTest nil）
       - `ScheduleTimerView.mouseDown` 重写：强制 key + 打印命中诊断
       - `nameField`/`durationField` 显式 `isEditable/isSelectable/isEnabled = true`
    4. **日期格式地区设置**：设置 → 通用 → 新增「日期与时间 → 日期格式」选择器（4 选项，写 `linger_dateLocale`）；编辑器日期选择器读该设置，**默认国际 ISO**。实测 NSDatePicker 渲染（cacheDisplay + Vision OCR）：sv_SE→`2026-08-01`（零填充 ISO，正是用户要的）/ zh_CN→`2026/8/1` / en_US→`8/1/2026` / ja_JP→`2026/8/1`
    5. **新增单测 `ScheduleEditorLayoutTests`（3 个）**：contentContainer 撑满 bounds、4 输入框中心 hitTest 命中 NSControl、宽度正确
  - 未完成/卡点：**实机验收输入是否真正可点**（诊断日志待用户跑后确认，可清）：
    - `LingerDiag schedule height anim done` / `schedule editor` / `schedule mouseDown` / `schedule click fell through`
  - 下一步：用户 `./script/build_and_run.sh` 或 Xcode ⌘R 验收 → 清诊断日志 → 拍板通知横幅方向 + 图标三风格实装
  - 如何验证：设置 → 通用 → 切「日期格式」4 选项（应见 2026-08-01 / 2026/8/1 / 8/1/2026）；hover 列表 → 点日历 → 编辑区展开 → 4 个输入框应都能点击输入；日志出现 `schedule mouseDown`（keyWindow=1）
  - 给下一位：
    - **关键决策**：无边框 statusBar 窗口在 .accessory app 里点击文本控件不一定自动成 key → 在 `HoverListWindow.sendEvent` 里强制（比在 expand 时 activate 一次更可靠，覆盖任意时刻点击）
    - **关键决策**：手动 timer 动画 frame 后必须 `layoutSubtreeIfNeeded()` 再允许交互，否则 autolayout 内部 frame 可能未解析（单测已证：layout 后 4 输入框中心 hitTest 均命中 NSControl）
    - **关键决策**：NSDatePicker `.yearMonthDay` 渲染跟随 locale 的数值模板（sv_SE=ISO `2026-08-01`）；要零填充 ISO 用 sv_SE，别用 en_US_POSIX（那是美式 `8/1/26`）
    - 诊断日志 4 处：HoverListWindow.sendEvent 无日志（行为修复）；`schedule height anim done`+`logEditorState()`、`schedule mouseDown`、`schedule click fell through`（HoverListView.mouseDown 兜底分支）

- **2026-08-05 晚 · 预约计时编辑区输入失效 + icon/文字错位修复（Solo/Trae · bug-fixing skill）**
  - 本次完成：3 轮迭代修复 spec 对齐后遗留的 2 个 bug
    1. **timer 打架（commit `dda2483`）**：`closeInlineSchedule` 把 close timer 存到 `heightAnimTimer`，紧接着 `notifyHeightChange()` → `animateHeight()` 第一行 `heightAnimTimer?.invalidate()` 把刚创建的 close timer 干掉。后果：scheduleView 永不移除，后续点击全走 close 但 timer 永不 fire。修复：新增独立 `scheduleHeightAnimTimer`（expand/close 专用），与 `heightAnimTimer`（驱动外层 HoverListView 高度）隔离
    2. **原型对齐 + NSApp.activate（commit `94f88eb`）**：日程名称胶囊补 bg-input 底色 + 去掉多余 return 图标；日期/时间胶囊改 flex-1/shrink-0 宽度比；`expandInlineSchedule` 加 `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront`（.accessory app 必须 activate 才能让 NSTextField 成为 firstResponder）
    3. **frame didSet 同步 + icon/content 垂直居中（commit `2683ce9`）** ← **真正根治输入失效**
       - 真根因：`scheduleView.frame` 在手动 timer 动画中变化，但 `contentContainer.frame` 只在 `layout()` 里同步，手动改 frame 不一定触发 `layout()`。结果 `contentContainer.bounds.height=0`，子 view 在 bounds 外，`hitTest` 返回 nil → 点击穿透到 HoverListView.mouseDown → 无响应
       - 修复：ScheduleTimerView 重写 `frame didSet` 强制同步 `contentContainer.frame = bounds`
       - icon/content 错位：icon 改 13x13 frame 居中（y=7.5），content 改 20pt 高度居中（y=4），都垂直居中在 capsuleHeight(28) 内
  - 编译：`swift build --disable-sandbox` 通过；`swift test` 12/12 绿
  - 未完成/卡点：实机验收待用户跑 `./script/build_and_run.sh` 确认输入框可点击获得光标；诊断日志 `schedule height anim done: frame=... contentContainer.bounds=...` 留在代码里，验收后可清
  - 下一步：实机验收 → 清诊断日志 → 拍板通知横幅方向 + 图标三风格实装
  - 如何验证：`./script/build_and_run.sh` → hover 列表 → 点日历按钮 → 220ms 后编辑区滑入（应看到 `schedule height anim done` 日志，frame 和 contentContainer.bounds 的 height 都=124）→ 点日期/时间/时长/日程输入框应能获得光标输入
  - 给下一位：
    - **关键决策**：`scheduleHeightAnimTimer` 与 `heightAnimTimer` 必须分开，前者驱动 scheduleView 自身高度动画，后者驱动外层 HoverListView 高度（onHeightAnimation 回调），两者并行跑互不 invalidate
    - **关键决策**：ScheduleTimerView `frame didSet` 必须同步 `contentContainer.frame = bounds`，否则手动 timer 改 frame 时 `layout()` 不触发，contentContainer.bounds 卡在 0 导致子 view hitTest 返回 nil
    - **关键决策**：.accessory app 让 NSTextField 获得 firstResponder 必须 `NSApp.activate(ignoringOtherApps: true)` + `window?.makeKeyAndOrderFront(nil)`，仅 `makeKey()` 不够
    - 诊断日志在 `animateScheduleViewHeight` 完成时打印 frame + contentContainer.bounds（通过 `ScheduleTimerView.contentContainerBounds()` 访问 private contentContainer）
    - bug-fixing skill 的 Phase 2 根因分析：第一次诊断停在 NSApp.activate（症状层），第二次才挖到 frame didSet 同步缺失（根因层）；UI bug 不能只读代码，要拿运行时日志验证 hitTest 链路

- **2026-08-05 下午 · 预约计时内联展开 spec 对齐（Solo/Trae）**
  - 本次完成：按 `schedule-timer-expand-handoff.md` spec 对齐 4 处偏差
    1. 编辑区垂直 padding 14→10pt（拆分 `sidePadding`(14,水平) / `verticalPadding`(10,垂直)，对齐 spec §6 `py-2.5=10`）；`preferredHeight` 132→124
    2. `revealContent` 时序拆分：opacity delay 100ms / translateY delay 120ms（原合并 100ms，对齐 spec §3.1）
    3. 确认时序对齐 spec §13.4：编辑区收回 → 420ms 后 `onScheduleConfirm`（原立即添加+同时收回）
    4. expand 路径补 `prefers-reduced-motion` 支持（原仅 close 路径有；新增 `contentContainerTransformIdentity()` 方法）
  - 编译：`swift build --disable-sandbox` 通过；`swift test` 12/12 绿
  - 未完成/卡点：步骤指示器 + 自动演示循环是原型演示辅助（生产省略，HANDOFF 已记录）；新日程项滑入依赖 TimerManager 添加后的 FLIP 动画（spec §3.4 的 max-height 0→72 + translateY -8→0 由列表 FLIP 覆盖）；实机验收待用户跑 `./script/build_and_run.sh`
  - 下一步：实机验收预约计时内联展开（点日历图标 → 220ms 后编辑区滑入 → 确认 → 420ms 后新日程出现）；之后拍板通知横幅方向 + 图标三风格实装
  - 如何验证：`./script/build_and_run.sh` → hover 列表 → 点日历按钮 → 展开动画 + 胶囊编辑区 → 确认/取消
  - 给下一位：revealContent 用两个 asyncAfter 分开 opacity/translateY 时序；确认时序在 `HoverListView.expandInlineSchedule` 的 `v.onConfirm` 闭包（closeInlineSchedule + 0.42s 延迟 onScheduleConfirm）；reduced-motion 在 expand/close 两条路径都处理；`ScheduleTimerView.contentContainerTransformIdentity()` 供 reduced-motion 跳过动画

- **2026-08-05 下午 · 预约计时内联化 + 进度整理（Codex）**
  - 本次完成：预约计时改为 hover 列表内联展开（schedule-timer-expand.html）；胶囊三行编辑区（日期/时间/时长/名称/预计结束+确认/取消）；
    NSDatePicker 支持任意日期时间（en_US_POSIX → yyyy-MM-dd / HH:mm）；展开/收起动画（日历按钮脉动/点击缩放、编辑区高度+滑入+淡入）；
    修复：编辑区位置（isFlipped 坐标下曾顶到最上方压住计时行，现锚定底栏上方）、输入失效（展开时 makeKey）、格式、高度动画改用 timer 防 animator 不生效
  - 测试环境：Xcode 可跑（SwiftPM 缓存清理 + NotificationManager bundle 兜底防 UNUserNotificationCenter 无 bundle 崩溃 + .swiftpm gitignore）
  - 未完成/卡点：本轮 4 个修复（位置/输入/格式）待实机确认；**通知横幅方向未定**（原型自定义玻璃横幅 vs 现状系统通知）；**图标三风格（Ring/Classic/timer）实际渲染未做**（设置里只有三选一选择器）；UI 统一性留最后
  - 下一步：确认预约计时 → 拍板通知横幅 → 图标三风格实装
  - 如何验证：Xcode ⌘R（Console 看 LingerDiag）或 `./script/build_and_run.sh`（.app，含通知）
  - 给下一位：HoverListView 是 **isFlipped**（坐标 y 向下、原点左上）；scheduleView 高度动画用**手动 timer**（animator 曾失效）；NSDatePicker 用 en_US_POSIX；编辑区在底栏上方；`statusItem.view` deprecation 是刻意保留（吞 mouseUp 老 bug 根治，勿改）

- **2026-08-05 · 预约计时按 schedule-timer-expand.html 规范实现（Codex）**
  - 本次完成：ScheduleTimerView 胶囊化三行（日期/时间、时长/名称、预计结束+确认/取消，input 底+图标，
    琥珀实底确认圆）；展开动画（日历按钮脉动 1.8s / 点击 scale 1→1.2→1.05 / 展开态激活 → 浮窗延长 0.38s
    → 220ms 后编辑区高度 0→full 380ms + 内容 translateY 滑入 + 淡入）；收起动画（编辑区收回 + 浮窗变矮）；
    新增 CalendarPulseButton（独立按钮 subview）；新增 LingerTheme.Color.input 令牌
  - 未完成/卡点：步骤指示器 + 自动演示循环是原型演示辅助（生产省略）；新日程项滑入动画未做（确认后列表刷新显示）
  - 下一步：notification 通知横幅方向待用户拍板（自定义玻璃横幅 vs 系统通知）
  - 如何验证：`./script/build_and_run.sh` → hover 列表 → 点日历按钮 → 展开动画 + 胶囊编辑区 → 确认/取消
  - 给下一位：展开时序在 HoverListView.expandInlineSchedule / closeInlineSchedule；编辑区动画
    ScheduleTimerView.revealContent / hideContent + 高度 animator；胶囊样式 makeCapsule

- **2026-08-05 · 关于并入设置 + 预约计时内联化（Codex）**
  - 本次完成：右键菜单删「关于 Linger」入口（关于=设置 tab 5，无独立窗口，AboutWindow.swift 已删）；
    预约计时改为 **hover-list 底部内联展开**（贴合 schedule-timer.html 原型），删独立浮窗
    （SchedulePanelWindow / presentScheduleTimer / schedulePanel 已废弃删除）
  - 未完成/卡点：预约编辑区控件还是系统默认样式（日期/时间/时长/名称胶囊化、预计结束排版）可后续微调
  - 下一步：notification 通知横幅——原型是自定义玻璃横幅，现状是系统通知，待用户拍板是否自绘替换
  - 如何验证：`./script/build_and_run.sh` → hover 列表底部日历按钮 → 内联展开预约编辑 → 确认创建预约
  - 给下一位：内联展开在 HoverListView（toggleInlineSchedule/closeInlineSchedule + onHeightAnimation 驱动高度）；
    ScheduleTimerView 直接作为 subview 复用

- **2026-08-04 晚 · 设置窗口按 settings-window.html 重构完成（Codex）**
  - 本次完成：5 tab（操作/通知/日历/通用/关于）；Tab 栏弃液态玻璃改底部 2pt 琥珀指示线 + 微琥珀底；
    面板统一 section/row 范式（去卡片框）；新增「关于」白底票据面板（AboutTicketView：锯齿边/虚线剪刀口/
    键值字段/页脚）；窗口标题随 tab 切换；切 tab 高度动画只伸缩底部（顶部固定，自定义插值不抽搐）
  - 未完成/卡点：票据字段是原型占位（你的名字 / https://your.blog / hello@example.com）待用户提供真实信息
  - 下一步：实机验收 5 tab + 关于票据观感；之后可继续 about/schedule-timer/notification 剩余页面对齐
  - 如何验证：`./script/build_and_run.sh` → 设置 → 切 5 tab → 看关于票据白底锯齿/深色文字/虚线剪刀口
  - 给下一位：票据深色文字在 AboutTicketView 局部令牌；系统标题栏勿回退透明；tab 指示线在 updateTabStyles.setTabIndicator

- **2026-08-04 下午 · 设置窗口统一原型落地（Trae）**
  - 本次完成：新增 `pages/settings-window.html` 统一原型（5 tab 合一：操作/通知/日历/通用/关于），含「关于」票据风格面板；Tab 栏改为贴底分割线 + 底部琥珀指示线（弃用液态玻璃容器）
  - 在本文件新增「设置窗口开发指引」章节（设计规范 + 原型架构/功能关联 + Codex 实现步骤），Codex 读完即可开发
  - 未完成/卡点：`SettingsWindow.swift` 尚未按新原型重构（4→5 tab breaking、Tab 栏样式重写、关于票据面板全新）
  - 下一步：按「设置窗口开发指引」第 8 节实现步骤重构 `SettingsWindow.swift`，编译 + 实机验收
  - 如何验证：`./script/build_and_run.sh` → 打开设置 → 切 5 个 tab → 看关于页票据白底锯齿/深色文字
  - 给下一位：现有 4 元素数组是 PRD §6.3 P2 越界防护，扩 5 个时同步所有数组 + switch + 保留 guard；系统标题栏勿回退透明（关闭按钮会消失）

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

## 最新进度（2026-08-06 增补）

- [x] **预约运行态显示修复**（2026-08-06）：预约到点激活后行内不再显示「待开始」——按实际状态渲染（running 琥珀倒计时+暂停/停止、paused 降透明）；停止运行中的预约也同步删除日历事件
- [x] **倒计时完成通知（自绘玻璃横幅）**（2026-08-06）：CompletionBanner 替换系统通知；NotificationManager 仅保留提示音；设置「完成弹窗（强提醒）」开关；ask 模式由横幅承担；17/17 绿
- [ ] **完成弹窗实机验收**：build_and_run.sh → 计时归零看右上角横幅（标题行/25:00/内联输入/↻/✓/8s 消失/开关）
- [x] **预约删除按钮 + 日历同步**（2026-08-06）：预约行 ✕ 删除 = 删计时 + 同步删日历事件
- [x] **计时→macOS 日历记录**（2026-08-06，重要功能）：新增 CalendarRecorder 协调器；拖拽计时完成按写入方式记录（默认 auto，已从 manual 改）；预约计时创建即按日期-时间-时长记录；横幅 Confirm/✎ 防重复；日历记录与通知开关解耦
- [ ] **日历记录实机验收**（写入方式已做 manual→auto 一次性迁移；**用 build_and_run.sh 打包 app 测**，Xcode 裸跑 TCC 不可靠已加 ensureFullAccess 兜底）：拖拽计时归零 / 创建预约 → 打开日历 app 看「Linger」日历事件
- [x] **预约编辑区 5 项反馈**（2026-08-06）：4 输入框等宽（fillEqually）；时间恒 24h；日程/时长输入框点击加固（HoverListWindow.sendEvent 强制 key + 动画后 layoutSubtreeIfNeeded + mouseDown 诊断）；日期格式地区设置（通用页选择器，默认 ISO sv_SE）；新增 ScheduleEditorLayoutTests 3 个
- [ ] **预约编辑区输入实机验收**：跑 `./script/build_and_run.sh` 确认 4 输入框可点击输入，看 LingerDiag 日志，通过后清诊断日志

## 最新进度（2026-08-04）

- [x] SwiftPM 工程搭建，**真编译通过**（5,500+ 行 2.0 代码收编 + 修复，首次真正 build 成功）
- [x] `script/build_and_run.sh` 一键构建 + 打 `dist/Linger.app`（ad-hoc 签名）+ 启动
- [x] **拖拽死锁修复**（根因：NSStatusBarButton cell tracking loop 吞 mouseUp →
      状态机卡死、松手不计时。方案：自定义 `LingerStatusItemView` 直接在视图层收鼠标事件）
- [x] **拖拽预览第一轮**（按 menubar-drag.html：4pt 渐变竖线 + 10pt 圆点 + 水平双轨
      for/til 均 24pt + 悬停高亮 + 提示文案）
- [x] **拖拽预览第二轮重构（用户 6 条反馈）**：
      - 计时字号 24→22pt，新增设置「计时字号」滑块（18–30pt，`linger_dragPreviewFontSize`）
      - 发光重构：`DragLineView` 手绘（外光晕 + 渐变核心线 NSShadow + 径向渐变光点 + 呼吸动画），
        替换原 CALayer 拼装（阴影不可见、圆点生硬）
      - til 结束时刻改为 HH:mm:ss；面板宽度按字号/最大时长自适应
      - 高亮侧字号 +2pt（提醒语义）
      - 提示文案只在前 3 次成功拖拽显示（`linger_dragHintUsageCount`）
      - 触顶橡皮筋：`DragPhysics.dampedOvershoot`（iOS 阻尼，上限 +40pt，面板向下生长）
        + trackpad 轻触反馈（NSHapticFeedbackManager，触顶瞬间一次）
- [x] **拖拽预览第三轮微调（用户 4 条反馈）**：
      - 发光回归 2.0 做法：紧致 glow（线 shadow 9 / 圆点 5）+ 实心亮金圆点，去掉过宽光晕带
      - Esc 可取消拖拽（monitor 加 .keyDown，keyCode 53）
      - 橡皮筋延伸 40 → 10pt（一点点即有反馈）
      - 默认字号 22 → 18pt（设置滑块 14–26）；高亮侧字号 +4 / 对侧 -2 + 弹跳动画，反差明显
- [x] **拖拽预览第四轮（用户反馈 + 2 bug）**：
      - 触顶三段式：线长到顶几乎不动（橡皮筋 10pt）→ 线宽按公式连续变细
        （`DragPhysics.lineWidth`：4 → 2，指数衰减）→ 数字冻结（触顶瞬间 til 冻结，两侧不再跳）
      - **Esc 断线动画**：取消时线条从中间裂开、圆点下坠、淡出（0.28s），不再瞬间消失
      - **修遮挡 bug**：`animateFontPop` 对侧动画值 1.15→0.98→1.0 是错的（本应变小的侧先放大 15%，
        盖住前缀末字符 + 顶掉右缘秒数）；改为 0.92→0.97→1.0 + frame 留 padding，彻底不裁字
      - 默认字号 18 → 16pt（滑块 12–24）
- [x] **拖拽预览第五轮（用户 2 个「没改对」）**：
      - **线长与最大时长同步**：线长上限 = `min(40·√maxMinutes, 百分比上限)`——
        30:00 时线正好到顶（219px），之后只剩 10pt 橡皮筋，不再空拉 141px
      - **Esc 可靠生效**：keyDown 在 app 未激活时不派发 → 改用 Carbon `RegisterEventHotKey`
        全局热键（无需辅助功能权限），拖拽开始注册 / 结束注销，触发断线动画
- [x] **拖拽预览第六轮（触顶反馈 + Esc 断线特效打磨）**：
      - 触顶反馈更明显：橡皮筋延伸 10 → 24pt（微微拉长可见），线宽衰减常数 k 40 → 60（变细过程平滑可见）
      - Esc 断线特效两阶段：先从中部裂开（缝扩大）→ 上段缩回菜单栏、下段带圆点重力下坠淡出（0.4s）
      - 修「闪一帧完整绳子的影子」：`isBreaking` 锁让断线期间忽略一切拖拽帧更新 + 首帧即 0.05 裂开
- [x] **拖拽预览第八轮（Esc 取消动画改为用户分镜「收回」特效）**：
      1. 圆球从外向内收缩消失（0–22%，easeOut）
      2. 线变到最细（当前宽→1pt）+ 颜色变暗（alpha 1→0.45）（22–52%）
      3. 整体向上收缩回菜单栏 icon（52–100%，easeOut 收尾加速），末端 15% 淡出；0.5s
- [x] **拖拽预览第九轮已回退（用户实测「从圆圈内部穿出」效果不好）**：
      - revert 圆心中锚点方案；回到第八轮：线从 **icon 中心正下方**延伸
      - 锚点 = 状态栏按钮（`buttonScreenRect`），窗口顶对齐按钮底边，线顶 = 按钮底边下方 12pt，水平居中按钮中心
      - 已删除 `iconCenterInScreen()` / `iconAnchorRect()` / `kIconLineGap`
- [x] **悬停列表按 hover-list.html 原型对齐（2026-08-04 下午）**：
      - 面板 240→300pt、圆角 16、玻璃半透明背景 rgba(24,24,28,0.72)
      - 行范式：卡片+色条+大数字 → **平铺行**（行高 52、行间 1px 分隔、hover 淡高亮）
      - 行内容：左标题（running 行 = 铅笔+文本+回车图标，视觉即原型输入框）+ 右时间 13pt 等宽 semibold + 按钮
      - 进度条：3px 纯色 → **2px 琥珀渐变 + 发光 + running 渐变流动动画**（paused 降透明 / scheduled 灰色）
      - 底栏：日历改圆形按钮（hover 琥珀软底）；「全部暂停/继续」对齐
      - 编辑交互：运行中行始终可点击改名（位置已适配单行 13pt 标题）
- [x] **纯逻辑单测接入 `swift test`**（DragPhysics 变细/同步公式、TimerEntry 格式、布局防遮挡，共 12 个，全绿）
- [ ] **待真机验收 v10**：悬停列表（用户已确认暂 OK，UI 统一性最后统一改）；拖拽预览回归
- [x] **toast 对齐 toast.html（2026-08-04 下午）**：
      - 毛玻璃胶囊（NSVisualEffectView hudWindow）+ 1px 边框 + 圆角 10，内容自适应（px-5/py-3）
      - 文案 13px ink，对齐原型「已达 N 个计时上限」
      - 动画：淡入 0.4s → 停留 2.5s → 淡出 0.4s（原 2s 直接消失）
- [x] **设置窗口按 settings-window.html 统一原型重构（2026-08-04 晚）**：
      - 5 tab（操作/通知/日历/通用/关于）；Tab 栏弃液态玻璃容器 → 底部 2pt 琥珀指示线 + 微琥珀底 + icon 18pt
      - 面板统一 **section/row 范式**（section-title 11px 大写 + 行间 1px 分隔，去卡片框）
      - 新增**关于票据面板** `AboutTicketView.swift`（白底 #faf9f6 + 点状纹理 + 上下锯齿 + 虚线剪刀口 + 键值字段 + 页脚）
      - 窗口标题随 tab 切换（title = tabTitles[index]）
      - 切 tab 高度动画：自定义插值只伸缩底部（顶部固定），消除抽搐
      - 字段值为原型占位（你的名字/blog/email），待用户提供真实信息
- [x] **修「设置窗口关不掉」bug（2026-08-04 下午）**：
      - 根因：SettingsWindow 依赖系统标题栏关闭按钮，但 `titlebarAppearsTransparent + isOpaque=false`
        下系统按钮不渲染，自定义标题栏又没关闭按钮 → 无任何关闭途径（既有缺陷，非本轮改动引入）
      - 修复：标题栏左侧加 traffic light（对齐原型）——红点 = 真实关闭按钮（performClose），两灰点装饰
- [x] **settings×4 对齐（2026-08-04 下午）**：
      - 外壳已有（520pt 玻璃 + 顶部图标 Tab）；本轮对齐内容区
      - 通知页：改**卡片**结构（授权绿点 + 「管理…」→ 系统通知设置 + 完成通知 switch + 提示音 select+switch），删废弃浮窗行
      - 日历页：授权绿点行 + **卡片1**（目标日历/写入方式/默认标题 + 灰注释）+ **卡片2**（快捷预设 fn/ctrl/opt 带 kbd 键帽 + 注释）
      - 通用页：加**图标三风格选择器**（Ring/Classic/SF Symbol 三选一，选中琥珀边框，绑定 linger_iconStyle，与 popup 双向同步）
      - 操作页：最大时长数字框加 **stepper 上下箭头**
      - 新增 token：LingerTheme.Color.surface/surface2（卡片面 #16161A / #1F1F25）
- [ ] 剩余页面对齐：about、schedule-timer、notification
- [ ] 按原型逐页对齐：hover-list（悬停列表）、toast、settings×4、about、schedule-timer、notification
- [ ] 通知/日历权限、预约计时、图标三风格（Ring/Classic/timer）
- [x] **预约计时内联化 + 修复**（2026-08-05）：hover 列表底部内联展开编辑区（胶囊三行 / NSDatePicker 任意日期时间 / 展开收起动画）；修复位置（isFlipped 坐标）、输入失效（makeKey）、日期时间格式（en_US_POSIX）、高度动画（timer）
- [x] **Xcode 测试环境就绪**（2026-08-05）：SwiftPM 缓存清理、NotificationManager bundle 兜底（无 .app 时防崩溃）、.swiftpm gitignore
- [ ] **通知横幅方向待定**（2026-08-05）：原型是自定义玻璃横幅，现状是系统通知（UNUserNotificationCenter）——待用户拍板
- [ ] **图标三风格实际渲染**（Ring/Classic/timer）：设置通用页有三选一选择器，但状态栏图标尚未按风格渲染
- [x] **设置窗口统一原型 `settings-window.html` 落地**（2026-08-04 下午，Trae）：5 tab 合一（操作/通知/日历/通用/关于），Tab 栏改贴底分割线+琥珀指示线，新增「关于」票据白底面板；同步在 HANDOFF 新增「设置窗口开发指引」章节
- [ ] 按 `settings-window.html` 重构 `SettingsWindow.swift`：4→5 tab、Tab 栏样式重写、关于票据面板、面板统一 section/row 范式

## 最近交接（2026-08-04 下午 · 悬停列表原型对齐）

**本次完成**
- 悬停列表视觉全面对齐 `hover-list.html`（300pt / 圆角16 / 玻璃底 / 平铺行 / 13pt 时间 /
  2px 渐变发光流动进度条 / 底栏圆形日历按钮 / 运行中行铅笔+文本+回车输入框样式）
- 保留既有能力：FLIP 动画、hover 高亮、三组排序、空态、按钮 hit 区、点击改名
- 拖拽预览仍为第八轮状态（icon 中心正下方 + Esc 收回三步）
- `swift build` 通过、`swift test` 12/12 绿

**未完成 / 卡点**
- 实机验收悬停列表（重点：平铺行间距、进度条发光/流动、底栏圆钮 hover、运行中行点击改名）
- 剩余页面对齐：toast、settings×4、about、schedule-timer、notification

**下一步（按优先级）**
1. 用户实机验收拖拽预览（`./script/build_and_run.sh`）
2. 按原型逐页对齐剩余页面（hover-list / toast / settings / about / schedule-timer / notification）
3. 通知/日历权限、预约计时、图标三风格

**如何验证**
- 拖拽：菜单栏图标下拉 → 观察发光竖线/光点、松手计时；拉过最长处感受橡皮筋 + 触顶震动
- 设置：设置窗口「操作」页 → 计时字号滑块 → 再拖拽看字号与面板宽度联动
- 单测：`swift test --disable-sandbox`（需 `DEVELOPER_DIR` 指向 Xcode）

**给下一位的提示**
- 发光/光点在 `DragLineView.draw(_:)` 手绘（NSShadow 紧致 glow，对齐 2.0 观感）；圆点直径 `DragLineView.dotDiameter`（10pt）
- 线长上限在 `DragFeedbackView.show()`：`max(100, min(40·√maxMinutes, percentLimit))`；橡皮筋 `kRubberHeadroom`（24pt）
- Esc 用 Carbon 热键（`installEscHotKey`/`uninstallEscHotKey`，拖拽期注册）——别再用 localMonitor 等 keyDown（未激活收不到）
- Esc「收回」三步动画在 `DragLineView.draw`：breakProgress 分段（0–0.22 圆球收缩 / 0.22–0.52 变细变暗 / 0.52–1 向上收回）；`isBreaking` 锁防拖拽帧干扰
- 动画时长 `DragFeedbackView.animateBreak`（0.5s）；首帧从 0.05 起防闪帧
- 线锚点：状态栏按钮 frame（`buttonScreenRect`），窗口顶对齐按钮底边、线顶在下方 12pt（`kTopY`）；
  曾尝试「圆圈中心锚点」已回退（线穿过按钮效果差，勿再改）
- **别再让字号弹跳动画的对侧从 >1 起跳**（会盖字），见 `animateFontPop`
- label frame 留 padding（前缀 +2 / 数字 +4），文字不贴右缘
- 断线动画：`DragFeedbackView.animateBreak` + `MenuBarManager.cancelDrag(animated: true)`
- 橡皮筋纯函数在 `DragPhysics.swift`（Foundation-only，可单测）；面板随溢出向下生长在
  `DragFeedbackView.update()`（顶部固定）
- 提示次数计数在 `MenuBarManager.finishDrag(with:)` 成功后 +1；改阈值看 `LingerTheme.maxDragHintShownCount`
- 字号设置键 `linger_dragPreviewFontSize`（18–30，默认 22）；面板宽度 `requiredPanelWidth()` 自适应
- 状态栏 `statusItem.view` deprecation 警告是刻意为之，勿改

## 设置窗口开发指引（settings-window.html）

> 本节为 `pages/settings-window.html` 原型的开发交接。Codex 读完本节即可开始实现/重构 `SettingsWindow.swift`。
> **原型是 UI 唯一准绳**；与旧代码冲突时以本原型为准。

### 1. 设计规范（Design Tokens）

所有颜色/圆角/字体必须走 `LingerTheme`，**禁止硬编码** `#F5A623` / 裸 NSColor。

色板（原型 CSS 变量 → LingerTheme 对应）：
- 主色琥珀金：`#F5A623`（primary）/ 浅 `#FFC966` / 深 `#D98E14` / 软底 `rgba(245,166,35,0.14)` / 发光 `rgba(245,166,35,0.40)`
- 背景：bg `#0C0C0E` / surface `#16161A` / surface-2 `#1F1F25`
- 文字：ink `#F5F5F3` / ink-2 `#A6A6AA` / ink-3 `#75757B`
- 分割线：`rgba(255,255,255,0.10)`
- 状态色：success `#30D158` / warning `#FF9F0A` / error `#FF453A` / info `#0A84FF`
- 圆角：sm 4 / md 8 / lg 12 / xl 16
- 玻璃面板：`rgba(24,24,28,0.72)` + `blur(16px) saturate(180%)`；强玻璃 `rgba(12,12,14,0.92)`
- 字体：正文 SF Pro Text/Display + PingFang SC；等宽 SF Mono

### 2. 窗口外壳

- 宽 520pt，高度随面板内容自适应（顶部固定，向下伸缩）
- 标题栏：**保持系统标题栏**（`.titled + .closable`，隐藏最小化/缩放）—— 关闭按钮原生可用（曾因 `titlebarAppearsTransparent` 导致关闭按钮不渲染，**勿回退**）。标题文字随当前 tab 变化（操作/通知/日历/通用/关于）
- 背景毛玻璃：`NSVisualEffectView` material `.hudWindow`，blending `.withinWindow`
- Tab 栏与内容之间：1px 分割线（`NSColor.separatorColor`）

### 3. Tab 栏（重点改动）

原型从「液态玻璃容器 + 玻璃激活态」改为「贴底分割线 + 底部指示线」：

- **5 个 tab**（原 4 个，新增「关于」）：操作 `sliders-horizontal` / 通知 `bell` / 日历 `calendar` / 通用 `settings` / 关于 `info`
- 每个 tab：图标 18pt + 文字 10pt，竖排居中
- 激活态：底部 2pt 琥珀金指示线 + 图标/文字琥珀金 + 背景 `rgba(245,166,35,0.08)`
- hover：`rgba(255,255,255,0.04)`
- 切换：高度 0.4s `cubic-bezier(0.32,0.72,0,1)`

⚠️ **Breaking**：现有 `tabTitles`/`tabIcons`/`builtPanels` 均为 4 元素数组（PRD §6.3 P2 越界防护）。扩到 5 个时必须同步更新所有数组与 `panelView(at:)` switch，`guard index < count` 边界检查保留。

### 4. 面板内容统一范式

所有设置面板（除「关于」）遵循 section/row 结构，**去掉卡片外框**：

- `panel-body`：padding 18/20/22
- `section`：margin-bottom 18px
- `section-title`：11px semibold，大写，字距 0.04em，ink-3 色
- `row`：flex 两端对齐，min-height 34px，padding 6px 0，底部 1px 分隔线（末行无）
- `row-label`：13px ink；`row-hint`：11px ink-3

### 4b. 控件自定义绘制铁律（Codex 上一轮做丑的根因）

> 照搬 `pages/settings-window.html` 第 9-49 行铁律块。违反即丑。

**实现铁律**
1. 所有颜色走 `LingerTheme`，禁止硬编码 `#F5A623` / 裸 NSColor
2. Switch 必须自定义绘制胶囊（36×20），**禁止** `NSButton(.switch)` 复选框 → `LingerSwitch(NSView/NSControl)`，关 `rgba(255,255,255,0.16)`、开 `amberGold`、滑块 16 白、0.2s easeInOut
3. Select 必须自定义外观（surface2 底 24pt 高 圆角 4），**禁止** NSPopUpButton 默认 bezel → `.inline` + `isBordered=false` + layer 自绘底/边框（`styleSelect`）
4. 标题栏保持系统原生（`.titled + .closable`），勿回退透明
5. 间距用 `LingerTheme.space1~6`（4/8/12/16/24/32），禁止任意值
6. 字号用 `LingerTheme.labelFont(size:)` / `timeFont(size:)`

**令牌映射**：primary `#F5A623`→`amberGold/Color.amber`；light `#FFC966`→`amberLight`；bg `#0C0C0E`→窗口底（hudWindow）；surface `#16161A`→`Color.surface`；surface2 `#1F1F25`→`Color.surface2`；ink `#F5F5F3`→`ink(.labelColor)`；ink2→`ink2`；ink3→`ink3`；line→`Color.line`；success→`stateSuccess`；info→系统链接色

**字号阶梯**：10 tab/kbd/票据label · 11 section标题/提示 · 12 控件值/select/票据value · 13 行标签 · 20 票据App名

**间距阶梯**：4→space1 · 8→space2 · 12→space3 · 16→space4 · 20→(space4+4) · 24→space5

**圆角**：4→radiusXS · 8→radiusSM · 12→radiusMD · 16→radiusLG

**关键尺寸**：窗口宽 520 · 标题栏 38 · Tab 栏 48 · 面板内边距 20H/24V · Section 间距 20 · Row 高 36 · Row padding 8 · Switch 36×20(滑块16) · Select 高 24 · Stepper 框 56×24 · Slider 轨道高4 宽160 · Kbd 20高 圆角5 · 状态点 6×6

### 5. 控件样式

- switch：36×20，圆角 full，关 `rgba(255,255,255,0.16)`，开琥珀金，滑块 16px 白
- select：高 24px，surface-2 底，1px 线边框，圆角 4px，12px 字
- stepper：56×24 数字框 + chevron-up/down
- slider：accent 琥珀金
- kbd 键帽：圆角 5px，surface-2 底，10px mono

### 6. 五个面板内容与功能关联

1. **操作**：下拉线最大长度（slider 25-75%）、最大计时时长（数字+stepper，分钟）、双轨显示（select）、时间格式（select）
2. **通知**：通知授权（绿点+管理按钮）、计时完成通知（switch）、提示音（select+switch）
3. **日历**：日历授权（绿点+管理）、目标日历（select）、写入方式（select）、默认标题（输入框+hint）、快捷预设 fn/⌃/⌥（kbd+输入框）
4. **通用**：开机自启（switch）、自动清理（select）、图标风格（select + Ring/Classic/SF Symbol 三选一选择器，选中琥珀边框）
5. **关于**：票据风格（见下）

### 7. 「关于」票据面板（全新）

暗色窗口里的白色纸张票据，视觉强对比：

- 白底 `#faf9f6` + 双层圆点纸张纹理
- 上下锯齿边：`radial-gradient` 圆形挖空，16px 间隔
- 圆角 10px，外阴影 + 内描边 0.5px
- 头部：48px 琥珀金渐变图标（圆角12）+ 「Linger」20px bold + 版本 mono 11px + slogan 12px 斜体
- 虚线分割：`repeating-linear-gradient` 4px 虚线 + 两端圆形剪刀口（挖空背景色）
- 字段键值对：label mono 10px 大写 / value 12px 深色（mono 变体 11px）
  - Developer / Blog / Email / Build / License
- 底部：感谢语 11px + mono 9px tracking
- ⚠️ 票据内文字用深色（`#1d1d1f`/`#6e6e73`/`#8e8e93`），与暗色窗口对比；锯齿/剪刀口要挖空成窗口背景色

### 8. Codex 实现步骤

1. 扩容 4→5：`tabTitles`/`tabIcons`/`builtPanels` 加第 5 元素（`"关于"` / `"info"`），`panelView(at:)` switch 加 `case 4: buildAboutPanel()`，保留边界 guard
2. 重写 `updateTabStyles()`：去掉液态玻璃激活态（`addGlassHighlight` / 玻璃底 / 高光边），改为底部 2pt 琥珀指示线 + 琥珀 `contentTintColor` + 微琥珀底；可给 tab button 加底部 indicator 子视图
3. 统一面板为 section/row 范式（去卡片框）：抽 `makeSection(title:)` / `makeRow(label:control:)` 通用助手
4. 实现 `buildAboutPanel()`：白底票据 NSView（layer 背景 + 锯齿 mask / 纹理绘制）+ 键值字段
5. 标题随 tab 切换：`selectTab` 里 `title = tabTitles[index]`
6. 所有颜色走 `LingerTheme`；票据深色文字可加 `LingerTheme.Color.ticketInk` 等令牌
7. 编译：`swift build --disable-sandbox`（`DEVELOPER_DIR` 指向 Xcode）；GUI 实机验收

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
- **反馈视图**：`DragFeedbackView.swift`（水平双轨、字号设置、橡皮筋动态增高）、
  `DragLineView.swift`（发光竖线/光点手绘）、`DragPhysics.swift`（触顶阻尼纯函数，可单测）
- **浮窗**：`HoverListView.swift`（300pt 毛玻璃列表，三组排序）、`ScheduleTimerView.swift`（预约）、
  `ToastView.swift`（居中提示）、`NotificationManager.swift`（横幅）、`SettingsWindow/AboutWindow/CalendarManager`

## 接手协议

0. **接力工具**：使用本仓库 `.agents/skills/linger-handoff/` skill（全局副本在
   `~/.codex/skills/linger-handoff/`）。Trae 等 agent 安装：把该 skill 文件夹放入其
   skills 目录（或按 Trae 导入说明），即可按 skill 的接手/跟进/交接流程执行。
1. 先读：本文件 → `pages/` 相关页 → `linger2_prd.md` 对应章节
2. UI 改动以 HTML 原型为准；引擎改动保持叶子模块纯净（可单测）
3. 改完必须能 `swift build`（`--disable-sandbox` + `DEVELOPER_DIR`），GUI 改动需实机验收
4. 每完成一个可验收里程碑：更新本文件"最新进度" + git commit（信息写清楚改了什么/为什么）
5. 不擅自改动 2.0 / 2.1 存档目录；有疑问标「待确认」，不臆造专有名词

## 已知问题

- `statusItem.view` 有 deprecation 警告（刻意为之：绕开 button 的 cell tracking loop），功能正常
- 沙箱内无法 `open` GUI app，启动验收需用户在 Codex Run 按钮 / 终端执行
