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

### 5. 控件样式

- switch：36×20，圆角 full，关 `rgba(255,255,255,0.16)`，开琥珀金，滑块 16px 白
- select：高 22px，surface-2 底，1px 线边框，圆角 4px，12px 字
- stepper：22×56 数字框 + chevron-up/down
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
