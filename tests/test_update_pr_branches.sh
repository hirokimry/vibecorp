#!/bin/bash
# test_update_pr_branches.sh — update-pr-branches.yml のロジックテスト
# 使い方: bash tests/test_update_pr_branches.sh

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
WORKFLOW_FILE="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/update-pr-branches.yml"

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

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

assert_equals() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (期待: '$expected', 実際: '$actual')"
  fi
}

# ファイルに対して直接 grep する（大きなファイルの変数展開問題を回避）
assert_file_contains() {
  local desc="$1"
  local file="$2"
  local needle="$3"
  if grep -q "$needle" "$file"; then
    pass "$desc"
  else
    fail "$desc (パターン '$needle' がファイル '$file' に見つからない)"
  fi
}

# --- ワークフローファイル構造テスト ---

echo "=== ワークフローファイル構造テスト ==="

test_workflow_uses_pat() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "GH_TOKEN に secrets.PAT を使用している" "$content" 'secrets.PAT'
  assert_not_contains "GITHUB_TOKEN を使用していない" "$content" 'secrets.GITHUB_TOKEN'
}

test_workflow_has_pat_guard() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "PAT 未設定時のガードがある" "$content" 'if \[ -z "\${GH_TOKEN}"'
  assert_contains "PAT 未設定時に warning を出力する" "$content" '::warning::'
}

test_workflow_no_include_pattern() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_not_contains "--include パターンを使用していない" "$content" '\-\-include'
  assert_not_contains "head -1 | awk パターンを使用していない" "$content" 'head -1 | awk'
}

test_workflow_has_conflict_category() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "CONFLICT カウンタがある" "$content" 'CONFLICT='
  assert_contains "merge conflict の判定がある" "$content" 'merge conflict'
  assert_contains "CONFLICT_PRS 変数がある" "$content" 'CONFLICT_PRS'
}

test_workflow_has_skipped_category() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "already up to date の判定がある" "$content" 'already up to date'
  assert_contains "SKIPPED カウンタがある" "$content" 'SKIPPED='
}

test_workflow_has_four_categories_in_summary() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "サマリーに更新成功がある" "$content" '更新成功:'
  assert_contains "サマリーにコンフリクトがある" "$content" 'コンフリクト:'
  assert_contains "サマリーにスキップがある" "$content" 'スキップ'
  assert_contains "サマリーに失敗がある" "$content" '失敗:'
}

test_workflow_has_conflict_pr_list() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "コンフリクト PR 一覧の出力がある" "$content" 'コンフリクト PR:'
}

test_workflow_uses_pagination() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  assert_contains "PR 一覧取得でページネーションを使用している" "$content" '\-\-paginate'
}

test_workflow_uses_exit_code_pattern() {
  local content
  content=$(cat "$WORKFLOW_FILE")
  # gh api ... && { success } || { failure } パターンを使用している
  assert_contains "終了コードで成功/失敗を分岐している" "$content" 'RESPONSE=.*gh api'
}

test_workflow_uses_pat
test_workflow_has_pat_guard
test_workflow_no_include_pattern
test_workflow_has_conflict_category
test_workflow_has_skipped_category
test_workflow_has_four_categories_in_summary
test_workflow_has_conflict_pr_list
test_workflow_uses_pagination
test_workflow_uses_exit_code_pattern

# --- README PAT セクションテスト ---

echo ""
echo "=== README PAT セクションテスト ==="

README_FILE="$(cd "$(dirname "$0")/.." && pwd)/README.md"

test_readme_has_pat_section() {
  assert_file_contains "PAT セットアップセクションがある" "$README_FILE" '## PAT セットアップ'
  assert_file_contains "Fine-grained PAT の作成手順がある" "$README_FILE" 'Fine-grained PAT'
  assert_file_contains "gh secret set コマンドがある" "$README_FILE" 'gh secret set PAT'
  assert_file_contains "注意事項セクションがある" "$README_FILE" '### 注意事項'
}

test_readme_has_pat_section

# --- 結果 ---

echo ""
echo "=== 結果 ==="
echo "合計: ${TOTAL} / 成功: ${PASSED} / 失敗: ${FAILED}"

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
