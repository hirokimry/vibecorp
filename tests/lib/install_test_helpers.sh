#!/bin/bash
# install_test_helpers.sh — install.sh 統合テストの共通ヘルパー
# source 専用: 直接実行しても何もしない
# 使い方:
#   source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"
#
# 提供するもの:
#   - カウンタ変数: PASSED / FAILED / TOTAL / TMPDIR_ROOT / INSTALL_SH / SCRIPT_DIR
#   - アサーション: pass / fail / assert_exit_code / assert_file_exists /
#     assert_file_not_exists / assert_dir_exists / assert_file_contains /
#     assert_file_not_contains / assert_file_executable
#   - セットアップ: create_test_repo / run_install / cleanup / require_darwin
#   - 後処理: trap cleanup EXIT を自動登録
#   - 結果出力: print_test_summary（末尾で呼ぶ、FAILED>0 で exit 1）

# source 呼び出し側の SCRIPT_DIR を尊重しつつ、未定義なら自動解決する
if [ -z "${SCRIPT_DIR:-}" ]; then
  # shellcheck disable=SC2155
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
INSTALL_SH="${SCRIPT_DIR}/install.sh"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""

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

assert_exit_code() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (期待: exit $expected, 実際: exit $actual)"
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: $path)"
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在する: $path)"
  fi
}

assert_dir_exists() {
  local desc="$1"
  local path="$2"
  if [ -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在しない: $path)"
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -e "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
  fi
}

assert_file_not_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if ! grep -q -e "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれている: $path)"
  fi
}

assert_file_executable() {
  local desc="$1"
  local path="$2"
  if [ -x "$path" ]; then
    pass "$desc"
  else
    fail "$desc (実行権限なし: $path)"
  fi
}

# --- セットアップ / クリーンアップ ---

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

run_install() {
  local exit_code=0
  bash "$INSTALL_SH" "$@" 2>/dev/null || exit_code=$?
  echo "$exit_code"
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    # 擬似 git リポジトリ・chmod 操作・シンボリックリンクを含むテストがあるため、
    # rm -rf の一時的失敗がテスト結果に波及しないように `|| true` で失敗を無害化する。
    # 詳細: .claude/rules/testing.md「trap cleanup EXIT でのリソース解放」
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# Darwin 限定テストで使用する skip ヘルパー
require_darwin() {
  local desc="$1"
  local os
  os=$(uname -s)
  if [ "$os" = "Darwin" ]; then
    return 0
  fi
  pass "${desc} (Darwin 以外のためスキップ)"
  return 1
}

# --- 結果出力 ---

print_test_summary() {
  echo ""
  echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

  if [ "$FAILED" -gt 0 ]; then
    exit 1
  fi
}
