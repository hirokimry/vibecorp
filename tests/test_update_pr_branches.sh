#!/bin/bash
# test_update_pr_branches.sh — update-pr-branches.yml + 切り出しスクリプトのロジックテスト
# 使い方: bash tests/test_update_pr_branches.sh
#
# Issue #624 以降: ロジック本体は .github/scripts/check-update-pr-branches.sh に切り出されたため、
# 「ワークフロー yaml レベルの構造」と「スクリプト本体のロジック」を別々に検証する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_FILE="${REPO_ROOT}/.github/workflows/update-pr-branches.yml"
SCRIPT_FILE="${REPO_ROOT}/.github/scripts/check-update-pr-branches.sh"

assert_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s\n' "$haystack" | grep -q "$needle"; then
    pass "$desc"
  else
    fail "$desc (パターン '$needle' が見つからない)"
  fi
}

assert_not_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s\n' "$haystack" | grep -q "$needle"; then
    fail "$desc (パターン '$needle' が見つかった)"
  else
    pass "$desc"
  fi
}

# --- ワークフローファイル構造テスト（workflow yaml 自体に残す責務） ---

echo "=== ワークフローファイル構造テスト ==="

test_workflow_uses_pat() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "GH_TOKEN に secrets.PAT を使用している" "$content" 'secrets.PAT'
  assert_not_contains "GITHUB_TOKEN を使用していない" "$content" 'secrets.GITHUB_TOKEN'
}

test_workflow_no_include_pattern() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_not_contains "--include パターンを使用していない" "$content" '\-\-include'
  assert_not_contains "head -1 | awk パターンを使用していない" "$content" 'head -1 | awk'
}

test_workflow_calls_script() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "切り出した check-update-pr-branches.sh を呼び出している" "$content" '.github/scripts/check-update-pr-branches.sh'
}

test_workflow_uses_pat
test_workflow_no_include_pattern
test_workflow_calls_script

# --- 切り出しスクリプト構造テスト（ロジック本体は .github/scripts/ に移動済み） ---

echo ""
echo "=== 切り出しスクリプト（.github/scripts/check-update-pr-branches.sh）ロジックテスト ==="

assert_file_exists "切り出しスクリプトが存在する" "$SCRIPT_FILE"
assert_file_executable "切り出しスクリプトに実行権限がある" "$SCRIPT_FILE"

test_script_has_pat_guard() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "PAT 未設定時のガードがある" "$content" 'if \[ -z "\${GH_TOKEN'
  assert_contains "PAT 未設定時に warning を出力する" "$content" '::warning::'
}

test_script_has_conflict_category() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "CONFLICT カウンタがある" "$content" 'CONFLICT='
  assert_contains "merge conflict の判定がある" "$content" 'merge conflict'
  assert_contains "CONFLICT_PRS 変数がある" "$content" 'CONFLICT_PRS'
}

test_script_has_skipped_category() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "already up to date の判定がある" "$content" 'already up to date'
  assert_contains "SKIPPED カウンタがある" "$content" 'SKIPPED='
}

test_script_has_four_categories_in_summary() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "サマリーに更新成功がある" "$content" '更新成功:'
  assert_contains "サマリーにコンフリクトがある" "$content" 'コンフリクト:'
  assert_contains "サマリーにスキップがある" "$content" 'スキップ'
  assert_contains "サマリーに失敗がある" "$content" '失敗:'
}

test_script_has_conflict_pr_list() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "コンフリクト PR 一覧の出力がある" "$content" 'コンフリクト PR:'
}

test_script_uses_pagination() {
  local content
  content=$(cat "$SCRIPT_FILE")
  assert_contains "PR 一覧取得でページネーションを使用している" "$content" '\-\-paginate'
}

test_script_uses_exit_code_pattern() {
  local content
  content=$(cat "$SCRIPT_FILE")
  # if RESPONSE=$(gh api ...); then ... else ... fi パターンで終了コードで分岐
  # （旧 A && B || C パターンは SC2015 の誤判定リスクのため if/else に変更）
  assert_contains "終了コードで成功/失敗を分岐している" "$content" 'if RESPONSE=.*gh api'
}

test_script_has_pat_guard
test_script_has_conflict_category
test_script_has_skipped_category
test_script_has_four_categories_in_summary
test_script_has_conflict_pr_list
test_script_uses_pagination
test_script_uses_exit_code_pattern

# --- docs/ai-review-auth.md PAT セクションテスト ---
#
# Issue #569 で README から docs/ai-review-auth.md に移譲したため、参照先を更新。
# 移譲後の見出しは「## 9. PAT セットアップ（update-pr-branches ワークフロー用）」
# 注意事項見出しは「### 9-4. 注意事項」

echo ""
echo "=== docs/ai-review-auth.md PAT セクションテスト ==="

PAT_DOC_FILE="${REPO_ROOT}/docs/ai-review-auth.md"

test_pat_section_present() {
  assert_file_contains "PAT セットアップセクションがある" "$PAT_DOC_FILE" 'PAT セットアップ'
  assert_file_contains "Fine-grained PAT の作成手順がある" "$PAT_DOC_FILE" 'Fine-grained PAT'
  assert_file_contains "gh secret set コマンドがある" "$PAT_DOC_FILE" 'gh secret set PAT'
  assert_file_contains "注意事項セクションがある" "$PAT_DOC_FILE" '注意事項'
}

test_pat_section_present

# --- 結果 ---

print_test_summary
