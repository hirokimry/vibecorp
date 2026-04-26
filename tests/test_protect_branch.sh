#!/bin/bash
# test_protect_branch.sh — protect-branch.sh のユニットテスト
# 使い方: bash tests/test_protect_branch.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"
TMPDIR_ROOT=""

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
    rm -rf "$TMPDIR_ROOT" "${TMPDIR_ROOT}.wt" || true
  fi
}
trap cleanup EXIT

run_hook() {
  # フック内の git -C "$CHECK_DIR" が worktree を見られるように、
  # GIT_DIR を渡さず TMPDIR_ROOT に cd して起動する。
  ( cd "$TMPDIR_ROOT" && bash "$HOOKS_DIR/protect-branch.sh" )
}

write_vibecorp_yml_with_base() {
  local base="$1"
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<YAML
name: test-project
base_branch: ${base}
YAML
}

setup_worktree() {
  local worktree_path="$1"
  local branch="$2"
  if ! git -C "$TMPDIR_ROOT" worktree add -B "$branch" "$worktree_path" >/dev/null 2>&1; then
    echo "  ERROR: worktree セットアップ失敗 (branch=$branch, path=$worktree_path)" >&2
    # 中途半端な worktree を残さないよう片付けてから終了
    git -C "$TMPDIR_ROOT" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
    exit 1
  fi
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
git init "$EMPTY_DIR" >/dev/null 2>&1
git -C "$EMPTY_DIR" config user.name "Test" >/dev/null 2>&1
git -C "$EMPTY_DIR" config user.email "test@example.com" >/dev/null 2>&1
git -C "$EMPTY_DIR" commit --allow-empty -m "init" >/dev/null 2>&1
set +e
OUTPUT=$(cd "$EMPTY_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | bash "$HOOKS_DIR/protect-branch.sh" 2>/dev/null)
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
# worktree シナリオ（WT-1〜WT-11） + diff チェック（DIFF-1）
# ============================================

WORKTREE_DEV="${TMPDIR_ROOT}.wt/dev_test"
WORKTREE_BASE="${TMPDIR_ROOT}.wt/base_test"

# 全 worktree テストの開始時に main repo を main ブランチ・base_branch=main にリセット
write_vibecorp_yml
switch_to_branch main

# WT-1: worktree が dev ブランチ → 内部ファイル Edit → allow
setup_worktree "$WORKTREE_DEV" "dev/test_branch"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_DEV/src/app.ts\"}}" | run_hook)
assert_allowed "WT-1: worktree dev ブランチ内 Edit → allow（main repo は main）" "$OUTPUT"

# WT-2: worktree が base_branch（develop）→ 内部ファイル Edit → deny
write_vibecorp_yml_with_base develop
switch_to_branch dev/main_test  # main repo は dev/main_test（base_branch でない）
setup_worktree "$WORKTREE_BASE" "develop"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_BASE/src/app.ts\"}}" | run_hook)
assert_blocked "WT-2: worktree が base_branch(develop) → 内部 Edit → deny" "$OUTPUT"
write_vibecorp_yml  # base_branch を main に戻す
switch_to_branch main

# WT-3: 存在しないファイル新規作成（親ディレクトリ遡及）→ worktree なら allow
# 注意: WORKTREE_DEV は WT-1 で setup_worktree 済み（dev/test_branch）。
# new/dir/ サブディレクトリは存在しないため遡及で WORKTREE_DEV まで戻る → allow
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_DEV/new/dir/file.ts\"}}" | run_hook)
assert_allowed "WT-3: worktree 内の新規パス Edit（遡及）→ allow" "$OUTPUT"

# WT-4: repo 外絶対パス → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/etc/passwd"}}' | run_hook)
assert_blocked "WT-4: repo 外絶対パス Edit → 安全側 deny" "$OUTPUT"

# WT-5: ~ 始まりパス → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"~/foo/bar.ts"}}' | run_hook)
assert_blocked "WT-5: ~ 始まり file_path → 安全側 deny" "$OUTPUT"

# WT-6: 深いパストラバーサル → 安全側 deny
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR_ROOT/../../../etc/passwd\"}}" | run_hook)
assert_blocked "WT-6: パストラバーサル Edit → 安全側 deny" "$OUTPUT"

# WT-7: 空文字 file_path → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":""}}' | run_hook)
assert_blocked "WT-7: 空文字 file_path → 安全側 deny" "$OUTPUT"

# WT-8: file_path キー欠落 → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{}}' | run_hook)
assert_blocked "WT-8: file_path キー欠落 → 安全側 deny" "$OUTPUT"

# WT-9: deny 出力に tool=Edit / check_dir が含まれる
# main repo が main ブランチ（base_branch=main と一致）なので Edit は deny される
switch_to_branch main
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
if echo "$OUTPUT" | grep -q 'tool=Edit' && echo "$OUTPUT" | grep -q 'check_dir='; then
  pass "WT-9: deny メッセージに tool=Edit / check_dir= が含まれる"
else
  fail "WT-9: deny メッセージに tool / check_dir が含まれない"
fi

# WT-10: Bash 経由 git commit の deny メッセージに tool=Bash が含まれる
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | run_hook)
if echo "$OUTPUT" | grep -q 'tool=Bash'; then
  pass "WT-10: Bash deny メッセージに tool=Bash が含まれる"
else
  fail "WT-10: Bash deny メッセージに tool=Bash が含まれない"
fi

# WT-11: ALLOWED_ROOT が "/" になるエッジケース → 安全側 deny
# CLAUDE_PROJECT_DIR=/ にすると ALLOWED_ROOT=resolve_realpath(/..)=/ になり、
# protect-branch.sh は ALLOWED_ROOT="/" を検出して file_path 解析をスキップ → CHECK_DIR="."
# になる。cwd は main repo（main ブランチ）なので deny される。
# テスト後に SAVED_CLAUDE_DIR で元の値に必ず戻す（後続 WT/DIFF テストへの影響を防ぐ）。
SAVED_CLAUDE_DIR="$CLAUDE_PROJECT_DIR"
export CLAUDE_PROJECT_DIR="/"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR_ROOT/src/app.ts\"}}" | run_hook)
assert_blocked "WT-11: ALLOWED_ROOT=/ のエッジケース → 安全側 deny" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$SAVED_CLAUDE_DIR"

# DIFF-1: .claude/hooks/ と templates/claude/hooks/ が同期されていること
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if diff -q "$REPO_ROOT/.claude/hooks/protect-branch.sh" "$REPO_ROOT/templates/claude/hooks/protect-branch.sh" >/dev/null 2>&1; then
  pass "DIFF-1: .claude/hooks/ と templates/claude/hooks/ の protect-branch.sh が同期"
else
  fail "DIFF-1: .claude/hooks/ と templates/claude/hooks/ の protect-branch.sh が差分あり"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
