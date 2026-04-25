#!/bin/bash
# test_install_merge_trap.sh — install.sh の一時ファイル trap が EXIT を含むことの検証 (#243)
#
# 検証対象:
#   merge_or_overwrite() / generate_claude_md() / generate_mvv_md() の3関数で
#   mktemp した一時ファイルの trap が EXIT を対象に含むこと。
#
# 目的:
#   trap が `INT TERM` のみだと set -e の途中失敗時に発動せず一時ファイルが
#   ディスクに残る（#243）。EXIT を含めて全終了経路でクリーンアップを保証する。
#
# 使い方: bash tests/test_install_merge_trap.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"

PASSED=0
FAILED=0
TOTAL=0

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

if [[ ! -f "$INSTALL_SH" ]]; then
  fail "install.sh が存在しない"
  exit 1
fi

echo "=== install.sh の一時ファイル trap 検証 (#243) ==="

# trap "rm -f ..." パターンで EXIT を含まないものが残っていないか検出
# - INT TERM のみで EXIT を含まない trap 行は #243 の修正対象だった
# - いずれの mktemp 一時ファイル trap も EXIT を含むことを保証する
non_exit_trap_count=$(awk '
  /trap "rm -f / {
    # この行に "EXIT" が含まれていなければ違反
    if ($0 !~ /EXIT/) print
  }
' "$INSTALL_SH" | wc -l | tr -d ' ')

if [[ "$non_exit_trap_count" -eq 0 ]]; then
  pass "tmp ファイルクリーンアップ trap は全て EXIT を対象に含む"
else
  fail "EXIT を含まない tmp 一時ファイル trap が ${non_exit_trap_count} 箇所残っている"
  awk '
    /trap "rm -f / {
      if ($0 !~ /EXIT/) printf "    L%d: %s\n", NR, $0
    }
  ' "$INSTALL_SH"
fi

# EXIT を対象にした trap "rm -f ..." が3箇所以上存在することを確認
# （merge_or_overwrite / generate_claude_md / generate_mvv_md の3関数分）
exit_trap_count=$(awk '
  /trap "rm -f / {
    if ($0 ~ /EXIT/) print
  }
' "$INSTALL_SH" | wc -l | tr -d ' ')

if [[ "$exit_trap_count" -ge 3 ]]; then
  pass "EXIT を含む tmp 一時ファイル trap が ${exit_trap_count} 箇所存在する（期待: 3 以上）"
else
  fail "EXIT を含む tmp 一時ファイル trap が ${exit_trap_count} 箇所のみ（期待: 3 以上）"
fi

# install.sh 全体の構文チェック
if bash -n "$INSTALL_SH" 2>/dev/null; then
  pass "install.sh の構文が妥当"
else
  fail "install.sh に構文エラーがある"
fi

echo ""
echo "=== 結果 ==="
echo "Total : $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
