#!/bin/bash
# test_review_metrics.sh
# ─────────────────────────────────────────────
# Issue #474: CodeRabbit と claude-action の並走比較メトリクス収集スクリプトの検証

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== Issue #474 並走比較メトリクス収集の検証 ==="

RUNNER="${SCRIPT_DIR}/scripts/collect-review-metrics.sh"

# ============================================
# 1. スクリプトの存在と実行権限
# ============================================
echo ""
echo "--- 1. スクリプト配置と実行権限 ---"
assert_file_exists "scripts/collect-review-metrics.sh" "$RUNNER"
assert_file_executable "実行権限あり" "$RUNNER"

# ============================================
# 2. シェル構文 OK
# ============================================
echo ""
echo "--- 2. シェル構文チェック ---"
if bash -n "$RUNNER" >/dev/null 2>&1; then
  pass "bash -n で構文エラーなし"
else
  fail "bash -n で構文エラー"
fi

# ============================================
# 3. 主要なメトリクス項目の取り扱い
# ============================================
echo ""
echo "--- 3. メトリクス項目の網羅 ---"
assert_file_contains "指摘件数（total_count）の集計" "$RUNNER" "total_count"
assert_file_contains "severity 分布の集計"           "$RUNNER" "severity"
for sev in critical major minor trivial info; do
  if grep -q -F -- "$sev" "$RUNNER"; then
    pass "severity '$sev' を扱う"
  else
    fail "severity '$sev' を扱わない"
  fi
done

# ============================================
# 4. 重複判定（同じファイル内）
# ============================================
echo ""
echo "--- 4. 重複判定ロジック ---"
assert_file_contains "両ツール同じファイル判定" "$RUNNER" "both_tools"
assert_file_contains "coderabbit_only 集計"    "$RUNNER" "coderabbit_only"
assert_file_contains "claude_action_only 集計" "$RUNNER" "claude_action_only"
assert_file_contains "comm でのパス比較"        "$RUNNER" "comm"

# ============================================
# 5. 揮発データ保存先
# ============================================
echo ""
echo "--- 5. 揮発データ保存先 ---"
assert_file_contains "review-metrics ディレクトリ" "$RUNNER" "review-metrics"
assert_file_contains "vibecorp_stamp_dir 利用"     "$RUNNER" "vibecorp_stamp_dir"
# knowledge / git に書かないことを記述で確認
assert_file_contains "knowledge / git 含めない注記" "$RUNNER" "knowledge / git"

# ============================================
# 6. PR マージ済み判定
# ============================================
echo ""
echo "--- 6. PR マージ済み判定 ---"
assert_file_contains "PR_STATE チェック" "$RUNNER" 'PR_STATE'
assert_file_contains "MERGED 比較"        "$RUNNER" "MERGED"

# ============================================
# 7. 引数チェック
# ============================================
echo ""
echo "--- 7. 引数なしでエラー終了 ---"
output=$(bash "$RUNNER" 2>&1 || true)
if echo "$output" | grep -q -F -- "使い方"; then
  pass "引数なしで使い方を表示してエラー終了"
else
  fail "引数なしで適切なエラーメッセージが出ない"
fi

print_test_summary
