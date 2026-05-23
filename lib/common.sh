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

# vibecorp_repo_id — リポジトリルートパスから ID 文字列を返す
# 出力例: vibecorp-a1b2c3d4
# 形式: <basename（サニタイズ済み）>-<sha256先頭8桁>
# ゲートスタンプ（vibecorp_stamp_dir）と knowledge/buffer worktree（knowledge_buffer.sh）で共有する
#
# worktree 対応: `--git-common-dir` は main repo の .git ディレクトリを常に返すため、
# main / 各 worktree のどこから呼んでも同一 repo_id が生成される。
# `--show-toplevel` は worktree ごとに別パスを返すため不可（Issue #600）。
vibecorp_repo_id() {
  local root
  local common_dir
  local start_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  if common_dir="$(git -C "$start_dir" rev-parse --git-common-dir 2>/dev/null)"; then
    # common_dir は main では ".git"（相対）、worktree では絶対パスを返すため正規化する
    if [[ "$common_dir" != /* ]]; then
      common_dir="$start_dir/$common_dir"
    fi
    # main repo root = .git の親ディレクトリ。
    # `pwd -P` で物理パスに正規化する（macOS の /tmp → /private/tmp 等のシンボリックリンクで
    #  main と worktree の解決パスが食い違うのを防ぐ）
    if ! root="$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd -P)"; then
      root="$start_dir"
      echo "vibecorp_repo_id: git common-dir 解決に失敗、フォールバック使用: ${root}" >&2
    fi
  else
    root="$start_dir"
    echo "vibecorp_repo_id: git common-dir 取得に失敗、フォールバック使用: ${root}" >&2
  fi
  # basename をサニタイズ（shell.md「ファイル名に外部入力を使う場合」ルール準拠）
  # printf で trailing newline を剥がしてから tr に渡す（改行が "_" に変換される副作用を防ぐ）
  local sanitized_base
  sanitized_base="$(printf '%s' "$(basename "$root")" | tr -cs 'A-Za-z0-9._-' '_')"
  printf '%s-%s' "$sanitized_base" "$(_vibecorp_sha256_short "$root")"
}

# vibecorp_cache_root — vibecorp 用 cache ディレクトリのルートを返す
# XDG_CACHE_HOME は絶対パスのみ有効（XDG 仕様）。相対値は $HOME/.cache にフォールバック
vibecorp_cache_root() {
  if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then
    printf '%s' "${XDG_CACHE_HOME}"
  else
    printf '%s/.cache' "${HOME}"
  fi
}

# vibecorp_stamp_dir — ゲートスタンプ保存先ディレクトリを返す
# .claude/ 配下を避けることで Claude Code の書込確認プロンプトを回避する
# 出力例: /Users/me/.cache/vibecorp/state/vibecorp-a1b2c3d4
#
# 脅威モデル: 同一ユーザーの別プロセスからのスタンプ偽造はスコープ外
# （信頼境界 = ユーザーアカウント）。chmod 700 で他ユーザーからの偽造のみブロック。
vibecorp_stamp_dir() {
  printf '%s/vibecorp/state/%s' "$(vibecorp_cache_root)" "$(vibecorp_repo_id)"
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

# vibecorp_state_path — 汎用 state ファイルのフルパスを返す（"-ok" 接尾辞なし）
# 引数: $1 = ファイル名（例: "command-log", "agent-role", "diagnose-active"）
# 出力: <vibecorp_stamp_dir>/<name>
# 既存スタンプと同じ <repo-id>/ ディレクトリを共有し、接尾辞の有無で区別する。
vibecorp_state_path() {
  printf '%s/%s' "$(vibecorp_stamp_dir)" "$1"
}

# vibecorp_state_mkdir — state ディレクトリを作成してパスを返す
# vibecorp_stamp_mkdir と同じディレクトリを共有するためエイリアス。
# 呼出側で「state を置く」意図を明示したい場合に使う。
vibecorp_state_mkdir() {
  vibecorp_stamp_mkdir
}

# vibecorp_plans_dir — plan mode 成果物の保存ディレクトリを返す
# 出力例: /Users/me/.cache/vibecorp/plans/vibecorp-a1b2c3d4
# .claude/plans/ への書込を避けることで Claude Code の書込確認プロンプトを回避する
# （Issue #334 / #369）。
vibecorp_plans_dir() {
  printf '%s/vibecorp/plans/%s' "$(vibecorp_cache_root)" "$(vibecorp_repo_id)"
}

# vibecorp_plans_mkdir — plans ディレクトリを 700 で作成し、パスを stdout に返す
# 失敗は exit code で呼出元に伝播。
vibecorp_plans_mkdir() {
  local dir
  dir="$(vibecorp_plans_dir)" || return 1
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# --- vibecorp.yml 実行時読み取り API ----------------------------------------
# 用途: plugin native 配布化（Issue #700 / #403）後に、hook 自身が起動時に
#       vibecorp.yml を読んで自己 skip 判定するための汎用 API。
# 実装方針: 純粋 bash + awk のみ（yq / jq に依存しない）、macOS bash 3.2 互換。
# 関連: Issue #702。

# _vibecorp_yml_path — 実行時参照する vibecorp.yml のフルパスを返す
# CLAUDE_PROJECT_DIR を起点に `.claude/vibecorp.yml` を解決する
# （install.sh の get_project_name と同じ規約）
_vibecorp_yml_path() {
  printf '%s/.claude/vibecorp.yml' "${CLAUDE_PROJECT_DIR:-.}"
}

# vibecorp_yml_get — vibecorp.yml の <section>.<key> の値を取得する
# 引数: $1 = section 名（例: hooks, coderabbit）
#       $2 = key 名（例: review-gate, enabled）
# 出力: stdout に値。yml 不在 or キー未定義時は空文字
# 値は前後の空白を除去して返す。引用符は剥がさない（呼出側で必要に応じて処理）
vibecorp_yml_get() {
  local section="$1"
  local key="$2"
  local yml
  yml="$(_vibecorp_yml_path)"

  [[ -f "$yml" ]] || return 0

  # awk: トップレベル行で section を追跡し、2-space インデント直下の key:value のみ拾う
  # （ネスト 3 階層以上は対象外、install.sh:97-105 の is_item_enabled と同じ規約）
  awk -v section="$section" -v key="$key" '
    /^[^ #]/ {
      current_section = $0
      gsub(/:.*/, "", current_section)
    }
    current_section == section && $0 ~ "^  " key ":" {
      sub("^  " key ":[ \t]*", "")
      sub(/[ \t]+$/, "")
      print
      exit
    }
  ' "$yml"
}

# vibecorp_yml_get_preset — 現在のプリセット名を返す
# 出力: stdout に preset 名。未定義時は "standard"（デフォルト）
vibecorp_yml_get_preset() {
  local yml
  yml="$(_vibecorp_yml_path)"

  local val=""
  if [[ -f "$yml" ]]; then
    # トップレベル `preset:` 行のみ拾う（section 内の preset: ではない）
    val=$(awk '/^preset:[[:space:]]*/ {
      sub(/^preset:[[:space:]]*/, "")
      sub(/[ \t]+$/, "")
      print
      exit
    }' "$yml")
  fi

  if [[ -z "${val:-}" ]]; then
    printf 'standard'
  else
    printf '%s' "$val"
  fi
}

# _vibecorp_preset_has_hook — 指定 preset で hook が有効かを返す（0 = 有効、1 = 無効）
# 引数: $1 = preset 名（minimal / standard / full）
#       $2 = hook 名（拡張子なし、例: role-gate）
# 有効リストは install.sh:868-936 のプリセット引き算定義から「足し算」に正規化したもの。
# install.sh の rm -f リストと逆引きの関係になっているため、両者を同期させる必要がある。
_vibecorp_preset_has_hook() {
  local preset="$1"
  local hook="$2"

  # 全プリセット共通 hook（install.sh で除外対象外のもの）
  case "$hook" in
    block-api-bypass|command-log|protect-branch|protect-files|protect-knowledge-bash-writes|protect-knowledge-direct-writes)
      return 0
      ;;
  esac

  # preset 別の追加 hook
  case "$preset" in
    minimal)
      # 全プリセット共通以外は無効
      return 1
      ;;
    standard)
      # minimal で除外される hook のうち、role-gate / diagnose-guard 以外を追加
      case "$hook" in
        sync-gate|review-gate|guide-gate)
          return 0
          ;;
      esac
      return 1
      ;;
    full)
      # full は全 hook 有効
      case "$hook" in
        sync-gate|review-gate|guide-gate|role-gate|diagnose-guard)
          return 0
          ;;
      esac
      return 1
      ;;
    *)
      # 未知の preset はフェイルセーフで standard 扱い
      case "$hook" in
        sync-gate|review-gate|guide-gate)
          return 0
          ;;
      esac
      return 1
      ;;
  esac
}

# hook_skip_if_disabled — hook が skip すべきかを判定する
# 引数: $1 = hook 名（拡張子 .sh は付けない、例: role-gate）
# 戻り値:
#   0 = skip すべき（yml で false / 現 preset の対象外）
#   1 = continue（処理を続行する）
# 想定使用法: 各 hook の冒頭で
#   source "$(dirname "$0")/../../lib/common.sh"
#   hook_skip_if_disabled role-gate && exit 0
# 機能: yml で skip させて良い hook かを判定する（CR PR #731 Major #3 対応）
# 保護系・ログ系・API バイパス防止系・ガードレール系は CISO 要件により無効化不可。
# 利用者の vibecorp.yml で hooks.<name>: false と書いてもこれらは skip されない。
_vibecorp_hook_can_be_disabled_by_yaml() {
  local hook="$1"
  case "$hook" in
    # 無効化可能: preset で on/off するオプトイン系 + 緊急停止用 (SECURITY.md 規定の "緊急一時措置" 限定)
    # CR PR #731 Major #3 v2 対応: protect-files / diagnose-guard は障害時の一時退避手段として yml で false 可
    sync-gate|review-gate|protect-files|diagnose-guard)
      return 0
      ;;
    # 無効化不可: 保護系・ログ系・API バイパス防止系・ガードレール系
    *)
      return 1
      ;;
  esac
}

hook_skip_if_disabled() {
  local hook="$1"

  # 1. yml で明示的に hooks: <name>: false → skip（無効化可能 hook のみ）
  local yml_val
  yml_val=$(vibecorp_yml_get hooks "$hook")
  if [[ "$yml_val" == "false" ]] && _vibecorp_hook_can_be_disabled_by_yaml "$hook"; then
    return 0
  fi

  # 2. 現在 preset の対象外 → skip
  local preset
  preset=$(vibecorp_yml_get_preset)
  if ! _vibecorp_preset_has_hook "$preset" "$hook"; then
    return 0
  fi

  # 3. それ以外は continue
  return 1
}
