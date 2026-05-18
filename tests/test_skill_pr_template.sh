#!/bin/bash
# test_skill_pr_template.sh
# ─────────────────────────────────────────────
# Issue #608: スキル群の PR テンプレート / Issue 参照書式が
# GitHub auto-close キーワード `Closes #N` / `Refs #N` 形式に統一されていることを静的検証する。
#
# 設計根拠:
#   - templates/.github/workflows/close-on-feature-merge.yml が
#     `(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+` のみを抽出対象とする
#   - URL 形式（`close <URL>`）では feature ブランチへのマージ時に Issue が auto-close されない
#   - 親エピック / 子 Issue の使い分け: 親は `Refs #N`、子は `Closes #N`
#
# 検証対象:
#   1. .claude/rules/workflow.md            — 規約明文化
#   2. skills/pr/SKILL.md                   — PR テンプレートの prefix・書式
#   3. skills/ship/SKILL.md                 — ステップ 9 の `--close` 説明
#   4. skills/pr-fix/SKILL.md               — PR 本文修正時のキーワード保持
#   5. skills/release-epic/SKILL.md         — リリース PR の `Closes #<親番号>`
#   6. skills/issue/SKILL.md                — 関連 Issue 参照は `Refs #N`
#   7. skills/plan-epic/SKILL.md            — 子 Issue 本文は `Refs #<親番号>`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

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
echo "=== Issue #608 スキル群 PR テンプレートが Closes #N / Refs #N 形式に統一されている ==="

# ============================================
# 1. .claude/rules/workflow.md に PR 本文 auto-close ルールが明文化されている
# ============================================
echo ""
echo "--- 1. .claude/rules/workflow.md ---"

WORKFLOW_RULE="${SCRIPT_DIR}/.claude/rules/workflow.md"

if [[ ! -f "$WORKFLOW_RULE" ]]; then
  fail ".claude/rules/workflow.md が存在しない"
  exit 1
fi
pass ".claude/rules/workflow.md が存在する"

assert_file_contains_fixed "workflow.md に「PR 本文の Issue リンク」セクションが追加されている" \
  "$WORKFLOW_RULE" "PR 本文の Issue リンク"
assert_file_contains_fixed "workflow.md に auto-close キーワードの言及がある" \
  "$WORKFLOW_RULE" "auto-close"
assert_file_contains_fixed "workflow.md で Closes #N 形式が必須化されている" \
  "$WORKFLOW_RULE" "Closes #N"
assert_file_contains_fixed "workflow.md で Refs #N の使い分けが明示されている" \
  "$WORKFLOW_RULE" "Refs #N"
assert_file_contains_fixed "workflow.md で #N 形式必須が明記されている（URL 形式不可）" \
  "$WORKFLOW_RULE" "#N"
assert_file_contains_fixed "workflow.md で close-on-feature-merge.yml の根拠が示されている" \
  "$WORKFLOW_RULE" "close-on-feature-merge.yml"

# ============================================
# 2. skills/pr/SKILL.md — Closes / Refs 大文字始まり prefix と #N 書式
# ============================================
echo ""
echo "--- 2. skills/pr/SKILL.md ---"

PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

if [[ ! -f "$PR_SKILL" ]]; then
  fail "skills/pr/SKILL.md が存在しない"
  exit 1
fi
pass "skills/pr/SKILL.md が存在する"

assert_file_contains_fixed "pr/SKILL.md で --close prefix が Closes（大文字始まり）" \
  "$PR_SKILL" "\`--close\` オプション指定時: \`Closes\`"
assert_file_contains_fixed "pr/SKILL.md で --ref prefix が Refs（大文字始まり）" \
  "$PR_SKILL" "\`--ref\` オプション指定時: \`Refs\`"
assert_file_contains_fixed "pr/SKILL.md で Issue リンク書式が #{ISSUE_NUMBER}（URL 形式ではない）" \
  "$PR_SKILL" "{prefix} #{ISSUE_NUMBER}"
assert_file_contains_fixed "pr/SKILL.md で Closes #123 の例が示されている" \
  "$PR_SKILL" "Closes #123"
assert_file_contains_fixed "pr/SKILL.md で Refs の例が示されている" \
  "$PR_SKILL" "Refs #"

# ============================================
# 3. skills/ship/SKILL.md — ステップ 9 の --close 説明が Closes #N
# ============================================
echo ""
echo "--- 3. skills/ship/SKILL.md ---"

SHIP_SKILL="${SCRIPT_DIR}/skills/ship/SKILL.md"

if [[ ! -f "$SHIP_SKILL" ]]; then
  fail "skills/ship/SKILL.md が存在しない"
  exit 1
fi
pass "skills/ship/SKILL.md が存在する"

assert_file_contains_fixed "ship/SKILL.md で --close が Closes #N 形式と明記されている" \
  "$SHIP_SKILL" "Closes #N"

# ============================================
# 4. skills/pr-fix/SKILL.md — PR 本文修正時のキーワード保持
# ============================================
echo ""
echo "--- 4. skills/pr-fix/SKILL.md ---"

PRFIX_SKILL="${SCRIPT_DIR}/skills/pr-fix/SKILL.md"

if [[ ! -f "$PRFIX_SKILL" ]]; then
  fail "skills/pr-fix/SKILL.md が存在しない"
  exit 1
fi
pass "skills/pr-fix/SKILL.md が存在する"

assert_file_contains_fixed "pr-fix/SKILL.md で PR 本文修正時の Closes #N / Refs #N 保持が制約化されている" \
  "$PRFIX_SKILL" "Closes #N"
assert_file_contains_fixed "pr-fix/SKILL.md で Refs #N の言及がある" \
  "$PRFIX_SKILL" "Refs #N"

# ============================================
# 5. skills/release-epic/SKILL.md — リリース PR テンプレに Closes #<親番号>
# ============================================
echo ""
echo "--- 5. skills/release-epic/SKILL.md ---"

RELEASE_SKILL="${SCRIPT_DIR}/skills/release-epic/SKILL.md"

if [[ ! -f "$RELEASE_SKILL" ]]; then
  fail "skills/release-epic/SKILL.md が存在しない"
  exit 1
fi
pass "skills/release-epic/SKILL.md が存在する"

assert_file_contains_fixed "release-epic/SKILL.md のリリース PR テンプレに Closes #<親番号> が含まれる" \
  "$RELEASE_SKILL" "Closes #<親番号>"

# ============================================
# 6. skills/issue/SKILL.md — 関連 Issue 参照は Refs #N
# ============================================
echo ""
echo "--- 6. skills/issue/SKILL.md ---"

ISSUE_SKILL="${SCRIPT_DIR}/skills/issue/SKILL.md"

if [[ ! -f "$ISSUE_SKILL" ]]; then
  fail "skills/issue/SKILL.md が存在しない"
  exit 1
fi
pass "skills/issue/SKILL.md が存在する"

assert_file_contains_fixed "issue/SKILL.md に関連 Issue 参照のガイダンス（Refs #N）が追記されている" \
  "$ISSUE_SKILL" "Refs #N"
assert_file_contains_fixed "issue/SKILL.md で関連 Issue / PR への参照セクションが追加されている" \
  "$ISSUE_SKILL" "関連 Issue"

# ============================================
# 7. skills/plan-epic/SKILL.md — 子 Issue 本文は Refs #<親番号>
# ============================================
echo ""
echo "--- 7. skills/plan-epic/SKILL.md ---"

PLAN_EPIC_SKILL="${SCRIPT_DIR}/skills/plan-epic/SKILL.md"

if [[ ! -f "$PLAN_EPIC_SKILL" ]]; then
  fail "skills/plan-epic/SKILL.md が存在しない"
  exit 1
fi
pass "skills/plan-epic/SKILL.md が存在する"

assert_file_contains_fixed "plan-epic/SKILL.md の子 Issue テンプレに Refs #<親エピック番号> または Refs #<親番号> が含まれる" \
  "$PLAN_EPIC_SKILL" "Refs #<親"

print_test_summary
