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
echo "=== Test 5: 新規 lock は v3 形式で hooks: / lib: / agents: セクションを書かない (#722 / #735) ==="

# generate_lock_file 関数の hooks: 出力削除を直接検証
if grep -q '_lock_list_section "hooks"' "$INSTALL_SH"; then
  fail "generate_lock_file が依然として hooks: セクションを出力している（v3 形式違反）"
else
  pass "generate_lock_file が hooks: セクションを出力しなくなった"
fi

if grep -q '_lock_list_section "lib"' "$INSTALL_SH"; then
  fail "generate_lock_file が lib: セクションを出力している（v3 形式違反）"
else
  pass "generate_lock_file が lib: セクションを出力しない（v3 形式準拠）"
fi

if grep -q '_lock_list_section "agents"' "$INSTALL_SH"; then
  fail "generate_lock_file が agents: セクションを出力している（v3 形式違反、#735）"
else
  pass "generate_lock_file が agents: セクションを出力しない（v3 形式準拠、#735）"
fi

if grep -q "^format_version: 3$" "$INSTALL_SH" || grep -q 'format_version: 3' "$INSTALL_SH"; then
  pass "lock ヘッダに format_version: 3 が追加された（#735: agents セクション廃止）"
else
  fail "lock ヘッダに format_version: 3 が追加されていない"
fi

echo ""
echo "=== Test 6: 旧 .claude/hooks/ / .claude/lib/ の vibecorp 配布物が物理削除される (#708 完了条件 [1]) ==="

TMPDIR_TEST="$(mktemp -d)"
mkdir -p "${TMPDIR_TEST}/.claude/hooks"
mkdir -p "${TMPDIR_TEST}/.claude/lib"
cp "$SCRIPT_DIR/hooks/protect-files.sh" "${TMPDIR_TEST}/.claude/hooks/protect-files.sh"
cp "$SCRIPT_DIR/hooks/command-log.sh" "${TMPDIR_TEST}/.claude/hooks/command-log.sh"
cp "$SCRIPT_DIR/lib/common.sh" "${TMPDIR_TEST}/.claude/lib/common.sh"
echo "user custom hook" > "${TMPDIR_TEST}/.claude/hooks/my-custom-hook.sh"
echo "user custom lib" > "${TMPDIR_TEST}/.claude/lib/my-custom.sh"

bash -c "
  REPO_ROOT='$TMPDIR_TEST'
  SCRIPT_DIR='$SCRIPT_DIR'
  UPDATE_MODE=true
  log_info() { :; }
  $(awk '/^migrate_legacy_layout\(\)/,/^}/' "$INSTALL_SH")
  migrate_legacy_layout
"

if [[ ! -f "${TMPDIR_TEST}/.claude/hooks/protect-files.sh" ]]; then
  pass "旧 .claude/hooks/protect-files.sh が削除された"
else
  fail "旧 .claude/hooks/protect-files.sh が残存している"
fi

if [[ ! -f "${TMPDIR_TEST}/.claude/hooks/command-log.sh" ]]; then
  pass "旧 .claude/hooks/command-log.sh が削除された"
else
  fail "旧 .claude/hooks/command-log.sh が残存している"
fi

if [[ ! -f "${TMPDIR_TEST}/.claude/lib/common.sh" ]]; then
  pass "旧 .claude/lib/common.sh が削除された"
else
  fail "旧 .claude/lib/common.sh が残存している"
fi

if [[ -f "${TMPDIR_TEST}/.claude/hooks/my-custom-hook.sh" ]]; then
  pass "ユーザー独自フック .claude/hooks/my-custom-hook.sh が保持された（安全側）"
else
  fail "ユーザー独自フックが誤って削除された（migration 過剰）"
fi

if [[ -f "${TMPDIR_TEST}/.claude/lib/my-custom.sh" ]]; then
  pass "ユーザー独自 lib .claude/lib/my-custom.sh が保持された（安全側）"
else
  fail "ユーザー独自 lib が誤って削除された（migration 過剰）"
fi

rm -rf "$TMPDIR_TEST"
TMPDIR_TEST=""

TMPDIR_TEST="$(mktemp -d)"
mkdir -p "${TMPDIR_TEST}/.claude/hooks"
mkdir -p "${TMPDIR_TEST}/.claude/lib"
cp "$SCRIPT_DIR/hooks/protect-files.sh" "${TMPDIR_TEST}/.claude/hooks/protect-files.sh"
cp "$SCRIPT_DIR/lib/common.sh" "${TMPDIR_TEST}/.claude/lib/common.sh"

bash -c "
  REPO_ROOT='$TMPDIR_TEST'
  SCRIPT_DIR='$SCRIPT_DIR'
  UPDATE_MODE=true
  log_info() { :; }
  $(awk '/^migrate_legacy_layout\(\)/,/^}/' "$INSTALL_SH")
  migrate_legacy_layout
"

if [[ ! -d "${TMPDIR_TEST}/.claude/hooks" ]]; then
  pass "全 vibecorp フック削除後は .claude/hooks/ ディレクトリも削除される"
else
  fail ".claude/hooks/ が空にならない（migration 不完全）"
fi

rm -rf "$TMPDIR_TEST"
TMPDIR_TEST=""

echo ""
echo "=== Test 7: settings.json migration が同名衝突 hook を境界判定で保護する (CR PR #731 Major #8 v4) ==="

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq 不在のためスキップ"
else
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.claude"
  SETTINGS_T7="${TMPDIR_TEST}/.claude/settings.json"
  cat > "$SETTINGS_T7" <<'JSON'
{
  "permissions": {"allow": ["Read(*)"]},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/protect-files.sh"},
          {"type": "command", "command": "bash \".claude/hooks/diagnose-guard.sh\""},
          {"type": "command", "command": "bash '.claude/hooks/role-gate.sh'"},
          {"type": "command", "command": "bash .claude/hooks/review-gate.sh-wrapper"},
          {"type": "command", "command": "bash .claude/hooks/my-custom-hook.sh"}
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

  # vibecorp hook (protect-files.sh) は settings.json から消えている
  if ! jq -e '.hooks' "$SETTINGS_T7" >/dev/null 2>&1; then
    pass "T7-a: settings.json から hooks ブロックが完全削除された"
  else
    fail "T7-a: settings.json に hooks ブロックが残存"
  fi

  # 同名衝突 (review-gate.sh-wrapper) と user hook (my-custom-hook.sh) は settings.local.json に移送されている
  LOCAL_T7="${TMPDIR_TEST}/.claude/settings.local.json"
  if [[ -f "$LOCAL_T7" ]]; then
    # CR PR #731 Major #9 v6 対応: 引用符付き vibecorp hook (diagnose-guard, role-gate) も
    # 引用符境界判定で削除される (custom hook と誤認しない)
    if jq -e '.hooks.PreToolUse[0].hooks | map(.command) | any(contains("diagnose-guard.sh"))' "$LOCAL_T7" >/dev/null 2>&1; then
      fail "T7-e: 引用符付き vibecorp diagnose-guard.sh が settings.local.json に誤移送された (引用符境界判定失敗)"
    else
      pass "T7-e: 引用符付き vibecorp diagnose-guard.sh が削除された (引用符境界判定で識別)"
    fi
    if jq -e '.hooks.PreToolUse[0].hooks | map(.command) | any(contains("role-gate.sh\""))' "$LOCAL_T7" >/dev/null 2>&1; then
      fail "T7-f: シングル引用符付き vibecorp role-gate.sh が settings.local.json に誤移送された"
    else
      pass "T7-f: シングル引用符付き vibecorp role-gate.sh が削除された (引用符境界判定で識別)"
    fi

    if jq -e '.hooks.PreToolUse[0].hooks | map(.command) | any(contains("review-gate.sh-wrapper"))' "$LOCAL_T7" >/dev/null 2>&1; then
      pass "T7-b: 同名衝突 review-gate.sh-wrapper が settings.local.json に移送された (境界判定で保護)"
    else
      fail "T7-b: 同名衝突 review-gate.sh-wrapper が誤って削除された (境界判定失敗)"
    fi

    if jq -e '.hooks.PreToolUse[0].hooks | map(.command) | any(contains("my-custom-hook.sh"))' "$LOCAL_T7" >/dev/null 2>&1; then
      pass "T7-c: ユーザー独自 my-custom-hook.sh が settings.local.json に移送された"
    else
      fail "T7-c: ユーザー独自 my-custom-hook.sh が settings.local.json に無い"
    fi

    # vibecorp hook (protect-files.sh) は settings.local.json に混入していない
    if jq -e '.hooks.PreToolUse[0].hooks | map(.command) | any(contains("protect-files.sh"))' "$LOCAL_T7" >/dev/null 2>&1; then
      fail "T7-d: settings.local.json に vibecorp 由来 protect-files.sh が混入"
    else
      pass "T7-d: settings.local.json に vibecorp 由来 hook が混入していない"
    fi
  else
    fail "T7-b/c/d: settings.local.json が作成されていない (custom hook 移送失敗)"
  fi

  rm -rf "$TMPDIR_TEST"
  TMPDIR_TEST=""
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
