#!/bin/bash
# test_state_no_placeholder.sh
# templates/claude/hooks と templates/claude/skills から
# {{PROJECT_NAME}} placeholder と /tmp/.${PROJECT_NAME} 参照が消滅していることを検証する回帰テスト
#
# Issue #255 で /tmp/ スタンプを $CLAUDE_PROJECT_DIR/.claude/state/ に移行した。
# 退化を防ぐため、CI で本テストが常に PASS する必要がある。
#
# 使い方: bash tests/test_state_no_placeholder.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
TOTAL=0

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

# --- 1. {{PROJECT_NAME}} placeholder の不在 ---

echo "=== {{PROJECT_NAME}} placeholder 検出 ==="

if grep -rn '{{PROJECT_NAME}}' \
    "${SCRIPT_DIR}/templates/claude/hooks" \
    "${SCRIPT_DIR}/templates/claude/skills" 2>/dev/null; then
  fail "{{PROJECT_NAME}} placeholder が hooks/skills に残存している"
else
  pass "{{PROJECT_NAME}} placeholder は hooks/skills に存在しない"
fi

# --- 2. /tmp/.${PROJECT_NAME} 参照の不在 ---

echo ""
echo "=== /tmp/ スタンプファイル参照検出 ==="

# /tmp/.${PROJECT_NAME}-* もしくは /tmp/.{{PROJECT_NAME}}-* 形式
# プロジェクト名を含む /tmp/ スタンプ参照を検出
TMP_PATTERN='/tmp/\.\${PROJECT_NAME}\|/tmp/\.{{PROJECT_NAME}}\|/tmp/\.{project}'
if grep -rn "$TMP_PATTERN" \
    "${SCRIPT_DIR}/templates/claude/hooks" \
    "${SCRIPT_DIR}/templates/claude/skills" 2>/dev/null; then
  fail "/tmp/.\${PROJECT_NAME} 参照が hooks/skills に残存している"
else
  pass "/tmp/.\${PROJECT_NAME} 参照は hooks/skills に存在しない"
fi

# --- 3. PROJECT_NAME 変数定義の不在（hooks 限定） ---
# hooks では get_project_name 呼び出しが消滅しているはず
# （SKILL.md は別の用途で PROJECT_NAME を扱う可能性があるため対象外）

echo ""
echo "=== hooks の PROJECT_NAME 変数定義検出 ==="

if grep -rn 'PROJECT_NAME=\$(get_project_name)' \
    "${SCRIPT_DIR}/templates/claude/hooks" 2>/dev/null; then
  fail "hooks に PROJECT_NAME=\$(get_project_name) が残存している"
else
  pass "hooks に PROJECT_NAME=\$(get_project_name) は存在しない"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
