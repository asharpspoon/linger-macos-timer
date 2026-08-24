# Linger

一款 macOS 菜单栏倒计时工具：**一拉即走，松手计时**。按住菜单栏图标下拉，拉多长就计多长，松手即开始。专为「不想打开日历、不想点一堆按钮，只想快速起个倒计时」的时刻设计。

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## 功能

- **拖拽即计时** — 按住菜单栏图标往下拉，一条细线实时预览时长（长度可在设置中调整），松手立即开始
- **计时粒度** — 10s / 20s / 30s / 60s 四档，下拉读数按所选颗粒度步进
- **多计时器并行** — 最多 10 个同时进行，悬停图标即可纵览
- **预约日程** — 未来某时刻自动开始计时（⌘⌥L 快速呼出），到点自动激活
- **自动写入日历** — 计时结束自动记入系统日历（可选目标日历），5 分钟取整、支持自定义默认标题
- **快捷键预设** — 拖拽时按 Fn / ⌃ / ⌥ 快速套用预设时长与标题
- **可换菜单栏图标** — 4 款内置图标，设置中即选即生效
- **计时中隐藏图标** — 倒计时读数自动接管菜单栏宽度，结束干净还原

## 安装

1. 从 [Releases](../../releases) 下载最新 `.dmg`
2. 打开后将 **Linger.app** 拖入 **Applications** 文件夹
3. 首次写入日历时会请求日历权限，按需允许即可

> 未签名应用：若 macOS 提示无法验证开发者，右键点 app →「打开」即可（或系统设置中允许）。

## 从源码构建

需要 Xcode 15+ 与 macOS 13+：

```bash
# 一键：编译 + 打包 .app + 启动
./script/build_and_run.sh

# 发布打包（只产出 dist/Linger.app，不启动）
./script/build_and_run.sh --release

# 运行测试
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --disable-sandbox
```

也可直接用 Xcode 打开 `Package.swift`，scheme 选 `Linger`。

## 隐私说明

- **不采集任何数据**，无遥测、无账号、无联网上报
- 日历读写仅发生在你本机，通过系统 EventKit 授权
- 后续版本的「检查更新」仅请求 GitHub Releases 公开 API 获取最新版本号

## 项目结构

```
Sources/Linger/       # 全部源码（AppKit 原生，无第三方依赖）
pages/                # UI 原型（HTML，设计唯一准绳）
Tests/LingerTests/    # 单元测试 + 布局/竞态探针测试
script/               # 构建打包 / DMG 制作脚本
docs/                 # 设计文档（更新机制等）
```

## License

[MIT](LICENSE) · 酒后制造 Made while drunk 🍺
