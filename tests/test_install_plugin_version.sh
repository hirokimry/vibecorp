#!/bin/bash
# test_install_plugin_version.sh — Issue #540: plugin.json drift 防止
#
# install.sh が consumer に配布する .claude-plugin/plugin.json の version が、
# vibecorp 自身の .claude-plugin/plugin.json (Source of Truth) と完全一致することを検証する。
#
# 重複 SoT (templates/claude-plugin/plugin.json) によるダウングレード再発を防ぐ
# 不変条件テスト。
#
# 使い方: bash tests/test_install_plugin_version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

SOT_PLUGIN="${SCRIPT_DIR}/.claude-plugin/plugin.json"

# 前提: SoT が存在し、version フィールドを持つ
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

extract_version() {
  local file="$1"
  jq -r '.version // ""' "$file"
}

# ============================================
echo ""
echo "=== Plugin version SoT 一致テスト (Issue #540) ==="
# ============================================

# --- A. --name 初回 install: consumer 側 plugin.json が SoT version と一致 ---

echo ""
echo "--- A. 初回 install で plugin.json version が SoT と一致 ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

CONSUMER_PLUGIN="${R}/.claude-plugin/plugin.json"
assert_file_exists "consumer 側 .claude-plugin/plugin.json が配置される" "$CONSUMER_PLUGIN"

CONSUMER_VERSION="$(extract_version "$CONSUMER_PLUGIN")"
assert_eq "consumer plugin.json version が SoT と一致" "$SOT_VERSION" "$CONSUMER_VERSION"

cleanup
TMPDIR_ROOT=""

# --- B. --update 再実行: consumer 側 plugin.json が SoT version と一致したまま ---

echo ""
echo "--- B. --update 再実行で plugin.json version が SoT と一致したまま ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# consumer 側 plugin.json を意図的に古いバージョンに書き換え（drift 模擬）
cat > "${R}/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "vibecorp",
  "version": "0.0.1",
  "description": "drift simulation"
}
EOF

# --update を実行
bash "$INSTALL_SH" --update 2>/dev/null

# SoT version に戻っていることを確認（ダウングレード/ドリフトが発生しない）
CONSUMER_VERSION="$(extract_version "${R}/.claude-plugin/plugin.json")"
assert_eq "--update で plugin.json version が SoT に再同期される" "$SOT_VERSION" "$CONSUMER_VERSION"

cleanup
TMPDIR_ROOT=""

# --- C. preset full でも同じ不変条件が保たれる ---

echo ""
echo "--- C. preset full でも plugin.json version が SoT と一致 ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full --language ja 2>/dev/null
R="$TMPDIR_ROOT"

CONSUMER_VERSION="$(extract_version "${R}/.claude-plugin/plugin.json")"
assert_eq "preset full の consumer plugin.json version が SoT と一致" "$SOT_VERSION" "$CONSUMER_VERSION"

cleanup
TMPDIR_ROOT=""

print_test_summary
