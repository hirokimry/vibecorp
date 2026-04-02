#!/bin/bash
# common.sh — フック共通ユーティリティ関数
# 各フックから source して使用する

# normalize_command — コマンド文字列を正規化する
# 引数: $1 = 生のコマンド文字列
# 出力: 正規化済みコマンド文字列を標準出力に出力
# 正規化手順:
#   1. 先頭空白除去
#   2. 環境変数プレフィックス (KEY=VALUE ...) を除去
#   3. ラッパーコマンド (env, command) を除去
#   4. 絶対パス/相対パスを basename に正規化
normalize_command() {
  local cmd="$1"
  # 1. 先頭空白除去 + 2. 環境変数プレフィックス除去
  cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//' | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')
  # 3. ラッパーコマンド除去ループ
  while true; do
    local first_token
    first_token=$(echo "$cmd" | awk '{print $1}')
    case "$first_token" in
      env|command) cmd=$(echo "$cmd" | sed -E 's/^[^ ]+ +//') ;;
      *) break ;;
    esac
  done
  # 4. 絶対パス/相対パスを basename に正規化
  local first_token
  first_token=$(echo "$cmd" | awk '{print $1}')
  if [[ "$first_token" == */* ]]; then
    local base_cmd rest
    base_cmd=$(basename "$first_token")
    rest=$(echo "$cmd" | awk '{$1=""; print}' | sed 's/^ *//')
    cmd="$base_cmd"
    [[ -n "$rest" ]] && cmd="${cmd} ${rest}"
  fi
  echo "$cmd"
}

# get_project_name — vibecorp.yml からプロジェクト名を取得する
# 引数: なし（CLAUDE_PROJECT_DIR 環境変数を参照）
# 出力: サニタイズ済みプロジェクト名を標準出力に出力
# フォールバック: vibecorp.yml が存在しない場合は "vibecorp-project" を返す
get_project_name() {
  local vibecorp_yml="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
  local project_name="vibecorp-project"
  if [ -f "$vibecorp_yml" ]; then
    local raw_name
    raw_name=$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$vibecorp_yml")
    if [ -n "${raw_name:-}" ]; then
      project_name=$(printf '%s' "$raw_name" | tr -cs 'A-Za-z0-9._-' '_')
    fi
  fi
  echo "$project_name"
}
