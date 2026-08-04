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

- _（暂无交接记录，2026-08-04 由 Codex 建立项目）_

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
- [x] **拖拽预览第七轮（Esc 断线改为「灯绳拉断」物理感特效）**：
      - 搜 GitHub 无现成 macOS 灯绳断裂动画（只有通用动画/物理引擎，引入过重）→ 按物理原理自绘
      - 特效：张力高频颤动 → 断口颈缩 1pt 细丝 + 纤维毛刺 → 啪断 → 上段弹回菜单栏、
        下段带圆点重力坠出 + 尾部钟摆甩动 + 碎屑飞散，0.55s 后淡出
      - 修坠落方向 bug（原来画成向上掉）；时长 0.4 → 0.55s
- [x] **纯逻辑单测接入 `swift test`**（DragPhysics 变细/同步公式、TimerEntry 格式、布局防遮挡，共 12 个，全绿）
- [ ] **待真机验收 v6**：灯绳拉断特效观感（张力颤动/颈缩/啪断/坠出/碎屑）、触顶拉长变细、是否还闪帧（用户实机确认中）
- [ ] 按原型逐页对齐：hover-list（悬停列表）、toast、settings×4、about、schedule-timer、notification
- [ ] 通知/日历权限、预约计时、图标三风格（Ring/Classic/timer）

## 最近交接（2026-08-04 下午 · 拖拽预览第七轮）

**本次完成**
- Esc 断线 → 「灯绳拉断」物理特效（`DragLineView.draw`，breakProgress 驱动）：
  张力颤动（sin 高频、振幅衰减）→ 断口颈缩细丝 + 纤维 → 啪断（上弹 6pt/下坠 6pt）→
  上段 easeOut 缩回菜单栏、下段平方加速坠出 + 钟摆甩尾 + 3 颗碎屑飞散 → 55% 后淡出
- 时长 0.55s；防闪帧 `isBreaking` 锁保留
- GitHub 检索结论：无现成 macOS 灯绳断裂动画库，物理元素均为自绘
- `swift build` 通过、`swift test` 12/12 绿

**未完成 / 卡点**
- 实机验收：灯绳拉断观感（重点看颤动/颈缩/啪断节奏）、触顶拉长变细、闪帧

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
- 灯绳断裂特效在 `DragLineView.draw`：breakProgress 分段（0.15 前张力颤动+颈缩、之后啪断坠落+碎屑+钟摆）；`isBreaking` 锁防拖拽帧干扰
- 断线时长 `DragFeedbackView.animateBreak`（0.55s）；坠落方向是 y 减小（向下），别写反
- **别再让字号弹跳动画的对侧从 >1 起跳**（会盖字），见 `animateFontPop`
- label frame 留 padding（前缀 +2 / 数字 +4），文字不贴右缘
- 断线动画：`DragFeedbackView.animateBreak` + `MenuBarManager.cancelDrag(animated: true)`
- 橡皮筋纯函数在 `DragPhysics.swift`（Foundation-only，可单测）；面板随溢出向下生长在
  `DragFeedbackView.update()`（顶部固定）
- 提示次数计数在 `MenuBarManager.finishDrag(with:)` 成功后 +1；改阈值看 `LingerTheme.maxDragHintShownCount`
- 字号设置键 `linger_dragPreviewFontSize`（18–30，默认 22）；面板宽度 `requiredPanelWidth()` 自适应
- 状态栏 `statusItem.view` deprecation 警告是刻意为之，勿改

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
