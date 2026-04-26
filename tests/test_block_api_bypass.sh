#!/bin/bash
# test_block_api_bypass.sh — block-api-bypass.sh のユニットテスト
# 使い方: bash tests/test_block_api_bypass.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"

assert_blocked() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    pass "$desc"
  else
    fail "$desc (期待: deny, 実際: allow)"
  fi
}

assert_allowed() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    fail "$desc (期待: allow, 実際: deny)"
  else
    pass "$desc"
  fi
}

run_hook() {
  bash "$HOOKS_DIR/$1"
}

# フックにブロックされないよう変数分割で組み立てる
CR_PREFIX="@coderabbit"
CR_APPROVE="${CR_PREFIX}ai approve"
CR_UPPER_PREFIX="@CodeRabbit"
CR_APPROVE_UPPER="${CR_UPPER_PREFIX}AI approve"
CR_REVIEW="${CR_PREFIX}ai review"
MERGE_PATH="pulls"
MERGE_SUFFIX="merge"

# テスト入力を生成するヘルパー（jq で正しく JSON エスケープする）
make_bash_input() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

make_other_input() {
  local tool="$1"
  local cmd="$2"
  jq -n --arg tool "$tool" --arg cmd "$cmd" '{"tool_name":$tool,"tool_input":{"command":$cmd}}'
}

# ============================================
echo "=== block-api-bypass.sh ==="
# ============================================

# 1. gh api による直接マージ → deny
OUTPUT=$(make_bash_input "gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX} -X PUT -f merge_method=squash" | run_hook block-api-bypass.sh)
assert_blocked "gh api による直接マージ → deny" "$OUTPUT"

# 2. 通常の gh pr merge → 許可
OUTPUT=$(make_bash_input "gh pr merge 123 --squash --delete-branch" | run_hook block-api-bypass.sh)
assert_allowed "通常の gh pr merge → 許可" "$OUTPUT"

# 3. 通常の gh api（マージ以外） → 許可
OUTPUT=$(make_bash_input "gh api repos/owner/repo/${MERGE_PATH}/123/reviews --paginate" | run_hook block-api-bypass.sh)
assert_allowed "gh api（マージ以外） → 許可" "$OUTPUT"

# 4. 環境変数プレフィックス付き直接マージ → deny
OUTPUT=$(make_bash_input "GH_TOKEN=abc gh api repos/owner/repo/${MERGE_PATH}/99/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
assert_blocked "環境変数プレフィックス付き直接マージ → deny" "$OUTPUT"

# 5. Bash 以外のツール → 許可（スキップ）
OUTPUT=$(make_other_input "Read" "gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX}" | run_hook block-api-bypass.sh)
assert_allowed "Bash 以外のツール → 許可" "$OUTPUT"

# 6. command が空 → 許可
OUTPUT=$(make_bash_input "" | run_hook block-api-bypass.sh)
assert_allowed "command が空 → 許可" "$OUTPUT"

# 7. deny 出力の JSON 構造検証
OUTPUT=$(make_bash_input "gh api repos/owner/repo/${MERGE_PATH}/1/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (構造が不正)"
fi

# 8. approve の投稿 → deny
OUTPUT=$(make_bash_input "gh api repos/owner/repo/issues/123/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
assert_blocked "${CR_APPROVE} の投稿 → deny" "$OUTPUT"

# 9. approve（大文字混在） → deny
OUTPUT=$(make_bash_input "gh api repos/owner/repo/issues/45/comments -X POST -f body=\"${CR_APPROVE_UPPER}\"" | run_hook block-api-bypass.sh)
assert_blocked "${CR_APPROVE_UPPER} → deny" "$OUTPUT"

# 10. 環境変数プレフィックス付き approve → deny
OUTPUT=$(make_bash_input "GH_TOKEN=abc gh api repos/owner/repo/issues/10/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
assert_blocked "環境変数プレフィックス付き approve → deny" "$OUTPUT"

# 11. approve 以外のコマンド → 許可
OUTPUT=$(make_bash_input "gh api repos/owner/repo/issues/123/comments -X POST -f body=\"${CR_REVIEW}\"" | run_hook block-api-bypass.sh)
assert_allowed "${CR_REVIEW}（approve以外） → 許可" "$OUTPUT"

# 12. approve ブロックの JSON 構造検証
OUTPUT=$(make_bash_input "gh api repos/owner/repo/issues/1/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "approve ブロックの JSON 構造検証"
else
  fail "approve ブロックの JSON 構造検証 (構造が不正)"
fi

# 13. env ラッパー付き直接マージ → deny
OUTPUT=$(make_bash_input "env gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
assert_blocked "env ラッパー付き直接マージ → deny" "$OUTPUT"

# 14. command ラッパー付き直接マージ → deny
OUTPUT=$(make_bash_input "command gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
assert_blocked "command ラッパー付き直接マージ → deny" "$OUTPUT"

# 15. KEY=VALUE 付き直接マージ → deny
OUTPUT=$(make_bash_input "KEY=VALUE gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
assert_blocked "KEY=VALUE 付き直接マージ → deny" "$OUTPUT"

# 16. 複数環境変数連結付き直接マージ → deny
OUTPUT=$(make_bash_input "GH_TOKEN=abc GITHUB_HOST=example.com gh api repos/owner/repo/${MERGE_PATH}/123/${MERGE_SUFFIX} -X PUT" | run_hook block-api-bypass.sh)
assert_blocked "複数環境変数連結付き直接マージ → deny" "$OUTPUT"

# 17. env ラッパー付き approve → deny
OUTPUT=$(make_bash_input "env gh api repos/owner/repo/issues/123/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
assert_blocked "env ラッパー付き approve → deny" "$OUTPUT"

# 18. command ラッパー付き approve → deny
OUTPUT=$(make_bash_input "command gh api repos/owner/repo/issues/123/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
assert_blocked "command ラッパー付き approve → deny" "$OUTPUT"

# 19. KEY=VALUE 付き approve → deny
OUTPUT=$(make_bash_input "KEY=VALUE gh api repos/owner/repo/issues/123/comments -X POST -f body=\"${CR_APPROVE}\"" | run_hook block-api-bypass.sh)
assert_blocked "KEY=VALUE 付き approve → deny" "$OUTPUT"

# --- 結果サマリ ---
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
