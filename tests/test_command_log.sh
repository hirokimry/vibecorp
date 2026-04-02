#!/bin/bash
# test_command_log.sh — command-log.sh のユニットテスト
# 使い方: bash tests/test_command_log.sh

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (期待: '$expected', 実際: '$actual')"
  fi
}

setup_project_dir() {
  TMPDIR_ROOT=$(mktemp -d)
  mkdir -p "${TMPDIR_ROOT}/.claude"
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: minimal
YAML
  # lib/common.sh をコピー
  mkdir -p "${TMPDIR_ROOT}/.claude/lib"
  cp "${HOOKS_DIR}/lib/common.sh" "${TMPDIR_ROOT}/.claude/lib/common.sh"
  # command-log.sh をコピー
  mkdir -p "${TMPDIR_ROOT}/.claude/hooks"
  cp "${HOOKS_DIR}/command-log.sh" "${TMPDIR_ROOT}/.claude/hooks/command-log.sh"
  chmod +x "${TMPDIR_ROOT}/.claude/hooks/command-log.sh"
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
  rm -f /tmp/.test-project-command-log
}
trap cleanup EXIT

# ============================================
echo ""
echo "=== A. command-log.sh 基本テスト ==="
# ============================================

# --- A1. Bash コマンドがログに記録される ---
echo "--- A1. Bash コマンドがログに記録される ---"
setup_project_dir
rm -f /tmp/.test-project-command-log

OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm run build"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1)
EXIT_CODE=$?

assert_eq "A1: exit code が 0" "0" "$EXIT_CODE"

if [ -f /tmp/.test-project-command-log ]; then
  pass "A1: ログファイルが作成された"
else
  fail "A1: ログファイルが作成されていない"
fi

if grep -q "npm run build" /tmp/.test-project-command-log; then
  pass "A1: コマンドがログに記録された"
else
  fail "A1: コマンドがログに記録されていない"
fi

# --- A2. タイムスタンプ形式の確認 ---
echo "--- A2. タイムスタンプ形式の確認 ---"
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' /tmp/.test-project-command-log; then
  pass "A2: タイムスタンプがISO形式で記録されている"
else
  fail "A2: タイムスタンプ形式が不正"
fi

# --- A3. Bash 以外のツールでは記録されない ---
echo "--- A3. Bash 以外のツールでは記録されない ---"
cleanup
setup_project_dir
rm -f /tmp/.test-project-command-log

echo '{"tool_name":"Edit","tool_input":{"file_path":"test.txt"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1
echo '{"tool_name":"Write","tool_input":{"file_path":"test.txt"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1
echo '{"tool_name":"Read","tool_input":{"file_path":"test.txt"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1

if [ -f /tmp/.test-project-command-log ]; then
  fail "A3: Bash 以外でログファイルが作成された"
else
  pass "A3: Bash 以外ではログファイルが作成されない"
fi

# --- A4. 複数コマンドが順番に追記される ---
echo "--- A4. 複数コマンドが順番に追記される ---"
cleanup
setup_project_dir
rm -f /tmp/.test-project-command-log

echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1

LINE_COUNT=$(wc -l < /tmp/.test-project-command-log | tr -d ' ')
assert_eq "A4: 3行のログが記録された" "3" "$LINE_COUNT"

# 順番の確認
FIRST_CMD=$(head -1 /tmp/.test-project-command-log | cut -f2-)
LAST_CMD=$(tail -1 /tmp/.test-project-command-log | cut -f2-)
assert_eq "A4: 最初のコマンド" "echo hello" "$FIRST_CMD"
assert_eq "A4: 最後のコマンド" "npm test" "$LAST_CMD"

# --- A5. 空コマンドは記録されない ---
echo "--- A5. 空コマンドは記録されない ---"
cleanup
setup_project_dir
rm -f /tmp/.test-project-command-log

echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1

if [ -f /tmp/.test-project-command-log ]; then
  fail "A5: 空コマンドでログファイルが作成された"
else
  pass "A5: 空コマンドではログに記録されない"
fi

# --- A6. JSON 出力なし（permissionDecision を返さない）---
echo "--- A6. JSON 出力なし ---"
cleanup
setup_project_dir
rm -f /tmp/.test-project-command-log

OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "${TMPDIR_ROOT}/.claude/hooks/command-log.sh" 2>&1)

if echo "$OUTPUT" | grep -q "permissionDecision"; then
  fail "A6: permissionDecision が返された（返すべきではない）"
else
  pass "A6: permissionDecision を返さない"
fi

# ============================================
echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

exit "$FAILED"
