# Linger

一款 macOS 菜单栏倒计时工具：**一拉即走，松手计时**。按住菜单栏图标下拉，拉多长就计多长，松手即开始。专为「不想打开日历、不想点一堆按钮，只想快速起个倒计时」的时刻设计。

**Linger** is a countdown timer for the macOS menu bar, built around a single gesture: **pull and let go**. Hold the menu bar icon and drag downward — how far you pull is how long you get — then release to start. Made for the moments when you don't want to open Calendar or click through a stack of dialogs; you just want a timer, right now.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## 功能 · Features

**中文**

- **拖拽即计时** — 按住菜单栏图标往下拉，一条细线实时预览时长（长度可在设置中调整），松手立即开始
- **计时粒度** — 10s / 20s / 30s / 60s 四档，下拉读数按所选颗粒度步进
- **多计时器并行** — 最多 10 个同时进行，悬停图标即可纵览
- **预约日程** — 未来某时刻自动开始计时（⌘⌥L 快速呼出），到点自动激活
- **自动写入日历** — 计时结束自动记入系统日历（可选目标日历），5 分钟取整、支持自定义默认标题
- **快捷键预设** — 拖拽时按 Fn / ⌃ / ⌥ 快速套用预设时长与标题
- **可换菜单栏图标** — 4 款内置图标，设置中即选即生效
- **计时中隐藏图标** — 倒计时读数自动接管菜单栏宽度，结束干净还原

**English**

- **Drag to time** — Hold the menu bar icon and pull down; a thin line previews the duration live (its length is adjustable in Settings). Release to start immediately.
- **Timer granularity** — Four steps: 10s / 20s / 30s / 60s. The drag readout advances by the unit you pick.
- **Multiple timers at once** — Up to 10 running in parallel; hover the icon to see them all.
- **Scheduled timers** — Start counting automatically at a future moment (press ⌘⌥L to bring up the panel). They activate on schedule.
- **Automatic calendar logging** — Every finished timer is written to your system calendar (target calendar selectable), rounded to 5 minutes, with a customizable default title.
- **Shortcut presets** — While dragging, press Fn / ⌃ / ⌥ to apply a preset duration and title.
- **Swappable menu bar icons** — 4 built-in styles; pick one in Settings and it takes effect instantly.
- **Icon hides while counting** — The countdown readout takes over the menu bar width, then restores cleanly when it ends.

## 安装 · Install

**中文**

1. 从 [Releases](../../releases) 下载最新 `.dmg`
2. 打开后将 **Linger.app** 拖入 **Applications** 文件夹
3. 首次写入日历时会请求日历权限，按需允许即可

> 未签名应用：若 macOS 提示无法验证开发者，右键点 app →「打开」即可（或系统设置中允许）。

**English**

1. Download the latest `.dmg` from [Releases](../../releases).
2. Open it and drag **Linger.app** into your **Applications** folder.
3. On the first calendar write, macOS asks for calendar access — allow it as you prefer.

> Unsigned app: if macOS warns that the developer cannot be verified, right-click the app → **Open** (or allow it in System Settings).

## 从源码构建 · Build from Source

需要 Xcode 15+ 与 macOS 13+（Requires Xcode 15+ and macOS 13+）：

```bash
# 一键：编译 + 打包 .app + 启动 · Build, bundle and launch
./script/build_and_run.sh

# 发布打包（只产出 dist/Linger.app，不启动）· Release bundle (no launch)
./script/build_and_run.sh --release

# 运行测试 · Run tests
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --disable-sandbox
```

也可直接用 Xcode 打开 `Package.swift`，scheme 选 `Linger`。

You can also open `Package.swift` in Xcode and select the `Linger` scheme.

## 隐私说明 · Privacy

**中文**

- **不采集任何数据**，无遥测、无账号、无联网上报
- 日历读写仅发生在你本机，通过系统 EventKit 授权
- 后续版本的「检查更新」仅请求 GitHub Releases 公开 API 获取最新版本号

**English**

- **No data collection** — no telemetry, no account, no reporting over the network.
- Calendar reads and writes happen entirely on your Mac, gated by the system EventKit permission.
- The "Check for Updates" feature only calls the public GitHub Releases API to read the latest version number.

## 项目结构 · Project Structure

```
Sources/Linger/       # 全部源码（AppKit 原生，无第三方依赖）· All source (native AppKit, no third-party dependencies)
pages/                # UI 原型（HTML，设计唯一准绳）· HTML prototypes (the design source of truth)
Tests/LingerTests/    # 单元测试 + 布局/竞态探针测试 · Unit tests plus layout and race-condition probes
script/               # 构建打包 / DMG 制作脚本 · Build, bundle and DMG scripts
docs/                 # 设计文档（更新机制等）· Design docs (update mechanism, etc.)
```

## License

[MIT](LICENSE) · 酒后制造 Made while drunk 🍺
