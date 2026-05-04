#!/bin/bash
# test_final_verification_artifacts.sh
# ─────────────────────────────────────────────
# Issue #475: 実機検証期間（2 週間並走）の運用基盤アーティファクトを検証

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
echo "=== Issue #475 実機検証運用基盤アーティファクトの検証 ==="

ROLLBACK="${SCRIPT_DIR}/docs/ai-review-rollback.md"
SUMMARY_TPL="${SCRIPT_DIR}/.claude/knowledge/cfo/templates/weekly-summary.md"
DEPENDENCY="${SCRIPT_DIR}/docs/ai-review-dependency.md"

# ============================================
# 1. ロールバック手順 docs
# ============================================
echo ""
echo "--- 1. docs/ai-review-rollback.md ---"
assert_file_exists "ロールバック手順ファイルが存在" "$ROLLBACK"
assert_file_contains       "claude_action のみが対象"        "$ROLLBACK" "claude-code-action のみ"
assert_file_contains_fixed "claude_action.enabled: false 手順" "$ROLLBACK" "claude_action:"
assert_file_contains_fixed "install.sh --update 手順"        "$ROLLBACK" "install.sh --update"
assert_file_contains       "Branch Protection 手動戻し"      "$ROLLBACK" "手動で実施"
assert_file_contains_fixed "スクリプト化しない明記"            "$ROLLBACK" "スクリプト化はしない"
assert_file_contains_fixed "再有効化手順"                     "$ROLLBACK" "再有効化"

# ============================================
# 2. 週次サマリテンプレート
# ============================================
echo ""
echo "--- 2. .claude/knowledge/cfo/templates/weekly-summary.md ---"
assert_file_exists "週次サマリテンプレが存在" "$SUMMARY_TPL"
assert_file_contains_fixed "A 契約レート消費"          "$SUMMARY_TPL" "A 契約"
assert_file_contains_fixed "B 契約 4 契約動作確認"      "$SUMMARY_TPL" "B 契約"
assert_file_contains       "Claude Max トークン消費"   "$SUMMARY_TPL" "Claude Max"
assert_file_contains_fixed "90M token/月の目安"        "$SUMMARY_TPL" "90M token"
assert_file_contains       "auto-review 行"            "$SUMMARY_TPL" "auto-review"
assert_file_contains       "approve 切替行"            "$SUMMARY_TPL" "approve"
assert_file_contains       "auto-resolve 行"           "$SUMMARY_TPL" "auto-resolve"
assert_file_contains       "日本語レビュー行"           "$SUMMARY_TPL" "日本語"
assert_file_contains       "ロールバック判断"           "$SUMMARY_TPL" "ロールバック"
assert_file_contains_fixed "重複指摘率の集計"           "$SUMMARY_TPL" "重複指摘率"

# ============================================
# 3. C*O 合議基準 docs
# ============================================
echo ""
echo "--- 3. docs/ai-review-dependency.md の C*O 合議セクション ---"
assert_file_contains "実機検証完了判定"      "$DEPENDENCY" "実機検証完了判定"
assert_file_contains "完了判定基準 A + B"   "$DEPENDENCY" "完了判定基準"
assert_file_contains "C*O 合議"             "$DEPENDENCY" "C*O 合議"
assert_file_contains "CFO 評価観点"          "$DEPENDENCY" "CFO"
assert_file_contains "CISO 評価観点"         "$DEPENDENCY" "CISO"
assert_file_contains "CTO 評価観点"          "$DEPENDENCY" "CTO"
assert_file_contains "CPO 評価観点"          "$DEPENDENCY" "CPO"
assert_file_contains "本番運用の定義"        "$DEPENDENCY" "本番運用"
assert_file_contains "cadence 24h → 36h"  "$DEPENDENCY" "24h"
assert_file_contains "NG 時の対応"           "$DEPENDENCY" "NG 時の対応"
assert_file_contains_fixed "ロールバック手順への参照" "$DEPENDENCY" "ai-review-rollback.md"
assert_file_contains_fixed "週次サマリテンプレへの参照" "$DEPENDENCY" "weekly-summary.md"

# ============================================
# 4. C・D 契約は判定外であることが明記されている
# ============================================
echo ""
echo "--- 4. C・D 契約の判定外明記 ---"
assert_file_contains "判定外（並走で観測）" "$DEPENDENCY" "判定外"
assert_file_contains "二重指摘ノイズ"        "$DEPENDENCY" "二重指摘"
assert_file_contains "利用者不満"            "$DEPENDENCY" "利用者不満"

print_test_summary
