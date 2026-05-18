#!/bin/bash
# test_review_intent_from_issue.sh
# ─────────────────────────────────────────────
# Issue #575: pr-fix / review-loop が Issue ラベルから intent を直接取得する設計に
# 切り替わっていることを SKILL.md の静的検証で担保する。

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
echo "=== Issue #575 pr-fix / review-loop が Issue ラベル直接参照に切り替わっていることを検証 ==="

PR_FIX="${SCRIPT_DIR}/skills/pr-fix/SKILL.md"
REVIEW_LOOP="${SCRIPT_DIR}/skills/review-loop/SKILL.md"

# ============================================
# 1. pr-fix SKILL.md が Issue ラベル直接参照ステップを持つ
# ============================================
echo ""
echo "--- 1. pr-fix が Issue ラベル直接参照ステップを持つ ---"
assert_file_exists "pr-fix SKILL.md" "$PR_FIX"
assert_file_contains_fixed "closingIssuesReferences 取得"                 "$PR_FIX" "closingIssuesReferences"
assert_file_contains_fixed "gh issue view --json labels 呼出"              "$PR_FIX" "gh issue view"
assert_file_contains_fixed "intent ラベル 7 種フィルタリング"               "$PR_FIX" 'startswith("intent/")'
assert_file_contains_fixed "SoT は Issue ラベルの明示"                     "$PR_FIX" "SoT は **Issue ラベル**"

# ============================================
# 2. review-loop SKILL.md が Issue ラベル直接参照ステップを持つ
# ============================================
echo ""
echo "--- 2. review-loop が Issue ラベル直接参照ステップを持つ ---"
assert_file_exists "review-loop SKILL.md" "$REVIEW_LOOP"
assert_file_contains_fixed "closingIssuesReferences 取得"                  "$REVIEW_LOOP" "closingIssuesReferences"
assert_file_contains_fixed "gh issue view --json labels 呼出"              "$REVIEW_LOOP" "gh issue view"
assert_file_contains_fixed "intent ラベル 7 種フィルタリング"               "$REVIEW_LOOP" 'startswith("intent/")'
assert_file_contains_fixed "SoT は Issue ラベルの明示"                     "$REVIEW_LOOP" "SoT は **Issue ラベル**"

# ============================================
# 3. 妥当性検証で PR_INTENT を使うことが明文化されている
# ============================================
echo ""
echo "--- 3. 妥当性検証で PR_INTENT を入力として使う ---"
assert_file_contains_fixed "pr-fix で PR_INTENT を入力に使う"      "$PR_FIX"      "PR_INTENT"
assert_file_contains_fixed "review-loop で PR_INTENT を入力に使う" "$REVIEW_LOOP" "PR_INTENT"

print_test_summary
