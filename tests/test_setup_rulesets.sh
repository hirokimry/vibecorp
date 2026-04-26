#!/bin/bash
# test_setup_rulesets.sh — setup-rulesets.sh のユニットテスト
# 使い方: bash tests/test_setup_rulesets.sh
#
# GitHub API 呼び出しはテストしない（CI 環境で admin 権限がないため）。
# 引数パース、前提チェック、JSON 生成ロジックを検証する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup-rulesets.sh"

# ============================================
echo "=== A. 引数パース ==="
# ============================================

# A1. --help でヘルプ表示・正常終了
EXIT_CODE=0; bash "$SETUP_SH" --help 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--help でヘルプ表示・正常終了" "0" "$EXIT_CODE"

# A2. -h でヘルプ表示・正常終了
EXIT_CODE=0; bash "$SETUP_SH" -h 2>/dev/null || EXIT_CODE=$?
assert_exit_code "-h でヘルプ表示・正常終了" "0" "$EXIT_CODE"

# A3. 不明オプションでエラー
EXIT_CODE=0; bash "$SETUP_SH" --unknown 2>/dev/null || EXIT_CODE=$?
assert_exit_code "不明オプションでエラー" "1" "$EXIT_CODE"

# A4. --delete オプションのパース（gh が認証済みでない場合はそこでエラーになるが、パース自体は通る）
# --delete は前提チェック後に処理されるため、gh 未認証なら detect_repo でエラー
# ここではパース + 前提チェックまでは通ることを確認
# ※ gh がインストールされていれば前提チェックは通るが、detect_repo で失敗する可能性がある
# そのため、--delete のパースは --help と組み合わせてはテストできない
# 代わりに、スクリプトを source して parse_args 関数を直接テストする

# source が難しいので、別アプローチ: --delete が不明オプション扱いにならないことを確認
# gh が認証済みかどうかに依存しないテスト方法として、エラーメッセージを確認
OUTPUT=$(bash "$SETUP_SH" --delete 2>&1 || true)
if echo "$OUTPUT" | grep -q "不明なオプション"; then
  fail "--delete が不明オプション扱いにならない"
else
  pass "--delete が不明オプション扱いにならない"
fi

# ============================================
echo ""
echo "=== B. Ruleset JSON 構造検証 ==="
# ============================================

# generate_ruleset_json のヒアドキュメントから JSON を直接抽出
RULESET_JSON=$(awk "/cat <<'JSON'/,/^JSON$/" "$SETUP_SH" | sed '1d;$d')

# B1. bypass_actors が空配列
BYPASS=$(echo "$RULESET_JSON" | jq '.bypass_actors')
if [ "$BYPASS" = "[]" ]; then
  pass "bypass_actors が空配列"
else
  fail "bypass_actors が空配列 (実際: $BYPASS)"
fi

# B2. conditions.ref_name.include に ~ALL
INCLUDE=$(echo "$RULESET_JSON" | jq -r '.conditions.ref_name.include[0]')
if [ "$INCLUDE" = "~ALL" ]; then
  pass "conditions.ref_name.include に ~ALL"
else
  fail "conditions.ref_name.include に ~ALL (実際: $INCLUDE)"
fi

# B3. conditions.ref_name.exclude が空配列
EXCLUDE=$(echo "$RULESET_JSON" | jq '.conditions.ref_name.exclude')
if [ "$EXCLUDE" = "[]" ]; then
  pass "conditions.ref_name.exclude が空配列"
else
  fail "conditions.ref_name.exclude が空配列 (実際: $EXCLUDE)"
fi

# B4. enforcement が active
ENFORCEMENT=$(echo "$RULESET_JSON" | jq -r '.enforcement')
if [ "$ENFORCEMENT" = "active" ]; then
  pass "enforcement が active"
else
  fail "enforcement が active (実際: $ENFORCEMENT)"
fi

# B5. target が branch
TARGET=$(echo "$RULESET_JSON" | jq -r '.target')
if [ "$TARGET" = "branch" ]; then
  pass "target が branch"
else
  fail "target が branch (実際: $TARGET)"
fi

# B6. name が vibecorp-protection
NAME=$(echo "$RULESET_JSON" | jq -r '.name')
if [ "$NAME" = "vibecorp-protection" ]; then
  pass "name が vibecorp-protection"
else
  fail "name が vibecorp-protection (実際: $NAME)"
fi

# B7. rules に pull_request が含まれる
PR_RULE=$(echo "$RULESET_JSON" | jq '[.rules[] | select(.type == "pull_request")] | length')
if [ "$PR_RULE" = "1" ]; then
  pass "rules に pull_request が含まれる"
else
  fail "rules に pull_request が含まれる (数: $PR_RULE)"
fi

# B8. rules に required_status_checks が含まれる
SC_RULE=$(echo "$RULESET_JSON" | jq '[.rules[] | select(.type == "required_status_checks")] | length')
if [ "$SC_RULE" = "1" ]; then
  pass "rules に required_status_checks が含まれる"
else
  fail "rules に required_status_checks が含まれる (数: $SC_RULE)"
fi

# B9. pull_request の required_approving_review_count が 1
REVIEW_COUNT=$(echo "$RULESET_JSON" | jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')
if [ "$REVIEW_COUNT" = "1" ]; then
  pass "required_approving_review_count が 1"
else
  fail "required_approving_review_count が 1 (実際: $REVIEW_COUNT)"
fi

# B10. pull_request の dismiss_stale_reviews_on_push が true
DISMISS=$(echo "$RULESET_JSON" | jq '.rules[] | select(.type == "pull_request") | .parameters.dismiss_stale_reviews_on_push')
if [ "$DISMISS" = "true" ]; then
  pass "dismiss_stale_reviews_on_push が true"
else
  fail "dismiss_stale_reviews_on_push が true (実際: $DISMISS)"
fi

# B11. required_status_checks に test が含まれる
TEST_CHECK=$(echo "$RULESET_JSON" | jq '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "test")] | length')
if [ "$TEST_CHECK" = "1" ]; then
  pass "required_status_checks に test が含まれる"
else
  fail "required_status_checks に test が含まれる (数: $TEST_CHECK)"
fi

# B12. required_status_checks に CodeRabbit が含まれる
CR_CHECK=$(echo "$RULESET_JSON" | jq '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "CodeRabbit")] | length')
if [ "$CR_CHECK" = "1" ]; then
  pass "required_status_checks に CodeRabbit が含まれる"
else
  fail "required_status_checks に CodeRabbit が含まれる (数: $CR_CHECK)"
fi

# B13. strict_required_status_checks_policy が true
STRICT=$(echo "$RULESET_JSON" | jq '.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy')
if [ "$STRICT" = "true" ]; then
  pass "strict_required_status_checks_policy が true"
else
  fail "strict_required_status_checks_policy が true (実際: $STRICT)"
fi

# B14. JSON が有効であること
if echo "$RULESET_JSON" | jq empty 2>/dev/null; then
  pass "生成された JSON が有効"
else
  fail "生成された JSON が有効"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
