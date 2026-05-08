#!/bin/bash
# test_pr_intent_inherit.sh
# ─────────────────────────────────────────────
# Issue #487 / #519: PR 作成時の intent ラベル継承責務が /vibecorp:pr に集中していることを検証する。
#
# 設計の経緯:
#   - 当初は CI workflow (pr-intent-inherit.yml) で後追い継承していた（責務逆転）
#   - PR 作成スキルが --label を渡さない責務放棄により CI race を引き起こしていた（Issue #517）
#   - 初期の Issue #519 修正では ship スキルに継承ロジックを直書きしたが、これも責務逆転
#     （ship は包括オーケストレーション、pr は PR 作成の単一責務、という分離原則に違反）
#   - 最終形（CTO レビュー後）: 継承責務は /vibecorp:pr に **完全集中**、ship は /vibecorp:pr を呼ぶだけ
#   - CI workflow (pr-intent-inherit.yml) は削除、CI は ai-review.yml の数チェックのみで検査
#
# 本テストは責務分離の最終形を静的検証する:
#   - /vibecorp:pr が継承ロジックを持つ（実装の主体）
#   - /vibecorp:ship は /vibecorp:pr を呼ぶだけで、自前の継承ロジックを持たない
#   - 旧 CI 継承機構は削除されている

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
echo "=== Issue #519 PR 作成時のラベル継承責務が /vibecorp:pr に集中していることを検証 ==="

SHIP_SKILL="${SCRIPT_DIR}/skills/ship/SKILL.md"
PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

# ============================================
# 1. /vibecorp:pr スキルが継承責務の **主体** である（実装あり）
# ============================================
echo ""
echo "--- 1. /vibecorp:pr スキルが継承の主体（実装あり） ---"
assert_file_exists "pr スキル定義" "$PR_SKILL"
assert_file_contains_fixed "Issue から intent 取得 (スキル側)"  "$PR_SKILL" "intent/* ラベルを取得"
assert_file_contains       "gh pr create に --label で渡す"   "$PR_SKILL" "LABEL_ARGS"
assert_file_contains       "ホワイトリスト 7 種参照"          "$PR_SKILL" "intent/feature"

# ============================================
# 2. /vibecorp:ship スキルは /vibecorp:pr を呼ぶだけ（責務委譲）
# ============================================
echo ""
echo "--- 2. /vibecorp:ship が /vibecorp:pr を呼ぶ（責務委譲） ---"
assert_file_exists "ship スキル定義" "$SHIP_SKILL"
assert_file_contains_fixed "ship が /vibecorp:pr に委譲する記述" "$SHIP_SKILL" "/vibecorp:pr"
assert_file_contains_fixed "ship が --close を渡す"               "$SHIP_SKILL" "--close"

# ============================================
# 3. /vibecorp:ship が **自前の継承ロジックを持たない**（責務違反防止）
# ============================================
echo ""
echo "--- 3. /vibecorp:ship に自前の継承ロジックが無い（責務分離） ---"

# ship は gh pr create を直接呼んではならない（pr スキルに委譲のため）
if grep -q -F -- "gh pr create --title" "$SHIP_SKILL"; then
  fail "ship スキルに gh pr create の直接呼び出しが残存（責務違反、/vibecorp:pr に委譲すべき）"
else
  pass "ship スキルに gh pr create の直接呼び出しが無い（/vibecorp:pr に委譲）"
fi

# ship は LABEL_ARGS を構築してはならない（pr スキルが内部で処理するため）
if grep -q -F -- "LABEL_ARGS=" "$SHIP_SKILL"; then
  fail "ship スキルに LABEL_ARGS 構築ロジックが残存（責務違反、/vibecorp:pr に委譲すべき）"
else
  pass "ship スキルに LABEL_ARGS 構築ロジックが無い（/vibecorp:pr が内部で処理）"
fi

# ship は INTENT_LABELS / ALLOWED 配列を持ってはならない（pr スキル側に集約）
if grep -q -F -- "INTENT_LABELS=" "$SHIP_SKILL"; then
  fail "ship スキルに INTENT_LABELS 取得ロジックが残存（責務違反）"
else
  pass "ship スキルに INTENT_LABELS 取得ロジックが無い（/vibecorp:pr に集約）"
fi

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
  fail "ai-review.yml に継承ステップが含まれている（Issue #519 で撤去のはず、責務は /vibecorp:pr 側）"
else
  pass "ai-review.yml に継承ステップは含まれない（CI は検査専任）"
fi

# 数チェックロジック自体は維持されていること
assert_file_contains "1 PR 1 intent 厳守チェックステップ" "$AI_REVIEW" "1 PR 1 intent 厳守チェック"

# ============================================
# 7. /vibecorp:pr のホワイトリスト 7 種チェック
# ============================================
echo ""
echo "--- 7. /vibecorp:pr のホワイトリスト 7 種 ---"
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -q -F -- "\"$intent\"" "$PR_SKILL"; then
    pass "/vibecorp:pr にホワイトリスト '$intent' 含む"
  else
    fail "/vibecorp:pr にホワイトリスト '$intent' 含まない"
  fi
done

print_test_summary
