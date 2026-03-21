#!/bin/bash
# setup-rulesets.sh — vibecorp リポジトリ保護ルールセット自動設定
# Usage: setup-rulesets.sh [--delete] [--help]
set -euo pipefail

RULESET_NAME="vibecorp-protection"

# ── ユーティリティ ─────────────────────────────────────

log_info()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
  local exit_code="${1:-1}"
  cat >&2 <<'USAGE'
Usage: setup-rulesets.sh [--delete] [--help]

GitHub Rulesets API を使用してリポジトリの全ブランチ保護を設定する。
admin 権限が必要。

Options:
  --delete  vibecorp-protection ルールセットを削除
  -h, --help  このヘルプを表示
USAGE
  exit "$exit_code"
}

# ── 引数パース ─────────────────────────────────────────

parse_args() {
  DELETE_MODE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --delete)  DELETE_MODE=true; shift ;;
      -h|--help) usage 0 ;;
      *)         log_error "不明なオプション: $1"; usage ;;
    esac
  done
}

# ── 前提チェック ───────────────────────────────────────

check_prerequisites() {
  if ! command -v gh >/dev/null 2>&1; then
    log_error "gh CLI が必要です。インストール: https://cli.github.com/"
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq が必要です。インストール: brew install jq"
    exit 1
  fi
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    log_error "git リポジトリ内で実行してください"
    exit 1
  fi
}

# ── リポジトリ情報取得 ─────────────────────────────────

detect_repo() {
  REPO_FULL=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  if [[ -z "$REPO_FULL" ]]; then
    log_error "GitHub リポジトリが見つかりません"
    exit 1
  fi
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
}

# ── Ruleset JSON 生成 ──────────────────────────────────

generate_ruleset_json() {
  cat <<'JSON'
{
  "name": "vibecorp-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "test" },
          { "context": "CodeRabbit" }
        ]
      }
    }
  ],
  "bypass_actors": []
}
JSON
}

# ── 既存ルールセット検索 ───────────────────────────────

find_existing_ruleset_id() {
  # vibecorp-protection ルールセットの ID を返す。見つからなければ空文字
  gh api --paginate "repos/${REPO_FULL}/rulesets" \
    --jq '.[] | select(.name == "'"${RULESET_NAME}"'") | .id' \
    2>/dev/null || true
}

# ── ルールセット作成/更新 ──────────────────────────────

create_or_update_ruleset() {
  local existing_id
  existing_id=$(find_existing_ruleset_id)
  local json
  json=$(generate_ruleset_json)

  if [[ -n "$existing_id" ]]; then
    # 既存を更新
    local response
    response=$(echo "$json" | gh api \
      --method PUT \
      "repos/${REPO_FULL}/rulesets/${existing_id}" \
      --input - 2>&1) || {
      handle_api_error "$response" "ルールセットの更新"
      return 1
    }
    log_info "ルールセット '${RULESET_NAME}' を更新しました (ID: ${existing_id})"
  else
    # 新規作成
    local response
    response=$(echo "$json" | gh api \
      --method POST \
      "repos/${REPO_FULL}/rulesets" \
      --input - 2>&1) || {
      handle_api_error "$response" "ルールセットの作成"
      return 1
    }
    local new_id
    new_id=$(echo "$response" | jq -r '.id // empty')
    log_info "ルールセット '${RULESET_NAME}' を作成しました (ID: ${new_id:-unknown})"
  fi
}

# ── 旧 Branch Protection 削除 ─────────────────────────

remove_legacy_branch_protection() {
  local branch="${DEFAULT_BRANCH:-main}"
  local response
  response=$(gh api \
    --method DELETE \
    "repos/${REPO_FULL}/branches/${branch}/protection" 2>&1) || {
    # 404 は無視（保護が設定されていない場合）
    if echo "$response" | grep -q "404\|Not Found"; then
      log_info "${branch} ブランチの旧保護ルールはありません（スキップ）"
      return 0
    fi
    handle_api_error "$response" "旧ブランチ保護の削除"
    return 1
  }
  log_info "${branch} ブランチの旧保護ルールを削除しました"
}

# ── ルールセット削除 ───────────────────────────────────

delete_ruleset() {
  local existing_id
  existing_id=$(find_existing_ruleset_id)

  if [[ -z "$existing_id" ]]; then
    log_info "ルールセット '${RULESET_NAME}' は存在しません（スキップ）"
    return 0
  fi

  local response
  response=$(gh api \
    --method DELETE \
    "repos/${REPO_FULL}/rulesets/${existing_id}" 2>&1) || {
    handle_api_error "$response" "ルールセットの削除"
    return 1
  }
  log_info "ルールセット '${RULESET_NAME}' を削除しました (ID: ${existing_id})"
}

# ── エラーハンドリング ─────────────────────────────────

handle_api_error() {
  local response="$1"
  local action="$2"

  if echo "$response" | grep -q "404\|Not Found"; then
    log_error "${action}に失敗しました: リポジトリが見つからないか、Rulesets API が利用できません"
    log_error "GitHub Free プランの private リポジトリでは Rulesets は利用できません"
  elif echo "$response" | grep -q "403\|Forbidden"; then
    log_error "${action}に失敗しました: admin 権限が必要です"
    log_error "リポジトリの admin 権限があるアカウントで gh auth login してください"
  elif echo "$response" | grep -q "422\|Unprocessable"; then
    log_error "${action}に失敗しました: リクエストが不正です"
    log_error "レスポンス: ${response}"
  else
    log_error "${action}に失敗しました"
    log_error "レスポンス: ${response}"
  fi
}

# ── メイン ─────────────────────────────────────────────

main() {
  parse_args "$@"
  check_prerequisites
  detect_repo

  if [[ "$DELETE_MODE" == true ]]; then
    delete_ruleset
  else
    create_or_update_ruleset
    remove_legacy_branch_protection
  fi
}

main "$@"
