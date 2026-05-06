#!/bin/bash
# test_pr_intent_inherit.sh
# ─────────────────────────────────────────────
# Issue #487: PR が Issue から intent ラベルを継承する機構の検証
# Issue #517: 旧 pr-intent-inherit.yml を削除し、継承ロジックを ai-review.yml の
#             intent-label-check ジョブの先頭ステップに統合した（CI race 解消）。
#
# 本テストは継承機構の **責務** を維持しつつ、検証対象を新しい配置（ai-review.yml 内）に
# 切り替えた。継承ステップが数チェックステップの **前** に存在することは
# tests/test_intent_label_ci_race.sh が別途検証する。

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
echo "=== Issue #487 PR intent ラベル継承機構の検証（ai-review.yml 統合後） ==="

WF="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

# ============================================
# 1. ai-review.yml ワークフロー（継承ステップ統合済み）
# ============================================
echo ""
echo "--- 1. ai-review.yml の継承ステップ統合確認 ---"
assert_file_exists "templates 側 ai-review.yml" "$WF"
assert_file_contains "PR opened/synchronize/ready_for_review トリガー" "$WF" "opened, synchronize, ready_for_review"
assert_file_contains "Fork PR 除外"              "$WF" "head.repo.full_name == github.repository"
assert_file_contains "draft 除外"                "$WF" "!github.event.pull_request.draft"
assert_file_contains "permissions: pull-requests: write" "$WF" "pull-requests: write"
assert_file_contains "permissions: issues: write"  "$WF" "issues: write"
assert_file_contains "継承ステップ名"              "$WF" "対応 Issue から intent ラベルを継承"

# gh コマンドの --repo "$REPO" 明示は引数順序に依存しない形で検査
# 該当 gh コマンドを含む **全ての行** に --repo "$REPO" が含まれることを確認
assert_line_has_repo_flag() {
  local desc="$1"
  local cmd_pattern="$2"
  local matched_lines without_repo total
  matched_lines="$(grep -E -- "$cmd_pattern" "$WF" || true)"
  if [ -z "$matched_lines" ]; then
    fail "$desc (パターン '${cmd_pattern}' に一致する行が見つからない: ${WF})"
    return
  fi
  total=$(printf '%s\n' "$matched_lines" | wc -l | tr -d ' ')
  without_repo=$( { printf '%s\n' "$matched_lines" | grep -v -F -- '--repo "$REPO"' || true; } | wc -l | tr -d ' ')
  if [ "$without_repo" -eq 0 ]; then
    pass "$desc (全 ${total} 行で --repo \"\$REPO\" 確認)"
  else
    fail "$desc (${total} 行中 ${without_repo} 行で --repo \"\$REPO\" が欠けている: ${WF})"
  fi
}
assert_line_has_repo_flag "gh pr view に --repo 明示"    'gh pr view "\$PR_NUMBER"'
assert_line_has_repo_flag "gh pr comment に --repo 明示" 'gh pr comment "\$PR_NUMBER"'
assert_line_has_repo_flag "gh pr edit に --repo 明示"    'gh pr edit "\$PR_NUMBER"'
assert_file_not_contains   "gh issue edit を PR に使わない" "$WF" "gh issue edit"

# ============================================
# 2. Issue 番号抽出のキーワード対応
# ============================================
echo ""
echo "--- 2. Issue 番号抽出のキーワード対応 ---"
assert_file_contains_fixed "close キーワード"     "$WF" "close"
assert_file_contains_fixed "fix キーワード"       "$WF" "fix"
assert_file_contains_fixed "resolve キーワード"   "$WF" "resolve"
assert_file_contains_fixed "refs キーワード"      "$WF" "refs"
assert_file_contains_fixed "Issue URL マッチ"     "$WF" "issues/[0-9]+"
assert_file_contains_fixed "#番号 マッチ"          "$WF" "#[0-9]+"

# ============================================
# 3. intent ホワイトリスト 7 種
# ============================================
echo ""
echo "--- 3. intent ホワイトリスト 7 種 ---"
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -q -F -- "\"$intent\"" "$WF"; then
    pass "ホワイトリストに '$intent' 含む"
  else
    fail "ホワイトリストに '$intent' 含まない"
  fi
done

# ============================================
# 4. ラベル継承ロジック
# ============================================
echo ""
echo "--- 4. ラベル継承ロジック ---"
assert_file_contains       "重複付与防止"               "$WF" "既に PR に同じ intent ラベル"
assert_file_contains_fixed "Issue 側 intent 不在時の警告" "$WF" "intent/* ラベルが付与されていません"

# ============================================
# 5. /vibecorp:pr スキル側の継承
# ============================================
echo ""
echo "--- 5. /vibecorp:pr スキル側の継承 ---"
assert_file_contains_fixed "Issue から intent 取得 (スキル側)"  "$SKILL" "intent/* ラベルを取得"
assert_file_contains       "gh pr create に --label で渡す"   "$SKILL" "LABEL_ARGS"
assert_file_contains       "ホワイトリスト 7 種参照"          "$SKILL" "intent/feature"

# ============================================
# 6. install で配布される + 旧 workflow 削除確認
# ============================================
echo ""
echo "--- 6. install 配布版でも反映 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal
R="$TMPDIR_ROOT"

assert_file_exists "配布: ai-review.yml"               "$R/.github/workflows/ai-review.yml"
# Issue #517: 旧 pr-intent-inherit.yml は配布されないこと
if [ -f "$R/.github/workflows/pr-intent-inherit.yml" ]; then
  fail "旧 pr-intent-inherit.yml が配布対象に残っている（Issue #517 で削除済みのはず）"
else
  pass "旧 pr-intent-inherit.yml が配布対象から削除されている"
fi
cleanup

print_test_summary
