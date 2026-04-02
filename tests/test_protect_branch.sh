#!/bin/bash
# test_protect_branch.sh — protect-branch.sh のユニットテスト
# 使い方: bash tests/test_protect_branch.sh

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

# --- セットアップ / クリーンアップ ---

setup_project_dir() {
  TMPDIR_ROOT=$(mktemp -d)
  mkdir -p "${TMPDIR_ROOT}/.claude"
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"

  # git リポジトリを初期化（git branch --show-current が動作するために必要）
  git init "$TMPDIR_ROOT" >/dev/null 2>&1
  git -C "$TMPDIR_ROOT" config user.name "Test" >/dev/null 2>&1
  git -C "$TMPDIR_ROOT" config user.email "test@example.com" >/dev/null 2>&1
  git -C "$TMPDIR_ROOT" commit --allow-empty -m "初期コミット" >/dev/null 2>&1
}

write_vibecorp_yml() {
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: minimal
language: ja
base_branch: main
YAML
}

switch_to_branch() {
  local branch="$1"
  git -C "$TMPDIR_ROOT" checkout -B "$branch" >/dev/null 2>&1
}

detach_head() {
  local commit_hash
  commit_hash=$(git -C "$TMPDIR_ROOT" rev-parse HEAD)
  git -C "$TMPDIR_ROOT" checkout "$commit_hash" >/dev/null 2>&1
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
}
trap cleanup EXIT

run_hook() {
  # フック内の git コマンドが TMPDIR_ROOT のリポジトリで動作するように
  # GIT_DIR を設定する
  GIT_DIR="${TMPDIR_ROOT}/.git" bash "$HOOKS_DIR/protect-branch.sh"
}

# ============================================
echo "=== protect-branch.sh ==="
# ============================================

setup_project_dir
write_vibecorp_yml
switch_to_branch main

# 1. main ブランチで Edit → deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_blocked "main ブランチで Edit → deny" "$OUTPUT"

# 2. main ブランチで Write → deny
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts","content":"hello"}}' | run_hook)
assert_blocked "main ブランチで Write → deny" "$OUTPUT"

# 3. main ブランチで git commit -m "msg" → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"テスト\""}}' | run_hook)
assert_blocked "main ブランチで git commit → deny" "$OUTPUT"

# 4. main ブランチで git commit --amend → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}' | run_hook)
assert_blocked "main ブランチで git commit --amend → deny" "$OUTPUT"

# 5. main ブランチで git add && git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git add . && git commit -m \"テスト\""}}' | run_hook)
assert_blocked "main ブランチで git add && git commit → deny" "$OUTPUT"

# 6. main ブランチで git add → allow
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git add ."}}' | run_hook)
assert_allowed "main ブランチで git add → allow" "$OUTPUT"

# 7. main ブランチで git push → allow（sync-gate の責務）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | run_hook)
assert_allowed "main ブランチで git push → allow" "$OUTPUT"

# 8. main ブランチで git checkout -b feature → allow
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/new"}}' | run_hook)
assert_allowed "main ブランチで git checkout -b → allow" "$OUTPUT"

# 9. フィーチャーブランチで Edit → allow
switch_to_branch "dev/123_feature"
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_allowed "フィーチャーブランチで Edit → allow" "$OUTPUT"

# 10. フィーチャーブランチで git commit → allow
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"テスト\""}}' | run_hook)
assert_allowed "フィーチャーブランチで git commit → allow" "$OUTPUT"

# 11. detached HEAD で Edit → allow
switch_to_branch main
detach_head
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_allowed "detached HEAD で Edit → allow" "$OUTPUT"

# main に戻す
switch_to_branch main

# 12. vibecorp.yml なし → main をデフォルトとして deny
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml" "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak"
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_blocked "vibecorp.yml なし → main をデフォルトとして deny" "$OUTPUT"
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak" "${TMPDIR_ROOT}/.claude/vibecorp.yml"

# 13. base_branch カスタム値（develop）→ develop で deny、main で allow
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
base_branch: develop
YAML

switch_to_branch develop
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_blocked "base_branch=develop で develop ブランチ → deny" "$OUTPUT"

switch_to_branch main
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_allowed "base_branch=develop で main ブランチ → allow" "$OUTPUT"

# 元に戻す
write_vibecorp_yml
switch_to_branch main

# 14. 環境変数プレフィックス付き git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"GIT_AUTHOR_NAME=test git commit -m \"テスト\""}}' | run_hook)
assert_blocked "環境変数プレフィックス付き git commit → deny" "$OUTPUT"

# 15. 絶対パス /usr/bin/git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/git commit -m \"テスト\""}}' | run_hook)
assert_blocked "絶対パス /usr/bin/git commit → deny" "$OUTPUT"

# 16. deny 出力の JSON 構造検証
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (hookEventName/permissionDecision/permissionDecisionReason が不足)"
fi

# 17. command が空 → allow
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":""}}' | run_hook)
assert_allowed "command が空 → allow" "$OUTPUT"

# 18. tool_name が空 → allow
OUTPUT=$(echo '{"tool_name":"","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
assert_allowed "tool_name が空 → allow" "$OUTPUT"

# 19. セミコロン区切り git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git add .; git commit -m \"テスト\""}}' | run_hook)
assert_blocked "セミコロン区切り git commit → deny" "$OUTPUT"

# 20. env ラッパー付き git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"env git commit -m \"テスト\""}}' | run_hook)
assert_blocked "env ラッパー付き git commit → deny" "$OUTPUT"

# 21. command ラッパー付き git commit → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"command git commit -m \"テスト\""}}' | run_hook)
assert_blocked "command ラッパー付き git commit → deny" "$OUTPUT"

# 22. CLAUDE_PROJECT_DIR 未設定 → デフォルト "." で動作
unset CLAUDE_PROJECT_DIR
EMPTY_DIR=$(mktemp -d)
set +e
OUTPUT=$(cd "$EMPTY_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | GIT_DIR="${TMPDIR_ROOT}/.git" bash "$HOOKS_DIR/protect-branch.sh" 2>/dev/null)
EXIT_CODE=$?
set -e
rm -rf "$EMPTY_DIR"
if [ "$EXIT_CODE" = "0" ]; then
  pass "CLAUDE_PROJECT_DIR 未設定時に異常終了しない"
else
  fail "CLAUDE_PROJECT_DIR 未設定時に異常終了しない (exit $EXIT_CODE)"
fi
export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
