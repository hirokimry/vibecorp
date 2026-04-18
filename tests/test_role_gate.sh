#!/bin/bash
# test_role_gate.sh — role-gate.sh のユニットテスト
# 使い方: bash tests/test_role_gate.sh

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"
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

# --- セットアップ / クリーンアップ ---

setup_project_dir() {
  TMPDIR_ROOT=$(mktemp -d)
  mkdir -p "${TMPDIR_ROOT}/.claude/state"
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
}

write_vibecorp_yml() {
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
base_branch: main
YAML
}

write_role_file() {
  local role="$1"
  echo "$role" > "${TMPDIR_ROOT}/.claude/state/agent-role"
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
}
trap cleanup EXIT

# ============================================
echo "=== role-gate.sh ==="
# ============================================

setup_project_dir
write_vibecorp_yml

# --- CPO ロール ---
echo ""
echo "--- CPO ロール ---"

write_role_file "cpo"

# 1. CPO が管轄内(docs/specification.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | run_hook role-gate.sh)
assert_allowed "CPO が docs/specification.md を編集 → 許可" "$OUTPUT"

# 2. CPO が管轄内(docs/screen-flow.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/screen-flow.md"}}' | run_hook role-gate.sh)
assert_allowed "CPO が docs/screen-flow.md を編集 → 許可" "$OUTPUT"

# 4. CPO が管轄外(docs/SECURITY.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_blocked "CPO が docs/SECURITY.md を編集 → deny" "$OUTPUT"

# 5. CPO が管轄外(docs/POLICY.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/POLICY.md"}}' | run_hook role-gate.sh)
assert_blocked "CPO が docs/POLICY.md を編集 → deny" "$OUTPUT"

# --- CTO ロール ---
echo ""
echo "--- CTO ロール ---"

write_role_file "cto"

# 6. CTO が管轄内(docs/specification.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | run_hook role-gate.sh)
assert_allowed "CTO が docs/specification.md を編集 → 許可" "$OUTPUT"

# 6b. CTO が管轄内(docs/design-philosophy.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/design-philosophy.md"}}' | run_hook role-gate.sh)
assert_allowed "CTO が docs/design-philosophy.md を編集 → 許可" "$OUTPUT"

# 7. CTO が管轄外(docs/screen-flow.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/screen-flow.md"}}' | run_hook role-gate.sh)
assert_blocked "CTO が docs/screen-flow.md を編集 → deny" "$OUTPUT"

# --- legal ロール ---
echo ""
echo "--- legal ロール ---"

write_role_file "legal"

# 8. legal が管轄内(docs/POLICY.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/POLICY.md"}}' | run_hook role-gate.sh)
assert_allowed "legal が docs/POLICY.md を編集 → 許可" "$OUTPUT"

# 9. legal が管轄外(docs/specification.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | run_hook role-gate.sh)
assert_blocked "legal が docs/specification.md を編集 → deny" "$OUTPUT"

# --- accounting ロール ---
echo ""
echo "--- accounting ロール ---"

write_role_file "accounting"

# 10. accounting が管轄内(docs/cost-analysis.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/cost-analysis.md"}}' | run_hook role-gate.sh)
assert_allowed "accounting が docs/cost-analysis.md を編集 → 許可" "$OUTPUT"

# 11. accounting が管轄外(docs/SECURITY.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_blocked "accounting が docs/SECURITY.md を編集 → deny" "$OUTPUT"

# --- security ロール ---
echo ""
echo "--- security ロール ---"

write_role_file "security"

# 12. security が管轄内(docs/SECURITY.md)を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_allowed "security が docs/SECURITY.md を編集 → 許可" "$OUTPUT"

# 13. security が管轄外(docs/cost-analysis.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/cost-analysis.md"}}' | run_hook role-gate.sh)
assert_blocked "security が docs/cost-analysis.md を編集 → deny" "$OUTPUT"

# --- SM ロール（docs/ai-organization.md のみ編集可、他の docs/ は不可） ---
echo ""
echo "--- SM ロール ---"

write_role_file "sm"

# 14. SM が docs/ai-organization.md を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/ai-organization.md"}}' | run_hook role-gate.sh)
assert_allowed "SM が docs/ai-organization.md を編集 → 許可" "$OUTPUT"

# 14b. SM が管轄外(docs/specification.md)を編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | run_hook role-gate.sh)
assert_blocked "SM が docs/specification.md を編集 → deny" "$OUTPUT"

# --- knowledge/ 配下 ---
echo ""
echo "--- knowledge/ 配下 ---"

write_role_file "cpo"

# 15. knowledge/ 配下は全ロール編集可
OUTPUT=$(echo '{"tool_input":{"file_path":"knowledge/cpo/decisions.md"}}' | run_hook role-gate.sh)
assert_allowed "CPO が knowledge/ 配下を編集 → 許可" "$OUTPUT"

write_role_file "cto"

# 16. CTO が knowledge/ 配下を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"knowledge/cto/tech-principles.md"}}' | run_hook role-gate.sh)
assert_allowed "CTO が knowledge/ 配下を編集 → 許可" "$OUTPUT"

write_role_file "sm"

# 17. SM が knowledge/ 配下を編集 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"knowledge/sm/notes.md"}}' | run_hook role-gate.sh)
assert_allowed "SM が knowledge/ 配下を編集 → 許可" "$OUTPUT"

# --- docs/ 外のファイル ---
echo ""
echo "--- docs/ 外のファイル ---"

write_role_file "cpo"

# 18. docs/ 外(README.md)はチェック対象外 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"README.md"}}' | run_hook role-gate.sh)
assert_allowed "docs/ 外のファイル(README.md) → 許可" "$OUTPUT"

# 19. docs/ 外(install.sh)はチェック対象外 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"install.sh"}}' | run_hook role-gate.sh)
assert_allowed "docs/ 外のファイル(install.sh) → 許可" "$OUTPUT"

# --- ロールファイル未設定 ---
echo ""
echo "--- ロールファイル未設定 ---"

rm -f "${TMPDIR_ROOT}/.claude/state/agent-role"

# 20. ロールファイルなし → 許可（通常セッション）
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_allowed "ロールファイル未設定 → 許可" "$OUTPUT"

# --- ロールファイル空 ---
echo ""
echo "--- ロールファイル空 ---"

echo "" > "${TMPDIR_ROOT}/.claude/state/agent-role"

# 21. ロールファイルが空 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_allowed "ロールファイルが空 → 許可" "$OUTPUT"

# --- 未知のロール ---
echo ""
echo "--- 未知のロール ---"

write_role_file "unknown_role"

# 22. 未知のロール → docs/ 配下はブロック
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | run_hook role-gate.sh)
assert_blocked "未知のロール → docs/ 配下はブロック" "$OUTPUT"

# 23. 未知のロール → knowledge/ 配下は許可
OUTPUT=$(echo '{"tool_input":{"file_path":"knowledge/test.md"}}' | run_hook role-gate.sh)
assert_allowed "未知のロール → knowledge/ 配下は許可" "$OUTPUT"

# 24. 未知のロール → docs/ 外は許可
OUTPUT=$(echo '{"tool_input":{"file_path":"install.sh"}}' | run_hook role-gate.sh)
assert_allowed "未知のロール → docs/ 外は許可" "$OUTPUT"

# --- 深いパス ---
echo ""
echo "--- 深いパスでのマッチ ---"

write_role_file "security"

# 25. 絶対パスでの docs/ マッチ → 管轄内は許可
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/project/docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_allowed "絶対パスでの管轄内ファイル → 許可" "$OUTPUT"

# 26. 絶対パスでの docs/ マッチ → 管轄外はブロック
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/project/docs/specification.md"}}' | run_hook role-gate.sh)
assert_blocked "絶対パスでの管轄外ファイル → deny" "$OUTPUT"

# --- file_path が空 / キー欠落 ---
echo ""
echo "--- file_path 異常値 ---"

write_role_file "cpo"

# 27. file_path が空 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":""}}' | run_hook role-gate.sh)
assert_allowed "file_path が空 → 許可" "$OUTPUT"

# 28. file_path キー欠落 → 許可
OUTPUT=$(echo '{"tool_input":{"other_key":"value"}}' | run_hook role-gate.sh)
assert_allowed "file_path キー欠落 → 許可" "$OUTPUT"

# --- deny 出力の JSON 構造検証 ---
echo ""
echo "--- JSON 構造検証 ---"

write_role_file "cpo"

# 29. deny 出力の JSON 構造検証
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (hookEventName/permissionDecision/permissionDecisionReason が不足)"
fi

# 30. deny メッセージにロール名が含まれる
REASON=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
if echo "$REASON" | grep -q "cpo"; then
  pass "deny メッセージにロール名が含まれる"
else
  fail "deny メッセージにロール名が含まれる (実際: $REASON)"
fi

# --- ROLE_FILE のパス ---
echo ""
echo "--- ROLE_FILE のパス ---"

# 31. ROLE_FILE は $CLAUDE_PROJECT_DIR/.claude/state/agent-role に配置される
write_role_file "cpo"
if [ -f "${TMPDIR_ROOT}/.claude/state/agent-role" ]; then
  pass "ROLE_FILE が \$CLAUDE_PROJECT_DIR/.claude/state/agent-role に配置される"
else
  fail "ROLE_FILE が \$CLAUDE_PROJECT_DIR/.claude/state/agent-role に配置される (見つからない)"
fi

# 32. 別の CLAUDE_PROJECT_DIR では別の ROLE_FILE が参照される（worktree 分離の核心）
ALT_DIR=$(mktemp -d)
mkdir -p "${ALT_DIR}/.claude/state"
echo "cto" > "${ALT_DIR}/.claude/state/agent-role"
ORIG_DIR="$CLAUDE_PROJECT_DIR"
export CLAUDE_PROJECT_DIR="$ALT_DIR"
# CTO は docs/specification.md を編集できるが docs/screen-flow.md は不可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/screen-flow.md"}}' | run_hook role-gate.sh)
assert_blocked "別の CLAUDE_PROJECT_DIR の ROLE_FILE が参照される（worktree 分離）" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$ORIG_DIR"
rm -rf "$ALT_DIR"

# --- CLAUDE_PROJECT_DIR 未設定 ---
echo ""
echo "--- CLAUDE_PROJECT_DIR 未設定 ---"

# 33. CLAUDE_PROJECT_DIR 未設定時に異常終了しない
unset CLAUDE_PROJECT_DIR
EMPTY_DIR=$(mktemp -d)
set +e
OUTPUT=$(cd "$EMPTY_DIR" && echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh 2>/dev/null)
EXIT_CODE=$?
set -e
rm -rf "$EMPTY_DIR"
if [ "$EXIT_CODE" = "0" ]; then
  pass "CLAUDE_PROJECT_DIR 未設定時に異常終了しない"
else
  fail "CLAUDE_PROJECT_DIR 未設定時に異常終了しない (exit $EXIT_CODE)"
fi
assert_allowed "CLAUDE_PROJECT_DIR 未設定 → 許可（ロールファイルなし）" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
