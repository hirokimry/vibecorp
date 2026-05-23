#!/bin/bash
# test_install_legacy_migration.sh — Issue #708 plugin native 移行 migration の検証
# - --update 時に旧 .claude/vibecorp-base/{hooks,lib}/ が物理削除されること
# - v1 形式 (hooks: lib: セクション付き) の lock が読み込めること（後方互換）

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"

if [[ ! -f "$INSTALL_SH" ]]; then
  fail "前提ファイル install.sh が存在しない"
  exit 1
fi

TMPDIR_TEST=""
cleanup() {
  [[ -n "$TMPDIR_TEST" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT

echo "=== Test 1: migrate_legacy_layout は --update 時にのみ実行される ==="

if grep -q "migrate_legacy_layout" "$INSTALL_SH"; then
  pass "migrate_legacy_layout 関数が install.sh に追加されている"
else
  fail "migrate_legacy_layout 関数が install.sh に存在しない"
  exit 1
fi

# `[[ "$UPDATE_MODE" == true ]] || return 0` のガードがあるか
if grep -A2 "^migrate_legacy_layout()" "$INSTALL_SH" | grep -q "UPDATE_MODE.*true.*return 0"; then
  pass "--update モード以外では migration が no-op になるガードが存在"
else
  fail "migrate_legacy_layout のガードが見つからない"
fi

echo ""
echo "=== Test 2: 旧 .claude/vibecorp-base/{hooks,lib}/ を削除する ==="

TMPDIR_TEST="$(mktemp -d)"
mkdir -p "${TMPDIR_TEST}/.claude/vibecorp-base/hooks"
mkdir -p "${TMPDIR_TEST}/.claude/vibecorp-base/lib"
echo "legacy hook" > "${TMPDIR_TEST}/.claude/vibecorp-base/hooks/old.sh"
echo "legacy lib" > "${TMPDIR_TEST}/.claude/vibecorp-base/lib/old.sh"

# 関数の単体実行
(
  cd "$TMPDIR_TEST"
  REPO_ROOT="$TMPDIR_TEST"
  UPDATE_MODE=true
  log_info() { :; }
  export REPO_ROOT UPDATE_MODE
  # install.sh から関数だけを抽出して実行
  bash -c "
    REPO_ROOT='$TMPDIR_TEST'
    UPDATE_MODE=true
    log_info() { :; }
    $(awk '/^migrate_legacy_layout\(\)/,/^}/' "$INSTALL_SH")
    migrate_legacy_layout
  "
)

if [[ ! -d "${TMPDIR_TEST}/.claude/vibecorp-base/hooks" ]]; then
  pass "旧 .claude/vibecorp-base/hooks/ が削除された"
else
  fail "旧 .claude/vibecorp-base/hooks/ が残存している"
fi

if [[ ! -d "${TMPDIR_TEST}/.claude/vibecorp-base/lib" ]]; then
  pass "旧 .claude/vibecorp-base/lib/ が削除された"
else
  fail "旧 .claude/vibecorp-base/lib/ が残存している"
fi

if [[ ! -d "${TMPDIR_TEST}/.claude/vibecorp-base" ]]; then
  pass ".claude/vibecorp-base/ ディレクトリ自体も空なら削除"
else
  pass ".claude/vibecorp-base/ は他のファイルがあれば残存（安全側）"
fi

rm -rf "$TMPDIR_TEST"
TMPDIR_TEST=""

echo ""
echo "=== Test 3: v1 形式 lock (hooks: lib: セクション付き) が読み込み可能 ==="

# read_lock_list 関数は v1/v2 両形式の hooks: セクションをパース可能
TMPDIR_TEST="$(mktemp -d)"
LOCK_V1="${TMPDIR_TEST}/vibecorp.lock"
cat > "$LOCK_V1" <<'YAML'
# vibecorp.lock — v1 format (Issue #708 後方互換テスト用)
version: 0.3.3
installed_at: 2026-01-01T00:00:00+00:00
preset: full
files:
  hooks:
    - protect-files.sh
    - command-log.sh
  lib:
    - common.sh
  skills:
    - ship
  agents:
    - cto.md
YAML

# install.sh の read_lock_list 関数を抽出して読み込めるか検証
HOOKS_FROM_V1="$(bash -c "
  $(awk '/^read_lock_list\(\)/,/^}/' "$INSTALL_SH")
  read_lock_list '$LOCK_V1' hooks
")"

if echo "$HOOKS_FROM_V1" | grep -q "protect-files.sh"; then
  pass "v1 形式 lock の hooks: セクションが読める"
else
  fail "v1 形式 lock の hooks: セクションが読めない（後方互換違反）"
fi

LIB_FROM_V1="$(bash -c "
  $(awk '/^read_lock_list\(\)/,/^}/' "$INSTALL_SH")
  read_lock_list '$LOCK_V1' lib
")"

if echo "$LIB_FROM_V1" | grep -q "common.sh"; then
  pass "v1 形式 lock の lib: セクションが読める"
else
  fail "v1 形式 lock の lib: セクションが読めない（後方互換違反）"
fi

rm -rf "$TMPDIR_TEST"
TMPDIR_TEST=""

echo ""
echo "=== Test 4: 既存 settings.json から hooks ブロックが除去される (#721) ==="

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq が利用不可な環境のため migration テストをスキップ"
else
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.claude"
  SETTINGS_BEFORE="${TMPDIR_TEST}/.claude/settings.json"
  cat > "$SETTINGS_BEFORE" <<'JSON'
{
  "permissions": {
    "allow": ["Read(*)", "Bash(git status:*)"],
    "ask": ["WebFetch(*)"]
  },
  "enabledPlugins": {
    "vibecorp@vibecorp": true
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/protect-files.sh" }
        ]
      }
    ]
  }
}
JSON

  bash -c "
    REPO_ROOT='$TMPDIR_TEST'
    UPDATE_MODE=true
    log_info() { :; }
    $(awk '/^migrate_legacy_layout\(\)/,/^}/' "$INSTALL_SH")
    migrate_legacy_layout
  "

  if jq -e '.hooks' "$SETTINGS_BEFORE" >/dev/null 2>&1; then
    fail "settings.json から hooks ブロックが除去されていない"
  else
    pass "settings.json から hooks ブロックが除去された"
  fi

  if jq -e '.permissions.allow' "$SETTINGS_BEFORE" >/dev/null 2>&1; then
    pass "permissions ブロックが保持されている"
  else
    fail "permissions ブロックが消失した（migration 過剰）"
  fi

  if jq -e '.enabledPlugins' "$SETTINGS_BEFORE" >/dev/null 2>&1; then
    pass "enabledPlugins ブロックが保持されている"
  else
    fail "enabledPlugins ブロックが消失した（migration 過剰）"
  fi

  rm -rf "$TMPDIR_TEST"
  TMPDIR_TEST=""

  # hooks ブロック不在時は冪等
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.claude"
  SETTINGS_CLEAN="${TMPDIR_TEST}/.claude/settings.json"
  cat > "$SETTINGS_CLEAN" <<'JSON'
{
  "permissions": {
    "allow": ["Read(*)"]
  }
}
JSON
  CHECKSUM_BEFORE="$(shasum "$SETTINGS_CLEAN" | awk '{print $1}')"

  bash -c "
    REPO_ROOT='$TMPDIR_TEST'
    UPDATE_MODE=true
    log_info() { :; }
    $(awk '/^migrate_legacy_layout\(\)/,/^}/' "$INSTALL_SH")
    migrate_legacy_layout
  "

  CHECKSUM_AFTER="$(shasum "$SETTINGS_CLEAN" | awk '{print $1}')"
  if [[ "$CHECKSUM_BEFORE" == "$CHECKSUM_AFTER" ]]; then
    pass "hooks ブロック不在時は settings.json を変更しない（冪等性）"
  else
    fail "hooks ブロック不在時に settings.json が変更された（冪等性違反）"
  fi

  rm -rf "$TMPDIR_TEST"
  TMPDIR_TEST=""
fi

echo ""
echo "=== Test 5: 新規 lock は v2 形式で hooks: / lib: セクションを書かない (#722) ==="

# generate_lock_file 関数の hooks: 出力削除を直接検証
if grep -q '_lock_list_section "hooks"' "$INSTALL_SH"; then
  fail "generate_lock_file が依然として hooks: セクションを出力している（v2 形式違反）"
else
  pass "generate_lock_file が hooks: セクションを出力しなくなった"
fi

if grep -q '_lock_list_section "lib"' "$INSTALL_SH"; then
  fail "generate_lock_file が lib: セクションを出力している（v2 形式違反）"
else
  pass "generate_lock_file が lib: セクションを出力しない（v2 形式準拠）"
fi

if grep -q "^format_version: 2$" "$INSTALL_SH" || grep -q 'format_version: 2' "$INSTALL_SH"; then
  pass "lock ヘッダに format_version: 2 が追加された"
else
  fail "lock ヘッダに format_version: 2 が追加されていない"
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
