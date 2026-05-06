#!/bin/bash
# test_ai_review_approve_request.sh
# ─────────────────────────────────────────────
# Issue #467: severity 別の approve / request_changes 自動発行ロジック
#
# REVIEW.md.tpl に発行ルール（review-handling.md 捌き基準・認証エラー対処・挙動不変性誤分類検出）が
# 記載され、claude-code-action がこれに従って動作することを検証

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
echo "=== Issue #467 approve / request_changes 発行ルールの検証 ==="

TPL="${SCRIPT_DIR}/templates/REVIEW.md.tpl"

# ============================================
# 1. approve / request_changes 発行ルールセクション
# ============================================
echo ""
echo "--- 1. 発行ルールセクション ---"
assert_file_contains "approve / request_changes 発行 Step（指示書型に書換、Issue #521）" "$TPL" "approve / request_changes を発行する"
assert_file_contains "review-handling.md 捌き基準への参照"  "$TPL" "review-handling.md"

# ============================================
# 2. 修正対象判定（severity × intent 重視軸）
# ============================================
echo ""
echo "--- 2. 修正対象判定の severity × intent 連動 ---"
assert_file_contains "Critical / Major intent 問わず必須" "$TPL" "Critical / Major"
assert_file_contains "Minor / Trivial / Info 重視軸該当のみ" "$TPL" "重視軸"

# ============================================
# 3. 発行コマンド表
# ============================================
echo ""
echo "--- 3. 発行コマンド表 ---"
assert_file_contains_fixed "request-changes 発行（指示書型では gh pr review に変数引数、Issue #521）" "$TPL" "--request-changes"
assert_file_contains_fixed "approve 発行（指示書型では gh pr review に変数引数、Issue #521）"          "$TPL" "--approve"
assert_file_contains       "1 件以上で request_changes" "$TPL" "1 件以上"
assert_file_contains       "0 件で approve"             "$TPL" "0 件"

# ============================================
# 4. 認証エラー時の挙動
# ============================================
echo ""
echo "--- 4. 認証エラー時の挙動 ---"
assert_file_contains "認証エラー時のフォールバック Step（指示書型、Issue #521）"      "$TPL" "認証エラー時のフォールバック"
assert_file_contains "approve / request_changes は発行しない（認証エラー時）" "$TPL" "発行しない"
assert_file_contains "Bot 認証エラー警告本文（指示書型、Issue #521）"          "$TPL" "Bot 認証エラー"
assert_file_contains "Branch Protection に委ねる" "$TPL" "Branch Protection"

# ============================================
# 5. 挙動不変性誤分類検出時の挙動
# ============================================
echo ""
echo "--- 5. 挙動不変性誤分類検出時 ---"
assert_file_contains "誤分類検出 Step（指示書型 Step 9、Issue #521）"        "$TPL" "誤分類検出時"
assert_file_contains "影響を与えない系 PR 誤分類" "$TPL" "影響を与えない系"
assert_file_contains "intent ラベル再分類要求"    "$TPL" "intent ラベルを再分類"
assert_file_contains "review-observations.md 参照" "$TPL" "review-observations.md"

# ============================================
# 6. 関連設定への参照
# ============================================
echo ""
echo "--- 6. 関連設定への参照 ---"
assert_file_contains "review-handling.md 関連リンク"  "$TPL" "review-handling.md"
assert_file_contains "review-observations.md 関連"    "$TPL" "review-observations.md"
assert_file_contains "intent-labels.md 関連"          "$TPL" "intent-labels.md"

# ============================================
# 7. install で配布版にも反映される
# ============================================
echo ""
echo "--- 7. install 配布版にも反映 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "配布: REVIEW.md に approve/request_changes 発行 Step（Issue #521）" "$R/REVIEW.md" "approve / request_changes を発行する"
assert_file_contains_fixed "配布: request-changes（指示書型、Issue #521）" "$R/REVIEW.md" "--request-changes"
assert_file_contains_fixed "配布: approve（指示書型、Issue #521）"          "$R/REVIEW.md" "--approve"
cleanup

print_test_summary
