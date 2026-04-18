#!/bin/bash
# knowledge_buffer.sh — knowledge/buffer ブランチの worktree 操作ヘルパー
# /review-harvest / /knowledge-pr / /session-harvest スキルから source して使用する
#
# 設計: .claude/state/ ではなく ~/.cache/vibecorp/buffer-worktree/<repo-id>/ に worktree を作る。
#       XDG_CACHE_HOME 準拠、worktree 跨ぎ・機械跨ぎで知見を git に載せて共有する。
#
# common.sh の vibecorp_repo_id / vibecorp_cache_root を再利用する。

# shellcheck source=./common.sh
_knowledge_buffer_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_knowledge_buffer_lib_dir}/common.sh"

# knowledge_buffer_repo_id — buffer worktree に使う repo-id を返す
# 現状は vibecorp_repo_id のシンラッパー（将来の拡張ポイント）
knowledge_buffer_repo_id() {
  vibecorp_repo_id
}

# knowledge_buffer_worktree_dir — buffer worktree のフルパスを返す
# 出力例: /Users/me/.cache/vibecorp/buffer-worktree/vibecorp-a1b2c3d4
#
# セキュリティ: HOME / XDG_CACHE_HOME が絶対パスでない場合や
# シンボリックリンクの場合は $HOME/.cache にフォールバック（共通の vibecorp_cache_root 経由）
knowledge_buffer_worktree_dir() {
  local cache_root
  cache_root="$(vibecorp_cache_root)"
  # cache_root が絶対パスでない場合はフォールバック（二重チェック）
  if [[ "$cache_root" != /* ]]; then
    cache_root="${HOME}/.cache"
  fi
  # シンボリックリンクの場合は警告して $HOME/.cache にフォールバック
  if [ -L "$cache_root" ]; then
    echo "knowledge_buffer: cache ルートがシンボリックリンクのためフォールバック: ${cache_root}" >&2
    cache_root="${HOME}/.cache"
  fi
  printf '%s/vibecorp/buffer-worktree/%s' "$cache_root" "$(knowledge_buffer_repo_id)"
}

# knowledge_buffer_path — worktree 内の相対パスをフルパスに解決する
# 引数: $1 = worktree 内の相対パス（例: ".harvest-state/last-pr.txt"）
knowledge_buffer_path() {
  printf '%s/%s' "$(knowledge_buffer_worktree_dir)" "$1"
}

# knowledge_buffer_lock_acquire — worktree 排他ロックを取得する
# 使用方法:
#   knowledge_buffer_lock_acquire || exit 2
#   trap knowledge_buffer_lock_release EXIT
# タイムアウト: VIBECORP_LOCK_TIMEOUT 環境変数（デフォルト 60s、CI で短縮可）
# 失敗時: stderr に通知して exit code 2 を返す
#
# 実装: mkdir はすべての POSIX 環境で原子的 (flock 非依存)
# macOS には flock がなく、bash 3.2 は動的 fd 割当を非サポートのため mkdir を採用する
# PID をロック内に記録し、プロセス終了検出時のスタールロックを呼出元で確認可能にする
_KNOWLEDGE_BUFFER_LOCK_HELD=""
_KNOWLEDGE_BUFFER_LOCK_DIR=""
knowledge_buffer_lock_acquire() {
  local timeout="${VIBECORP_LOCK_TIMEOUT:-60}"
  local dir
  dir="$(knowledge_buffer_worktree_dir)"
  mkdir -p "$dir"
  local lock_dir="${dir}/.buffer.lock.d"
  local waited=0
  # 1 秒刻みでリトライ（waited を秒単位で加算し timeout と直接比較）
  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "[knowledge-buffer] lock acquire timeout (${timeout}s): ${lock_dir}" >&2
      return 2
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "$$" > "${lock_dir}/pid"
  _KNOWLEDGE_BUFFER_LOCK_DIR="$lock_dir"
  _KNOWLEDGE_BUFFER_LOCK_HELD=1
  return 0
}

# knowledge_buffer_lock_release — 排他ロックを解放する（trap EXIT で呼ぶ想定）
knowledge_buffer_lock_release() {
  if [ -n "$_KNOWLEDGE_BUFFER_LOCK_HELD" ] && [ -n "$_KNOWLEDGE_BUFFER_LOCK_DIR" ]; then
    rm -rf "$_KNOWLEDGE_BUFFER_LOCK_DIR" 2>/dev/null || true
    _KNOWLEDGE_BUFFER_LOCK_DIR=""
    _KNOWLEDGE_BUFFER_LOCK_HELD=""
  fi
}

# knowledge_buffer_ensure — worktree を最新化する（未作成なら新規作成）
# - 未作成: git worktree add -B knowledge/buffer <dir> origin/main
# - 既存: git fetch origin → git pull --ff-only（失敗時は未push commit有無を検査して reset または中断）
# - worktree prune 必要なら自動復旧
# 呼出元は CLAUDE_PROJECT_DIR（git toplevel）で実行する想定
knowledge_buffer_ensure() {
  local dir
  dir="$(knowledge_buffer_worktree_dir)"
  local parent
  parent="$(dirname "$dir")"
  mkdir -p "$parent"

  local repo_root
  if ! repo_root="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "[knowledge-buffer] git toplevel が取得できません" >&2
    return 1
  fi

  # worktree が未作成、またはディレクトリが削除済み
  if [ ! -d "$dir/.git" ] && [ ! -f "$dir/.git" ]; then
    # 古い worktree 参照が残っていれば prune
    git -C "$repo_root" worktree prune >/dev/null 2>&1 || true
    # origin/main を最新化
    if ! git -C "$repo_root" fetch origin main >/dev/null 2>&1; then
      echo "[knowledge-buffer] git fetch origin main 失敗" >&2
      return 1
    fi
    # worktree 作成（knowledge/buffer ブランチが未存在でも -B で作る）
    if ! git -C "$repo_root" worktree add -B knowledge/buffer "$dir" origin/main >/dev/null 2>&1; then
      echo "[knowledge-buffer] git worktree add 失敗: ${dir}" >&2
      return 1
    fi
    return 0
  fi

  # 既存 worktree: fetch して ff-only pull を試行
  git -C "$dir" fetch origin >/dev/null 2>&1 || true

  # origin/knowledge/buffer がまだ無い場合（初 push 前）は pull せず終了
  if ! git -C "$dir" rev-parse --verify origin/knowledge/buffer >/dev/null 2>&1; then
    return 0
  fi

  if git -C "$dir" pull --ff-only origin knowledge/buffer >/dev/null 2>&1; then
    return 0
  fi

  # ff 失敗: 未 push commit の有無を検査
  local unpushed
  unpushed="$(git -C "$dir" log origin/knowledge/buffer..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${unpushed:-0}" -gt 0 ]; then
    echo "[knowledge-buffer] 未 push の harvest commit が ${unpushed} 件あるため reset を中断" >&2
    echo "[knowledge-buffer] ネットワーク復旧後に手動で push してください: git -C ${dir} push origin knowledge/buffer" >&2
    return 1
  fi

  echo "[knowledge-buffer] ff 失敗のため origin/main にリセットします" >&2
  if ! git -C "$dir" reset --hard origin/main >/dev/null 2>&1; then
    echo "[knowledge-buffer] reset --hard origin/main 失敗" >&2
    return 1
  fi
  return 0
}

# knowledge_buffer_read_last_pr — .harvest-state/last-pr.txt を読む
# 未作成 / 非数値なら空文字列を返す（tampering 検知）
knowledge_buffer_read_last_pr() {
  local file
  file="$(knowledge_buffer_path ".harvest-state/last-pr.txt")"
  if [ ! -f "$file" ]; then
    printf ''
    return 0
  fi
  local value
  value="$(cat "$file" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf ''
  fi
}

# knowledge_buffer_write_last_pr — PR 番号を .harvest-state/last-pr.txt に書く
# 入力が非数値なら exit 1（tampering 防止）
# 引数: $1 = PR 番号（整数）
knowledge_buffer_write_last_pr() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "[knowledge-buffer] write_last_pr: 非数値入力を拒否: '${value}'" >&2
    return 1
  fi
  local file
  file="$(knowledge_buffer_path ".harvest-state/last-pr.txt")"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$value" > "$file"
}

# knowledge_buffer_commit — worktree 内で add + commit する
# 引数: $1 = コミットメッセージ
# 動作: 差分なしならスキップ（exit 0）
# author: git config の vibecorp.knowledge-bot.name / .email を優先、未設定時は現在の git user
knowledge_buffer_commit() {
  local message="$1"
  local dir
  dir="$(knowledge_buffer_worktree_dir)"
  git -C "$dir" add -A

  # 差分なしならスキップ
  if git -C "$dir" diff --cached --quiet; then
    return 0
  fi

  local bot_name bot_email
  bot_name="$(git -C "$dir" config --get vibecorp.knowledge-bot.name 2>/dev/null || true)"
  bot_email="$(git -C "$dir" config --get vibecorp.knowledge-bot.email 2>/dev/null || true)"
  # bash 3.2 + set -u の空配列展開バグ（unbound variable）を回避するため
  # 分岐で if/else を使い、配列を経由しない
  if [ -n "$bot_name" ] && [ -n "$bot_email" ]; then
    git -C "$dir" commit --author "${bot_name} <${bot_email}>" -m "$message"
  else
    git -C "$dir" commit -m "$message"
  fi
}

# knowledge_buffer_push — knowledge/buffer ブランチを origin に push する
# 初回は --set-upstream 付き、2 回目以降は付けない
# 失敗時: exit 3（呼出元は commit を worktree に残したまま終了することで reset ロストを防ぐ）
knowledge_buffer_push() {
  local dir
  dir="$(knowledge_buffer_worktree_dir)"
  local push_args=(origin knowledge/buffer)

  # upstream 未設定か判定
  if ! git -C "$dir" rev-parse --verify origin/knowledge/buffer >/dev/null 2>&1; then
    push_args=(--set-upstream origin knowledge/buffer)
  fi

  if ! git -C "$dir" push "${push_args[@]}" >/dev/null 2>&1; then
    echo "[knowledge-buffer] push 失敗（commit は worktree に保持）: ${dir}" >&2
    return 3
  fi
  return 0
}
