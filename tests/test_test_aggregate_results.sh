#!/bin/bash
# test_test_aggregate_results.sh
# ─────────────────────────────────────────────
# Issue #625: .github/scripts/test-aggregate-results.sh の挙動テスト。
# 環境変数 SHELLCHECK_RESULT / UBUNTU_RESULT / MACOS_RESULT の組み合わせで
# 集約ジョブが pass / fail に分岐する挙動を網羅的に検証する。
#
# 集約ジョブは Branch Protection の required check として機能する。
# 誤判定はリリース全体の品質に直結するため、状態組み合わせを表で検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

TARGET="${SCRIPT_DIR}/.github/scripts/test-aggregate-results.sh"

if [ ! -x "$TARGET" ]; then
  fail "test-aggregate-results.sh が存在し実行可能である"
  exit 1
fi

echo "=== Issue #625: test-aggregate-results.sh の挙動テスト ==="
echo ""

# run_aggregate <shellcheck> <ubuntu> <macos>
# 集約スクリプトを 3 結果で実行し、終了コードを返す。stdout は捨てる。
run_aggregate() {
  local sc_result="$1"
  local ubuntu_result="$2"
  local macos_result="$3"
  local exit_code=0
  SHELLCHECK_RESULT="$sc_result" \
    UBUNTU_RESULT="$ubuntu_result" \
    MACOS_RESULT="$macos_result" \
    bash "$TARGET" >/dev/null 2>&1 || exit_code=$?
  echo "$exit_code"
}

echo "--- ケース 1: 全 success → pass ---"
rc=$(run_aggregate "success" "success" "success")
assert_exit_code "全 success は exit 0" "0" "$rc"

echo "--- ケース 2: PR シナリオ（macOS skipped） → pass ---"
rc=$(run_aggregate "success" "success" "skipped")
assert_exit_code "macOS skipped は pass" "0" "$rc"

# --- ケース 3: shellcheck skipped（仮想ケース） → pass ---
echo "--- ケース 3: 全 skipped 含む組み合わせも pass ---"
rc=$(run_aggregate "skipped" "success" "skipped")
assert_exit_code "skipped は success 同等として pass" "0" "$rc"

echo "--- ケース 4: shellcheck failure → fail ---"
rc=$(run_aggregate "failure" "success" "skipped")
assert_exit_code "shellcheck failure で exit 1" "1" "$rc"

echo "--- ケース 5: ubuntu failure → fail ---"
rc=$(run_aggregate "success" "failure" "skipped")
assert_exit_code "ubuntu failure で exit 1" "1" "$rc"

echo "--- ケース 6: macos failure → fail ---"
rc=$(run_aggregate "success" "success" "failure")
assert_exit_code "macos failure で exit 1" "1" "$rc"

# --- ケース 7: cancelled → fail（異常終了扱い） ---
echo "--- ケース 7: cancelled → fail ---"
rc=$(run_aggregate "success" "cancelled" "skipped")
assert_exit_code "cancelled は fail 扱い" "1" "$rc"

echo "--- ケース 8: 未知の result → fail ---"
rc=$(run_aggregate "success" "neutral" "skipped")
assert_exit_code "未知の result（neutral）は fail" "1" "$rc"

# --- ケース 9: stdout に各ジョブの結果が表示される ---
echo "--- ケース 9: stdout 出力の検証 ---"
output=$(SHELLCHECK_RESULT="success" UBUNTU_RESULT="success" MACOS_RESULT="skipped" bash "$TARGET" 2>&1)
if echo "$output" | grep -q "shellcheck: success"; then
  pass "出力に shellcheck の結果が含まれる"
else
  fail "出力に shellcheck の結果が含まれない: $output"
fi
if echo "$output" | grep -q "test-ubuntu: success"; then
  pass "出力に test-ubuntu の結果が含まれる"
else
  fail "出力に test-ubuntu の結果が含まれない: $output"
fi
if echo "$output" | grep -q "test-macos: skipped"; then
  pass "出力に test-macos の結果が含まれる"
else
  fail "出力に test-macos の結果が含まれない: $output"
fi

echo ""
print_test_summary
