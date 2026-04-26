#!/bin/bash
# test_helpers.sh — tests/ 配下で共通利用するアサーション・カウンタ・サマリ
# source 専用: 直接実行しても何もしない
#
# 使い方:
#   set -euo pipefail
#   TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck disable=SC1091
#   source "${TESTS_DIR}/lib/test_helpers.sh"
#
# 提供するもの:
#   - カウンタ変数: PASSED / FAILED / TOTAL（初期化済み）
#   - アサーション: pass / fail / assert_eq / assert_equals /
#     assert_file_exists / assert_file_not_exists / assert_dir_exists /
#     assert_file_contains / assert_file_not_contains /
#     assert_file_executable / assert_exit_code
#   - 結果出力: print_test_summary（末尾で呼ぶ、FAILED>0 で exit 1）
#
# 制約:
#   - macOS の bash 3.2 と Ubuntu の bash 5.x の両方で動作する範囲の構文を使う
#     （連想配列・local -n・printf %()T など bash 4+ の機能を避ける）
#   - 呼び出し側の set -euo pipefail を変更しない
#   - trap を登録しない（呼び出し側のクリーンアップ機構を阻害しない）

PASSED=0
FAILED=0
TOTAL=0

# --- カウンタ更新ヘルパー ---

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

# --- 値比較 ---

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (期待: '${expected}', 実際: '${actual}')"
  fi
}

# 既存呼び出し互換のため assert_equals を assert_eq のエイリアスとして提供する
assert_equals() {
  assert_eq "$@"
}

# --- 終了コード ---

assert_exit_code() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (期待: exit ${expected}, 実際: exit ${actual})"
  fi
}

# --- ファイル / ディレクトリ存在 ---

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: ${path})"
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在する: ${path})"
  fi
}

assert_dir_exists() {
  local desc="$1"
  local path="$2"
  if [ -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在しない: ${path})"
  fi
}

assert_file_executable() {
  local desc="$1"
  local path="$2"
  if [ -x "$path" ]; then
    pass "$desc"
  else
    fail "$desc (実行権限なし: ${path})"
  fi
}

# --- 内容パターン ---
# 注意: pattern が `-` で始まる場合の grep オプション誤認を防ぐため -e を明示する
# （.claude/rules/shell.md「grep で - 始まりのパターンを検索する場合」参照）

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -e "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

assert_file_not_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if ! grep -q -e "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれている: ${path})"
  fi
}

# --- 結果出力 ---

print_test_summary() {
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

  if [ "$FAILED" -gt 0 ]; then
    exit 1
  fi
}
