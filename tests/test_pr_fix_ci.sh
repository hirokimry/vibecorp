#!/bin/bash
# test_pr_fix_ci.sh — /vibecorp:pr-fix の CI 失敗検知仕様ガード
# 使い方: bash tests/test_pr_fix_ci.sh

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_DIR/skills/pr-fix/SKILL.md"

echo "=== /vibecorp:pr-fix CI 失敗検知仕様ガード テスト ==="
echo ""

# --- テスト1: SKILL.md の存在 ---

echo "--- テスト1: SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "pr-fix SKILL.md が存在する"
else
  fail "pr-fix SKILL.md が存在しない: $SKILL_FILE"
  exit 1
fi

echo ""

# --- テスト2: CI ステータス取得ステップの存在 ---

echo "--- テスト2: CI ステータス取得 ---"

if grep -q -e 'statusCheckRollup' "$SKILL_FILE"; then
  pass "statusCheckRollup による CI ステータス取得が記述されている"
else
  fail "statusCheckRollup による CI ステータス取得が記述されていない"
fi

if grep -q -e 'gh run view' "$SKILL_FILE"; then
  pass "gh run view による失敗ログ取得が記述されている"
else
  fail "gh run view による失敗ログ取得が記述されていない"
fi

if grep -q -e 'log-failed' "$SKILL_FILE"; then
  pass "--log-failed オプションが記述されている"
else
  fail "--log-failed オプションが記述されていない"
fi

echo ""

# --- テスト3: CI 状態分類 ---

echo "--- テスト3: CI 状態分類 ---"

CI_CONCLUSIONS=("SUCCESS" "NEUTRAL" "SKIPPED" "FAILURE" "CANCELLED" "TIMED_OUT" "ACTION_REQUIRED")
for conclusion in "${CI_CONCLUSIONS[@]}"; do
  if grep -q -e "$conclusion" "$SKILL_FILE"; then
    pass "CI conclusion '$conclusion' が記述されている"
  else
    fail "CI conclusion '$conclusion' が記述されていない"
  fi
done

if grep -q -e 'PENDING\|待機' "$SKILL_FILE"; then
  pass "CI 待機（PENDING）状態が記述されている"
else
  fail "CI 待機（PENDING）状態が記述されていない"
fi

echo ""

# --- テスト4: 外部要因キーワード ---

echo "--- テスト4: 外部要因 CI 失敗キーワード ---"

EXTERNAL_KEYWORDS=("Rate limit" "429" "ECONNREFUSED" "ETIMEDOUT" "ENOTFOUND")
for kw in "${EXTERNAL_KEYWORDS[@]}"; do
  if grep -q -e "$kw" "$SKILL_FILE"; then
    pass "外部要因キーワード '$kw' が記述されている"
  else
    fail "外部要因キーワード '$kw' が記述されていない"
  fi
done

echo ""

# --- テスト5: エスカレーション ---

echo "--- テスト5: エスカレーション ---"

if grep -q -e '外部要因' "$SKILL_FILE"; then
  pass "外部要因 CI 失敗のエスカレーション記述がある"
else
  fail "外部要因 CI 失敗のエスカレーション記述がない"
fi

echo ""

# --- テスト6: 終了条件に CI が含まれる ---

echo "--- テスト6: 終了条件に CI green ---"

if grep -q -e 'CI 失敗 0 件\|CI green\|CI.*失敗.*0' "$SKILL_FILE"; then
  pass "終了条件に CI 失敗 0 件が含まれている"
else
  fail "終了条件に CI 失敗 0 件が含まれていない"
fi

echo ""

# --- テスト7: 結果報告に CI 修正件数 ---

echo "--- テスト7: 結果報告に CI 修正件数 ---"

if grep -q -e 'CI 修正' "$SKILL_FILE"; then
  pass "結果報告に CI 修正件数が含まれている"
else
  fail "結果報告に CI 修正件数が含まれていない"
fi

if grep -q -e 'CI 待機' "$SKILL_FILE"; then
  pass "結果報告に CI 待機件数が含まれている"
else
  fail "結果報告に CI 待機件数が含まれていない"
fi

echo ""

# --- テスト8: コードブロック言語指定 ---

echo "--- テスト8: コードブロック言語指定 ---"

bare_opens=$(awk '
  /^```[a-zA-Z]/ { in_fence = 1; next }
  /^```$/ {
    if (in_fence) { in_fence = 0 }
    else { count++ }
    next
  }
  END { print count + 0 }
' "$SKILL_FILE")

if [ "$bare_opens" -eq 0 ]; then
  pass "全てのコードブロックに言語指定がある"
else
  fail "言語指定なしのコードブロックが ${bare_opens} 件ある"
fi

echo ""

# --- 結果表示 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
