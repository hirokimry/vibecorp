#!/bin/bash
# test_knowledge_buffer.sh — lib/knowledge_buffer.sh のユニットテスト
# 使い方: bash tests/test_knowledge_buffer.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/knowledge_buffer.sh"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

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
# 注: bash の subshell `(...)` は親プロセスの $$ を共有するため、
# subshell で knowledge_buffer_lock_acquire を呼ぶと pid ファイルに親 PID が
# 書かれ、後続が「自分自身 PID = 自家中毒」と誤判定して stale 削除してしまう。
# 本番では Claude Code が別 Bash プロセスとして fork するため $$ が分離される。
# テストでも `bash -c` で別 bash プロセスを起動して本番と同条件にする。
bash -c "
  set -e
  export CLAUDE_PROJECT_DIR='${WORK_REPO}'
  export XDG_CACHE_HOME='${CACHE_ROOT}'
  export VIBECORP_LOCK_TIMEOUT=2
  source '${LIB}'
  knowledge_buffer_lock_acquire
  sleep 5  # タイムアウト(2s) より長く保持
  knowledge_buffer_lock_release
" &
BG_PID=$!
# 先行が lock 取るのを少し待つ
sleep 0.5

set +e
knowledge_buffer_lock_acquire 2>/dev/null
LOCK_EXIT=$?
set -e
assert_eq "後続プロセスは timeout で exit 2" "2" "$LOCK_EXIT"

wait "$BG_PID" || true

# 後続テスト用に lock dir を確実に解放しておく
rm -rf "${WORKTREE_DIR}/.buffer.lock.d"

# ============================================
echo ""
echo "=== knowledge_buffer_commit: ネスト検知 (Issue #559) ==="
# ============================================

# repo-id 同名のサブディレクトリが存在すると commit は exit 4 で中止される
NESTED_PATH="${WORKTREE_DIR}/$(basename "${WORKTREE_DIR}")"
mkdir -p "${NESTED_PATH}/.claude/knowledge/cto"
echo "fake nested file" > "${NESTED_PATH}/.claude/knowledge/cto/fake.md"

# 通常の差分も用意（ネスト検知が「差分なしスキップ」より先に効くことを確認）
echo "real note" > "$(knowledge_buffer_path 'real-note.txt')"

set +e
knowledge_buffer_commit "test: ネスト検知" >/dev/null 2>&1
NEST_EXIT=$?
set -e
assert_eq "ネスト存在時 commit が exit 4 で中止" "4" "$NEST_EXIT"

# ネスト除去後は通常通り commit できる
rm -rf "$NESTED_PATH"
if knowledge_buffer_commit "test: ネスト除去後" >/dev/null 2>&1; then
  pass "ネスト除去後 commit が成功する"
else
  fail "ネスト除去後 commit が失敗した"
fi

# 後始末: real-note を削除（次テストの混乱回避）
rm -f "$(knowledge_buffer_path 'real-note.txt')"
knowledge_buffer_commit "test: cleanup real-note" >/dev/null 2>&1 || true

# ============================================
echo ""
echo "=== knowledge_buffer_lock_acquire: stale 検出 (Issue #559) ==="
# ============================================

# stale 1: 死んだプロセスの pid → 自動削除して取得
# /proc 等を見ない代替として、明らかに存在しない PID を使う。
# kill -0 は権限エラーでも 1 を返すが、生存プロセスなら 0 を返すため、
# 99999 が偶然生きていた場合のみテストが false positive になる。
# 安全策として「事前に kill -0 で非存在を確認」してから使う。
DEAD_PID=99999
if kill -0 "$DEAD_PID" 2>/dev/null; then
  echo "[test] PID ${DEAD_PID} が偶然生きているため stale (dead pid) テストをスキップ" >&2
else
  mkdir -p "${WORKTREE_DIR}/.buffer.lock.d"
  echo "$DEAD_PID" > "${WORKTREE_DIR}/.buffer.lock.d/pid"
  if knowledge_buffer_lock_acquire >/dev/null 2>&1; then
    pass "stale lock (dead pid) を自動削除して取得できる"
  else
    fail "stale lock (dead pid) を取得できない"
  fi
  knowledge_buffer_lock_release
fi

# stale 2: 自分自身の PID が記録済み → 自家中毒検出して取得
# Claude Code sandbox 環境で $$ が常に同じ値になる現象への対応。
# 前回実行で残ったロックを「自分のロック」と再認識する自家中毒を解消する。
mkdir -p "${WORKTREE_DIR}/.buffer.lock.d"
echo "$$" > "${WORKTREE_DIR}/.buffer.lock.d/pid"
if knowledge_buffer_lock_acquire >/dev/null 2>&1; then
  pass "stale lock (自分自身の PID = 自家中毒) を自動削除して取得できる"
else
  fail "stale lock (自分自身の PID) を取得できない"
fi
knowledge_buffer_lock_release

# ============================================
echo ""
echo "=== knowledge_buffer_ensure: .gitignore 配置 (Issue #559) ==="
# ============================================

# 既存 .gitignore をクリアして ensure → .gitignore に .buffer.lock.d/ が追記される
# `knowledge_buffer_ensure` を直接呼ぶ代わりに、内部関数 `knowledge_buffer_ensure_gitignore`
# を直接呼ぶ。ensure 経由だと git fetch / pull 等の副作用があり、テスト不安定要因になる。
# .gitignore 配置ロジックの単体検証としては内部関数の直接呼出しの方が適切。
rm -f "${WORKTREE_DIR}/.gitignore"
knowledge_buffer_ensure_gitignore "${WORKTREE_DIR}"
if [ -f "${WORKTREE_DIR}/.gitignore" ] && grep -qxF '.buffer.lock.d/' "${WORKTREE_DIR}/.gitignore"; then
  pass ".gitignore に .buffer.lock.d/ が追記される"
else
  fail ".gitignore に .buffer.lock.d/ が追記されていない"
fi

# 二重実行で重複しない (idempotent)
knowledge_buffer_ensure_gitignore "${WORKTREE_DIR}"
COUNT=$(grep -cxF '.buffer.lock.d/' "${WORKTREE_DIR}/.gitignore")
assert_eq ".gitignore の .buffer.lock.d/ 行が重複しない (idempotent)" "1" "$COUNT"

# 既存 .gitignore に別行があっても .buffer.lock.d/ 行が追加される
rm -f "${WORKTREE_DIR}/.gitignore"
printf '%s\n' '*.tmp' > "${WORKTREE_DIR}/.gitignore"
knowledge_buffer_ensure_gitignore "${WORKTREE_DIR}"
if grep -qxF '.buffer.lock.d/' "${WORKTREE_DIR}/.gitignore" && grep -qxF '*.tmp' "${WORKTREE_DIR}/.gitignore"; then
  pass "既存 .gitignore に他規則がある場合でも .buffer.lock.d/ が追加される"
else
  fail "既存 .gitignore に他規則がある場合の .buffer.lock.d/ 追加が壊れた"
fi

# ensure() 経由でも .gitignore が配置されることを確認（統合テスト）
# worktree を一度削除してから ensure を呼び、新規作成パスで .gitignore が配置されることを検証する。
# （直前テストの dirty 状態を持ち越さずクリーンに統合動作を確認するため）
rm -rf "${WORKTREE_DIR}"
git -C "$WORK_REPO" worktree prune >/dev/null 2>&1 || true
git -C "$WORK_REPO" branch -D knowledge/buffer 2>/dev/null || true
if knowledge_buffer_ensure >/dev/null 2>&1; then
  if [ -f "${WORKTREE_DIR}/.gitignore" ] && grep -qxF '.buffer.lock.d/' "${WORKTREE_DIR}/.gitignore"; then
    pass "knowledge_buffer_ensure 経由でも .gitignore が配置される（新規作成パス）"
  else
    fail "knowledge_buffer_ensure 経由で .gitignore が配置されない"
  fi
else
  fail "knowledge_buffer_ensure が失敗した（.gitignore 統合テスト）"
fi

# ============================================
echo ""
echo "=== harvest スキル SKILL.md パス指定ルール検証 (Issue #559) ==="
# ============================================

SESSION_HARVEST_SKILL="${SCRIPT_DIR}/skills/session-harvest/SKILL.md"
REVIEW_HARVEST_SKILL="${SCRIPT_DIR}/skills/review-harvest/SKILL.md"

# session-harvest: 必須キーワードが含まれること
if [ -f "$SESSION_HARVEST_SKILL" ]; then
  if grep -qF '絶対パス' "$SESSION_HARVEST_SKILL" \
    && grep -qF '相対パス' "$SESSION_HARVEST_SKILL" \
    && grep -qF 'BUFFER_DIR' "$SESSION_HARVEST_SKILL"; then
    pass "session-harvest SKILL.md にパス指定ルール必須キーワードが含まれる"
  else
    fail "session-harvest SKILL.md にパス指定ルール必須キーワードが欠落"
  fi
else
  fail "session-harvest SKILL.md が見つからない: ${SESSION_HARVEST_SKILL}"
fi

# review-harvest: 必須キーワードが含まれること
if [ -f "$REVIEW_HARVEST_SKILL" ]; then
  if grep -qF '絶対パス' "$REVIEW_HARVEST_SKILL" \
    && grep -qF '相対パス' "$REVIEW_HARVEST_SKILL" \
    && grep -qF 'BUFFER_WORKTREE' "$REVIEW_HARVEST_SKILL"; then
    pass "review-harvest SKILL.md にパス指定ルール必須キーワードが含まれる"
  else
    fail "review-harvest SKILL.md にパス指定ルール必須キーワードが欠落"
  fi
else
  fail "review-harvest SKILL.md が見つからない: ${REVIEW_HARVEST_SKILL}"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
