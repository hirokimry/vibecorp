#!/bin/bash
# test_review_intent_fallback.sh
# ─────────────────────────────────────────────
# Issue #575: pr-fix / review-loop の Issue 番号解決 4 段フォールバックと
# severity-only fallback 挙動が SKILL.md に明文化されていることを検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

assert_file_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path"; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

echo ""
echo "=== Issue #575 Issue 番号解決の 4 段フォールバック設計を検証 ==="

PR_FIX="${SCRIPT_DIR}/skills/pr-fix/SKILL.md"
REVIEW_LOOP="${SCRIPT_DIR}/skills/review-loop/SKILL.md"

for SKILL_PATH in "$PR_FIX" "$REVIEW_LOOP"; do
  SKILL_NAME=$(basename "$(dirname "$SKILL_PATH")")
  echo ""
  echo "--- $SKILL_NAME の 4 段フォールバック ---"
  assert_file_exists "$SKILL_NAME SKILL.md" "$SKILL_PATH"

  # 4 段フォールバックの全段階が明記されている
  assert_file_contains_fixed "$SKILL_NAME: 優先 1 closingIssuesReferences" "$SKILL_PATH" "closingIssuesReferences"
  assert_file_contains_fixed "$SKILL_NAME: 優先 2 PR 本文 grep（regex 明示）" "$SKILL_PATH" "close[sd]?"
  assert_file_contains_fixed "$SKILL_NAME: 優先 3 ブランチ名から抽出"           "$SKILL_PATH" 'dev/<num>_*'
  assert_file_contains_fixed "$SKILL_NAME: 優先 4 severity-only fallback"      "$SKILL_PATH" "severity-only fallback"

  # severity-only fallback の挙動明示
  echo "--- $SKILL_NAME の severity-only fallback 挙動 ---"
  assert_file_contains_fixed "$SKILL_NAME: Critical / Major のみ修正対象" "$SKILL_PATH" "Critical / Major"
  assert_file_contains_fixed "$SKILL_NAME: Minor 以下はスキップ"          "$SKILL_PATH" "Minor 以下"
  assert_file_contains_fixed "$SKILL_NAME: warning ログ出力"               "$SKILL_PATH" "[WARN]"
done

print_test_summary
