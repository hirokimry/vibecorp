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
assert_file_contains_fixed "claude-code-action のみが対象"        "$ROLLBACK" "claude-code-action のみ"
assert_file_contains_fixed "claude_action.enabled: false 手順" "$ROLLBACK" "claude_action.enabled: false"
assert_file_contains_fixed "install.sh --update 手順"        "$ROLLBACK" "install.sh --update"
assert_file_contains_fixed "Branch Protection 手動戻し"      "$ROLLBACK" "GitHub の UI または \`gh api\` で利用者が手動で実施"
assert_file_contains_fixed "スクリプト化しない明記"            "$ROLLBACK" "スクリプト化はしない"
assert_file_contains_fixed "再有効化手順"                     "$ROLLBACK" "再有効化"

# ============================================
# 2. 週次サマリテンプレート
# ============================================
echo ""
echo "--- 2. .claude/knowledge/cfo/templates/weekly-summary.md ---"
assert_file_exists "週次サマリテンプレが存在" "$SUMMARY_TPL"
assert_file_contains_fixed "A 契約レート消費"          "$SUMMARY_TPL" "1. レート消費（A 契約）"
assert_file_contains_fixed "B 契約 4 契約動作確認"      "$SUMMARY_TPL" "2. 4 契約動作確認（B 契約）"
assert_file_contains_fixed "Claude Max トークン消費"   "$SUMMARY_TPL" "Claude Max トークン消費"
assert_file_contains_fixed "90M token/月の目安"        "$SUMMARY_TPL" "90M token/月"
assert_file_contains_fixed "auto-review 行"            "$SUMMARY_TPL" "① auto-review"
assert_file_contains_fixed "approve 切替行"            "$SUMMARY_TPL" "② approve / request_changes 切替"
assert_file_contains_fixed "auto-resolve 行"           "$SUMMARY_TPL" "③ auto-resolve"
assert_file_contains_fixed "日本語レビュー行"           "$SUMMARY_TPL" "④ 日本語レビュー"
assert_file_contains_fixed "ロールバック判断"           "$SUMMARY_TPL" "ロールバック判断"
assert_file_contains_fixed "重複指摘率の集計"           "$SUMMARY_TPL" "重複指摘率"
assert_file_contains_fixed "完了判定 A+B のみ"        "$SUMMARY_TPL" "## 検証完了判定基準"
assert_file_contains_fixed "本番切替が別セクション"    "$SUMMARY_TPL" "## 本番運用切替判定（検証完了の後段）"

# ============================================
# 3. C*O 合議基準 docs
# ============================================
echo ""
echo "--- 3. docs/ai-review-dependency.md の C*O 合議セクション ---"
assert_file_contains_fixed "実機検証完了判定見出し"   "$DEPENDENCY" "## 実機検証完了判定（Issue #475 確定）"
assert_file_contains_fixed "完了判定基準 A + B"      "$DEPENDENCY" "### 完了判定基準（A + B）"
assert_file_contains_fixed "C*O 合議"                "$DEPENDENCY" "C*O 合議による本番運用切替"
assert_file_contains_fixed "CFO 評価観点"            "$DEPENDENCY" "| CFO |"
assert_file_contains_fixed "CISO 評価観点"           "$DEPENDENCY" "| CISO |"
assert_file_contains_fixed "CTO 評価観点"            "$DEPENDENCY" "| CTO |"
assert_file_contains_fixed "CPO 評価観点"            "$DEPENDENCY" "| CPO |"
assert_file_contains_fixed "本番運用の定義"          "$DEPENDENCY" "### 「本番運用」の定義"
assert_file_contains_fixed "cadence 24h → 36h"     "$DEPENDENCY" "cadence 24h → 36h に即伸長"
assert_file_contains_fixed "NG 時の対応"             "$DEPENDENCY" "### NG 時の対応"
assert_file_contains_fixed "ロールバック手順への参照" "$DEPENDENCY" "ai-review-rollback.md"
assert_file_contains_fixed "週次サマリテンプレへの参照" "$DEPENDENCY" "weekly-summary.md"

# ============================================
# 4. C・D 契約は判定外であることが明記されている
# ============================================
echo ""
echo "--- 4. C・D 契約の判定外明記 ---"
assert_file_contains_fixed "判定外（並走で観測）" "$DEPENDENCY" "**判定外**"
assert_file_contains_fixed "二重指摘ノイズ"        "$DEPENDENCY" "二重指摘ノイズ閾値"
assert_file_contains_fixed "利用者不満"            "$DEPENDENCY" "利用者不満ゼロ"

print_test_summary
