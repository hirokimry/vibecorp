#!/bin/bash
# test_communication_rule.sh — CEO 報告「動作で語る」規約（Issue #342）の整合性テスト
# 使い方: bash tests/test_communication_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMM_RULE="${SCRIPT_DIR}/.claude/rules/communication.md"
ROLES="${SCRIPT_DIR}/.claude/rules/roles.md"
AI_ORG="${SCRIPT_DIR}/docs/ai-organization.md"
ISSUE_SKILL="${SCRIPT_DIR}/skills/issue/SKILL.md"
PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"
COMMIT_SKILL="${SCRIPT_DIR}/skills/commit/SKILL.md"

# ============================================
echo "=== .claude/rules/communication.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/communication.md が存在する" "$COMM_RULE"

if [[ ! -f "$COMM_RULE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "communication.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== communication.md の主要見出しが含まれる ==="
# ============================================

assert_file_contains "communication.md に「前提」セクション" "$COMM_RULE" "^## 前提"
assert_file_contains "communication.md に「対象文面」セクション" "$COMM_RULE" "^## 対象文面"
assert_file_contains "communication.md に「動作主語で語る」セクション" "$COMM_RULE" "動作主語で語る"
assert_file_contains "communication.md に「30 秒ルール」" "$COMM_RULE" "30 秒ルール"
assert_file_contains "communication.md に状態絵文字（✅）" "$COMM_RULE" "✅"

# ============================================
echo "=== docs/ai-organization.md に CEO 性質が記述されている ==="
# ============================================

assert_file_exists "docs/ai-organization.md が存在する" "$AI_ORG"
assert_file_contains "ai-organization.md に CEO キーワード" "$AI_ORG" "CEO"
assert_file_contains "ai-organization.md に「経営者」" "$AI_ORG" "経営者"
assert_file_contains "ai-organization.md に「ふるまい」" "$AI_ORG" "ふるまい"

# ============================================
echo "=== .claude/rules/roles.md の CEO セクションに communication.md 参照 ==="
# ============================================

assert_file_exists ".claude/rules/roles.md が存在する" "$ROLES"
# CEO セクションから他ロールまでの範囲を抽出し、communication.md 参照の有無を確認
CEO_SECTION=$(awk '/^## CEO/{flag=1; next} /^## /{flag=0} flag' "$ROLES")
if echo "$CEO_SECTION" | grep -q -e "communication.md"; then
  pass "roles.md の CEO セクションに communication.md 参照"
else
  fail "roles.md の CEO セクションに communication.md 参照がない"
fi
if echo "$CEO_SECTION" | grep -q -e "経営者"; then
  pass "roles.md の CEO セクションに「経営者」"
else
  fail "roles.md の CEO セクションに「経営者」がない"
fi

# ============================================
echo "=== /vibecorp:issue /vibecorp:pr /vibecorp:commit の SKILL.md に communication.md 参照 ==="
# ============================================

assert_file_contains "/vibecorp:issue SKILL.md に communication.md 参照" "$ISSUE_SKILL" "communication.md"
assert_file_contains "/vibecorp:pr SKILL.md に communication.md 参照" "$PR_SKILL" "communication.md"
assert_file_contains "/vibecorp:commit SKILL.md に communication.md 参照" "$COMMIT_SKILL" "communication.md"

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
