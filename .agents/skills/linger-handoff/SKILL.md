---
name: linger-handoff
description: Linger 2.5 项目接力编程与交接协议。当用户要求继续/接手/接力 Linger 的开发工作、按 HANDOFF.md 跟进或更新进度、或将工作交接给其他 agent（Trae/Codex/WorkBuddy）时使用。核心：先读 HANDOFF.md → 按规则干活 → 更新进度并 git 提交 → 写交接说明。
---

# Linger 2.5 接力编程 & 交接协议

本 skill 让任意 agent（Codex / Trae / WorkBuddy / 新会话）接手或交接 Linger 2.5 开发工作。
**项目当前状态以项目内 `HANDOFF.md` 为权威**，本文件只规定"怎么接力"。

## 项目位置与准绳

- 项目根：`/Users/dawang/Downloads/vibecoding/Linger2.5/`
- 接手必读（按顺序）：
  1. `HANDOFF.md` —— 最新进度 + 接手协议（**第一入口**）
  2. `pages/` 相关 HTML 原型 —— UI 唯一准绳
  3. `linger2_prd.md` 相关章节 —— 功能需求
  4. `phase1-architecture-blueprint.md` —— 架构/设计令牌
- 铁律：UI 以 HTML 原型为准；与旧代码/蓝图冲突时，**原型优先**。

## 接手流程

1. **读**：先读 `HANDOFF.md` 全文 + 本次任务相关的原型页 / PRD 章节。不凭记忆、不臆造。
2. **环境**：构建必须用完整 Xcode 工具链（xcode-select 可能仍指向 CommandLineTools）：
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   swift build --disable-sandbox
   ```
   一键运行：`./script/build_and_run.sh`（kill + build + 打 .app + 启动；支持 `--logs` / `--verify`）。
   Xcode 方式：直接打开 `Package.swift`，scheme 选 `Linger`。
3. **干活约束**（详见 `references/linger25.md`）：
   - 设计令牌一律走 `LingerTheme`，禁止硬编码 `#F5A623` / 裸 NSColor
   - 引擎层（`TimerEntry` / `TimerManager`）保持 Foundation-only 纯净（可单测）
   - 状态栏用 `LingerStatusItemView` 自定义视图（吞 mouseUp 老 bug 的根治方案，**勿回退**到 `button.sendAction(on:)`）
4. **验证**：改动必须能编译通过；GUI 改动需实机验收（沙箱内无法 `open` GUI，需用户在 Codex Run 按钮 / 终端执行）。

## 持续跟进（每个里程碑后必做）

1. 更新 `HANDOFF.md`「最新进度」：勾选完成项 `[x]`、新增待办，**不删历史**。
2. `git add -A && git commit`，信息写清「改了什么 / 为什么」。
3. 进度更新与代码改动分开 commit 更清晰。

## 交接（交回用户或其他 agent 时必写）

在 `HANDOFF.md`「最近交接」追加一段，包含：
- **本次完成**：功能/修复清单（一句话一条）
- **未完成/卡点**：卡在哪、原因
- **下一步**：下一位该做什么（按优先级）
- **如何验证**：跑什么命令 / 看什么现象
- **给下一位的提示**：易踩的坑、关键决策位置

## 边界

- 不碰 `../Linger2.0` / `../Linger2.1` 存档目录（已失败，只读，勿回改）。
- 不臆造专有名词 / 设计决策；有疑问标「待确认」。
