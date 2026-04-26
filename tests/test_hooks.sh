#!/bin/bash
# test_hooks.sh — protect-files.sh / sync-gate.sh / block-api-bypass.sh のユニットテスト
# 使い方: bash tests/test_hooks.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"
LIB_DIR="$(cd "$(dirname "$0")/../templates/claude/lib" && pwd)"
TMPDIR_ROOT=""

# 共通ヘルパーを source（vibecorp_stamp_path を使うため）
# shellcheck source=../templates/claude/lib/common.sh
source "${LIB_DIR}/common.sh"

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
  mkdir -p "${TMPDIR_ROOT}/.claude/state"
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
  # ホスト ~/.cache を汚染しないよう XDG_CACHE_HOME を分離
  export XDG_CACHE_HOME="${TMPDIR_ROOT}/cache"
  # vibecorp_stamp_dir が toplevel を引けるよう git 初期化
  ( cd "$TMPDIR_ROOT" && git init -q . && git config user.email t@example.com && git config user.name t )
  # 各 stamp の現在パスを計算してエクスポート（テスト内で参照）
  STAMP_SYNC="$(vibecorp_stamp_path sync)"
  mkdir -p "$(dirname "$STAMP_SYNC")"
}

write_vibecorp_yml() {
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: minimal
language: ja
base_branch: main
protected_files:
  - MVV.md
YAML
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
}
trap cleanup EXIT

# ============================================
echo "=== protect-files.sh ==="
# ============================================

setup_project_dir
write_vibecorp_yml

# テンプレートのフックは実行権限がないので bash 経由で呼び出す
run_hook() {
  bash "$HOOKS_DIR/$1"
}

# 1. 保護ファイル(MVV.md)への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_blocked "保護ファイル(MVV.md)への編集 → deny" "$OUTPUT"

# 2. 深いパスでの末尾一致 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/some/deep/path/MVV.md"}}' | run_hook protect-files.sh)
assert_blocked "深いパスでの末尾一致 → deny" "$OUTPUT"

# 3. 保護対象外(README.md) → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"README.md"}}' | run_hook protect-files.sh)
assert_allowed "保護対象外(README.md) → 許可" "$OUTPUT"

# 4. 部分不一致(MVV.md.bak) → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md.bak"}}' | run_hook protect-files.sh)
assert_allowed "部分不一致(MVV.md.bak) → 許可" "$OUTPUT"

# 5. file_path が空 → 許可
OUTPUT=$(echo '{"tool_input":{"file_path":""}}' | run_hook protect-files.sh)
assert_allowed "file_path が空 → 許可" "$OUTPUT"

# 6. file_path キー欠落 → 許可
OUTPUT=$(echo '{"tool_input":{"other_key":"value"}}' | run_hook protect-files.sh)
assert_allowed "file_path キー欠落 → 許可" "$OUTPUT"

# 7. vibecorp.yml がない場合 → 許可
SAVED_YML="${TMPDIR_ROOT}/.claude/vibecorp.yml"
mv "$SAVED_YML" "${SAVED_YML}.bak"
OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_allowed "vibecorp.yml がない場合 → 許可" "$OUTPUT"
mv "${SAVED_YML}.bak" "$SAVED_YML"

# 8-9. 複数保護ファイル
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
protected_files:
  - MVV.md
  - POLICY.md
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_blocked "複数保護ファイル — MVV.md ブロック" "$OUTPUT"

OUTPUT=$(echo '{"tool_input":{"file_path":"POLICY.md"}}' | run_hook protect-files.sh)
assert_blocked "複数保護ファイル — POLICY.md ブロック" "$OUTPUT"

OUTPUT=$(echo '{"tool_input":{"file_path":"README.md"}}' | run_hook protect-files.sh)
assert_allowed "複数保護ファイル — 対象外は許可" "$OUTPUT"

# 10a. protected_files が null（値なし）
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
protected_files:
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_allowed "protected_files が null → 許可" "$OUTPUT"

# 10b. protected_files が空リスト
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
protected_files: []
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_allowed "protected_files が空リスト → 許可" "$OUTPUT"

# 11. protected_files キーがない
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: minimal
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
assert_allowed "protected_files キーがない → 許可" "$OUTPUT"

# 12. deny 出力の JSON 構造検証
write_vibecorp_yml
OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (hookEventName/permissionDecision/permissionDecisionReason が不足)"
fi

# 13. ファイル名にスペース含む → deny
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: test-project
protected_files:
  - my file.md
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"docs/my file.md"}}' | run_hook protect-files.sh)
assert_blocked "ファイル名にスペース含む → deny" "$OUTPUT"

# 14. CLAUDE_PROJECT_DIR 未設定（デフォルト "."）→ 許可（カレントに yml なし）
unset CLAUDE_PROJECT_DIR
# カレントディレクトリに .claude/vibecorp.yml がないことを保証するため一時ディレクトリで実行
EMPTY_DIR=$(mktemp -d)
set +e
OUTPUT=$(cd "$EMPTY_DIR" && echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh 2>/dev/null)
EXIT_CODE=$?
set -e
rm -rf "$EMPTY_DIR"
assert_exit_code "CLAUDE_PROJECT_DIR 未設定時に異常終了しない" "0" "$EXIT_CODE"
assert_allowed "CLAUDE_PROJECT_DIR 未設定 → 許可" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"

# ============================================
echo ""
echo "=== sync-gate.sh ==="
# ============================================

write_vibecorp_yml

# 1. スタンプなしで git push → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "スタンプなしで git push → deny" "$OUTPUT"

# 2. スタンプありで git push → 許可
touch "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "スタンプありで git push → 許可" "$OUTPUT"

# 3. 許可後にスタンプ削除確認
assert_file_not_exists "許可後にスタンプ削除確認" "${STAMP_SYNC}"

# 4. git push（引数なし） → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push"}}' | run_hook sync-gate.sh)
assert_blocked "git push（引数なし） → deny" "$OUTPUT"

# 5. git push --delete → スタンプなしでも許可
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push --delete origin feature-branch"}}' | run_hook sync-gate.sh)
assert_allowed "git push --delete → スタンプなしでも許可" "$OUTPUT"

# 6. git push -d → スタンプなしでも許可
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push -d origin feature-branch"}}' | run_hook sync-gate.sh)
assert_allowed "git push -d → スタンプなしでも許可" "$OUTPUT"

# 7. 先頭スペース付き push → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"  git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "先頭スペース付き push → deny" "$OUTPUT"

# 8. 環境変数プレフィックス付き → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"GIT_SSH_COMMAND=ssh git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 9. 複数環境変数プレフィックス → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"FOO=bar BAZ=qux git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "複数環境変数プレフィックス → deny" "$OUTPUT"

# 10. env ラッパー付き → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"env git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 11. command ラッパー付き → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"command git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "command ラッパー付き → deny" "$OUTPUT"

# 12. 絶対パス(/usr/bin/git) → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"/usr/bin/git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "絶対パス(/usr/bin/git) → deny" "$OUTPUT"

# 13. 相対パス(./bin/git) → deny
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"./bin/git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "相対パス(./bin/git) → deny" "$OUTPUT"

# 14. 対象外コマンド(gh pr merge) → 許可
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80 --squash"}}' | run_hook sync-gate.sh)
assert_allowed "対象外コマンド(gh pr merge) → 許可" "$OUTPUT"

# 15. 対象外コマンド(git commit) → 許可
OUTPUT=$(echo '{"tool_input":{"command":"git commit -m \"test\""}}' | run_hook sync-gate.sh)
assert_allowed "対象外コマンド(git commit) → 許可" "$OUTPUT"

# 16. 対象外コマンド(git pull) → 許可
OUTPUT=$(echo '{"tool_input":{"command":"git pull origin main"}}' | run_hook sync-gate.sh)
assert_allowed "対象外コマンド(git pull) → 許可" "$OUTPUT"

# 17. STAMP_FILE は $XDG_CACHE_HOME/vibecorp/state/<repo-id>/sync-ok に配置される
write_vibecorp_yml
touch "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "STAMP_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/sync-ok に配置される" "$OUTPUT"

# 18. 別の CLAUDE_PROJECT_DIR の state は影響しない（worktree 分離）
ALT_DIR=$(mktemp -d)
( cd "$ALT_DIR" && git init -q . && git config user.email t@example.com && git config user.name t )
ORIG_DIR="$CLAUDE_PROJECT_DIR"
rm -f "${STAMP_SYNC}"
export CLAUDE_PROJECT_DIR="$ALT_DIR"
ALT_STAMP="$(vibecorp_stamp_path sync)"
mkdir -p "$(dirname "$ALT_STAMP")"
touch "$ALT_STAMP"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "別の CLAUDE_PROJECT_DIR の state を参照する（worktree 分離）" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$ORIG_DIR"
rm -rf "$ALT_DIR"

# 20. deny 出力の JSON 構造検証
write_vibecorp_yml
rm -f "${STAMP_SYNC}"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (構造が不正)"
fi

# ============================================
echo ""
echo "=== block-api-bypass.sh ==="
# ============================================

# 1. gh api による直接マージ → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/pulls/123/merge -X PUT -f merge_method=squash"}}' | run_hook block-api-bypass.sh)
assert_blocked "gh api による直接マージ → deny" "$OUTPUT"

# 2. 通常の gh pr merge → 許可
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 123 --squash --delete-branch"}}' | run_hook block-api-bypass.sh)
assert_allowed "通常の gh pr merge → 許可" "$OUTPUT"

# 3. 通常の gh api（マージ以外） → 許可
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/pulls/123/reviews --paginate"}}' | run_hook block-api-bypass.sh)
assert_allowed "gh api（マージ以外） → 許可" "$OUTPUT"

# 4. 環境変数プレフィックス付き直接マージ → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=abc gh api repos/owner/repo/pulls/99/merge -X PUT"}}' | run_hook block-api-bypass.sh)
assert_blocked "環境変数プレフィックス付き直接マージ → deny" "$OUTPUT"

# 5. Bash 以外のツール → 許可（スキップ）
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"command":"gh api repos/owner/repo/pulls/123/merge"}}' | run_hook block-api-bypass.sh)
assert_allowed "Bash 以外のツール → 許可" "$OUTPUT"

# 6. command が空 → 許可
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":""}}' | run_hook block-api-bypass.sh)
assert_allowed "command が空 → 許可" "$OUTPUT"

# 7. deny 出力の JSON 構造検証
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/pulls/1/merge -X PUT"}}' | run_hook block-api-bypass.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "deny 出力の JSON 構造検証"
else
  fail "deny 出力の JSON 構造検証 (構造が不正)"
fi

# 8. @coderabbitai approve の投稿 → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/issues/123/comments -X POST -f body=\"@coderabbitai approve\""}}' | run_hook block-api-bypass.sh)
assert_blocked "@coderabbitai approve の投稿 → deny" "$OUTPUT"

# 9. @coderabbitai approve（大文字混在） → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/issues/45/comments -X POST -f body=\"@CodeRabbitAI approve\""}}' | run_hook block-api-bypass.sh)
assert_blocked "@coderabbitai approve（大文字混在） → deny" "$OUTPUT"

# 10. 環境変数プレフィックス付き approve → deny
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=abc gh api repos/owner/repo/issues/10/comments -X POST -f body=\"@coderabbitai approve\""}}' | run_hook block-api-bypass.sh)
assert_blocked "環境変数プレフィックス付き approve → deny" "$OUTPUT"

# 11. approve 以外の @coderabbitai コマンド → 許可
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/issues/123/comments -X POST -f body=\"@coderabbitai review\""}}' | run_hook block-api-bypass.sh)
assert_allowed "@coderabbitai review（approve以外） → 許可" "$OUTPUT"

# 12. approve ブロックの JSON 構造検証
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/issues/1/comments -X POST -f body=\"@coderabbitai approve\""}}' | run_hook block-api-bypass.sh)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "approve ブロックの JSON 構造検証"
else
  fail "approve ブロックの JSON 構造検証 (構造が不正)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
