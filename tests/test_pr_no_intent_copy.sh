#!/bin/bash
# test_pr_no_intent_copy.sh
# ─────────────────────────────────────────────
# Issue #575: PR 作成時の Issue → PR intent ラベルコピー処理が撤廃されていることを検証する。
#
# 設計の経緯:
#   - Issue #487 / #519: 当初は CI workflow → pr スキル側に責務集約させた（旧 test_pr_intent_inherit.sh）
#   - Issue #575: PR ラベルコピー自体を撤廃し、レビュー判定は pr-fix / review-loop が
#     Issue ラベルを直接参照する設計に切替（intent の SoT を Issue ラベルに一元化）
#
# 本テストは Issue #575 完了形を静的検証する:
#   - /vibecorp:pr が Issue → PR ラベルコピー処理を **持たない**
#   - /vibecorp:ship は /vibecorp:pr を呼ぶだけで、自前の継承ロジックを持たない
#   - PR 側 intent-label-check CI ジョブが削除されている
#   - intent ラベル 7 種は intent-labels.md（SoT）で参照される

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

assert_file_not_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path"; then
    fail "$desc (パターン '${pattern}' がファイルに残存: ${path})"
  else
    pass "$desc"
  fi
}

echo ""
echo "=== Issue #575 PR ラベルコピー処理が撤廃されていることを検証 ==="

SHIP_SKILL="${SCRIPT_DIR}/skills/ship/SKILL.md"
PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"
RULE_INTENT="${SCRIPT_DIR}/.claude/rules/intent-labels.md"
RULE_INTENT_TPL="${SCRIPT_DIR}/rules/intent-labels.md"

# ============================================
# 1. /vibecorp:pr スキルがラベルコピー処理を持たない
# ============================================
echo ""
echo "--- 1. /vibecorp:pr スキルにラベルコピー処理が無い ---"
assert_file_exists "pr スキル定義" "$PR_SKILL"
assert_file_not_contains_fixed "ISSUE_INTENTS 取得ロジックが無い"   "$PR_SKILL" "ISSUE_INTENTS="
assert_file_not_contains_fixed "LABEL_ARGS 構築ロジックが無い"     "$PR_SKILL" "LABEL_ARGS="
assert_file_not_contains_fixed "gh pr create に --label が無い"     "$PR_SKILL" "--label \$LABEL_ARGS"

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
assert_file_not_contains_fixed "ship に gh pr create 直接呼び出しが無い" "$SHIP_SKILL" "gh pr create --title"
assert_file_not_contains_fixed "ship に LABEL_ARGS が無い"               "$SHIP_SKILL" "LABEL_ARGS="
assert_file_not_contains_fixed "ship に INTENT_LABELS が無い"            "$SHIP_SKILL" "INTENT_LABELS="

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
# 6. ai-review.yml テンプレート自体が撤去されている（Issue #531）
#    レビュー機能は vibehawk へ移譲され、claude-code-action 用 ai-review.yml は配布されない。
#    PR 側 intent-label-check ジョブが「存在しない」ことは、テンプレ不在で自明に満たされる。
# ============================================
echo ""
echo "--- 6. ai-review.yml テンプレートが撤去されている（vibehawk 移譲） ---"
AI_REVIEW="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
if [ -e "$AI_REVIEW" ]; then
  fail "ai-review.yml テンプレートが残存（Issue #531 で撤去済みのはず）"
else
  pass "ai-review.yml テンプレートが撤去されている（vibehawk 移譲）"
fi

# ============================================
# 7. intent ラベル 7 種は .claude/rules/intent-labels.md（SoT）で参照される
# ============================================
echo ""
echo "--- 7. intent ラベル 7 種が intent-labels.md に存在する（SoT） ---"
assert_file_exists "intent-labels.md" "$RULE_INTENT"
assert_file_exists "intent-labels.md（SSOT rules/ 版）" "$RULE_INTENT_TPL"

for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -q -F -- "$intent" "$RULE_INTENT"; then
    pass "intent-labels.md に '$intent' 含む"
  else
    fail "intent-labels.md に '$intent' 含まない"
  fi
  if grep -q -F -- "$intent" "$RULE_INTENT_TPL"; then
    pass "intent-labels.md（SSOT rules/ 版）に '$intent' 含む"
  else
    fail "intent-labels.md（SSOT rules/ 版）に '$intent' 含まない"
  fi
done

# ============================================
# 8. intent-labels.md が「PR には付与しない」旨を明示
# ============================================
echo ""
echo "--- 8. intent-labels.md が SoT を Issue に一元化していることを明示 ---"
assert_file_contains_fixed "「PR には intent ラベルを付与しない」記載" "$RULE_INTENT" "PR には intent ラベルを付与しない"
assert_file_contains_fixed "「SoT は Issue ラベル」記載" "$RULE_INTENT" "intent の SoT は Issue ラベル"
assert_file_contains_fixed "SSOT rules/ 版も同様" "$RULE_INTENT_TPL" "PR には intent ラベルを付与しない"

print_test_summary
