#!/bin/bash
# install_test_helpers.sh — install.sh 統合テストの共通ヘルパー
# source 専用: 直接実行しても何もしない
# 使い方:
#   source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"
#
# 提供するもの:
#   - tests/lib/test_helpers.sh の全機能（pass/fail/assert_eq/assert_file_*/print_test_summary 等）を再エクスポート
#   - 変数: INSTALL_SH / TMPDIR_ROOT / SCRIPT_DIR
#   - install 固有セットアップ: create_test_repo / run_install / cleanup / require_darwin
#   - 後処理: trap cleanup EXIT を自動登録

# まず共通ヘルパーを読み込む
HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HELPERS_DIR}/test_helpers.sh"

# source 呼び出し側の SCRIPT_DIR を尊重しつつ、未定義なら自動解決する
if [ -z "${SCRIPT_DIR:-}" ]; then
  # shellcheck disable=SC2155
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
INSTALL_SH="${SCRIPT_DIR}/install.sh"
TMPDIR_ROOT=""

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
