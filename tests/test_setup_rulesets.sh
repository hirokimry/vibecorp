#!/bin/bash
# test_setup_rulesets.sh — setup-rulesets.sh のユニットテスト
# 使い方: bash tests/test_setup_rulesets.sh
# 注意: GitHub API 呼び出しはテストしない（CI 環境で admin 権限がないため）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup-rulesets.sh"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_exit_code() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (期待: exit $expected, 実際: exit $actual)"
  fi
}

# --- セットアップ / クリーンアップ ---

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
  cd "$SCRIPT_DIR"
}
trap cleanup EXIT

# ============================================
echo "=== A. 引数パース ==="
# ============================================

# A1. --help でヘルプ表示・正常終了
EXIT_CODE=0; bash "$SETUP_SH" --help 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--help で正常終了" "0" "$EXIT_CODE"

# A2. 不明オプションでエラー
EXIT_CODE=0; bash "$SETUP_SH" --unknown 2>/dev/null || EXIT_CODE=$?
assert_exit_code "不明オプションでエラー" "1" "$EXIT_CODE"

# ============================================
echo ""
echo "=== B. 前提条件チェック ==="
# ============================================

# B1. vibecorp.yml なしでエラー
create_test_repo
EXIT_CODE=0; bash "$SETUP_SH" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "vibecorp.yml なしでエラー" "1" "$EXIT_CODE"
cleanup

# B2. vibecorp.yml に name なしでエラー
create_test_repo
mkdir -p "${TMPDIR_ROOT}/.claude"
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
preset: minimal
YAML
EXIT_CODE=0; bash "$SETUP_SH" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "vibecorp.yml に name なしでエラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== C. ルールセット JSON 構造検証 ==="
# ============================================

# generate_ruleset_json 関数を直接テスト
# setup-rulesets.sh を source して関数を呼び出す
RULESET_JSON=$(bash -c 'source "'"$SETUP_SH"'" 2>/dev/null; generate_ruleset_json')

# C1. enforcement が active
VALUE=$(echo "$RULESET_JSON" | jq -r '.enforcement')
if [ "$VALUE" = "active" ]; then
  pass "enforcement が active"
else
  fail "enforcement が active (実際: $VALUE)"
fi

# C2. target が branch
VALUE=$(echo "$RULESET_JSON" | jq -r '.target')
if [ "$VALUE" = "branch" ]; then
  pass "target が branch"
else
  fail "target が branch (実際: $VALUE)"
fi

# C3. conditions.ref_name.include に ~ALL
VALUE=$(echo "$RULESET_JSON" | jq -r '.conditions.ref_name.include[0]')
if [ "$VALUE" = "~ALL" ]; then
  pass "conditions に ~ALL"
else
  fail "conditions に ~ALL (実際: $VALUE)"
fi

# C4. pull_request ルールが存在
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "pull_request") | .type')
if [ "$VALUE" = "pull_request" ]; then
  pass "pull_request ルールが存在"
else
  fail "pull_request ルールが存在"
fi

# C5. required_approving_review_count が 1
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')
if [ "$VALUE" = "1" ]; then
  pass "required_approving_review_count が 1"
else
  fail "required_approving_review_count が 1 (実際: $VALUE)"
fi

# C6. dismiss_stale_reviews_on_push が true
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "pull_request") | .parameters.dismiss_stale_reviews_on_push')
if [ "$VALUE" = "true" ]; then
  pass "dismiss_stale_reviews_on_push が true"
else
  fail "dismiss_stale_reviews_on_push が true (実際: $VALUE)"
fi

# C7. required_status_checks ルールが存在
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "required_status_checks") | .type')
if [ "$VALUE" = "required_status_checks" ]; then
  pass "required_status_checks ルールが存在"
else
  fail "required_status_checks ルールが存在"
fi

# C8. strict_required_status_checks_policy が true
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy')
if [ "$VALUE" = "true" ]; then
  pass "strict_required_status_checks_policy が true"
else
  fail "strict_required_status_checks_policy が true (実際: $VALUE)"
fi

# C9. test status check が含まれる
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "test") | .context')
if [ "$VALUE" = "test" ]; then
  pass "test status check が含まれる"
else
  fail "test status check が含まれる"
fi

# C10. CodeRabbit status check が含まれる
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "CodeRabbit") | .context')
if [ "$VALUE" = "CodeRabbit" ]; then
  pass "CodeRabbit status check が含まれる"
else
  fail "CodeRabbit status check が含まれる"
fi

# C11. integration_id が省略されている（任意ソース受け入れ）
VALUE=$(echo "$RULESET_JSON" | jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[0] | has("integration_id")')
if [ "$VALUE" = "false" ]; then
  pass "integration_id が省略されている"
else
  fail "integration_id が省略されている (integration_id が含まれている)"
fi

# C12. bypass_actors に RepositoryRole (admin) が含まれる
VALUE=$(echo "$RULESET_JSON" | jq -r '.bypass_actors[0].actor_type')
if [ "$VALUE" = "RepositoryRole" ]; then
  pass "bypass_actors に RepositoryRole が含まれる"
else
  fail "bypass_actors に RepositoryRole が含まれる (実際: $VALUE)"
fi

# C13. bypass_actors の actor_id が 5 (Admin)
VALUE=$(echo "$RULESET_JSON" | jq -r '.bypass_actors[0].actor_id')
if [ "$VALUE" = "5" ]; then
  pass "bypass_actors の actor_id が 5 (Admin)"
else
  fail "bypass_actors の actor_id が 5 (Admin) (実際: $VALUE)"
fi

# C14. ルールセット名が vibecorp-protection
VALUE=$(echo "$RULESET_JSON" | jq -r '.name')
if [ "$VALUE" = "vibecorp-protection" ]; then
  pass "ルールセット名が vibecorp-protection"
else
  fail "ルールセット名が vibecorp-protection (実際: $VALUE)"
fi

# C15. JSON 全体が有効
if echo "$RULESET_JSON" | jq empty 2>/dev/null; then
  pass "JSON 全体が有効"
else
  fail "JSON 全体が有効 (パースエラー)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
