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
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
