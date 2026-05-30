#!/bin/bash
# test_install_plugin_version.sh — Issue #764: plugin.json は利用者 repo に配布しない
#
# install.sh が利用者 (consumer) repo に .claude-plugin/plugin.json を配置しないことを検証する。
# プラグイン消費側は ~/.claude/plugins/cache/ から読むため、利用者 repo にマニフェストは不要
# (#700/#737/#744 の plugin native 化で利用者 repo にプラグイン実体が無くなったため)。
#
# vibecorp 自身の .claude-plugin/plugin.json (Source of Truth) は開発元の必須マニフェストとして
# git 管理下で保持される — その version フィールド存在は前提として確認する。
#
# 旧不変条件 (Issue #540: consumer 側 version が SoT と一致) は #764 で廃止された
# (そもそも consumer に配らなくなったため)。
#
# 使い方: bash tests/test_install_plugin_version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

SOT_PLUGIN="${SCRIPT_DIR}/.claude-plugin/plugin.json"

# 前提: SoT が存在し、version フィールドを持つ (開発元の必須マニフェスト)
if [[ ! -f "$SOT_PLUGIN" ]]; then
  fail "SoT (.claude-plugin/plugin.json) が存在しない"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "jq が必要です"
  exit 1
fi

SOT_VERSION="$(jq -r '.version // ""' "$SOT_PLUGIN")"
if [[ -z "$SOT_VERSION" ]]; then
  fail "SoT plugin.json に version フィールドがない"
  exit 1
fi

# ============================================
echo ""
echo "=== Plugin.json 利用者非配布テスト (Issue #764) ==="
# ============================================

# --- A. --name 初回 install: consumer 側 plugin.json が配置されない ---

echo ""
echo "--- A. 初回 install で consumer に plugin.json が配置されない ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_not_exists "consumer 側 .claude-plugin/plugin.json が配置されない" "${R}/.claude-plugin/plugin.json"

cleanup
TMPDIR_ROOT=""

# --- B. --update 再実行: consumer 側 plugin.json が配置されないまま ---

echo ""
echo "--- B. --update 再実行でも consumer に plugin.json が配置されない ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# --update を実行
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_not_exists "--update 後も consumer に plugin.json が配置されない" "${R}/.claude-plugin/plugin.json"

cleanup
TMPDIR_ROOT=""

# --- C. preset full でも consumer に plugin.json が配置されない ---

echo ""
echo "--- C. preset full でも consumer に plugin.json が配置されない ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full --language ja 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_not_exists "preset full でも consumer に plugin.json が配置されない" "${R}/.claude-plugin/plugin.json"

cleanup
TMPDIR_ROOT=""

print_test_summary
