#!/bin/bash
# test_pr_intent_inherit.sh
# ─────────────────────────────────────────────
# Issue #487: PR が Issue から intent ラベルを継承する機構の検証

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

assert_file_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

echo ""
echo "=== Issue #487 PR intent ラベル継承機構の検証 ==="

WF="${SCRIPT_DIR}/templates/.github/workflows/pr-intent-inherit.yml"
SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

# ============================================
# 1. ワークフローファイル
# ============================================
echo ""
echo "--- 1. pr-intent-inherit.yml ワークフロー ---"
assert_file_exists "templates 側にワークフロー" "$WF"
assert_file_contains "PR opened/edited トリガー" "$WF" "opened, edited"
assert_file_contains "Fork PR 除外"              "$WF" "head.repo.full_name == github.repository"
assert_file_contains "draft 除外"                "$WF" "!github.event.pull_request.draft"
assert_file_contains "permissions: pull-requests: write" "$WF" "pull-requests: write"
assert_file_contains "permissions: issues: read"  "$WF" "issues: read"

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
# 6. install で配布される
# ============================================
echo ""
echo "--- 6. install 配布版でも反映 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "配布: pr-intent-inherit.yml" "$R/.github/workflows/pr-intent-inherit.yml"
cleanup

print_test_summary
