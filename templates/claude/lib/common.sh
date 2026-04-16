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

# _vibecorp_sha256_short — 文字列の SHA-256 先頭 8 文字を返す
# shasum / sha256sum / openssl の順で実装をフォールバック
# どれも不在の場合は "00000000" を返す（テストで検出可能）
_vibecorp_sha256_short() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | cut -c1-8
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | cut -c1-8
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$input" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}'
  else
    echo "00000000"
  fi
}

# vibecorp_stamp_dir — ゲートスタンプ保存先ディレクトリを返す
# .claude/ 配下を避けることで Claude Code の書込確認プロンプトを回避する
# 出力例: /Users/me/.cache/vibecorp/state/vibecorp-a1b2c3d4
#
# 脅威モデル: 同一ユーザーの別プロセスからのスタンプ偽造はスコープ外
# （信頼境界 = ユーザーアカウント）。chmod 700 で他ユーザーからの偽造のみブロック。
vibecorp_stamp_dir() {
  local root
  if ! root="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
    root="${CLAUDE_PROJECT_DIR:-$PWD}"
    # フォールバック発動を可観測にする（gate hook はこの stderr を消費しないため push に影響しない）
    echo "vibecorp_stamp_dir: git toplevel 取得に失敗、フォールバック使用: ${root}" >&2
  fi
  # XDG_CACHE_HOME は絶対パスのみ有効（XDG 仕様）。相対値は $HOME/.cache にフォールバック
  local cache_root="${HOME}/.cache"
  if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then
    cache_root="${XDG_CACHE_HOME}"
  fi
  # basename をサニタイズ（shell.md「ファイル名に外部入力を使う場合」ルール準拠）
  # printf で trailing newline を剥がしてから tr に渡す（改行が "_" に変換される副作用を防ぐ）
  local sanitized_base
  sanitized_base="$(printf '%s' "$(basename "$root")" | tr -cs 'A-Za-z0-9._-' '_')"
  local id="${sanitized_base}-$(_vibecorp_sha256_short "$root")"
  printf '%s/vibecorp/state/%s' "$cache_root" "$id"
}

# vibecorp_stamp_path — 名前付きスタンプファイルのフルパスを返す
# 引数: $1 = スタンプ名（"sync", "session-harvest" 等。"-ok" 接尾辞は付けない）
vibecorp_stamp_path() {
  printf '%s/%s-ok' "$(vibecorp_stamp_dir)" "$1"
}

# vibecorp_stamp_mkdir — スタンプディレクトリを 700 パーミッションで作成し、
#                       作成したディレクトリパスを stdout に返す
# スキル側のスタンプ発行ブロックで使用する。
# 失敗（mkdir 拒否、ディスクフル等）は exit code で呼び出し元に伝播させる。
vibecorp_stamp_mkdir() {
  local dir
  dir="$(vibecorp_stamp_dir)" || return 1
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}
