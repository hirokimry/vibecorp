#!/bin/bash
# test_knowledge_buffer.sh — lib/knowledge_buffer.sh のユニットテスト
# 使い方: bash tests/test_knowledge_buffer.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/knowledge_buffer.sh"
COMMON_LIB="${SCRIPT_DIR}/templates/claude/lib/common.sh"
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

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (期待: '$expected', 実際: '$actual')"
  fi
}

assert_contains() {
  local desc="$1"
  local expected_substr="$2"
  local actual="$3"
  if [[ "$actual" == *"$expected_substr"* ]]; then
    pass "$desc"
  else
    fail "$desc (部分文字列 '$expected_substr' が '$actual' に含まれない)"
  fi
}

# 前提ファイル存在確認
if [ ! -f "$LIB" ]; then
  fail "knowledge_buffer.sh が存在しない: $LIB"
  exit 1
fi
if [ ! -f "$COMMON_LIB" ]; then
  fail "common.sh が存在しない: $COMMON_LIB"
  exit 1
fi

# テスト用 git リポジトリを作る
TMPDIR_ROOT=$(mktemp -d)

cleanup() {
  # テスト中の worktree を cleanup（影響を他テストに波及させない）
  if [ -n "${ORIGIN_REPO:-}" ] && [ -d "$ORIGIN_REPO/.git" ]; then
    git -C "$ORIGIN_REPO" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

# origin 役の bare リポジトリ + 作業リポジトリを作る
ORIGIN_REPO="${TMPDIR_ROOT}/origin.git"
WORK_REPO="${TMPDIR_ROOT}/work"
CACHE_ROOT="${TMPDIR_ROOT}/cache"

git init --bare "$ORIGIN_REPO" >/dev/null 2>&1
git -C "$ORIGIN_REPO" symbolic-ref HEAD refs/heads/main

git init "$WORK_REPO" >/dev/null 2>&1
cd "$WORK_REPO"
git config user.email "test@example.com"
git config user.name "Test User"
git checkout -b main >/dev/null 2>&1
echo "hello" > README.md
git add README.md
git commit -m "initial" >/dev/null 2>&1
git remote add origin "$ORIGIN_REPO"
git push -u origin main >/dev/null 2>&1
cd - >/dev/null

# 以降のテストは WORK_REPO を CLAUDE_PROJECT_DIR として扱う
export CLAUDE_PROJECT_DIR="$WORK_REPO"
export XDG_CACHE_HOME="$CACHE_ROOT"
export VIBECORP_LOCK_TIMEOUT=2  # CI を高速化

# shellcheck disable=SC1090
source "$LIB"

# ============================================
echo "=== knowledge_buffer_repo_id / worktree_dir ==="
# ============================================

REPO_ID=$(knowledge_buffer_repo_id)
# 形式: <basename>-<sha256先頭8桁>
if [[ "$REPO_ID" =~ ^[A-Za-z0-9._-]+-[0-9a-f]{8}$ ]]; then
  pass "repo_id が形式 '<basename>-<sha256:8>' に一致"
else
  fail "repo_id 形式不一致: '$REPO_ID'"
fi

# vibecorp_stamp_dir と同一 ID を生成
# shellcheck disable=SC1090
source "$COMMON_LIB"
STAMP_ID=$(vibecorp_repo_id)
assert_eq "knowledge_buffer_repo_id と vibecorp_repo_id が一致" "$STAMP_ID" "$REPO_ID"

WORKTREE_DIR=$(knowledge_buffer_worktree_dir)
assert_eq "worktree_dir が XDG_CACHE_HOME 配下に置かれる" \
  "${CACHE_ROOT}/vibecorp/buffer-worktree/${REPO_ID}" "$WORKTREE_DIR"

# XDG_CACHE_HOME 未設定時は $HOME/.cache
TEST_HOME="${TMPDIR_ROOT}/homedir"
mkdir -p "$TEST_HOME/.cache"
RESULT=$(HOME="$TEST_HOME" XDG_CACHE_HOME="" knowledge_buffer_worktree_dir)
assert_eq "XDG_CACHE_HOME 未設定時は HOME/.cache" \
  "${TEST_HOME}/.cache/vibecorp/buffer-worktree/${REPO_ID}" "$RESULT"

# XDG_CACHE_HOME が非絶対パスならフォールバック
RESULT=$(HOME="$TEST_HOME" XDG_CACHE_HOME="relative/path" knowledge_buffer_worktree_dir)
assert_eq "XDG_CACHE_HOME が非絶対パス → HOME/.cache にフォールバック" \
  "${TEST_HOME}/.cache/vibecorp/buffer-worktree/${REPO_ID}" "$RESULT"

# ============================================
echo ""
echo "=== knowledge_buffer_ensure ==="
# ============================================

# 初回作成
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "ensure 新規作成が成功する"
else
  fail "ensure 新規作成が失敗した"
fi

if [ -d "${WORKTREE_DIR}" ]; then
  pass "worktree ディレクトリが作成されている"
else
  fail "worktree ディレクトリが作成されていない"
fi

# 既存 worktree で idempotent
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "ensure 既存 worktree で idempotent に成功する"
else
  fail "ensure 既存 worktree で失敗した"
fi

# worktree が削除された状態から復旧
rm -rf "$WORKTREE_DIR"
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "ensure がディレクトリ削除済みから復旧する"
else
  fail "ensure がディレクトリ削除済みから復旧できない"
fi

# ============================================
echo ""
echo "=== knowledge_buffer_read/write_last_pr ==="
# ============================================

RESULT=$(knowledge_buffer_read_last_pr)
assert_eq "未作成時は空文字列" "" "$RESULT"

knowledge_buffer_write_last_pr 42
RESULT=$(knowledge_buffer_read_last_pr)
assert_eq "write → read ラウンドトリップ" "42" "$RESULT"

# 非数値入力拒否
if knowledge_buffer_write_last_pr "abc" 2>/dev/null; then
  fail "write_last_pr が非数値を受理してしまった"
else
  pass "write_last_pr が非数値を拒否する"
fi

# tampering: ファイルに直接ゴミを書いて read が空を返すか
LAST_PR_FILE="$(knowledge_buffer_path ".harvest-state/last-pr.txt")"
echo "garbage" > "$LAST_PR_FILE"
RESULT=$(knowledge_buffer_read_last_pr)
assert_eq "非数値ファイルを空扱い (tampering 検知)" "" "$RESULT"

# 値を戻しておく
knowledge_buffer_write_last_pr 42

# ============================================
echo ""
echo "=== knowledge_buffer_commit ==="
# ============================================

# 差分なしならスキップ（既に write_last_pr でコミットしていない状態）
# ここでは確実に差分ありの状態を作る
echo "test note" > "$(knowledge_buffer_path "test-note.txt")"
if knowledge_buffer_commit "test: note 追加" >/dev/null 2>&1; then
  pass "commit が差分ありで成功する"
else
  fail "commit が差分ありで失敗した"
fi

# 差分なしでスキップ
if knowledge_buffer_commit "test: 空コミット" >/dev/null 2>&1; then
  pass "commit が差分なしでスキップする (exit 0)"
else
  fail "commit が差分なしで失敗した"
fi

# author 分岐: bot 設定ありのケース
git -C "$WORKTREE_DIR" config vibecorp.knowledge-bot.name "vibecorp-bot"
git -C "$WORKTREE_DIR" config vibecorp.knowledge-bot.email "bot@example.com"
echo "bot commit" > "$(knowledge_buffer_path "bot-note.txt")"
knowledge_buffer_commit "test: bot author" >/dev/null 2>&1
AUTHOR=$(git -C "$WORKTREE_DIR" log -1 --format='%an <%ae>')
assert_eq "bot 設定時は bot author が使われる" "vibecorp-bot <bot@example.com>" "$AUTHOR"

# bot 設定を解除してもう一度
git -C "$WORKTREE_DIR" config --unset vibecorp.knowledge-bot.name
git -C "$WORKTREE_DIR" config --unset vibecorp.knowledge-bot.email
echo "user commit" > "$(knowledge_buffer_path "user-note.txt")"
knowledge_buffer_commit "test: user author" >/dev/null 2>&1
AUTHOR=$(git -C "$WORKTREE_DIR" log -1 --format='%an <%ae>')
assert_eq "bot 未設定時は git user が使われる" "Test User <test@example.com>" "$AUTHOR"

# ============================================
echo ""
echo "=== knowledge_buffer_push ==="
# ============================================

# 初回 push（--set-upstream）
if knowledge_buffer_push >/dev/null 2>&1; then
  pass "push 初回成功"
else
  fail "push 初回失敗"
fi

# origin に knowledge/buffer ブランチが作られた
if git -C "$ORIGIN_REPO" rev-parse --verify refs/heads/knowledge/buffer >/dev/null 2>&1; then
  pass "origin に knowledge/buffer ブランチが作成されている"
else
  fail "origin に knowledge/buffer ブランチが作成されていない"
fi

# 2 回目 push
echo "second commit" > "$(knowledge_buffer_path "second.txt")"
knowledge_buffer_commit "test: 2 回目" >/dev/null 2>&1
if knowledge_buffer_push >/dev/null 2>&1; then
  pass "push 2 回目成功"
else
  fail "push 2 回目失敗"
fi

# push 失敗テスト: origin を破壊
rm -rf "$ORIGIN_REPO"
echo "will fail" > "$(knowledge_buffer_path "fail.txt")"
knowledge_buffer_commit "test: push 失敗テスト" >/dev/null 2>&1
set +e
knowledge_buffer_push >/dev/null 2>&1
PUSH_EXIT=$?
set -e
assert_eq "push 失敗時 exit 3" "3" "$PUSH_EXIT"

# ============================================
echo ""
echo "=== knowledge_buffer_lock ==="
# ============================================

# lock 取得 → release を単一プロセスで確認
if knowledge_buffer_lock_acquire >/dev/null 2>&1; then
  pass "lock_acquire 成功 (単一プロセス)"
else
  fail "lock_acquire 失敗"
fi
knowledge_buffer_lock_release

# 2 プロセス同時実行: 先行プロセスが保持 → 後続が timeout
(
  knowledge_buffer_lock_acquire
  sleep 5  # タイムアウト(2s) より長く保持
  knowledge_buffer_lock_release
) &
BG_PID=$!
# 先行が lock 取るのを少し待つ
sleep 0.5

set +e
knowledge_buffer_lock_acquire 2>/dev/null
LOCK_EXIT=$?
set -e
assert_eq "後続プロセスは timeout で exit 2" "2" "$LOCK_EXIT"

wait "$BG_PID" || true

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
