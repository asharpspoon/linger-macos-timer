#!/usr/bin/env bash
# release.sh — Linger 一键发布（docs/update-design.md §3 模块 5）
# 用法：./script/release.sh
# 流程：构建 → DMG → git tag → GitHub Release（notes + dmg 附件）
#
# ⚠️ 必须在用户自己的终端运行（内部调用 make_dmg.sh，hdiutil 需访问 /dev/disk*）。
# 发布说明：若存在 docs/release-notes/v{版本}.md 则自动使用，否则弹出编辑器手写。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Linger"
# 版本号唯一真源：Sources/Linger/AppVersion.swift
APP_VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$ROOT_DIR/Sources/Linger/AppVersion.swift")"
if [[ -z "$APP_VERSION" ]]; then
  echo "❌ 无法从 AppVersion.swift 解析版本号" >&2
  exit 1
fi
TAG="v$APP_VERSION"
DMG="$ROOT_DIR/$APP_NAME-$APP_VERSION.dmg"
NOTES_FILE="$ROOT_DIR/docs/release-notes/$TAG.md"

echo "==> 发布 $APP_NAME $APP_VERSION (tag $TAG)"

# ── 前置校验 ──────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "❌ 缺少 gh CLI（brew install gh && gh auth login）" >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌ 本地已存在 tag ${TAG}。若要重发：git tag -d ${TAG} && git push origin :refs/tags/${TAG}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ 工作区有未提交改动，先 commit 再发布：" >&2
  git status --short >&2
  exit 1
fi

# ── 构建 + 打包 ──────────────────────────────────────────
echo "==> [1/4] Release 构建"
./script/build_and_run.sh --release

echo "==> [2/4] 制作 DMG"
./script/make_dmg.sh

# ── 发布 ─────────────────────────────────────────────────
echo "==> [3/4] 打 tag 并推送"
git tag "$TAG"
git push origin "$TAG"

echo "==> [4/4] 创建 GitHub Release"
if [[ -f "$NOTES_FILE" ]]; then
  gh release create "$TAG" --title "$APP_NAME $APP_VERSION" --notes-file "$NOTES_FILE" "$DMG"
else
  echo "    （未找到 ${NOTES_FILE}，将在编辑器中手写发布说明）"
  gh release create "$TAG" --title "$APP_NAME $APP_VERSION" "$DMG"
fi

echo "✅ 发布完成：https://github.com/asharpspoon/linger-macos-timer/releases/tag/$TAG"
