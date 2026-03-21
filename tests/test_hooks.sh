#!/bin/bash
# test_hooks.sh — protect-files.sh / review-to-rules-gate.sh / sync-gate.sh のユニットテスト
# 使い方: bash tests/test_hooks.sh

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

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: $path)"
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在する: $path)"
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない)"
  fi
}

# --- セットアップ / クリーンアップ ---

setup_project_dir() {
  TMPDIR_ROOT=$(mktemp -d)
  mkdir -p "${TMPDIR_ROOT}/.claude"
  export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
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
  # テストで作成されうるスタンプファイルを削除
  rm -f /tmp/.test-project-review-to-rules-ok
  rm -f /tmp/.vibecorp-project-review-to-rules-ok
  rm -f /tmp/.my-project-review-to-rules-ok
  rm -f /tmp/.test-project-sync-ok
  rm -f /tmp/.vibecorp-project-sync-ok
  rm -f /tmp/.my-project-sync-ok
  # サニタイズロジックと同じ方法で生成した名前を削除
  local sanitized
  sanitized=$(printf '%s' "hello world!@#" | tr -cs 'A-Za-z0-9._-' '_')
  rm -f "/tmp/.${sanitized}-review-to-rules-ok"
  rm -f "/tmp/.${sanitized}-sync-ok"
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
# カレントディレクトリに .claude/vibecorp.yml がないことを前提
set +e
OUTPUT=$(echo '{"tool_input":{"file_path":"MVV.md"}}' | run_hook protect-files.sh 2>/dev/null)
EXIT_CODE=$?
set -e
assert_exit_code "CLAUDE_PROJECT_DIR 未設定時に異常終了しない" "0" "$EXIT_CODE"
assert_allowed "CLAUDE_PROJECT_DIR 未設定 → 許可" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"

# ============================================
echo ""
echo "=== review-to-rules-gate.sh ==="
# ============================================

write_vibecorp_yml

# 1. スタンプなしで gh pr merge → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80 --squash --delete-branch"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "スタンプなしで gh pr merge → deny" "$OUTPUT"

# 2. スタンプありで gh pr merge → 許可
touch /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80 --squash --delete-branch"}}' | run_hook review-to-rules-gate.sh)
assert_allowed "スタンプありで gh pr merge → 許可" "$OUTPUT"

# 3. 許可後にスタンプ削除確認
assert_file_not_exists "許可後にスタンプ削除確認" "/tmp/.test-project-review-to-rules-ok"

# 4. merge 以外(gh pr view) → 許可
OUTPUT=$(echo '{"tool_input":{"command":"gh pr view 80"}}' | run_hook review-to-rules-gate.sh)
assert_allowed "merge 以外(gh pr view) → 許可" "$OUTPUT"

# 5. 先頭スペース付き merge → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"  gh pr merge 80 --squash"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "先頭スペース付き merge → deny" "$OUTPUT"

# 6. 環境変数プレフィックス付き → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"GH_TOKEN=dummy gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 7. 複数環境変数プレフィックス → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"FOO=bar BAZ=qux gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "複数環境変数プレフィックス → deny" "$OUTPUT"

# 8. env ラッパー付き → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"env gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 9. command ラッパー付き → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"command gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "command ラッパー付き → deny" "$OUTPUT"

# 10. 絶対パス(/usr/bin/gh) → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"/usr/bin/gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "絶対パス(/usr/bin/gh) → deny" "$OUTPUT"

# 11. 相対パス(./bin/gh) → deny
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"./bin/gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_blocked "相対パス(./bin/gh) → deny" "$OUTPUT"

# 12. gh pr create (bodyにmerge含む) → 許可
OUTPUT=$(echo '{"tool_input":{"command":"gh pr create --title \"test\" --body \"gh pr merge pattern\""}}' | run_hook review-to-rules-gate.sh)
assert_allowed "gh pr create (bodyにmerge含む) → 許可" "$OUTPUT"

# 13. vibecorp.yml なし — デフォルト名
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml" "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak"
rm -f /tmp/.vibecorp-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
# デフォルト名 vibecorp-project のスタンプが使われるか確認
assert_blocked "vibecorp.yml なし — デフォルト名で deny" "$OUTPUT"
# スタンプファイル名を確認（デフォルト名でスタンプを作って許可されるか）
touch /tmp/.vibecorp-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_allowed "vibecorp.yml なし — デフォルト名スタンプで許可" "$OUTPUT"
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak" "${TMPDIR_ROOT}/.claude/vibecorp.yml"

# 14. vibecorp.yml からプロジェクト名取得
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: my-project
preset: minimal
YAML
rm -f /tmp/.my-project-review-to-rules-ok
touch /tmp/.my-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_allowed "vibecorp.yml からプロジェクト名取得 → スタンプ名一致" "$OUTPUT"

# 15. プロジェクト名のサニタイズ
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: hello world!@#
preset: minimal
YAML
rm -f /tmp/.hello__world___-review-to-rules-ok
# サニタイズ後: hello_world___ (tr -cs で不正文字が _ に)
# スタンプを作成して許可されるか確認
SANITIZED_NAME=$(printf '%s' "hello world!@#" | tr -cs 'A-Za-z0-9._-' '_')
touch "/tmp/.${SANITIZED_NAME}-review-to-rules-ok"
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
assert_allowed "プロジェクト名のサニタイズ → スタンプ名に不正文字なし" "$OUTPUT"
rm -f "/tmp/.${SANITIZED_NAME}-review-to-rules-ok"

# 16. deny 出力の JSON 構造検証
write_vibecorp_yml
rm -f /tmp/.test-project-review-to-rules-ok
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge 80"}}' | run_hook review-to-rules-gate.sh)
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
echo "=== sync-gate.sh ==="
# ============================================

write_vibecorp_yml

# 1. スタンプなしで git push → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "スタンプなしで git push → deny" "$OUTPUT"

# 2. スタンプありで git push → 許可
touch /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "スタンプありで git push → 許可" "$OUTPUT"

# 3. 許可後にスタンプ削除確認
assert_file_not_exists "許可後にスタンプ削除確認" "/tmp/.test-project-sync-ok"

# 4. git push（引数なし） → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push"}}' | run_hook sync-gate.sh)
assert_blocked "git push（引数なし） → deny" "$OUTPUT"

# 5. git push --delete → スタンプなしでも許可
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push --delete origin feature-branch"}}' | run_hook sync-gate.sh)
assert_allowed "git push --delete → スタンプなしでも許可" "$OUTPUT"

# 6. git push -d → スタンプなしでも許可
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push -d origin feature-branch"}}' | run_hook sync-gate.sh)
assert_allowed "git push -d → スタンプなしでも許可" "$OUTPUT"

# 7. 先頭スペース付き push → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"  git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "先頭スペース付き push → deny" "$OUTPUT"

# 8. 環境変数プレフィックス付き → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"GIT_SSH_COMMAND=ssh git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 9. 複数環境変数プレフィックス → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"FOO=bar BAZ=qux git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "複数環境変数プレフィックス → deny" "$OUTPUT"

# 10. env ラッパー付き → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"env git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 11. command ラッパー付き → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"command git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "command ラッパー付き → deny" "$OUTPUT"

# 12. 絶対パス(/usr/bin/git) → deny
rm -f /tmp/.test-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"/usr/bin/git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "絶対パス(/usr/bin/git) → deny" "$OUTPUT"

# 13. 相対パス(./bin/git) → deny
rm -f /tmp/.test-project-sync-ok
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

# 17. vibecorp.yml なし — デフォルト名
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml" "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak"
rm -f /tmp/.vibecorp-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_blocked "vibecorp.yml なし — デフォルト名で deny" "$OUTPUT"
touch /tmp/.vibecorp-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "vibecorp.yml なし — デフォルト名スタンプで許可" "$OUTPUT"
mv "${TMPDIR_ROOT}/.claude/vibecorp.yml.bak" "${TMPDIR_ROOT}/.claude/vibecorp.yml"

# 18. vibecorp.yml からプロジェクト名取得
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: my-project
preset: minimal
YAML
rm -f /tmp/.my-project-sync-ok
touch /tmp/.my-project-sync-ok
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "vibecorp.yml からプロジェクト名取得 → スタンプ名一致" "$OUTPUT"

# 19. プロジェクト名のサニタイズ
cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<'YAML'
name: hello world!@#
preset: minimal
YAML
SANITIZED_NAME=$(printf '%s' "hello world!@#" | tr -cs 'A-Za-z0-9._-' '_')
rm -f "/tmp/.${SANITIZED_NAME}-sync-ok"
touch "/tmp/.${SANITIZED_NAME}-sync-ok"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | run_hook sync-gate.sh)
assert_allowed "プロジェクト名のサニタイズ → スタンプ名に不正文字なし" "$OUTPUT"
rm -f "/tmp/.${SANITIZED_NAME}-sync-ok"

# 20. deny 出力の JSON 構造検証
write_vibecorp_yml
rm -f /tmp/.test-project-sync-ok
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

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
