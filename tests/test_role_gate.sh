#!/bin/bash
# test_role_gate.sh — role-gate.sh のユニットテスト
# 使い方: bash tests/test_role_gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/templates/claude/hooks"
LIB_DIR="${SCRIPT_DIR}/templates/claude/lib"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""
ROLE_FILE=""

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
  mkdir -p "${TMPDIR_ROOT}/.claude/hooks"
  mkdir -p "${TMPDIR_ROOT}/.claude/lib"
  # hook が source する common.sh を配置
  cp "${LIB_DIR}/common.sh" "${TMPDIR_ROOT}/.claude/lib/common.sh"
  # repo-id 計算に git が必要
  ( cd "$TMPDIR_ROOT" && git init -q . && git config user.email t@example.com && git config user.name t )
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
  # XDG サンドボックス化：実ホームを汚さない
  export HOME="${TMPDIR_ROOT}/fakehome"
  export XDG_CACHE_HOME="${TMPDIR_ROOT}/xdg-cache"
  mkdir -p "$HOME" "$XDG_CACHE_HOME"
  # ロールファイルパスを計算
  ROLE_FILE=$( source "${TMPDIR_ROOT}/.claude/lib/common.sh" && vibecorp_state_path agent-role )
  # state ディレクトリを作成
  mkdir -p "$(dirname "$ROLE_FILE")"
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
  echo "$role" > "$ROLE_FILE"
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
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

rm -f "$ROLE_FILE"

# 20. ロールファイルなし → 許可（通常セッション）
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/SECURITY.md"}}' | run_hook role-gate.sh)
assert_allowed "ロールファイル未設定 → 許可" "$OUTPUT"

# --- ロールファイル空 ---
echo ""
echo "--- ロールファイル空 ---"

echo "" > "$ROLE_FILE"

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

# --- ROLE_FILE のパス（新パス: ~/.cache/vibecorp/state/<repo-id>/agent-role） ---
echo ""
echo "--- ROLE_FILE のパス ---"

# 31. ROLE_FILE は XDG cache 配下に配置される
write_role_file "cpo"
if [ -f "$ROLE_FILE" ] \
  && [[ "$ROLE_FILE" == "${XDG_CACHE_HOME}/vibecorp/state/"*/agent-role ]]; then
  pass "ROLE_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/agent-role に配置される"
else
  fail "ROLE_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/agent-role に配置される (actual: $ROLE_FILE)"
fi

# 31b. 旧パス .claude/state/agent-role には書き込まれない（退行検知）
if [ ! -e "${TMPDIR_ROOT}/.claude/state/agent-role" ]; then
  pass "旧パス .claude/state/agent-role に書き込まれない"
else
  fail "旧パス .claude/state/agent-role に書き込まれている（退行）"
fi

# 32. 別の CLAUDE_PROJECT_DIR では別の ROLE_FILE が参照される（worktree 分離の核心）
ALT_DIR=$(mktemp -d)
mkdir -p "${ALT_DIR}/.claude/lib"
cp "${LIB_DIR}/common.sh" "${ALT_DIR}/.claude/lib/common.sh"
( cd "$ALT_DIR" && git init -q . && git config user.email t@example.com && git config user.name t )
ORIG_DIR="$CLAUDE_PROJECT_DIR"
export CLAUDE_PROJECT_DIR="$ALT_DIR"
# ALT_DIR 用の ROLE_FILE パスを計算して CTO ロールを書き込む
ALT_ROLE_FILE=$( source "${ALT_DIR}/.claude/lib/common.sh" && vibecorp_state_path agent-role )
mkdir -p "$(dirname "$ALT_ROLE_FILE")"
echo "cto" > "$ALT_ROLE_FILE"
# CTO は docs/specification.md を編集できるが docs/screen-flow.md は不可
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/screen-flow.md"}}' | run_hook role-gate.sh)
assert_blocked "別の CLAUDE_PROJECT_DIR の ROLE_FILE が参照される（worktree 分離）" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$ORIG_DIR"
rm -rf "$ALT_DIR"

# --- CLAUDE_PROJECT_DIR 未設定 ---
echo ""
echo "--- CLAUDE_PROJECT_DIR 未設定 ---"

# 33. CLAUDE_PROJECT_DIR 未設定時に異常終了しない（common.sh も見つからないのでスキップせず pass 扱い）
# common.sh が CLAUDE_PROJECT_DIR 未設定で存在しないパスを source してエラーになるため、
# テストは fallback として CWD に common.sh が存在する状況を再現する。
EMPTY_DIR=$(mktemp -d)
mkdir -p "${EMPTY_DIR}/.claude/lib"
cp "${LIB_DIR}/common.sh" "${EMPTY_DIR}/.claude/lib/common.sh"
( cd "$EMPTY_DIR" && git init -q . && git config user.email t@example.com && git config user.name t )
unset CLAUDE_PROJECT_DIR
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
