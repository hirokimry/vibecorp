#!/bin/bash
# setup-rulesets.sh — vibecorp リポジトリ保護ルールセット自動設定
# Usage: setup-rulesets.sh [--delete] [--help]
set -euo pipefail

RULESET_NAME="vibecorp-protection"
# create/update 経路で解決した既存 ruleset の ID（adopt 時は別名 ruleset の ID）。空なら新規作成。
EXISTING_RULESET_ID=""

# ── ユーティリティ ─────────────────────────────────────

log_info()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*" >&2; }
log_warn()  { printf '\033[33m[WARN]\033[0m  %s\n' "$*" >&2; }
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
        "required_approving_review_count": 0,
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
          { "context": "vibehawk" }
        ]
      }
    }
  ],
  "bypass_actors": []
}
JSON
}

# ── 既存ルールセット検索（冪等化の核心） ───────────────

# 採用すべき ruleset の ID を決定する純粋関数（API 非依存・テスト可能）。
# 入力: stdin に正規化済み ruleset 配列 JSON（各要素 {id,name,target,enforcement,include,exclude,has_status}）。
# 出力/終了コード:
#   - 名前一致 or 単一の vibecorp gate 相当 ruleset → その ID を stdout、exit 0
#   - 該当なし → 空出力、exit 0（新規作成へ）
#   - vibecorp gate 相当が複数 → return 3（曖昧・中断シグナル。誤った上書きを防ぐ）
select_managed_ruleset_id() {
  local json by_name filter count
  json=$(cat)

  # 1) 名前一致（このスクリプトが作成した ruleset）を最優先
  by_name=$(printf '%s' "$json" | jq -r --arg n "$RULESET_NAME" \
    '[.[] | select(.name == $n) | .id] | .[0] // empty')
  if [[ -n "$by_name" ]]; then
    printf '%s' "$by_name"
    return 0
  fi

  # 2) vibecorp gate 相当の候補のみ adopt（重複作成を回避）。
  #    安全弁: exclude 空（除外設定を消さない）+ required_status_checks 保有（別目的 ruleset を乗っ取らない）。
  filter='[.[] | select(
            .target == "branch"
            and .enforcement == "active"
            and ((.include // []) | index("~ALL") != null)
            and ((.exclude // []) | length == 0)
            and (.has_status == true)
          )]'
  count=$(printf '%s' "$json" | jq "${filter} | length")
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi
  if [[ "$count" -gt 1 ]]; then
    return 3
  fi
  printf '%s' "$json" | jq -r "${filter}[0].id"
  return 0
}

# 名前完全一致の ID のみを返す純粋関数（adopt しない。delete 専用）。
select_ruleset_id_name_only() {
  jq -r --arg n "$RULESET_NAME" '[.[] | select(.name == $n) | .id] | .[0] // empty'
}

# rulesets list（lite）から branch ruleset を抽出し、各詳細を GET して正規化する。
# lite list は conditions/rules を含まないため、include/exclude/has_status は詳細 GET から取る。
build_ruleset_index() {
  local list="$1"
  local ids out id detail
  out='[]'
  ids=$(printf '%s' "$list" | jq -r '.[] | select(.target == "branch") | .id')
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    # 詳細取得失敗時はその ruleset を冪等判定からスキップする（continue）。
    # 取りこぼしで重複作成が起きうるため warn で可視化する（silent にしない）。
    if ! detail=$(gh api "repos/${REPO_FULL}/rulesets/${id}" 2>/dev/null); then
      log_warn "ruleset 詳細の取得に失敗しました (ID: ${id})。冪等判定から除外します（重複作成の可能性）。"
      continue
    fi
    out=$(printf '%s' "$out" | jq --argjson d "$detail" '. + [{
      id: $d.id,
      name: $d.name,
      target: $d.target,
      enforcement: $d.enforcement,
      include: ($d.conditions.ref_name.include // []),
      exclude: ($d.conditions.ref_name.exclude // []),
      has_status: (($d.rules // []) | map(.type) | index("required_status_checks") != null)
    }]')
  done <<< "$ids"
  printf '%s' "$out"
}

# create/update 用: 既存 ruleset を冪等に解決して EXISTING_RULESET_ID に格納する。
# main シェルから直接呼ぶ（command substitution のサブシェルにしない）ことで exit 1 が確実に全体を止める。
resolve_existing_ruleset_id() {
  local list normalized rc=0
  list=$(gh api --paginate "repos/${REPO_FULL}/rulesets" 2>/dev/null || printf '[]')
  normalized=$(build_ruleset_index "$list")
  # return 3（曖昧）を set -e で殺さず捕捉する。$? を即時取得するため間にコマンドを挟まない。
  EXISTING_RULESET_ID="$(printf '%s' "$normalized" | select_managed_ruleset_id)" || rc=$?
  if [[ "$rc" -eq 3 ]]; then
    log_error "~ALL を対象とする vibecorp gate 相当の branch ruleset が複数存在します。"
    log_error "どれを ${RULESET_NAME} として管理すべきか曖昧なため中断しました。"
    log_error "不要な ruleset を削除/統合してから再実行してください。"
    exit 1
  elif [[ "$rc" -ne 0 ]]; then
    log_error "既存 ruleset の解決に失敗しました（rc=${rc}）"
    exit 1
  fi
  if [[ -n "$EXISTING_RULESET_ID" ]]; then
    local matched_name
    matched_name=$(printf '%s' "$normalized" | jq -r --arg id "$EXISTING_RULESET_ID" \
      '.[] | select((.id|tostring) == $id) | .name')
    if [[ "$matched_name" != "$RULESET_NAME" ]]; then
      log_warn "既存 ruleset「${matched_name}」(ID: ${EXISTING_RULESET_ID}) を ${RULESET_NAME} として PUT 上書き（リネーム）します。これは破壊的操作です（重複作成は回避）。"
    fi
  fi
}

# delete 用: 名前完全一致の ID を解決する（adopt しない＝別名の稼働 ruleset を誤削除しない）。
find_ruleset_id_by_name() {
  local list
  list=$(gh api --paginate "repos/${REPO_FULL}/rulesets" 2>/dev/null || printf '[]')
  printf '%s' "$list" | select_ruleset_id_name_only
}

# ── ルールセット作成/更新 ──────────────────────────────

create_or_update_ruleset() {
  # EXISTING_RULESET_ID は main() が resolve_existing_ruleset_id で事前解決済み。
  local json
  json=$(generate_ruleset_json)

  if [[ -n "$EXISTING_RULESET_ID" ]]; then
    # 既存を更新（adopt 時は別名 ruleset を vibecorp-protection に正規化＝リネーム、ID 不変）
    local response
    response=$(echo "$json" | gh api \
      --method PUT \
      "repos/${REPO_FULL}/rulesets/${EXISTING_RULESET_ID}" \
      --input - 2>&1) || {
      handle_api_error "$response" "ルールセットの更新"
      return 1
    }
    log_info "ルールセット '${RULESET_NAME}' を更新しました (ID: ${EXISTING_RULESET_ID})"
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
  # delete は名前完全一致のみ（adopt しない＝CEO の別名稼働 ruleset を誤削除しない）。
  local existing_id
  existing_id=$(find_ruleset_id_by_name)

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
    resolve_existing_ruleset_id
    # ruleset の作成/更新が成功してから classic protection を削除する。
    # 順序を守らないと、upsert 失敗時に保護が一時的に外れる窓（gate 不在）が生じる。
    if create_or_update_ruleset; then
      remove_legacy_branch_protection
    else
      log_error "ルールセットの作成/更新に失敗したため、classic protection の削除を中止しました（gate 不在の窓を回避）"
      exit 1
    fi
  fi
}

# 直接実行された場合のみ main を走らせる（テストから source して純粋関数を呼べるようにする）。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
