#!/bin/bash
# test_repo_id_worktree.sh — vibecorp_repo_id が main / worktree で同一 ID を返すことを検証
# 使い方: bash tests/test_repo_id_worktree.sh
# CI: GitHub Actions で自動実行
#
# Issue #600 のリグレッション防止:
# - 旧実装は `git rev-parse --show-toplevel` ベースで worktree ごとに別 ID を生成し、
#   guide-gate / sync-gate / review-gate のスタンプ消費が成立しなかった。
# - 新実装は `git rev-parse --git-common-dir` ベースで main の .git を常に指すため、
#   main / 各 worktree のどこから呼んでも同一 ID が生成される。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/common.sh"

# 前提ファイル確認
if [[ ! -f "$LIB" ]]; then
  fail "前提: $LIB が存在する"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

# ============================================
echo "=== 一時 git リポジトリと worktree を作成 ==="
# ============================================

TMPROOT="$(mktemp -d)"

cleanup() {
  # worktree を先に除去（main を消すと worktree 側 git も壊れる）
  if [[ -d "${TMPROOT}/main" ]]; then
    git -C "${TMPROOT}/main" worktree remove --force "${TMPROOT}/wt1" 2>/dev/null || true
    git -C "${TMPROOT}/main" worktree remove --force "${TMPROOT}/wt2" 2>/dev/null || true
  fi
  rm -rf "$TMPROOT" || true
}
trap cleanup EXIT

# main リポジトリ作成（vibecorp という名前で）
mkdir -p "${TMPROOT}/main"
git -C "${TMPROOT}/main" init -q -b main
git -C "${TMPROOT}/main" config user.email "test@example.com"
git -C "${TMPROOT}/main" config user.name "test"
echo "init" > "${TMPROOT}/main/README.md"
git -C "${TMPROOT}/main" add README.md
git -C "${TMPROOT}/main" commit -q -m "init"

# worktree 2 つ作成（パス名は意図的に main と異なる）
git -C "${TMPROOT}/main" worktree add -q -b feature/test1 "${TMPROOT}/wt1" >/dev/null 2>&1
git -C "${TMPROOT}/main" worktree add -q -b feature/test2 "${TMPROOT}/wt2" >/dev/null 2>&1

pass "main / wt1 / wt2 の git リポジトリ準備"

# ============================================
echo ""
echo "=== vibecorp_repo_id が main / worktree で同一 ==="
# ============================================

# サブシェルで独立評価（CLAUDE_PROJECT_DIR の汚染を避ける）
ID_MAIN="$(unset CLAUDE_PROJECT_DIR; cd "${TMPROOT}/main" && bash -c "source '$LIB' && vibecorp_repo_id")"
ID_WT1="$(unset CLAUDE_PROJECT_DIR; cd "${TMPROOT}/wt1" && bash -c "source '$LIB' && vibecorp_repo_id")"
ID_WT2="$(unset CLAUDE_PROJECT_DIR; cd "${TMPROOT}/wt2" && bash -c "source '$LIB' && vibecorp_repo_id")"

echo "  main repo_id: $ID_MAIN"
echo "  wt1 repo_id:  $ID_WT1"
echo "  wt2 repo_id:  $ID_WT2"

assert_eq "main と wt1 の repo_id が一致する" "$ID_MAIN" "$ID_WT1"
assert_eq "main と wt2 の repo_id が一致する" "$ID_MAIN" "$ID_WT2"
assert_eq "wt1 と wt2 の repo_id が一致する" "$ID_WT1" "$ID_WT2"

# ============================================
echo ""
echo "=== ID の構成要素: basename は main 側の名前 ==="
# ============================================

# 期待: main ディレクトリ名は "main" なので prefix は "main-..."
# basename が main / wt1 / wt2 のどれを使うかで差が出る → main を採用していることを確認
case "$ID_WT1" in
  main-*)
    pass "worktree から呼んでも basename は main 側を使う"
    ;;
  *)
    fail "worktree から呼んだ basename が main を指していない（実際: '$ID_WT1'）"
    ;;
esac

# ============================================
echo ""
echo "=== CLAUDE_PROJECT_DIR が worktree でも main の repo_id が返る ==="
# ============================================

# 実運用: Claude Code 親プロセスは main で起動するが、子プロセスが worktree 内ファイルを
# 編集する際は CLAUDE_PROJECT_DIR=worktree でも main のスタンプを参照したい
ID_VIA_WT_ENV="$(CLAUDE_PROJECT_DIR="${TMPROOT}/wt1" bash -c "source '$LIB' && vibecorp_repo_id")"
assert_eq "CLAUDE_PROJECT_DIR=worktree でも main の repo_id が返る" "$ID_MAIN" "$ID_VIA_WT_ENV"

# ============================================
echo ""
echo "=== vibecorp_stamp_path / vibecorp_stamp_dir も worktree 共有 ==="
# ============================================

STAMP_MAIN="$(unset CLAUDE_PROJECT_DIR; cd "${TMPROOT}/main" && bash -c "source '$LIB' && vibecorp_stamp_path guide")"
STAMP_WT1="$(unset CLAUDE_PROJECT_DIR; cd "${TMPROOT}/wt1" && bash -c "source '$LIB' && vibecorp_stamp_path guide")"

assert_eq "guide スタンプパスが main / worktree で一致する" "$STAMP_MAIN" "$STAMP_WT1"

# ============================================
echo ""
echo "=== 非 git ディレクトリ: フォールバックで PWD ベースの ID を返す ==="
# ============================================

NON_GIT="${TMPROOT}/notgit"
mkdir -p "$NON_GIT"
ID_NON_GIT="$(unset CLAUDE_PROJECT_DIR; cd "$NON_GIT" && bash -c "source '$LIB' && vibecorp_repo_id" 2>/dev/null)"

# フォールバック ID は notgit ディレクトリ名で始まるはず（git common-dir 失敗 → start_dir に倒れる）
case "$ID_NON_GIT" in
  notgit-*)
    pass "非 git ディレクトリでフォールバック ID を返す"
    ;;
  *)
    fail "非 git ディレクトリでフォールバック ID が不正（実際: '$ID_NON_GIT'）"
    ;;
esac

# ============================================
echo ""
print_test_summary
