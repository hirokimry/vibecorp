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

# B9. pull_request の required_approving_review_count が 0（Issue #783: vibehawk status check を merge gate 主軸にし approval 0）
REVIEW_COUNT=$(echo "$RULESET_JSON" | jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')
if [ "$REVIEW_COUNT" = "0" ]; then
  pass "required_approving_review_count が 0"
else
  fail "required_approving_review_count が 0 (実際: $REVIEW_COUNT)"
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

# B12. required_status_checks に vibehawk が含まれる（Issue #783: vibehawk-only に移行）
VH_CHECK=$(echo "$RULESET_JSON" | jq '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "vibehawk")] | length')
if [ "$VH_CHECK" = "1" ]; then
  pass "required_status_checks に vibehawk が含まれる"
else
  fail "required_status_checks に vibehawk が含まれる (数: $VH_CHECK)"
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
echo "=== C. 冪等性解決（純粋関数 select_managed_ruleset_id / select_ruleset_id_name_only） ==="
# ============================================
# setup-rulesets.sh を source して純粋関数を直接呼ぶ（main 実行ガードで main/gh は走らない）。
# RULESET_NAME は source 後にデフォルト "vibecorp-protection" がセットされる。
# shellcheck disable=SC1090
source "$SETUP_SH"

# C0. source ガード: 関数が定義され、main（gh API 呼び出し）が走っていない
if declare -F select_managed_ruleset_id >/dev/null && declare -F select_ruleset_id_name_only >/dev/null; then
  pass "source で純粋関数が定義される（main 実行ガードで main は走らない）"
else
  fail "source で純粋関数が定義されない"
  exit 1
fi

# テスト用ヘルパ: 正規化済み ruleset 要素を組み立てる
mk() {
  # 引数: id name target enforcement include_json exclude_json has_status
  jq -nc \
    --argjson id "$1" --arg name "$2" --arg target "$3" --arg enf "$4" \
    --argjson inc "$5" --argjson exc "$6" --argjson hs "$7" \
    '{id: $id, name: $name, target: $target, enforcement: $enf, include: $inc, exclude: $exc, has_status: $hs}'
}

VP="vibecorp-protection"
OTHER="全ブランチ保護"

# C1. 名前一致 → その ID を返す
JSON="[$(mk 999 "$VP" branch active '["~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "999" ]; then
  pass "C1 名前一致 → ID 999 を返す"
else
  fail "C1 名前一致 (rc=$rc out=$out)"
fi

# C2. 名前不一致 + 単一の vibecorp gate 相当（~ALL/active/branch/status/exclude空）→ adopt
JSON="[$(mk 14181995 "$OTHER" branch active '["~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "14181995" ]; then
  pass "C2 名前不一致 + 単一適格 ~ALL → adopt (ID 14181995)"
else
  fail "C2 adopt (rc=$rc out=$out)"
fi

# C2b. include 多値 ["refs/heads/x","~ALL"] でも adopt（index 判定で取りこぼさない）
JSON="[$(mk 222 "$OTHER" branch active '["refs/heads/x","~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "222" ]; then
  pass "C2b include 多値に ~ALL を含む → adopt (ID 222)"
else
  fail "C2b include 多値 (rc=$rc out=$out)"
fi

# C3. 名前不一致 + ~ALL なし → 空（新規作成）
JSON="[$(mk 333 "$OTHER" branch active '["refs/heads/main"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C3 ~ALL なし → 空（新規作成へ）"
else
  fail "C3 ~ALL なし (rc=$rc out=$out)"
fi

# C4. 名前不一致 + 適格 ~ALL ruleset 複数 → rc=3（曖昧・中断）
JSON="[$(mk 401 "$OTHER" branch active '["~ALL"]' '[]' true),$(mk 402 "別ゲート" branch active '["~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 3 ]; then
  pass "C4 適格 ~ALL 複数 → rc=3（中断）"
else
  fail "C4 複数中断 (rc=$rc out=$out)"
fi

# C5. ~ALL だが enforcement=disabled → adopt しない（空）
JSON="[$(mk 501 "$OTHER" branch disabled '["~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C5 enforcement=disabled → adopt しない（空）"
else
  fail "C5 disabled 除外 (rc=$rc out=$out)"
fi

# C6. ~ALL だが target=tag → adopt しない（空）
JSON="[$(mk 601 "$OTHER" tag active '["~ALL"]' '[]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C6 target=tag → adopt しない（空）"
else
  fail "C6 tag 除外 (rc=$rc out=$out)"
fi

# C7. ~ALL だが exclude 非空 → adopt しない（空）🔒 除外設定を消さない
JSON="[$(mk 701 "$OTHER" branch active '["~ALL"]' '["refs/heads/release/*"]' true)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C7 exclude 非空 → adopt しない（空）"
else
  fail "C7 exclude 安全弁 (rc=$rc out=$out)"
fi

# C8. ~ALL active branch だが required_status_checks なし（has_status=false）→ adopt しない（空）🔒
JSON="[$(mk 801 "$OTHER" branch active '["~ALL"]' '[]' false)]"
rc=0; out="$(printf '%s' "$JSON" | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C8 required_status_checks なし → adopt しない（空）"
else
  fail "C8 has_status 安全弁 (rc=$rc out=$out)"
fi

# C9. 空入力 [] → 空（新規作成）
rc=0; out="$(printf '%s' '[]' | select_managed_ruleset_id)" || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "C9 空入力 → 空（新規作成へ）"
else
  fail "C9 空入力 (rc=$rc out=$out)"
fi

# C-del1. delete 用 name-only: 名前不一致のみ → 空（adopt しないことを実証）
JSON="[$(mk 14181995 "$OTHER" branch active '["~ALL"]' '[]' true)]"
out="$(printf '%s' "$JSON" | select_ruleset_id_name_only)"
if [ -z "$out" ]; then
  pass "C-del1 name-only は名前不一致 ~ALL を拾わない（誤削除防止）"
else
  fail "C-del1 name-only 誤検出 (out=$out)"
fi

# C-del2. delete 用 name-only: 名前一致 → その ID
JSON="[$(mk 909 "$VP" branch active '["~ALL"]' '[]' true)]"
out="$(printf '%s' "$JSON" | select_ruleset_id_name_only)"
if [ "$out" = "909" ]; then
  pass "C-del2 name-only は名前一致 → ID 909"
else
  fail "C-del2 name-only 名前一致 (out=$out)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
