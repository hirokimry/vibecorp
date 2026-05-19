#!/bin/bash
# check-plugin-version-bump.sh — plugin.json bump 漏れ自動検知
#
# Issue #458: PR で .claude-plugin/marketplace.json の plugins[0].skills が変化したのに
# .claude-plugin/plugin.json の version が bump されていない場合に警告する。
# PR #459 で発生した「新スキル 3 件追加したのに plugin.json を 0.2.0 のまま放置」事象の再発防止。
#
# 使い方:
#   bash scripts/check-plugin-version-bump.sh <BASE_REF> <HEAD_REF>
#
# 終了コード:
#   0 — 問題なし（skills 不変、または skills 変更ありかつ version bump あり、または marketplace.json 不在）
#   1 — 警告（skills 変更ありかつ plugin.json version 不変）
#   2 — 引数不足・前提コマンド不在等のエラー

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "使い方: bash scripts/check-plugin-version-bump.sh <BASE_REF> <HEAD_REF>" >&2
  exit 2
fi

BASE_REF="$1"
HEAD_REF="$2"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq が必要です" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "❌ git が必要です" >&2
  exit 2
fi

MARKETPLACE_PATH=".claude-plugin/marketplace.json"
PLUGIN_PATH=".claude-plugin/plugin.json"

# ref に当該パスが存在しない場合は空文字を返す（base / head 片側不在を許容するため）
git_show_or_empty() {
  local ref="$1"
  local path="$2"
  if git cat-file -e "${ref}:${path}" 2>/dev/null; then
    git show "${ref}:${path}"
  else
    echo ""
  fi
}

base_marketplace=$(git_show_or_empty "$BASE_REF" "$MARKETPLACE_PATH")
head_marketplace=$(git_show_or_empty "$HEAD_REF" "$MARKETPLACE_PATH")

# plugin リポではない / 初期化前は marketplace.json が片側に無いため graceful skip する
if [[ -z "$base_marketplace" || -z "$head_marketplace" ]]; then
  echo "✅ marketplace.json が base / head のいずれかに存在しないため、チェックをスキップします"
  exit 0
fi

base_skills=$(echo "$base_marketplace" | jq -c '.plugins[0].skills // []')
head_skills=$(echo "$head_marketplace" | jq -c '.plugins[0].skills // []')

if [[ "$base_skills" == "$head_skills" ]]; then
  echo "✅ marketplace.json の plugins[0].skills に変更なし"
  exit 0
fi

base_plugin=$(git_show_or_empty "$BASE_REF" "$PLUGIN_PATH")
head_plugin=$(git_show_or_empty "$HEAD_REF" "$PLUGIN_PATH")

if [[ -z "$base_plugin" || -z "$head_plugin" ]]; then
  echo "✅ plugin.json が base / head のいずれかに存在しないため、チェックをスキップします"
  exit 0
fi

base_version=$(echo "$base_plugin" | jq -r '.version // ""')
head_version=$(echo "$head_plugin" | jq -r '.version // ""')

if [[ -z "$base_version" || -z "$head_version" ]]; then
  echo "✅ plugin.json に version フィールドが見つからないため、チェックをスキップします"
  exit 0
fi

if [[ "$base_version" != "$head_version" ]]; then
  echo "✅ skills 変更ありかつ plugin.json version が ${base_version} → ${head_version} に bump 済み"
  exit 0
fi

{
  echo "⚠️ marketplace.json の plugins[0].skills が変更されているが、plugin.json の version (${base_version}) が bump されていません。"
  echo "   利用者は新しいスキルを取得するために version bump を必要とします。"
  echo "   PR #459 と同種の取りこぼしを防ぐため、.claude-plugin/plugin.json の version を更新してください。"
} >&2
exit 1
