#!/bin/bash
# test_knowledge_buffer_migration.sh — Issue #543: 旧構造 buffer worktree の自動 migration
#
# PR #344 (2026-04-18) で knowledge_buffer.sh が
#   ~/.cache/vibecorp/buffer-worktree/<repo-id>/
# の repo-id namespace 構造に変更された。それ以前に旧構造
#   ~/.cache/vibecorp/buffer-worktree/
# 直下に作られた worktree を新構造へ自動 migrate するロジックを検証する。
#
# 使い方: bash tests/test_knowledge_buffer_migration.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/knowledge_buffer.sh"
COMMON_LIB="${SCRIPT_DIR}/templates/claude/lib/common.sh"

if [ ! -f "$LIB" ]; then
  fail "knowledge_buffer.sh が存在しない: $LIB"
  exit 1
fi
if [ ! -f "$COMMON_LIB" ]; then
  fail "common.sh が存在しない: $COMMON_LIB"
  exit 1
fi

# 各テストごとに環境を作り直す（前のテストの worktree 状態に汚染されないため）
TMPDIR_ROOT=""
ORIGIN_REPO=""
WORK_REPO=""
LEGACY_DIR=""
NEW_DIR=""

setup_env() {
  TMPDIR_ROOT=$(mktemp -d)
  # macOS の /var → /private/var canonicalization 対策（git worktree list は canonical path を返すため）
  TMPDIR_ROOT="$(cd "$TMPDIR_ROOT" && pwd -P)"
  ORIGIN_REPO="${TMPDIR_ROOT}/origin.git"
  WORK_REPO="${TMPDIR_ROOT}/work"
  local cache_root="${TMPDIR_ROOT}/cache"

  git init --bare "$ORIGIN_REPO" >/dev/null 2>&1
  git -C "$ORIGIN_REPO" symbolic-ref HEAD refs/heads/main

  git init "$WORK_REPO" >/dev/null 2>&1
  git -C "$WORK_REPO" config user.email "test@example.com"
  git -C "$WORK_REPO" config user.name "Test User"
  git -C "$WORK_REPO" checkout -b main >/dev/null 2>&1
  echo "hello" > "${WORK_REPO}/README.md"
  git -C "$WORK_REPO" add README.md
  git -C "$WORK_REPO" commit -m "initial" >/dev/null 2>&1
  git -C "$WORK_REPO" remote add origin "$ORIGIN_REPO"
  git -C "$WORK_REPO" push -u origin main >/dev/null 2>&1

  export CLAUDE_PROJECT_DIR="$WORK_REPO"
  export XDG_CACHE_HOME="$cache_root"
  export VIBECORP_LOCK_TIMEOUT=2

  # shellcheck disable=SC1090
  source "$LIB"

  NEW_DIR="$(knowledge_buffer_worktree_dir)"
  LEGACY_DIR="$(dirname "$NEW_DIR")"
  mkdir -p "$LEGACY_DIR"
}

teardown_env() {
  if [ -n "${WORK_REPO:-}" ] && [ -d "$WORK_REPO/.git" ]; then
    git -C "$WORK_REPO" worktree prune >/dev/null 2>&1 || true
  fi
  if [ -n "${TMPDIR_ROOT:-}" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  TMPDIR_ROOT=""
  ORIGIN_REPO=""
  WORK_REPO=""
  LEGACY_DIR=""
  NEW_DIR=""
}

# 全 case 終了後に最終 cleanup（途中失敗時の保険）
trap teardown_env EXIT

# 旧構造 worktree を `git worktree add` で作る
# 引数: $1 = legacy_dir
create_legacy_worktree() {
  local legacy="$1"
  rm -rf "$legacy"
  mkdir -p "$(dirname "$legacy")"
  git -C "$WORK_REPO" worktree add -B knowledge/buffer "$legacy" origin/main >/dev/null 2>&1
}

# Worktree が登録されているか（git worktree list の path 完全一致）
is_worktree_registered() {
  local target="$1"
  git -C "$WORK_REPO" worktree list --porcelain 2>/dev/null \
    | awk -v target="$target" '
        /^worktree / { if ($2 == target) { print "yes"; exit } }
      ' \
    | grep -q yes
}

# ============================================
echo ""
echo "=== Issue #543: buffer worktree 旧構造 自動 migration ==="
# ============================================

# --- Case 1: 旧構造のみ存在 → 新構造へ migrate ---

echo ""
echo "--- Case 1: 旧構造のみ → 新構造へ migrate ---"
setup_env

# 旧構造 worktree を作成
create_legacy_worktree "$LEGACY_DIR"

# 前提確認
if is_worktree_registered "$LEGACY_DIR"; then
  pass "前提: 旧構造 worktree が登録されている"
else
  fail "前提: 旧構造 worktree が登録されていない"
  teardown_env
  exit 1
fi

# knowledge_buffer_ensure を実行
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "Case 1: ensure が migration 経路で成功する"
else
  fail "Case 1: ensure が失敗した"
fi

# 旧構造が登録解除されている
if is_worktree_registered "$LEGACY_DIR"; then
  fail "Case 1: 旧構造 worktree がまだ登録されている"
else
  pass "Case 1: 旧構造 worktree が登録解除されている"
fi

# 新構造が登録されている
if is_worktree_registered "$NEW_DIR"; then
  pass "Case 1: 新構造 worktree が登録されている"
else
  fail "Case 1: 新構造 worktree が登録されていない"
fi

# 新構造ディレクトリに .git が存在する
if [ -e "${NEW_DIR}/.git" ]; then
  pass "Case 1: 新構造ディレクトリに .git が存在する"
else
  fail "Case 1: 新構造ディレクトリに .git が存在しない"
fi

teardown_env

# --- Case 2: 新構造のみ存在 → idempotent (migration 不要) ---

echo ""
echo "--- Case 2: 新構造のみ → migration 不要 (idempotent) ---"
setup_env

# 通常フローで新構造作成（migration ロジックを通らない）
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "前提: 新構造を初回作成"
else
  fail "前提: 新構造の初回作成に失敗"
  teardown_env
  exit 1
fi

# 旧構造は無いことを確認
if is_worktree_registered "$LEGACY_DIR"; then
  fail "前提: 旧構造が誤って登録されている"
fi

# 再度 ensure → 何も変化しない
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "Case 2: ensure が新構造のみで idempotent"
else
  fail "Case 2: ensure が新構造のみで失敗した"
fi

if is_worktree_registered "$NEW_DIR"; then
  pass "Case 2: 新構造のまま登録されている"
else
  fail "Case 2: 新構造の登録が失われた"
fi

if is_worktree_registered "$LEGACY_DIR"; then
  fail "Case 2: 旧構造が誤って登録された"
else
  pass "Case 2: 旧構造は登録されないまま"
fi

teardown_env

# --- Case 3: 旧構造 + 新 path に残骸ディレクトリ → migrate ---

echo ""
echo "--- Case 3: 旧構造 + 新 path 残骸 → 旧解除 + 残骸削除 + 新作成 ---"
setup_env

# 旧構造を作成
create_legacy_worktree "$LEGACY_DIR"

# 新 path に空ディレクトリ（残骸）を仕込む
mkdir -p "$NEW_DIR"

if [ -d "$NEW_DIR" ]; then
  pass "前提: 新 path に残骸ディレクトリが存在"
else
  fail "前提: 新 path 残骸の作成に失敗"
  teardown_env
  exit 1
fi

# ensure 実行
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "Case 3: ensure が migration + 残骸クリーンアップで成功する"
else
  fail "Case 3: ensure が失敗した"
fi

if is_worktree_registered "$LEGACY_DIR"; then
  fail "Case 3: 旧構造がまだ登録されている"
else
  pass "Case 3: 旧構造が登録解除されている"
fi

if is_worktree_registered "$NEW_DIR"; then
  pass "Case 3: 新構造が正しく登録されている"
else
  fail "Case 3: 新構造が登録されていない"
fi

if [ -e "${NEW_DIR}/.git" ]; then
  pass "Case 3: 新構造ディレクトリに .git が存在する"
else
  fail "Case 3: 新構造ディレクトリに .git が存在しない"
fi

teardown_env

# --- Case 4: 旧構造に未 push commit あり → migration 中断（データ保全） ---

echo ""
echo "--- Case 4: 旧構造に未 push commit → 停止して保全 ---"
setup_env

# 旧構造作成 + 未 push commit を残す
create_legacy_worktree "$LEGACY_DIR"

# upstream を作るために空 push（worktree から）
# まず空 push を成功させ、upstream を確立する
git -C "$LEGACY_DIR" push --set-upstream origin knowledge/buffer >/dev/null 2>&1

# 未 push commit を作成
echo "unpushed harvest data" > "${LEGACY_DIR}/harvest.txt"
git -C "$LEGACY_DIR" add harvest.txt
git -C "$LEGACY_DIR" commit -m "wip harvest (unpushed)" >/dev/null 2>&1

# 未 push 件数の前提確認
unpushed=$(git -C "$LEGACY_DIR" rev-list --count "@{u}..HEAD" 2>/dev/null)
if [ "${unpushed:-0}" -gt 0 ]; then
  pass "前提: 旧 worktree に ${unpushed} 件の未 push commit がある"
else
  fail "前提: 未 push commit の作成に失敗"
  teardown_env
  exit 1
fi

# ensure 実行 → 失敗するべき
if knowledge_buffer_ensure >/dev/null 2>&1; then
  fail "Case 4: 未 push commit があるのに migration が実行された (データロストリスク)"
else
  pass "Case 4: 未 push commit を検知して ensure が中断した"
fi

# 旧構造はまだ登録されている（保全されている）
if is_worktree_registered "$LEGACY_DIR"; then
  pass "Case 4: 旧構造 worktree が保全されている"
else
  fail "Case 4: 旧構造 worktree が誤って削除された"
fi

# 旧 worktree の commit が残っている
if [ -f "${LEGACY_DIR}/harvest.txt" ]; then
  pass "Case 4: 未 push データがディスク上に保全されている"
else
  fail "Case 4: 未 push データが消えた"
fi

teardown_env

print_test_summary
