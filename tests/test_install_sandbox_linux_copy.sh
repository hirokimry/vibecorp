#!/bin/bash
# test_install_sandbox_linux_copy.sh — Issue #761: Linux で bwrap-args.sh が実体コピー配置されることを実行検証する
#
# 対象（実機 Linux での install.sh --preset full 実行時の配置）:
#   - .claude/sandbox/bwrap-args.sh が実体ファイル（symlink でない）で配置される
#     bwrap-args.sh は vibecorp-sandbox が source 実行するため、symlink にすると
#     Link Following 拒否ガード（#310）と衝突して隔離レイヤ起動が回帰する。
#     install.sh の symlink 分岐は macOS(claude.sb) にゲートされており、Linux では
#     self/user いずれの install でも実体コピーになることを実行レベルで担保する。
#   - macOS 専用プロファイル claude.sb は Linux には配置されない（OS 別選択）
#
# 静的検証（install.sh のゲート条件・vibecorp-sandbox のガード存在）は
# tests/test_sandbox_ssot_symlink.sh が担う。本テストは実機 Linux での配置を実行確認する。
#
# 非 Linux では早期 skip（macOS CI が赤くならないように）。bwrap 不在環境でも skip。
# CI（GitHub Actions ubuntu）は bubblewrap を install 済みのため本テストが実行される
# （bwrap の実起動は不要、check_isolation_deps は command -v bwrap のみ要求）。

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: tests/test_install_sandbox_linux_copy.sh は Linux 以外では実行しない（現在: $(uname -s)）"
  exit 0
fi

if ! command -v bwrap >/dev/null 2>&1; then
  echo "SKIP: bwrap がインストールされていないためスキップ（full preset の隔離依存チェックを通せない）"
  exit 0
fi

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
TMPDIR_ROOT=""

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# ============================================
echo "=== Linux full preset: sandbox の配置（bwrap-args.sh 実体コピー） ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"

# bwrap-args.sh が配置される（OS 該当ファイル）
assert_file_exists "L1: .claude/sandbox/bwrap-args.sh が配置される" "$R/.claude/sandbox/bwrap-args.sh"

# bwrap-args.sh は symlink ではなく実体コピー（source 実行 → Link Following ガード #310 と整合）
if [[ -L "$R/.claude/sandbox/bwrap-args.sh" ]]; then
  fail "L2: bwrap-args.sh が symlink（source 実行されるため実体コピーであるべき・回帰）"
else
  pass "L2: bwrap-args.sh は実体コピー（symlink でない）"
fi

# 内容が SSOT と一致する
if diff -q "${SCRIPT_DIR}/templates/claude/sandbox/bwrap-args.sh" "$R/.claude/sandbox/bwrap-args.sh" >/dev/null 2>&1; then
  pass "L3: bwrap-args.sh が SSOT と同一内容"
else
  fail "L3: bwrap-args.sh が SSOT と同一内容でない"
fi

# macOS 専用プロファイル claude.sb は Linux には配置されない（OS 別選択）
assert_file_not_exists "L4: Linux では claude.sb が配置されない" "$R/.claude/sandbox/claude.sb"

cleanup

print_test_summary
