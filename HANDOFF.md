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

- **2026-08-24 凌晨⑥ · 关于页定稿 + 2.5.0 发布打包（Trae）**
  - **关于页内容定稿（AboutTicketView.swift）**：
    - 头部 icon：自绘琥珀圆环 → 用户 app 图标（Support/LingerIcon-Fullbleed.png 同源，48pt 圆角 12）；资源经 SwiftPM `Resources/AboutAssets` 打包
    - 删 slogan「一拉即走，松手计时」；Version 2.5.0
    - 字段：Developer 早餐酒 / Blog 小红书链接（前置 SF Symbol book.fill 小红书红 #FF2442 icon，12pt 与文字同高）/ Email breakfastwine@agent.qq.com / Build→**Release Date 2026.08.24**（发版时更新此值）/ License 行删除
    - **Blog/Email 链接化**：新增 LinkLabel（amberDarker + 下划线 + hover 手型指针 + 按钮语义防拖出误触）：Blog 走默认浏览器、Email 走 `mailto:` 呼默认邮件 app
    - 页脚：「Made with care…/— LINGER · 2026 —」→「**酒后制造 / Made while drunk**」
  - **右键菜单**：「设置…」移到最上方（设置→预约→日历授权→退出）
  - **修复：关于页图片不显示**：`.copy` 资源在 bundle 子目录里，`url(forResource:)` 不搜子目录 → 加载静默 nil。修法：`Bundle.module.url(forResource:withExtension:subdirectory: "AboutAssets")`（与菜单栏图标同款写法）。**教训：SwiftPM `.copy` 资源目录必须带 subdirectory 参数查**
  - **发布打包（build_and_run.sh）**：新增 `--release` 模式（Release 构建 + 只打包不启动）；版本号变量化 `APP_VERSION=2.5.0`（发版改这一处，Info.plist 自动同步）。产物：**项目根目录 `Linger.app`**（Release 6.0MB，冒烟运行通过），拖入「应用程序」即装。未开发者签名（本机用 OK；外部分发需右键打开绕 Gatekeeper，正式分发需 Apple 开发者账号做 DMG+公证）
  - 验证：swift build + 全测试绿 + release 实机 pid 39807
  - **流程变更（用户指示）**：HANDOFF 不再每轮自动回填，由用户主动提醒时登记

- **2026-08-24 凌晨⑤ · 修复回归：✓/✕ 按钮「按不了」（Trae，含回归解剖）**
  - **Bug Summary [P1，凌晨④ 引入的回归]**：
    - 症状：椭圆修复（NSButton→NSView 重写）后，确认/取消按钮完全点不了
    - 根因（探针测试拿运行时证据）：CircularIconButton 覆写 hitTest 做「圆形热区」，但 **AppKit 的 hitTest(point) 传入 point 是 superview 坐标系**（文档原文 "in the coordinate system of the view's superview"），覆写直接拿它与自身 bounds 圆心比较 → 真实点击（window 自顶向下派发）全数错位 miss → 事件落到父级 NSStackView（无点击处理）→ 无反应
    - 修复（双管）：
      1. **删除 hitTest 覆写**——回到 NSView 默认方形热区（与 NSButton 语义一致）；教训已写进类注释
      2. **新增 PassThroughImageView**（hitTest 恒 nil 的 NSImageView 子类）——真实子视图 NSImageView 会截获 mouseDown 吞掉事件（NSButton 时代图片是 cell 私有绘制、非子视图，所以以前没这问题）
    - 回归测试 ClickChainProbeTests：① row3 层 hitTest 必须命中按钮本体（坐标系约定锁定）② 图标穿透恒 nil ③ 反向锚点（自身坐标直传必须 miss，防「双命中」假实现）
  - **回归解剖**：原 bug 是椭圆 → 我用「自定义 hitTest 圆形热区」过度设计修外观 → 引入坐标系 bug。**预防**：外观问题用默认热区即可（26×26 方形 vs 圆形热区视觉无感）；覆写 hitTest 前必须先写坐标系约定测试
  - **AppKit 知识沉淀（给下一位，Rule 7）**：hitTest(point) 的 point 是 superview 坐标系——测试正确姿势 `button.convert(center, to: superview)` 后再调 `superview.hitTest(...)`；直传 `button.hitTest(自身坐标)` 是 miss（可用作负例锚点）
  - 验证：swift build + 全测试绿（新增 3 组断言）+ dist 实机 pid 37186

- **2026-08-24 凌晨④ · 全局快捷键 + 椭圆按钮根治（Trae）**
  - **本批完成（swift build 通过，全测试绿含新回归测试，dist 实机 pid 35475）**：
    1. **全局快捷键（Carbon RegisterEventHotKey，常驻）**：⌘, → 打开设置；⌘⌥L → 预约日程（openScheduleEntry）。installGlobalHotKeys() 在 MenuBarManager.init 调用，一个 EventHandler 按 EventHotKeyID.id（2/3，signature "LNGR" 与 Esc 热键同族不同 id）分发，回调 dispatch 到主线程。热键路径 showSettings 前 NSApp.activate（后台触发需激活才带到前台）。右键菜单同步显示快捷键（keyEquivalent 纯展示，实际触发力是 Carbon）
    2. **椭圆按钮根治**：用户报 ✓/✕ 仍是椭圆。写布局探针测试拿运行时证据：NSButton 的 width==26/height==26 约束均 active，但最终 frame 26×29/26×31（无约束冲突日志）——NSButton cell 在 NSStackView 中的内部高度行为强吃 required 约束。**修复：CircularIconButton 从 NSButton 改为 NSView**（照抄 CalendarPulseButton 已验证模式）：layer 实底 + 居中 NSImageView + trackingArea hover + mouseDown onClick + hitTest 限定正圆内命中。target/action → onClick 闭包（@objc 方法保留，传 () 兜 Any 参数）。探针升级为正式回归测试 ButtonShapeProbeTests（断言 26×26 正方形 + 不溢出行边界）
  - **给下一位的提示**：
    - Carbon 全局热键会**系统级遮蔽**其他 app 的同组合键：⌘, 在 Safari 等前台 app 中会打开 Linger 设置而非该 app 偏好设置；⌘⌥L 会遮蔽 Finder「下载」文件夹快捷键。用户明确要求这两个组合，属预期行为，若反馈冲突需评估换键
    - NSButton 尺寸被 cell 侵蚀的坑（约束 active 但 frame 不符、无冲突日志）已写入 CircularIconButton 头注释，别改回 NSButton
    - CircularIconButton 的 hitTest 只认正圆内命中（27×27 方形四角点击会穿透到父视图），这是有意的

- **2026-08-24 凌晨③ · 修复：右键预约→取消后悬浮窗永久留存（Trae）**
  - **Bug Summary [P2]**：
    - 症状：右键「预约日程…」→ 点取消 → 悬浮面板永久留存桌面，鼠标移走也不关
    - 根因：关闭链路完全依赖 trackingArea exit 事件，右键路径下两个事件源**都丢事件**——
      ① icon 侧：NSMenu.popUp 是 tracking session，鼠标「离开 icon 进入菜单」的 mouseExited 被吞，菜单关闭后 AppKit 不补发；
      ② 面板侧：点取消 → 编辑区收回 → 面板 frame 手动动画缩小把鼠标「甩出」rect，AppKit 对 rect 变化类不保证派发 exit
    - 修复（双管齐下）：
      1. **openScheduleEntry 改走 handleHoverEntered()**（用户建议的「模拟 hover」）：与鼠标悬停完全同一入口/状态机，面板已开只刷新，不再死板 showHoverList + 手动 lock
      2. **鼠标看门狗**（根治兜底）：showHoverList 启动 0.5s 轮询 timer，hideHoverListNow 停止；tick 判定鼠标既不在面板 frame 也不在 icon frame（8pt 缓冲）→ 走既有 scheduleHoverHideCheck（0.3s 宽限内滑回可救）。isScheduling 展开期间豁免——NSDatePicker 系统日历弹层在面板外，防误杀
    - 验证：swift build + 全测试绿 + dist 实机 pid 32823；实机路径：右键预约→取消→鼠标移开→面板应在 ~0.8s 内收起
  - **给下一位的提示**：hoverWatchdogTimer 是兜底层不是替代层，面板/icon 的 trackingArea 事件链保持原样未动；同类「面板关不掉」问题（快速滑过、frame 动画）从此免疫，无需再逐个排查

- **2026-08-24 凌晨② · 日程预约模块 5 项（Trae）**
  - **本次完成（swift build 通过，全测试绿，dist 实机运行 pid 31848）**：
    1. **右键直达预约**：右键菜单第一项「预约日程…」→ openScheduleEntry：无面板先 showHoverList（含空态）→ hoverListView.expandScheduleDirectly()（HoverListView 新公开方法，scheduleView 已存在则不动作）→ hoverIsLockedOpen=true（与悬停进入同语义，关闭判定由面板 trackingArea 接管）
    2. **悬浮框不透明度加强**：HoverDesign.panelBg alpha 0.72 → 0.92（用户：背后窗口文字干扰；玻璃质感减弱但保留一丝通透）
    3. **预约时间校验（bug）**：confirmTapped 里 resolveStartDate() < Date() 时钳制到当前时刻并回写 datePicker/timePicker（所见即所得，创建即开始）。没用 NSDatePicker.minDate——timePicker 只读时分、与 datePicker 日期正交组合，minDate 会把「先选明天 09:00 中的 09:00」误拦
    4. **预约态隐藏空态提示**：draw() 空态分支加 !isScheduling 判定（「暂无计时器」之前挡住输入区）
    5. **勾/叉正圆按钮**：新增 CircularIconButton（NSButton 子类，实底圆 + SF Symbol + hover 提亮换底色，layout 时 cornerRadius=min(w,h)/2 恒正圆）。确认 = 琥珀圆 26pt + check（hover amberLight）；取消 = surface2 圆 + ×（hover line 色；此前是裸 × 悬浮无底，观感差的根因）。尺寸 24 → 26
  - **给下一位的提示**：
    - CircularIconButton 是 ScheduleTimerView.swift 文件内 private 类，若其他面板要复用需提为 internal
    - 右键菜单时序：NSMenu.popUp 阻塞至菜单关闭，action 触发时菜单已消失 → openScheduleEntry 弹面板无冲突
    - panelBg 是整个 hover 面板共用（非预约态专属），不透明度调整对普通悬停列表同样生效

- **2026-08-24 凌晨 · 「写入方式」选择器隐藏，统一自动（Trae）**
  - 用户结论：auto/ask/manual 三种模式实际体验没区别，要求隐藏选择器、默认全用自动
  - 改动：
    1. SettingsWindow 日历 section 移除 buildWriteModeRow() 行（方法与 writeModeChanged action 保留，想恢复加回即可，与通用页隐藏三行同模式）
    2. CalendarManager.init 归一：writeMode != .auto 时 setWriteMode(.auto)（否则 UI 藏了残留 ask/manual 永远改不回来）
    3. 默认标题输入框原 isEnabled 绑定 writeMode==.auto，改为恒可用；hint 从「仅在自动写入模式下使用」改为「计时完成后自动写入时使用的标题」
  - 行为变化：所有拖拽计时归零即自动写入（默认标题兜底）；完成横幅输入标题仍走 recordFromBanner 的「更新已有事件标题」分支（不重复建事件）；hover 编辑标题对已记录条目只改显示标题
  - 编译 + 全测试绿 + dist 实机运行（pid 30287）

- **2026-08-23 深夜⑤ · 菜单栏图标换矢量 PDF（解决模糊）（Trae）**
  - 用户重新导出了 4 个图标为 PDF 矢量（旧 PNG 18×18 位图在高分屏发虚）。已完成替换：
    - Resources/MenuBarIcons/ 删 4 个 PNG 进 4 个 PDF（Jump_time_fill/Ring/Desk_fill/Import_fill.pdf）
    - loadImage 扩展名 png → pdf，NSImage(contentsOf:) 原生支持 PDF 矢量
    - 已验证：4 个 PDF 均为 36×36 正方形画板、NSPDFImageRep 纯矢量（pixelsWide=0）、内容纯黑+alpha（标准 template，深浅模式自适应）；渲染 18pt 时矢量缩放 Retina 无损
  - 编译 + 全测试绿 + dist 实机运行验证（pid 28051）；Package.swift 无需改（.copy 整目录）

- **2026-08-23 深夜④ · 菜单栏图标 4 项调整 + 计时粒度 + 通用页精简（Trae）**
  - **本次完成（swift build 通过，全测试绿，dist 实机运行验证）**：
    1. **图标加大**：16 → 18pt（素材原生分辨率 18×18，对齐微信/企业微信菜单栏规格；LingerStatusItemView.iconSize + loadImage 尺寸同步改）
    2. **下拉显示英文**：displayName 改 Jump/Ring/Desk/Import
    3. **默认图标 Jump_time_fill**：`MenuBarIconStyle.current` 回退 .jump，allCases 顺序 jump 第一。注意：用户昨天测试若手动选过图标，defaults 里已有旧值（com.linger.app 域 linger_iconStyle），需手动切回 Jump 或 `defaults delete com.linger.app linger_iconStyle`
    4. **倒计时只显示时间**：LingerStatusItemView 新增 applyDisplayMode —— title 非空（含拖拽预览）→ 图标隐藏 + iconWidthConstraint 收拢为 0 + 宽度=6+文字；title 空（空闲）→ 只显示图标（24pt）。intrinsicContentSize 按模式计算，statusItem.length 经 onContentWidthChanged 同步 → 无残留空白
    5. **计时粒度（设置-通用新行）**：`linger_timerGranularity`（10/20/30/60s，默认 60）。TimerEntry.duration 新增 granularity 参数：raw=p²×maxSeconds 后吸附到粒度整数倍，最小仍 1 分钟；pollDrag/finishDrag 双调用点接入；snapToMinuteIfClose 保留（阈值 5s < 粒度最小间隔 10s，不冲突）。单测 testDurationGranularity 覆盖
    6. **通用页精简**：「自动清理」「日历归档导出」「导出目录」三行暂隐藏（用户：还没想好怎么做），后端 + @objc action 全保留
  - **给下一位的提示**：
    - 显示模式切换在 setTitle→applyDisplayMode（视图自治），Manager 无需感知；icon 切换通知只 setIcon，倒计时中换图标会在计时结束后生效显示
    - 粒度吸附在 duration 纯函数内（WYSIWYG：预览与松手同一条链路）；粒度选项数组 [10,20,30,60] 在 SettingsWindow 和 TimerEntry 测试两处硬编码，改选项要同步
    - 最小计时仍是 1 分钟（与 2.1 一致），粒度只影响步进不影响下限

- **2026-08-23 深夜③ · 菜单栏图标可选 + 宽度自适应修复 + 新 app 图标（Trae）**
  - **本次完成（swift build 通过，全测试绿，dist 实机运行验证）**：
    1. **菜单栏图标可选（设置-通用第一行）**：NSPopUpButton 下拉项带图标预览（NSMenuItem.image），4 个风格全部用用户提供的 18×18 template PNG（Desk_fill/Import_fill/Jump_time_fill/Ring，已验证纯黑+透明，isTemplate=true 深浅自适应）；资源走 SwiftPM `.copy("Resources/MenuBarIcons")` → Linger_Linger.bundle，build_and_run.sh 拷进 app Resources；选择即生效（NotificationCenter lingerMenuBarIconDidChange 热更新，无需重启）；复用既有 `linger_iconStyle` key（raw: ring/desk/import/jump，`import` 是关键字故枚举名 importIcon）；资源缺失回退自绘 Ring
    2. **宽度自适应修复（bug：倒计时→图标 切换后菜单栏留大片空白）**：根因是 AppKit 对「variableLength + custom view」只在内容变宽时自动跟随 intrinsicContentSize，变窄不缩回。修法：LingerStatusItemView.setIcon/setTitle 后回调 onContentWidthChanged → MenuBarManager 手动同步 statusItem.length（双向生效，带 0.5pt 去抖）
    3. **新 app 图标**：用户的 Linger_icon（PSD 824×833）sips 转 PNG 替换 Support/LingerIcon-Fullbleed.png，打包脚本自动生成 icns（旧图标在 git 历史）
    4. 显示逻辑（沿既有行为）：无计时 = 纯图标；有计时 = 图标 + 最近一个倒计时读数
  - **给下一位的提示**：
    - SwiftPM 资源新增流程：Sources/Linger/Resources/ 下放文件 → Package.swift `.copy(...)` → build_and_run.sh 已有通用拷贝逻辑（BUILD_BIN_PATH/Linger_Linger.bundle → Contents/Resources）→ 代码用 `Bundle.module.url(forResource:withExtension:subdirectory:)` 读
    - MenuBarIconStyle 枚举定义在 MenuBarManager.swift 顶部（文件级），SettingsWindow 直接复用其 displayName/loadImage
    - statusItem.length 手动同步是 custom view 动态宽度的唯一可靠方案，intrinsicContentSize 双向自动跟随不可信

- **2026-08-23 深夜② · 假授权诊断修复（日志实锤）+ 授权行 UI 3 项（Trae）**
  - **日志关键证据（用户提供 20260823 日志.md）**：`RIGHTCLICK bundleID=nil status=0 granted=1 hasAccess=1` + `EKCADErrorDomain Code=1013 "Access denied"` —— 进程是**裸二进制**（无 .app bundle，可能是 swift run / 直接跑 .build/debug/Linger），TCC 归因失效；`grantedByRequest=1` 是 UserDefaults 历史残留**假授权标记**（旧二进制授权记录，新二进制身份变化后 TCC 不认）→ UI 显示「已授权」但 EventKit 实际拒绝。这解释了「以前版本都对」——以前是打包 .app 跑的
  - **本次完成（swift build 通过，全测试绿）**：
    1. **CalendarManager.resetAuthorization()**：清 grantedByRequest 假标记（发通知刷新 UI）→ 重新走 requestPermissionIfNeeded（notDetermined 触发系统弹窗 / denied 弹 NSAlert 引导系统设置）
    2. **裸二进制警告**：init 时 bundleID=nil 打 error 日志提示用 build_and_run.sh 打包运行；availableCalendars 检测「granted=true 但 0 日历 + defaultCalendarForNewEvents=nil」打假授权警告（不自动重置，防 store 未就绪误判）
    3. **UI（用户 3 项需求）**：① 授权状态去掉左侧绿点只留 ✓/⚠（删 makeStatusDot/makeAuthStatusView/calAuthDot 死代码）② 「管理…」→「管理授权」（未授权分支仍「去授权…」）③ 授权行新增循环 icon 按钮（SF Symbol arrow.triangle.2.circlepath，tooltip「重置授权并重新申请」）→ resetCalAuthorization action
    4. **顺带修**：makeBetaBadge label 缺 translatesAutoresizingMaskIntoConstraints=false 导致的约束冲突（日志刷屏 "Will attempt to recover by breaking"）；os_log 宏内不能用隐式字符串拼接（编译错误）
  - **待实机验收（关键）**：**必须用 `./script/build_and_run.sh` 启动（打包 .app）**，不要 swift run；启动后设置 → 日历 → 点循环按钮 → 系统弹授权窗 → 允许 → 下拉应显示真实日历。裸二进制下 TCC 每次构建漂移，重置授权也救不了
  - **给下一位的提示**：
    - 假授权判定三要素：bundleID=nil（裸跑）+ status=0 + granted=1；真授权失败证据是 EKCADError 1013 Access denied
    - `grantedByRequest` 持久化标记是双刃剑：解决裸 bundle 下 status 恒 notDetermined 的问题，但二进制身份漂移后变假阳性 —— 重置按钮就是为此设计的逃生门
    - os_log 第一个参数必须是单个字符串字面量，不能隐式拼接多段

- **2026-08-23 深夜 · 3 bug 修复：时间映射跟随线长 / EventKit 异步加载 / 零时长事件（Trae）**
  - **背景**：用户实机验收发现 3 个 bug（日志被 TRAE 沙箱拦截无法直读，靠代码审查定位）
  - **本次完成（swift build 通过，全测试绿）**：
    1. **Bug「线拉长时间不变」**：根因 `TimerEntry.duration` 是固定物理刻度（40px=1min²），与线长无关 → 滑块调长线后时间在旧刻度处封顶。重设计为**归一化映射**：`p = px/lineMaxLength`，`minutes = round(p² × maxMinutes)`，拉满线=最大时长（WYSIWYG）。新增纯函数 `DragPhysics.dragLineFraction(percent:)`（0→25%屏高、100→75%），`DragFeedbackView.show()`（渲染线长）与 `MenuBarManager.currentDragLineMaxLength()`（映射分母）共用同一函数保证一致；duration 签名改为 `(fromDragDistance:lineMaxLength:maxSeconds:)`，单测重写为新语义（含「线更长同一距离时间更短」「拉满任意线长=最大时长」）
    2. **Bug「计入日历下拉读不到日历」**：根因 **EKEventStore 数据库异步加载**——授权回调/启动后立即查 `calendars()`/`sources` 可能返回空（2.0 恰好没踩到时序）。修复：CalendarManager init 监听 `.EKEventStoreChanged`（数据库就绪/变更时发 `lingerCalendarAccessDidRefresh` → 设置页重建下拉）；`availableCalendars()` 加诊断日志（数量+标题列表）
    3. **Bug「写入日历后日历里没有」**：三重修复：① 同根源②——store 未就绪时 `findOrCreateCalendar` 找不到 source 写入失败，CalendarRecorder.writeCompletion 失败后延迟 1.5s 重试一次；② **零时长事件**：短计时（<5min）双端 5 分钟向上取整后 start==end（如 14:02→14:03 均取整 14:05）→ 日历里不可见，现保证最小 5 分钟块；③ writeEvent 成功日志带起止时间（对账用）
  - **待实机验收**：滑块 0/50/100 三档，拉满线应分别=最大时长；打开设置看下拉列表（store 就绪后应显示真实日历）；跑一次短计时（1-2 分钟）→ 日历 app 检查「Linger」日历（**注意左侧栏勾选**，本地日历默认可能未勾选）
  - **给下一位的提示**：
    - TRAE RunCommand 沙箱拦截 `/usr/bin/log`（"Cannot run while sandboxed"），读统一日志需用户跑 `./script/build_and_run.sh --logs`
    - 时间映射分母在 `MenuBarManager.currentDragLineMaxLength()`，与 `DragFeedbackView.show()` 必须同步改（WYSIWYG 铁律）
    - EventKit 异步加载是 macOS 常见坑：授权回调 granted=true ≠ 数据库就绪，写入/查询前需容错（重试或等 EKEventStoreChanged）

- **2026-08-23 晚 · 设置窗口 4 项修复：拖拽线映射 / 计入日历下拉 / Beta 标签（Trae）**
  - **本次完成（swift build 通过，swift test 21/21 绿）**：
    1. **拖拽线最大长度修复（bug：调了没反应）**：真凶是 `DragFeedbackView.show()` 里 `min(syncDistance, percentLimit)` —— syncDistance（由最大时长算出的物理距离，如 10 分钟 ≈ 126pt）恒压制百分比，滑块怎么调都被卡死。现改为滑块 0-100 线性映射到屏幕可见高度 **25%-75%**（0 → 25%，100 → 75%，默认 50%），彻底移除 syncDistance 约束；`currentDragLinePercent()` 同步修复（旧版把合法值 0 兜底成 50）
    2. **「目标日历」→「计入日历」**：label 文案更新
    3. **计入日历改回下拉菜单**：读 `CalendarManager.availableCalendars()`（日历 app 中用户已创建的可写日历），Linger 固定第一项（默认，写入时自动创建），其余按系统顺序去重；`CalendarManager` 暴露 `targetCalendarTitle`（无效选择回退 Linger）；授权变更通知 + 窗口 orderFront 时重建选项
    4. **(Beta) 文字改胶囊标签**：`makeBetaBadge()`（10pt medium ink2 + surface2 底 + line 边框 + 8pt 全圆角，高 16）；`makeSection`/`makeRow` 各加 badge 参数，「快捷键预设」「默认标题」两处挂载
  - **待实机验收**：拖拽线滑块 0/50/100 三档线长明显不同；计入日历下拉能看到日历 app 已有日历并可选择写入；Beta 胶囊渲染正常
  - **给下一位的提示**：
    - 拖拽线长度映射在 `DragFeedbackView.show()`（`fraction = 0.25 + p/100 * 0.5`），不要再把 `DragPhysics.lineMaxDistance` 约束加回来（那就是本次 bug 根源；该函数仅剩单测引用）
    - 计入日历下拉选项重建入口：`rebuildTargetCalendarOptions(_:)`，授权后 `lingerCalendarAccessDidRefresh` 通知自动触发
    - 时间映射（s=d² + maxSeconds 钳制）未动：滑块只控制线的视觉长度上限；若后续要求「拉满线 = 拉满最大时长」需改 `TimerEntry.duration` 纯函数 + 单测

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
- [x] **拖拽线最大长度 0-100 → 屏高 25%-75% 映射（修复调了不变 bug）**（2026-08-23 晚）
- [x] **「目标日历」→「计入日历」+ 下拉读真实日历列表（默认 Linger）**（2026-08-23 晚）
- [x] **(Beta) 文字改胶囊标签（快捷键预设 section / 默认标题 row）**（2026-08-23 晚）
- [x] **时间映射归一化：拉满线=最大时长（WYSIWYG）**（2026-08-23 深夜）
- [x] **菜单栏图标可选（4 款 template PNG 带预览热切换）+ 状态栏宽度自适应修复 + 新 app 图标**（2026-08-23 深夜③）
- [x] **图标 18pt + 英文名 + 默认 Jump + 倒计时纯时间显示 + 计时粒度（10/20/30/60s）+ 通用页隐藏三个未定稿行**（2026-08-23 深夜④）

### 待验收 / 待办
- [ ] **图标 + 粒度实机验收**：菜单栏图标大小接近微信规格；下拉显示 Jump/Ring/Desk/Import（默认 Jump）；倒计时进行中只显示时间（无图标）、结束后图标回归且无空白残留；计时粒度切 10 秒后拖拽读数按 1:10 步进（2026-08-23 深夜④）
- [ ] **拖拽线滑块实机验收**：0 / 50 / 100 三档线长明显不同（25% / 50% / 75% 屏高）（2026-08-23 晚）
- [ ] **计入日历下拉实机验收**：下拉列表显示日历 app 已有日历、可选择、计时完成后写入所选日历（2026-08-23 晚）
- [ ] **Beta 胶囊标签实机验收**：日历页「快捷键预设」「默认标题」旁胶囊渲染正常（2026-08-23 晚）
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
