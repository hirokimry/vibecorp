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

resolve_coderabbit_language() {
  case "$1" in
    ja) echo "ja-JP" ;;
    en) echo "en-US" ;;
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

read_lock_list() {
  # lock ファイルから指定セクションのファイル一覧を取得
  # 使い方: read_lock_list <lock_file> <section_name>
  # awk でブロック単位に抽出（grep -A N はセクション境界を越えるため使わない）
  local lock_file="$1"
  local section="$2"

  [[ -f "$lock_file" ]] || return 0

  awk -v section="$section" '
    /^  [a-z_]+:/ {
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
    [[ -n "$name" ]] && rm -f "${hooks_dir}/${name}"
  done < <(read_lock_list "$lock" "hooks")

  # lock 記載の skills を削除
  while IFS= read -r name; do
    [[ -n "$name" ]] && rm -rf "${skills_dir}/${name}"
  done < <(read_lock_list "$lock" "skills")

  log_info "管理ファイルを削除（lock ベース）"
}

copy_managed_files() {
  # テンプレートをコピー（既存ユーザーファイルはスキップ）
  local hooks_dir="${REPO_ROOT}/.claude/hooks"
  local skills_dir="${REPO_ROOT}/.claude/skills"

  mkdir -p "$hooks_dir" "$skills_dir"

  # hooks: 同名ファイルが既存ならスキップ
  for src in "${SCRIPT_DIR}/templates/claude/hooks/"*.sh; do
    [[ -f "$src" ]] || continue
    local name
    name=$(basename "$src")
    if [[ -f "${hooks_dir}/${name}" ]]; then
      log_skip "hooks/${name} は既存のためスキップ"
    else
      cp "$src" "${hooks_dir}/${name}"
    fi
  done

  # skills: 同名ディレクトリが既存ならスキップ
  for src_dir in "${SCRIPT_DIR}/templates/claude/skills/"*/; do
    [[ -d "$src_dir" ]] || continue
    local name
    name=$(basename "$src_dir")
    if [[ -d "${skills_dir}/${name}" ]]; then
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

generate_coderabbit_yaml() {
  local target="${REPO_ROOT}/.coderabbit.yaml"
  local template="${SCRIPT_DIR}/templates/coderabbit.yaml.tpl"

  if [[ -f "$target" ]]; then
    log_skip ".coderabbit.yaml は既存のためスキップ"
    return
  fi

  local lang_code
  lang_code=$(resolve_coderabbit_language "$LANGUAGE")

  sed \
    -e "s|{{LANGUAGE}}|${lang_code}|g" \
    "$template" > "$target"
  log_info ".coderabbit.yaml を生成"
}

generate_ci_workflow() {
  local target="${REPO_ROOT}/.github/workflows/test.yml"
  local template="${SCRIPT_DIR}/templates/.github/workflows/test.yml"

  if [[ -f "$target" ]]; then
    log_skip ".github/workflows/test.yml は既存のためスキップ"
    return
  fi

  mkdir -p "${REPO_ROOT}/.github/workflows"
  cp "$template" "$target"
  log_info ".github/workflows/test.yml を生成"
}

configure_github_repo() {
  # gh CLI が利用できない場合はスキップ
  if ! command -v gh >/dev/null 2>&1; then
    log_skip "gh CLI が見つかりません。リポジトリ設定は手動で行ってください"
    return
  fi

  # GitHub リポジトリ情報を取得
  local name_with_owner
  if ! name_with_owner=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null); then
    log_skip "GitHub リポジトリに接続できません。リポジトリ設定は手動で行ってください"
    return
  fi

  # vibecorp.yml から base_branch を取得（デフォルト: main）
  local base_branch="main"
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  if [[ -f "$yml" ]]; then
    local parsed
    parsed=$(awk '/^base_branch:/ { print $2 }' "$yml")
    [[ -n "$parsed" ]] && base_branch="$parsed"
  fi

  # マージ戦略の設定
  if gh api "repos/${name_with_owner}" -X PATCH \
    -f allow_squash_merge=true \
    -f allow_merge_commit=false \
    -f allow_rebase_merge=false \
    -f allow_auto_merge=true \
    -f delete_branch_on_merge=true \
    -f allow_update_branch=true \
    >/dev/null 2>&1; then
    log_info "マージ戦略を設定（squash merge のみ、auto-merge 有効）"
  else
    log_error "マージ戦略の設定に失敗しました（admin 権限が必要です）"
    log_error "手動設定: https://github.com/${name_with_owner}/settings"
  fi

  # Branch Protection の設定
  # CodeRabbit が導入されている場合は required check に追加
  local status_checks='["test"]'
  if [[ -f "${REPO_ROOT}/.coderabbit.yaml" ]]; then
    status_checks='["test","CodeRabbit"]'
  fi

  local protection_json
  protection_json=$(jq -n \
    --argjson contexts "$status_checks" \
    '{
      required_status_checks: {
        strict: true,
        contexts: $contexts
      },
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false,
        require_last_push_approval: false,
        required_approving_review_count: 1
      },
      enforce_admins: true,
      restrictions: null,
      allow_force_pushes: false,
      allow_deletions: false,
      block_creations: false,
      required_conversation_resolution: false
    }')

  if echo "$protection_json" | gh api "repos/${name_with_owner}/branches/${base_branch}/protection" \
    -X PUT --input - >/dev/null 2>&1; then
    log_info "ブランチ保護を設定（${base_branch}: CI必須、PR必須、approve必須）"
  else
    log_error "ブランチ保護の設定に失敗しました（admin 権限が必要です）"
    log_error "手動設定: https://github.com/${name_with_owner}/settings/branches"
  fi
}

generate_vibecorp_lock() {
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local installed_at
  installed_at=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
  local vibecorp_commit
  vibecorp_commit=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # vibecorp が管理するファイルのマニフェストを生成（テンプレート由来のみ）
  local hooks_list="" skills_list="" rules_list="" issue_templates_list=""

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
  for f in "${SCRIPT_DIR}/templates/.github/ISSUE_TEMPLATE/"*; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    [[ -f "${REPO_ROOT}/.github/ISSUE_TEMPLATE/${name}" ]] && issue_templates_list="${issue_templates_list}    - ${name}"$'\n'
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
${rules_list}  issue_templates:
${issue_templates_list}
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

copy_issue_templates() {
  local src="${SCRIPT_DIR}/templates/.github/ISSUE_TEMPLATE"
  local dest="${REPO_ROOT}/.github/ISSUE_TEMPLATE"

  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"

  for f in "${src}"/*; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    if [[ -f "${dest}/${name}" ]]; then
      log_skip "ISSUE_TEMPLATE/${name} は既存のためスキップ"
    else
      cp "$f" "${dest}/${name}"
    fi
  done

  log_info "Issue テンプレートをコピー"
}

create_labels() {
  # gh 未インストール or リポジトリ未接続ならスキップ
  if ! command -v gh >/dev/null 2>&1; then
    log_skip "gh 未インストールのためラベル作成をスキップ"
    return 0
  fi
  if ! gh repo view >/dev/null 2>&1; then
    log_skip "リポジトリ未接続のためラベル作成をスキップ"
    return 0
  fi

  local VIBECORP_LABELS=(
    "bug:d73a4a:不具合の報告"
    "enhancement:a2eeef:機能追加・改善"
    "documentation:0075ca:ドキュメントの追加・修正"
    "question:d876e3:質問・相談"
    "good first issue:7057ff:初心者向けのタスク"
    "help wanted:008672:協力者募集"
    "design:f9d0c4:設計・計画"
    "testing:bfd4f2:テスト関連"
    "refactor:d4c5f9:リファクタリング"
    "priority/high:b60205:優先度: 高"
    "priority/low:c2e0c6:優先度: 低"
  )

  # 既存ラベル一覧を取得
  local existing_labels
  existing_labels=$(gh label list --json name --jq '.[].name' --limit 100 2>/dev/null || echo "")

  for entry in "${VIBECORP_LABELS[@]}"; do
    local label_name label_color label_desc
    label_name="${entry%%:*}"
    local rest="${entry#*:}"
    label_color="${rest%%:*}"
    label_desc="${rest#*:}"

    if echo "$existing_labels" | grep -qxF "$label_name"; then
      log_skip "ラベル '${label_name}' は既存のためスキップ"
    else
      gh label create "$label_name" --color "$label_color" --description "$label_desc" 2>/dev/null \
        && log_info "ラベル '${label_name}' を作成" \
        || log_skip "ラベル '${label_name}' の作成に失敗（スキップ）"
    fi
  done
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
  remove_managed_files
  copy_managed_files
  generate_vibecorp_yml
  generate_coderabbit_yaml
  generate_ci_workflow
  configure_github_repo
  generate_settings_json
  copy_rules
  copy_issue_templates
  generate_claude_md
  generate_mvv_md
  create_labels
  generate_vibecorp_lock
  print_completion
}

main "$@"
