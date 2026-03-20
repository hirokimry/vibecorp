#!/bin/bash
# install.sh — vibecorp プラグインインストーラー
# Usage: install.sh --name <project-name> [--preset minimal|standard|full] [--language ja|en|...]
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

Options:
  --name      プロジェクト名（必須、英数字とハイフン、1-50文字）
  --preset    組織プリセット: minimal（デフォルト: minimal）
  --language  回答言語: ja, en, または任意（デフォルト: ja）
  -h, --help  このヘルプを表示
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
  PRESET="minimal"
  LANGUAGE="ja"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--name に値が必要です"; usage; }; PROJECT_NAME="$2"; shift 2 ;;
      --preset)   [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--preset に値が必要です"; usage; }; PRESET="$2"; shift 2 ;;
      --language) [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--language に値が必要です"; usage; }; LANGUAGE="$2"; shift 2 ;;
      -h|--help)  usage 0 ;;
      *)          log_error "不明なオプション: $1"; usage ;;
    esac
  done

  if [[ -z "$PROJECT_NAME" ]]; then
    log_error "--name は必須です"
    usage
  fi
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

create_vibecorp_dir() {
  mkdir -p "${REPO_ROOT}/.claude/vibecorp"
  log_info ".claude/vibecorp/ を作成"
}

copy_templates() {
  # hooks と skills をコピー（rules は copy_rules() で .claude/rules/ へ直接コピー）
  # 再実行時のネスト防止: 既存ディレクトリを削除してからコピー
  rm -rf "${REPO_ROOT}/.claude/vibecorp/hooks" "${REPO_ROOT}/.claude/vibecorp/skills"
  cp -R "${SCRIPT_DIR}/templates/claude/hooks" "${REPO_ROOT}/.claude/vibecorp/"
  cp -R "${SCRIPT_DIR}/templates/claude/skills" "${REPO_ROOT}/.claude/vibecorp/"

  # プレースホルダー置換（現テンプレートには該当なし、将来用に仕組みだけ入れる）
  # macOS 互換: sed ... > tmp && mv tmp original（sed -i の BSD/GNU 差異を回避）
  find "${REPO_ROOT}/.claude/vibecorp" -type f \( -name '*.sh' -o -name '*.md' \) | while IFS= read -r f; do
    if grep -q '{{' "$f" 2>/dev/null; then
      sed \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        -e "s|{{PRESET}}|${PRESET}|g" \
        -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
        "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    fi
  done

  # hooks に実行権限を付与
  chmod +x "${REPO_ROOT}/.claude/vibecorp/hooks/"*.sh

  # プリセット別削除（引き算方式）
  case "$PRESET" in
    minimal)
      rm -f "${REPO_ROOT}/.claude/vibecorp/hooks/review-to-rules-gate.sh"
      rm -rf "${REPO_ROOT}/.claude/vibecorp/skills/review-to-rules"
      ;;
  esac

  log_info "テンプレートをコピー (preset: ${PRESET})"
}

generate_version() {
  echo "${VIBECORP_VERSION}" > "${REPO_ROOT}/.claude/vibecorp/VERSION"
  log_info "VERSION を生成 (${VIBECORP_VERSION})"
}

update_gitignore() {
  local gitignore="${REPO_ROOT}/.gitignore"
  local entry=".claude/vibecorp/"

  if [[ -f "$gitignore" ]] && grep -qxF "$entry" "$gitignore"; then
    log_skip ".gitignore に ${entry} は追記済み"
  else
    # 末尾改行がない場合に行が連結されるのを防止
    if [[ -f "$gitignore" ]] && [[ -s "$gitignore" ]] && [[ -n "$(tail -c 1 "$gitignore")" ]]; then
      printf '\n' >> "$gitignore"
    fi
    printf '%s\n' "$entry" >> "$gitignore"
    log_info ".gitignore に ${entry} を追記"
  fi
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

  cat > "$lock" <<YAML
# vibecorp.lock — 自動生成、手動編集禁止
version: ${VIBECORP_VERSION}
installed_at: ${installed_at}
preset: ${PRESET}
vibecorp_commit: ${vibecorp_commit}
YAML
  log_info "vibecorp.lock を生成"
}

generate_settings_json() {
  local settings="${REPO_ROOT}/.claude/settings.json"
  local template="${SCRIPT_DIR}/templates/settings.json.tpl"

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
    # 既存: ユーザーフックを保持し、vibecorp フックのみ差し替え
    local new_hooks
    new_hooks=$(echo "$new_settings" | jq '.hooks.PreToolUse')

    jq --argjson new "$new_hooks" '
      def strip_vibecorp_hooks:
        .hooks |= map(select(.command | contains(".claude/vibecorp/hooks/") | not));
      # 既存から vibecorp フックを除去し、新規と結合後、同一 matcher をマージ
      .hooks.PreToolUse = (
        [(.hooks.PreToolUse // [])[] | strip_vibecorp_hooks | select((.hooks | length) > 0)]
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
    if [[ -f "${dest}/${basename}" ]]; then
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
  cat >&2 <<DONE

────────────────────────────────────────────
  vibecorp ${VIBECORP_VERSION} のインストールが完了しました
  プロジェクト: ${PROJECT_NAME}
  プリセット:   ${PRESET}
  リポジトリ:   ${REPO_ROOT}
────────────────────────────────────────────

DONE
}

# ── メイン ─────────────────────────────────────────────

main() {
  parse_args "$@"
  validate_name
  validate_preset
  validate_language
  check_prerequisites
  detect_repo_root
  create_vibecorp_dir
  copy_templates
  generate_version
  update_gitignore
  generate_vibecorp_yml
  generate_vibecorp_lock
  generate_settings_json
  copy_rules
  generate_claude_md
  generate_mvv_md
  print_completion
}

main "$@"
