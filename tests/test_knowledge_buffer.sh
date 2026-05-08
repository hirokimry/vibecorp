#!/bin/bash
# test_knowledge_buffer.sh — lib/knowledge_buffer.sh のユニットテスト
# 使い方: bash tests/test_knowledge_buffer.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/knowledge_buffer.sh"
COMMON_LIB="${SCRIPT_DIR}/templates/claude/lib/common.sh"

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
echo "=== ensure: 蓄積保持シナリオ (Issue #541) ==="
# ============================================

# 復旧用 origin を作り直す（push 失敗テストで origin が破壊されているため）
git init --bare "$ORIGIN_REPO" >/dev/null 2>&1
git -C "$ORIGIN_REPO" symbolic-ref HEAD refs/heads/main
git -C "$WORK_REPO" push origin main >/dev/null 2>&1

# まず buffer worktree を初期化し、harvest 1 件目を push して origin/knowledge/buffer を作る
rm -rf "$WORKTREE_DIR"
git -C "$WORK_REPO" worktree prune >/dev/null 2>&1 || true
git -C "$WORK_REPO" branch -D knowledge/buffer 2>/dev/null || true
knowledge_buffer_ensure >/dev/null 2>&1
echo "harvest #1" > "$(knowledge_buffer_path 'harvest-1.txt')"
knowledge_buffer_commit "test: harvest 1" >/dev/null 2>&1
knowledge_buffer_push >/dev/null 2>&1

# シナリオ A（別マシン初回）: worktree dir を削除した状態から ensure() →
# origin/knowledge/buffer をベースに作り直すことで harvest 蓄積を引き継ぐ
rm -rf "$WORKTREE_DIR"
git -C "$WORK_REPO" worktree prune >/dev/null 2>&1 || true
git -C "$WORK_REPO" branch -D knowledge/buffer 2>/dev/null || true
if knowledge_buffer_ensure >/dev/null 2>&1; then
  pass "ensure: cache クリア後に origin/knowledge/buffer から復元する"
else
  fail "ensure: cache クリア後の復元に失敗"
fi
if [ -f "$(knowledge_buffer_path 'harvest-1.txt')" ]; then
  pass "ensure: 復元後に過去 harvest が working tree に存在する"
else
  fail "ensure: 復元後に過去 harvest が消失している（origin/main から派生してしまった）"
fi

# シナリオ B（ff 失敗時の reset 先）: 別 worktree からリモートに同一ファイルへの変更を
# push し、ローカル側でも同じファイルを汚す。pull --ff-only が dirty tree コンフリクトで
# 失敗する経路を作り、ensure() が origin/main ではなく origin/knowledge/buffer に
# reset することを検証する。
TMP_WT="${TMPDIR_ROOT}/tmp-buffer-wt"
git -C "$WORK_REPO" worktree add -B tmp-buffer "$TMP_WT" origin/knowledge/buffer >/dev/null 2>&1
echo "remote modification" >> "${TMP_WT}/harvest-1.txt"
git -C "$TMP_WT" add -A >/dev/null 2>&1
git -C "$TMP_WT" commit -m "remote: harvest-1 を変更" >/dev/null 2>&1
git -C "$TMP_WT" push origin tmp-buffer:knowledge/buffer >/dev/null 2>&1
git -C "$WORK_REPO" worktree remove --force "$TMP_WT" >/dev/null 2>&1
git -C "$WORK_REPO" branch -D tmp-buffer >/dev/null 2>&1

# ローカル dirty: 同じファイルを汚すと pull --ff-only がコンフリクトで失敗する
echo "local dirty change" >> "$(knowledge_buffer_path 'harvest-1.txt')"

ENSURE_OUT=$(knowledge_buffer_ensure 2>&1) || true
HEAD_AFTER=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
ORIGIN_BUFFER_AFTER=$(git -C "$WORKTREE_DIR" rev-parse origin/knowledge/buffer)
assert_eq "ensure: ff 失敗時に origin/knowledge/buffer にリセットする" \
  "$ORIGIN_BUFFER_AFTER" "$HEAD_AFTER"
assert_contains "ensure: リセット先メッセージが origin/knowledge/buffer を示す" \
  "origin/knowledge/buffer" "$ENSURE_OUT"

# Issue #541 リグレッション防止: ソースコードに `reset --hard origin/main` が残っていないこと
if grep -qF -- 'reset --hard origin/main' "$LIB"; then
  fail "regression: knowledge_buffer.sh が依然として origin/main へリセットしている (Issue #541)"
else
  pass "knowledge_buffer.sh は origin/main へリセットしない (Issue #541 修正済)"
fi

# ============================================
echo ""
echo "=== commit: lock dir 除外 (Issue #541) ==="
# ============================================

# lock 取得中に commit が呼ばれても .buffer.lock.d/ が commit に含まれないこと
knowledge_buffer_lock_acquire >/dev/null 2>&1
LOCK_PID_FILE="${WORKTREE_DIR}/.buffer.lock.d/pid"
if [ -f "$LOCK_PID_FILE" ]; then
  pass "lock_acquire: lock pid file が working tree に作成される"
else
  fail "lock_acquire: lock pid file が作成されていない"
fi
echo "note while locked" > "$(knowledge_buffer_path 'locked-note.txt')"
knowledge_buffer_commit "test: lock 取得中のコミット" >/dev/null 2>&1
TRACKED=$(git -C "$WORKTREE_DIR" ls-tree -r HEAD --name-only)
if echo "$TRACKED" | grep -q '^\.buffer\.lock\.d/'; then
  fail "commit: lock dir が commit に含まれてしまった"
else
  pass "commit: lock dir が commit に含まれない"
fi
knowledge_buffer_lock_release

# orphan な .buffer.lock.d/ が HEAD にある状態 → 次の commit で削除される（自動掃除）
mkdir -p "${WORKTREE_DIR}/.buffer.lock.d"
echo 99999 > "${WORKTREE_DIR}/.buffer.lock.d/pid"
git -C "$WORKTREE_DIR" add -f .buffer.lock.d/pid >/dev/null 2>&1
git -C "$WORKTREE_DIR" commit -m "test: simulate orphan lock" >/dev/null 2>&1
TRACKED_BEFORE=$(git -C "$WORKTREE_DIR" ls-tree -r HEAD --name-only)
if echo "$TRACKED_BEFORE" | grep -q '^\.buffer\.lock\.d/pid$'; then
  pass "前提: orphan lock dir が HEAD に含まれている状態を再現できた"
else
  fail "前提: orphan lock dir 再現に失敗"
fi
echo "next harvest" > "$(knowledge_buffer_path 'next-harvest.txt')"
knowledge_buffer_commit "test: orphan 自動掃除" >/dev/null 2>&1
TRACKED_AFTER=$(git -C "$WORKTREE_DIR" ls-tree -r HEAD --name-only)
if echo "$TRACKED_AFTER" | grep -q '^\.buffer\.lock\.d/'; then
  fail "commit: orphan な lock dir が次の commit でも残存している"
else
  pass "commit: orphan な lock dir が次の commit で削除される（自動掃除）"
fi

# 後続の lock テスト用に working tree の .buffer.lock.d/ を片付ける
# （rm --cached は index からのみ除去し、working tree のディレクトリは残るため）
rm -rf "${WORKTREE_DIR}/.buffer.lock.d"

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
