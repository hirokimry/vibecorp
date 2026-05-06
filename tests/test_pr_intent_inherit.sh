#!/bin/bash
# test_pr_intent_inherit.sh
# ─────────────────────────────────────────────
# Issue #487 / #519: PR 作成スキルが Issue から intent ラベルを継承する責務を果たしていることを検証する。
#
# 設計の経緯:
#   - 当初は CI workflow (pr-intent-inherit.yml) で後追い継承していた
#   - PR 作成スキルが --label を渡さない責務放棄により CI race を引き起こしていた（Issue #517）
#   - Issue #519 で根本対応: ラベル付与は PR 作成スキル（/vibecorp:ship, /vibecorp:pr）の責務に集中
#   - CI workflow (pr-intent-inherit.yml) は削除、CI は ai-review.yml の数チェックのみで検査
#
# 本テストは「PR 作成スキルが --label でラベル継承する」ロジックが SKILL.md に記述されていることを
# 静的検証する。

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
echo "=== Issue #519 PR 作成スキルが intent ラベルを継承する責務を果たしているか検証 ==="

SHIP_SKILL="${SCRIPT_DIR}/skills/ship/SKILL.md"
PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

# ============================================
# 1. /vibecorp:ship スキルが PR 作成時にラベル継承する（Issue #519）
# ============================================
echo ""
echo "--- 1. /vibecorp:ship スキルのラベル継承 ---"
assert_file_exists "ship スキル定義" "$SHIP_SKILL"
assert_file_contains_fixed "Issue から intent ラベル取得"     "$SHIP_SKILL" "Issue から intent ラベルを継承"
assert_file_contains       "ホワイトリスト 7 種参照"          "$SHIP_SKILL" "intent/feature"
assert_file_contains       "LABEL_ARGS で --label 構築"      "$SHIP_SKILL" "LABEL_ARGS"
assert_file_contains       "gh pr create に \$LABEL_ARGS"    "$SHIP_SKILL" "gh pr create --title"

# ============================================
# 2. /vibecorp:pr スキルがラベル継承する（既存実装、Issue #487）
# ============================================
echo ""
echo "--- 2. /vibecorp:pr スキルのラベル継承 ---"
assert_file_exists "pr スキル定義" "$PR_SKILL"
assert_file_contains_fixed "Issue から intent 取得 (スキル側)"  "$PR_SKILL" "intent/* ラベルを取得"
assert_file_contains       "gh pr create に --label で渡す"   "$PR_SKILL" "LABEL_ARGS"
assert_file_contains       "ホワイトリスト 7 種参照"          "$PR_SKILL" "intent/feature"

# ============================================
# 3. intent ホワイトリスト 7 種が両スキルで一致
# ============================================
echo ""
echo "--- 3. intent ホワイトリスト 7 種が両スキルで一致 ---"
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -q -F -- "\"$intent\"" "$SHIP_SKILL"; then
    pass "ship スキルにホワイトリスト '$intent' 含む"
  else
    fail "ship スキルにホワイトリスト '$intent' 含まない"
  fi
  if grep -q -F -- "\"$intent\"" "$PR_SKILL"; then
    pass "pr スキルにホワイトリスト '$intent' 含む"
  else
    fail "pr スキルにホワイトリスト '$intent' 含まない"
  fi
done

# ============================================
# 4. 旧 CI 継承機構（pr-intent-inherit.yml）が削除されている
# ============================================
echo ""
echo "--- 4. 旧 CI 継承機構が削除されている ---"
if [ -e "${SCRIPT_DIR}/.github/workflows/pr-intent-inherit.yml" ]; then
  fail "自リポ版 pr-intent-inherit.yml が残存（Issue #519 で削除済みのはず）"
else
  pass "自リポ版 pr-intent-inherit.yml が削除されている"
fi

if [ -e "${SCRIPT_DIR}/templates/.github/workflows/pr-intent-inherit.yml" ]; then
  fail "配布版 pr-intent-inherit.yml が残存（Issue #519 で削除済みのはず）"
else
  pass "配布版 pr-intent-inherit.yml が削除されている"
fi

# ============================================
# 5. install で配布されない（旧 workflow 削除確認）
# ============================================
echo ""
echo "--- 5. install 後にも pr-intent-inherit.yml が配布されない ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal
R="$TMPDIR_ROOT"

if [ -e "$R/.github/workflows/pr-intent-inherit.yml" ]; then
  fail "install 後に pr-intent-inherit.yml が配布されている（Issue #519 で削除済みのはず）"
else
  pass "install 後 pr-intent-inherit.yml が配布されない"
fi
cleanup

# ============================================
# 6. ai-review.yml は数チェックのみ（継承責務を持たない）
# ============================================
echo ""
echo "--- 6. ai-review.yml の intent-label-check が継承責務を持たない ---"
AI_REVIEW="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
assert_file_exists "ai-review.yml" "$AI_REVIEW"

# 「Issue から intent ラベルを継承」ステップは存在しないこと
if grep -q -F -- "対応 Issue から intent ラベルを継承" "$AI_REVIEW"; then
  fail "ai-review.yml に継承ステップが含まれている（Issue #519 で撤去のはず、責務は ship/pr スキル側）"
else
  pass "ai-review.yml に継承ステップは含まれない（CI は検査専任）"
fi

# 数チェックロジック自体は維持されていること
assert_file_contains "1 PR 1 intent 厳守チェックステップ" "$AI_REVIEW" "1 PR 1 intent 厳守チェック"

print_test_summary
