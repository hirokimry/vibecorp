#!/bin/bash
# zombie_agent.sh — 親 worktree が消えたゾンビエージェントを検出・kill する
#
# ship-parallel が tmux ペインで起動した Agent は、対応する worktree が削除されると
# シェルが `cd: no such file or directory` のループに入り CPU を消費し続ける（Issue #253）。
# このスクリプトは ~/.claude/teams/*/config.json を走査し、worktree が消えた tmux 連動
# エージェントの tmux ペインを検出して kill する。
#
# 使い方:
#   bash zombie_agent.sh list   # ゾンビ一覧を tab 区切りで標準出力（kill しない）
#   bash zombie_agent.sh kill   # ゾンビ kill を実行
#
# 出力フォーマット（list）:
#   <team>\t<member-name>\t<tmuxPaneId>\t<missing-worktree-path>
#
# 環境変数:
#   CLAUDE_TEAMS_DIR  — team config の探索ルート（既定: ~/.claude/teams）
#                       テスト・スタブ用途で上書き可能。

set -euo pipefail

TEAMS_DIR="${CLAUDE_TEAMS_DIR:-${HOME}/.claude/teams}"

# _extract_worktree_path — prompt 文字列から worktree 絶対パスを抽出する
#
# ship-parallel の prompt は「- worktree パス: <path>」形式の行を含む。
# パスにスペースが含まれる可能性に備え、行末まで取得して trailing whitespace を除去する。
_extract_worktree_path() {
  local prompt="$1"
  printf '%s\n' "$prompt" | awk '
    /worktree パス:/ {
      sub(/.*worktree パス:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  '
}

# _scan_team_config — 単一の team config を走査してゾンビ候補を出力する
_scan_team_config() {
  local config="$1"
  local team count i
  team=$(jq -r '.name // ""' "$config")
  count=$(jq -r '.members | length' "$config")

  for ((i = 0; i < count; i++)); do
    local backend pane_id name prompt worktree
    backend=$(jq -r --argjson i "$i" '.members[$i].backendType // ""' "$config")
    if [[ "$backend" != "tmux" ]]; then
      continue
    fi

    pane_id=$(jq -r --argjson i "$i" '.members[$i].tmuxPaneId // ""' "$config")
    if [[ -z "$pane_id" ]]; then
      continue
    fi

    name=$(jq -r --argjson i "$i" '.members[$i].name // ""' "$config")
    prompt=$(jq -r --argjson i "$i" '.members[$i].prompt // ""' "$config")

    worktree=$(_extract_worktree_path "$prompt")
    if [[ -z "$worktree" ]]; then
      continue
    fi

    if [[ ! -d "$worktree" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$team" "$name" "$pane_id" "$worktree"
    fi
  done
}

# list_zombies — 全 team config を走査してゾンビ一覧を出力する
list_zombies() {
  if [[ ! -d "$TEAMS_DIR" ]]; then
    return 0
  fi

  local config
  for config in "$TEAMS_DIR"/*/config.json; do
    if [[ -f "$config" ]]; then
      _scan_team_config "$config"
    fi
  done
}

# kill_zombies — list_zombies が検出したゾンビの tmux ペインを kill する
#
# tmux サーバー未起動 / ペインが既に消滅している場合はスキップする。
kill_zombies() {
  local killed=0
  local skipped=0
  local team name pane_id worktree
  local active_panes=""

  if tmux has-session 2>/dev/null; then
    active_panes=$(tmux list-panes -a -F '#{pane_id}')
  else
    printf 'tmux サーバーが起動していません。kill 対象なしとして終了します。\n'
  fi

  while IFS=$'\t' read -r team name pane_id worktree; do
    if [[ -z "$team" ]]; then
      continue
    fi

    if [[ -n "$active_panes" ]] && printf '%s\n' "$active_panes" | grep -qx "$pane_id"; then
      tmux kill-pane -t "$pane_id"
      printf 'Killed: %s/%s pane=%s worktree=%s\n' "$team" "$name" "$pane_id" "$worktree"
      killed=$((killed + 1))
    else
      printf 'Skipped: %s/%s pane=%s (既に消滅 or tmux 未起動) worktree=%s\n' \
        "$team" "$name" "$pane_id" "$worktree"
      skipped=$((skipped + 1))
    fi
  done < <(list_zombies)

  printf -- '---\n'
  printf 'Killed: %d, Skipped: %d\n' "$killed" "$skipped"
}

# 直接実行された場合のみサブコマンド処理を行う（source 用途と両立）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-list}" in
    list) list_zombies ;;
    kill) kill_zombies ;;
    *)
      printf 'Usage: %s [list|kill]\n' "$0" >&2
      exit 1
      ;;
  esac
fi
