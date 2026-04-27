#!/bin/bash
# test_completion_criteria_template.sh — Issue #437 完了条件・関連ファイルテンプレ追加の検証
# 使い方: bash tests/test_completion_criteria_template.sh
# CI: GitHub Actions で自動実行
#
# 検証対象（Issue #437 完了条件）:
#   1. .github/ISSUE_TEMPLATE/feature_request.md / bug_report.md に
#      「## ✅ 完了条件」「## 📍 関連ファイル」セクションが追加されている
#   2. templates/.github/ISSUE_TEMPLATE/ 配下にも同等セクションが追加されている
#   3. skills/issue/SKILL.md ステップ 2 が「タイトル / 本文 / 完了条件 / 関連ファイル」
#      の 4 項目を 1 ターンでバッチ質問する記述になっている
#   4. skills/issue/SKILL.md ステップ 6b CPO 判定基準に Anthropic 公式 4 要素チェックがある
#   5. skills/diagnose/SKILL.md の自律起票テンプレに 2 セクションが含まれる
#   6. skills/plan-epic/SKILL.md 親 Issue 本文テンプレに「## 📍 関連ファイル」がある
#   7. user interaction を増やしていないこと（複数ターン化していない）が
#      SKILL.md の手順記述で明らかである

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

GITHUB_FEATURE="${SCRIPT_DIR}/.github/ISSUE_TEMPLATE/feature_request.md"
GITHUB_BUG="${SCRIPT_DIR}/.github/ISSUE_TEMPLATE/bug_report.md"
TEMPLATES_FEATURE="${SCRIPT_DIR}/templates/.github/ISSUE_TEMPLATE/feature_request.md"
TEMPLATES_BUG="${SCRIPT_DIR}/templates/.github/ISSUE_TEMPLATE/bug_report.md"
ISSUE_SKILL="${SCRIPT_DIR}/skills/issue/SKILL.md"
DIAGNOSE_SKILL="${SCRIPT_DIR}/skills/diagnose/SKILL.md"
PLAN_EPIC_SKILL="${SCRIPT_DIR}/skills/plan-epic/SKILL.md"

# ============================================
echo "=== Issue #437 完了条件・関連ファイルテンプレ追加 ==="
# ============================================

# --- A. .github/ISSUE_TEMPLATE/ への追加 ---

echo "--- A. .github/ISSUE_TEMPLATE/ への追加 ---"

assert_file_exists ".github/ISSUE_TEMPLATE/feature_request.md が存在する" "$GITHUB_FEATURE"
assert_file_exists ".github/ISSUE_TEMPLATE/bug_report.md が存在する" "$GITHUB_BUG"

if [[ ! -f "$GITHUB_FEATURE" ]] || [[ ! -f "$GITHUB_BUG" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

assert_file_contains "feature_request.md に「## ✅ 完了条件」セクションがある" "$GITHUB_FEATURE" "^## ✅ 完了条件"
assert_file_contains "feature_request.md に「## 📍 関連ファイル」セクションがある" "$GITHUB_FEATURE" "^## 📍 関連ファイル"
assert_file_contains "feature_request.md に acceptance criteria の語が含まれる" "$GITHUB_FEATURE" "acceptance criteria"
assert_file_contains "feature_request.md に relevant file locations の語が含まれる" "$GITHUB_FEATURE" "relevant file locations"

assert_file_contains "bug_report.md に「## ✅ 完了条件」セクションがある" "$GITHUB_BUG" "^## ✅ 完了条件"
assert_file_contains "bug_report.md に「## 📍 関連ファイル」セクションがある" "$GITHUB_BUG" "^## 📍 関連ファイル"
assert_file_contains "bug_report.md に acceptance criteria の語が含まれる" "$GITHUB_BUG" "acceptance criteria"
assert_file_contains "bug_report.md に relevant file locations の語が含まれる" "$GITHUB_BUG" "relevant file locations"

# --- B. templates/.github/ISSUE_TEMPLATE/ への追加 ---

echo "--- B. templates/.github/ISSUE_TEMPLATE/ への追加 ---"

assert_file_exists "templates/.github/ISSUE_TEMPLATE/feature_request.md が存在する" "$TEMPLATES_FEATURE"
assert_file_exists "templates/.github/ISSUE_TEMPLATE/bug_report.md が存在する" "$TEMPLATES_BUG"

if [[ ! -f "$TEMPLATES_FEATURE" ]] || [[ ! -f "$TEMPLATES_BUG" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

assert_file_contains "templates feature_request.md に「## ✅ 完了条件」がある" "$TEMPLATES_FEATURE" "^## ✅ 完了条件"
assert_file_contains "templates feature_request.md に「## 📍 関連ファイル」がある" "$TEMPLATES_FEATURE" "^## 📍 関連ファイル"
assert_file_contains "templates bug_report.md に「## ✅ 完了条件」がある" "$TEMPLATES_BUG" "^## ✅ 完了条件"
assert_file_contains "templates bug_report.md に「## 📍 関連ファイル」がある" "$TEMPLATES_BUG" "^## 📍 関連ファイル"

# --- C. skills/issue/SKILL.md ステップ 2: 1 ターンバッチ質問 ---

echo "--- C. skills/issue/SKILL.md ステップ 2: 1 ターンバッチ質問 ---"

assert_file_exists "skills/issue/SKILL.md が存在する" "$ISSUE_SKILL"

if [[ ! -f "$ISSUE_SKILL" ]]; then
  exit 1
fi

# 1 ターンバッチ質問の明記
assert_file_contains "ステップ 2 が 1 ターンバッチ質問である記述がある" "$ISSUE_SKILL" "1 ターンバッチ質問"
assert_file_contains "1 ターンでバッチ質問する記述がある" "$ISSUE_SKILL" "1 ターンでバッチ質問"

# user interaction を増やしていない明記（複数ターンに分けない）
assert_file_contains "複数ターンに分けない記述がある（user interaction 維持）" "$ISSUE_SKILL" "複数ターンに分けない"
assert_file_contains "Reduce user interactions 原則の参照がある" "$ISSUE_SKILL" "Reduce the number of required user interactions"

# 4 項目（タイトル / 本文 / 完了条件 / 関連ファイル）の列挙
assert_file_contains "ヒアリング項目: タイトルがある" "$ISSUE_SKILL" "\*\*タイトル\*\*"
assert_file_contains "ヒアリング項目: 本文がある" "$ISSUE_SKILL" "\*\*本文\*\*"
assert_file_contains "ヒアリング項目: 完了条件がある" "$ISSUE_SKILL" "\*\*完了条件\*\*"
assert_file_contains "ヒアリング項目: 関連ファイルがある" "$ISSUE_SKILL" "\*\*関連ファイル\*\*"

# 4 要素マッピング
assert_file_contains "intent への言及がある" "$ISSUE_SKILL" "intent"
assert_file_contains "constraints への言及がある" "$ISSUE_SKILL" "constraints"
assert_file_contains "acceptance criteria への言及がある" "$ISSUE_SKILL" "acceptance criteria"
assert_file_contains "relevant file locations への言及がある" "$ISSUE_SKILL" "relevant file locations"

# Anthropic 公式 best practices 参照
assert_file_contains "Anthropic 公式 Best practices への参照がある" "$ISSUE_SKILL" "Best practices for using Claude Opus 4.7"

# --- D. skills/issue/SKILL.md ステップ 6b CPO: 4 要素チェック ---

echo "--- D. skills/issue/SKILL.md ステップ 6b CPO: 4 要素チェック ---"

# CPO ステップで 4 要素チェックが追加されている
assert_file_contains "CPO ステップ見出しに 4 要素チェックの語がある" "$ISSUE_SKILL" "4 要素チェック"
assert_file_contains "CPO 判定基準に 4 要素列挙がある" "$ISSUE_SKILL" "intent / constraints / acceptance criteria / relevant file locations"

# 各要素のチェック観点が説明されている
assert_file_contains "CPO 判定: ✅ 完了条件 セクション要件" "$ISSUE_SKILL" "## ✅ 完了条件"
assert_file_contains "CPO 判定: 📍 関連ファイル セクション要件" "$ISSUE_SKILL" "## 📍 関連ファイル"
assert_file_contains "CPO 判定: 完了条件の空欄不可" "$ISSUE_SKILL" "空欄不可"

# --- E. skills/diagnose/SKILL.md 自律起票テンプレ ---

echo "--- E. skills/diagnose/SKILL.md 自律起票テンプレ ---"

assert_file_exists "skills/diagnose/SKILL.md が存在する" "$DIAGNOSE_SKILL"

if [[ ! -f "$DIAGNOSE_SKILL" ]]; then
  exit 1
fi

# 自律起票時の本文テンプレに 2 セクションが含まれる
assert_file_contains "diagnose 自律起票テンプレに「## ✅ 完了条件」がある" "$DIAGNOSE_SKILL" "^## ✅ 完了条件"
assert_file_contains "diagnose 自律起票テンプレに「## 📍 関連ファイル」がある" "$DIAGNOSE_SKILL" "^## 📍 関連ファイル"

# 自律起票時の本文テンプレ見出しがある
assert_file_contains "自律起票時の本文テンプレ見出しがある" "$DIAGNOSE_SKILL" "自律起票時の本文テンプレ"
assert_file_contains "diagnose で acceptance criteria への言及がある" "$DIAGNOSE_SKILL" "acceptance criteria"
assert_file_contains "diagnose で relevant file locations への言及がある" "$DIAGNOSE_SKILL" "relevant file locations"

# --- F. skills/plan-epic/SKILL.md 親 Issue 本文テンプレ ---

echo "--- F. skills/plan-epic/SKILL.md 親 Issue 本文テンプレ ---"

assert_file_exists "skills/plan-epic/SKILL.md が存在する" "$PLAN_EPIC_SKILL"

if [[ ! -f "$PLAN_EPIC_SKILL" ]]; then
  exit 1
fi

# 親 Issue 本文に 関連ファイルセクションが追加されている
# （完了基準セクションは既に存在するため、ここでは関連ファイルのみ確認）
assert_file_contains "plan-epic 親 Issue テンプレに「## 📍 関連ファイル」がある" "$PLAN_EPIC_SKILL" "^## 📍 関連ファイル"

# 既存の完了基準セクションは保持されている（リグレッション防止）
assert_file_contains "plan-epic に「## ✅ 完了基準」が保持されている" "$PLAN_EPIC_SKILL" "^## ✅ 完了基準"

# relevant file locations への言及
assert_file_contains "plan-epic で relevant file locations への言及がある" "$PLAN_EPIC_SKILL" "relevant file locations"

# ============================================
print_test_summary
