#!/bin/bash
# setup-rulesets.sh — GitHub リポジトリ保護ルールセットの自動設定
# Usage: setup-rulesets.sh [--delete]
set -euo pipefail

RULESET_NAME="vibecorp-protection"

# ── ユーティリティ ─────────────────────────────────────

log_info()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
log_skip()  { printf '\033[33m[SKIP]\033[0m  %s\n' "$*" >&2; }

usage() {
  local exit_code="${1:-1}"
  cat >&2 <<'USAGE'
Usage: setup-rulesets.sh [--delete]

GitHub リポジトリに vibecorp 標準の保護ルールセットを設定します。
admin 権限が必要です。

Options:
  --delete    既存の vibecorp-protection ルールセットを削除
  -h, --help  このヘルプを表示

設定内容:
  - 対象: 全ブランチ
  - PR レビュー: 1件承認必須、stale レビュー却下
  - CI 必須: test + CodeRabbit
  - strict: ベースブランチとの最新同期を要求
USAGE
  exit "$exit_code"
}

# ── ルールセット JSON 生成 ───────────────────────────────

generate_ruleset_json() {
  # テスト可能な関数としてJSON生成を分離
  jq -n '{
    "name": "vibecorp-protection",
    "target": "branch",
    "enforcement": "active",
    "bypass_actors": [
      {
        "actor_id": 5,
        "actor_type": "RepositoryRole",
        "bypass_mode": "always"
      }
    ],
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
          "required_status_checks": [
            {
              "context": "test"
            },
            {
              "context": "CodeRabbit"
            }
          ]
        }
      }
    ]
  }'
}

# ── ステップ関数 ───────────────────────────────────────

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

check_prerequisites() {
  if ! command -v gh >/dev/null 2>&1; then
    log_error "gh CLI が必要です。インストール: https://cli.github.com/"
    exit 1
  fi
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
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ ! -f "$yml" ]]; then
    log_error "vibecorp.yml が見つかりません。先に install.sh を実行してください"
    exit 1
  fi

  PROJECT_NAME=$(awk '/^name:/ { print $2 }' "$yml")
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    log_error "vibecorp.yml に name が定義されていません"
    exit 1
  fi

  log_info "プロジェクト: ${PROJECT_NAME}"
}

detect_github_repo() {
  REPO_NWOPATH=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  if [[ -z "${REPO_NWOPATH:-}" ]]; then
    log_error "GitHub リポジトリの情報を取得できません。gh auth login を実行してください"
    exit 1
  fi
  log_info "リポジトリ: ${REPO_NWOPATH}"
}

find_existing_ruleset() {
  # 既存の vibecorp-protection ルールセットを検索
  EXISTING_RULESET_ID=$(gh api --paginate "repos/${REPO_NWOPATH}/rulesets" \
    --jq '.[] | select(.name == "'"${RULESET_NAME}"'") | .id' \
    | head -1 \
    || echo "")

  if [[ -n "$EXISTING_RULESET_ID" ]]; then
    log_info "既存ルールセット検出: ID ${EXISTING_RULESET_ID}"
    return 0
  else
    EXISTING_RULESET_ID=""
    return 1
  fi
}

delete_ruleset() {
  if ! find_existing_ruleset; then
    log_skip "削除対象のルールセット '${RULESET_NAME}' が見つかりません"
    return 0
  fi

  local http_status
  http_status=$(gh api -X DELETE "repos/${REPO_NWOPATH}/rulesets/${EXISTING_RULESET_ID}" \
    --silent 2>&1) || {
    local exit_code=$?
    log_error "ルールセットの削除に失敗しました"
    handle_api_error "$exit_code"
    exit 1
  }

  log_info "ルールセット '${RULESET_NAME}' を削除しました"
}

create_or_update_ruleset() {
  local ruleset_json
  ruleset_json=$(generate_ruleset_json)

  if find_existing_ruleset; then
    # 既存ルールセットを更新
    gh api -X PUT "repos/${REPO_NWOPATH}/rulesets/${EXISTING_RULESET_ID}" \
      --input - <<< "$ruleset_json" > /dev/null || {
      local exit_code=$?
      log_error "ルールセットの更新に失敗しました"
      handle_api_error "$exit_code"
      exit 1
    }
    log_info "ルールセット '${RULESET_NAME}' を更新しました"
  else
    # 新規作成
    gh api -X POST "repos/${REPO_NWOPATH}/rulesets" \
      --input - <<< "$ruleset_json" > /dev/null || {
      local exit_code=$?
      log_error "ルールセットの作成に失敗しました"
      handle_api_error "$exit_code"
      exit 1
    }
    log_info "ルールセット '${RULESET_NAME}' を作成しました"
  fi
}

handle_api_error() {
  local exit_code="$1"
  # gh CLI は HTTP エラー時に stderr にメッセージを出力する
  # 一般的なエラーケースの案内を追加
  cat >&2 <<'MSG'

考えられる原因:
  - admin 権限がない → リポジトリの Settings > Collaborators で権限を確認してください
  - GitHub Free プランの private リポジトリ → Rulesets は public リポジトリまたは有料プランが必要です
  - GitHub CLI の認証切れ → gh auth login を実行してください
MSG
}

print_completion() {
  cat >&2 <<DONE

────────────────────────────────────────────
  vibecorp リポジトリ保護ルールセットを設定しました
  プロジェクト: ${PROJECT_NAME}
  リポジトリ:   ${REPO_NWOPATH}
  ルールセット: ${RULESET_NAME}

  設定内容:
    - 全ブランチ保護
    - PR レビュー 1件承認必須
    - CI (test + CodeRabbit) 必須
────────────────────────────────────────────

DONE
}

# ── メイン ─────────────────────────────────────────────

main() {
  parse_args "$@"
  check_prerequisites
  detect_repo_root
  read_vibecorp_yml

  if [[ "$DELETE_MODE" == true ]]; then
    detect_github_repo
    delete_ruleset
  else
    detect_github_repo
    create_or_update_ruleset
    print_completion
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
