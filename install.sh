#!/bin/bash
# install.sh — vibecorp プラグインインストーラー
# Usage: install.sh --name <project-name> [--preset minimal] [--language ja|en|...]
#        install.sh --update [--preset minimal]
set -euo pipefail

VIBECORP_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── ユーティリティ ─────────────────────────────────────

log_info()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
log_skip()  { printf '\033[33m[SKIP]\033[0m  %s\n' "$*" >&2; }

usage() {
  local exit_code="${1:-1}"
  cat >&2 <<'USAGE'
Usage: install.sh --name <project-name> [--preset minimal] [--language ja]
       install.sh --update [--preset minimal]

Options:
  --name      プロジェクト名（初回インストール時に必須）
  --update    既存インストールを更新（vibecorp.yml から設定を読み取る）
  --preset    組織プリセット: minimal（デフォルト: minimal）
  --language  回答言語: ja, en, または任意（デフォルト: ja）
  -h, --help  このヘルプを表示

--name と --update は同時に指定できません。
USAGE
  exit "$exit_code"
}

resolve_language() {
  case "$1" in
    ja) echo "日本語" ;;
    en) echo "English" ;;
    *)  echo "$1" ;;
  esac
}

# ── ステップ関数 ───────────────────────────────────────

parse_args() {
  PROJECT_NAME=""
  PRESET=""
  LANGUAGE=""
  UPDATE_MODE=false
  PRESET_SPECIFIED=false
  LANGUAGE_SPECIFIED=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--name に値が必要です"; usage; }; PROJECT_NAME="$2"; shift 2 ;;
      --update)   UPDATE_MODE=true; shift ;;
      --preset)   [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--preset に値が必要です"; usage; }; PRESET="$2"; PRESET_SPECIFIED=true; shift 2 ;;
      --language) [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--language に値が必要です"; usage; }; LANGUAGE="$2"; LANGUAGE_SPECIFIED=true; shift 2 ;;
      -h|--help)  usage 0 ;;
      *)          log_error "不明なオプション: $1"; usage ;;
    esac
  done

  if [[ "$UPDATE_MODE" == true && -n "$PROJECT_NAME" ]]; then
    log_error "--name と --update は同時に指定できません"
    usage
  fi

  if [[ "$UPDATE_MODE" == false && -z "$PROJECT_NAME" ]]; then
    log_error "--name は必須です"
    usage
  fi

  # デフォルト値の設定（--update 時は read_vibecorp_yml で上書きされる）
  if [[ -z "$PRESET" ]]; then PRESET="minimal"; fi
  if [[ -z "$LANGUAGE" ]]; then LANGUAGE="ja"; fi
}

validate_name() {
  if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,48}[A-Za-z0-9]$ ]] && [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9]$ ]]; then
    log_error "プロジェクト名が不正です（英数字とハイフンのみ、1-50文字）"
    exit 1
  fi
}

validate_preset() {
  case "$PRESET" in
    minimal) ;;
    *)
      log_error "--preset は現在 minimal のみ対応です"
      exit 1
      ;;
  esac
}

validate_language() {
  # sed 区切り文字やシェル特殊文字を含む値を拒否（英数字、ハイフン、アンダースコアのみ許可）
  if [[ ! "$LANGUAGE" =~ ^[A-Za-z0-9_-]+$ ]]; then
    log_error "言語コードが不正です（英数字、ハイフン、アンダースコアのみ）"
    exit 1
  fi
}

check_prerequisites() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq が必要です。インストール: brew install jq"
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    log_error "git が必要です"
    exit 1
  fi
}

detect_repo_root() {
  if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    log_error "git リポジトリ内で実行してください"
    exit 1
  fi
}

read_vibecorp_yml() {
  # vibecorp.yml からプロジェクト設定を読み取る（--update モード用）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ ! -f "$yml" ]]; then
    log_error "vibecorp.yml が見つかりません。初回は --name でインストールしてください"
    exit 1
  fi

  # awk でトップレベルキーの値を抽出
  PROJECT_NAME=$(awk '/^name:/ { print $2 }' "$yml")
  local yml_preset
  yml_preset=$(awk '/^preset:/ { print $2 }' "$yml")
  local yml_language
  yml_language=$(awk '/^language:/ { print $2 }' "$yml")

  # --preset 未指定なら yml の値を使う
  if [[ "$PRESET_SPECIFIED" == false ]]; then
    PRESET="${yml_preset:-minimal}"
  fi
  # --language 未指定なら yml の値を使う
  if [[ "$LANGUAGE_SPECIFIED" == false ]]; then
    LANGUAGE="${yml_language:-ja}"
  fi

  if [[ -z "$PROJECT_NAME" ]]; then
    log_error "vibecorp.yml に name が定義されていません"
    exit 1
  fi

  log_info "vibecorp.yml から設定を読み取り (name: ${PROJECT_NAME}, preset: ${PRESET})"
}

update_vibecorp_yml() {
  # --update + --preset 指定時に vibecorp.yml の preset を更新
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  [[ "$PRESET_SPECIFIED" == true ]] || return 0
  [[ -f "$yml" ]] || return 0

  local current_preset
  current_preset=$(awk '/^preset:/ { print $2 }' "$yml")

  if [[ "$current_preset" != "$PRESET" ]]; then
    sed "s|^preset: .*|preset: ${PRESET}|" "$yml" > "${yml}.tmp" && mv "${yml}.tmp" "$yml"
    log_info "vibecorp.yml の preset を更新: ${current_preset} → ${PRESET}"
  fi
}

read_lock_list() {
  # lock ファイルから指定セクションのファイル一覧を取得
  # 使い方: read_lock_list <lock_file> <section_name>
  # awk でブロック単位に抽出（grep -A N はセクション境界を越えるため使わない）
  local lock_file="$1"
  local section="$2"

  [[ -f "$lock_file" ]] || return 0

  awk -v section="$section" '
    /^  [a-z]+:/ {
      current = $1
      gsub(/:$/, "", current)
      next
    }
    current == section && /^    - / {
      sub(/^    - /, "")
      print
    }
  ' "$lock_file"
}

remove_managed_files() {
  # lock に記載された vibecorp 管理ファイルのみ削除
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local hooks_dir="${REPO_ROOT}/.claude/hooks"
  local skills_dir="${REPO_ROOT}/.claude/skills"

  [[ -f "$lock" ]] || return 0

  # lock 記載の hooks を削除
  while IFS= read -r name; do
    [[ -n "$name" ]] && rm -f "${hooks_dir:?}/${name:?}"
  done < <(read_lock_list "$lock" "hooks")

  # lock 記載の skills を削除
  while IFS= read -r name; do
    [[ -n "$name" ]] && rm -rf "${skills_dir:?}/${name:?}"
  done < <(read_lock_list "$lock" "skills")

  log_info "管理ファイルを削除（lock ベース）"
}

copy_managed_files() {
  # テンプレートをコピー（既存ユーザーファイルはスキップ）
  local hooks_dir="${REPO_ROOT}/.claude/hooks"
  local skills_dir="${REPO_ROOT}/.claude/skills"

  mkdir -p "$hooks_dir" "$skills_dir"

  # hooks: --update 時は上書き、通常時は既存スキップ
  for src in "${SCRIPT_DIR}/templates/claude/hooks/"*.sh; do
    [[ -f "$src" ]] || continue
    local name
    name=$(basename "$src")
    if [[ "$UPDATE_MODE" == true ]]; then
      cp "$src" "${hooks_dir}/${name}"
    elif [[ -f "${hooks_dir}/${name}" ]]; then
      log_skip "hooks/${name} は既存のためスキップ"
    else
      cp "$src" "${hooks_dir}/${name}"
    fi
  done

  # skills: --update 時は上書き、通常時は既存スキップ
  for src_dir in "${SCRIPT_DIR}/templates/claude/skills/"*/; do
    [[ -d "$src_dir" ]] || continue
    local name
    name=$(basename "$src_dir")
    if [[ "$UPDATE_MODE" == true ]]; then
      rm -rf "${skills_dir:?}/${name:?}"
      cp -R "$src_dir" "${skills_dir}/${name}"
    elif [[ -d "${skills_dir}/${name}" ]]; then
      log_skip "skills/${name} は既存のためスキップ"
    else
      cp -R "$src_dir" "${skills_dir}/${name}"
    fi
  done

  # プレースホルダー置換
  # macOS 互換: sed ... > tmp && mv tmp original（sed -i の BSD/GNU 差異を回避）
  local target_dirs=("$hooks_dir" "$skills_dir")
  for dir in "${target_dirs[@]}"; do
    find "$dir" -type f \( -name '*.sh' -o -name '*.md' \) | while IFS= read -r f; do
      if grep -q '{{' "$f" 2>/dev/null; then
        sed \
          -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
          -e "s|{{PRESET}}|${PRESET}|g" \
          -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
          "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
      fi
    done
  done

  # hooks に実行権限を付与
  for f in "${hooks_dir}/"*.sh; do
    [[ -f "$f" ]] && chmod +x "$f"
  done

  # プリセット別削除（引き算方式）
  case "$PRESET" in
    minimal)
      rm -f "${hooks_dir}/review-to-rules-gate.sh"
      rm -rf "${skills_dir}/review-to-rules"
      ;;
  esac

  log_info "テンプレートをコピー (preset: ${PRESET})"
}

generate_vibecorp_yml() {
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ -f "$yml" ]]; then
    log_skip "vibecorp.yml は既存のためスキップ"
    return
  fi

  cat > "$yml" <<YAML
# vibecorp.yml — プロジェクト設定
name: ${PROJECT_NAME}
preset: ${PRESET}
language: ${LANGUAGE}
base_branch: main
protected_files:
  - MVV.md
YAML
  log_info "vibecorp.yml を生成"
}

generate_vibecorp_lock() {
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local installed_at
  installed_at=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
  local vibecorp_commit
  vibecorp_commit=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # vibecorp が管理するファイルのマニフェストを生成（テンプレート由来のみ）
  local hooks_list="" skills_list="" rules_list=""

  # テンプレートに存在し、プリセット削除後も残っているファイルを記録
  for f in "${SCRIPT_DIR}/templates/claude/hooks/"*.sh; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    # 実際に配置先に存在するもののみ記録（プリセット削除分を除外）
    [[ -f "${REPO_ROOT}/.claude/hooks/${name}" ]] && hooks_list="${hooks_list}    - ${name}"$'\n'
  done
  for d in "${SCRIPT_DIR}/templates/claude/skills/"*/; do
    [[ -d "$d" ]] || continue
    local name
    name=$(basename "$d")
    [[ -d "${REPO_ROOT}/.claude/skills/${name}" ]] && skills_list="${skills_list}    - ${name}"$'\n'
  done
  for f in "${SCRIPT_DIR}/templates/claude/rules/"*.md; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    [[ -f "${REPO_ROOT}/.claude/rules/${name}" ]] && rules_list="${rules_list}    - ${name}"$'\n'
  done

  cat > "$lock" <<YAML
# vibecorp.lock — 自動生成、手動編集禁止
version: ${VIBECORP_VERSION}
installed_at: ${installed_at}
preset: ${PRESET}
vibecorp_commit: ${vibecorp_commit}
files:
  hooks:
${hooks_list}  skills:
${skills_list}  rules:
${rules_list}
YAML
  log_info "vibecorp.lock を生成"
}

generate_settings_json() {
  local settings="${REPO_ROOT}/.claude/settings.json"
  local template="${SCRIPT_DIR}/templates/settings.json.tpl"
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"

  # テンプレートにプリセットフィルタを適用
  local new_settings
  new_settings=$(cat "$template")

  case "$PRESET" in
    minimal)
      new_settings=$(echo "$new_settings" | jq '
        .hooks.PreToolUse |= [
          .[]
          | .hooks |= [.[] | select(.command | contains("review-to-rules-gate") | not)]
          | select((.hooks | length) > 0)
        ]
      ')
      ;;
  esac

  if [[ ! -f "$settings" ]]; then
    # 新規: フィルタ済みテンプレートをそのまま書き出し
    echo "$new_settings" | jq '.' > "$settings"
    log_info "settings.json を生成"
  else
    # 既存: lock のフック名リストで vibecorp 管理判定（パス文字列判定をやめる）
    local managed_hooks_json="[]"
    if [[ -f "$lock" ]]; then
      # lock 記載のフック名から jq フィルタ用の JSON 配列を生成
      managed_hooks_json=$(read_lock_list "$lock" "hooks" | jq -R -s 'split("\n") | map(select(length > 0))')
    fi

    local new_hooks
    new_hooks=$(echo "$new_settings" | jq '.hooks.PreToolUse')

    jq --argjson new "$new_hooks" --argjson managed "$managed_hooks_json" '
      def is_managed_hook:
        (.command | split("/") | last) as $basename |
        any($managed[]; . == $basename);
      def strip_managed_hooks:
        .hooks |= map(select(is_managed_hook | not));
      # 既存から vibecorp 管理フックを除去し、新規と結合後、同一 matcher をマージ
      .hooks.PreToolUse = (
        [(.hooks.PreToolUse // [])[] | strip_managed_hooks | select((.hooks | length) > 0)]
        + $new
        | group_by(.matcher)
        | map({matcher: .[0].matcher, hooks: [.[].hooks[]]})
      )
    ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    log_info "settings.json をマージ（ユーザーフック保持）"
  fi
}

copy_rules() {
  local src="${SCRIPT_DIR}/templates/claude/rules"
  local dest="${REPO_ROOT}/.claude/rules"
  mkdir -p "$dest"

  for rule in "${src}"/*.md; do
    local basename
    basename=$(basename "$rule")
    if [[ "$UPDATE_MODE" == true ]]; then
      cp "$rule" "${dest}/${basename}"
      log_info "rules/${basename} を更新"
    elif [[ -f "${dest}/${basename}" ]]; then
      log_skip "rules/${basename} は既存のためスキップ"
    else
      cp "$rule" "${dest}/${basename}"
      log_info "rules/${basename} をコピー"
    fi
  done
}

generate_claude_md() {
  local target="${REPO_ROOT}/.claude/CLAUDE.md"

  if [[ -f "$target" ]]; then
    log_skip "CLAUDE.md は既存のためスキップ"
    return
  fi

  local lang_display
  lang_display=$(resolve_language "$LANGUAGE")

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{LANGUAGE}}|${lang_display}|g" \
    "${SCRIPT_DIR}/templates/CLAUDE.md.tpl" > "$target"
  log_info "CLAUDE.md を生成"
}

generate_mvv_md() {
  local target="${REPO_ROOT}/MVV.md"

  if [[ -f "$target" ]]; then
    log_skip "MVV.md は既存のためスキップ"
    return
  fi

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    "${SCRIPT_DIR}/templates/MVV.md.tpl" > "$target"
  log_info "MVV.md を生成"
}

print_completion() {
  local action="インストール"
  [[ "$UPDATE_MODE" == true ]] && action="更新"

  cat >&2 <<DONE

────────────────────────────────────────────
  vibecorp ${VIBECORP_VERSION} の${action}が完了しました
  プロジェクト: ${PROJECT_NAME}
  プリセット:   ${PRESET}
  リポジトリ:   ${REPO_ROOT}
────────────────────────────────────────────

DONE
}

# ── メイン ─────────────────────────────────────────────

main() {
  parse_args "$@"
  check_prerequisites
  detect_repo_root

  if [[ "$UPDATE_MODE" == true ]]; then
    read_vibecorp_yml
  fi

  validate_name
  validate_preset
  validate_language
  remove_managed_files
  copy_managed_files
  generate_vibecorp_yml

  if [[ "$UPDATE_MODE" == true ]]; then
    update_vibecorp_yml
  fi

  generate_settings_json
  copy_rules
  generate_claude_md
  generate_mvv_md
  generate_vibecorp_lock
  print_completion
}

main "$@"
