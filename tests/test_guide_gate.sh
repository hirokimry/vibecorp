#!/bin/bash
# guide-gate.sh のユニットテスト
# 使い方: bash tests/test_guide_gate.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/templates/claude/hooks/guide-gate.sh"

if [[ -f "$HOOK" ]]; then
  pass "guide-gate.sh が存在する"
else
  fail "guide-gate.sh が存在しない"
  exit 1
fi

assert_blocked() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    pass "$desc"
  else
    fail "$desc (expected: deny, got: allow)"
  fi
}

assert_allowed() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    fail "$desc (expected: allow, got: deny)"
  else
    pass "$desc"
  fi
}

# --- テスト用の vibecorp.yml + git リポジトリを準備 ---

TMPDIR_TEST=$(mktemp -d)
mkdir -p "${TMPDIR_TEST}/.claude"
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
YAML
# git リポジトリ初期化（vibecorp_stamp_dir が toplevel を引けるように）
( cd "$TMPDIR_TEST" && git init -q . && git config user.email t@example.com && git config user.name t )

# CLAUDE_PROJECT_DIR と XDG_CACHE_HOME を分離して
# ホスト側の ~/.cache を汚染せずスタンプを TMPDIR 配下に隔離
export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
export XDG_CACHE_HOME="${TMPDIR_TEST}/cache"

# 共通ヘルパーからスタンプパスを動的に取得
# shellcheck source=../templates/claude/lib/common.sh
source "${SCRIPT_DIR}/templates/claude/lib/common.sh"
STAMP_FILE="$(vibecorp_stamp_path guide)"
mkdir -p "$(dirname "$STAMP_FILE")"

# --- クリーンアップ ---

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT
# スタンプを削除（TMPDIR_TEST はフック実行に必要なので残す）
rm -f "$STAMP_FILE"

# ============================================
echo "=== guide-gate.sh ==="
# ============================================

# --- デフォルトスコープ内のテスト ---

# 1. スタンプなしで .claude/hooks/ 配下を Edit → deny
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/hooks/my-hook.sh"}}' | "$HOOK")
assert_blocked "スタンプなしで .claude/hooks/ 配下を Edit → deny" "$OUTPUT"

# 2. スタンプありで .claude/hooks/ 配下を Edit → allow
touch "$STAMP_FILE"
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/hooks/my-hook.sh"}}' | "$HOOK")
assert_allowed "スタンプありで .claude/hooks/ 配下を Edit → allow" "$OUTPUT"

# 3. スタンプが消費される
if [ ! -f "$STAMP_FILE" ]; then
  pass "スタンプが消費される"
else
  fail "スタンプが消費される (ファイルが残っている)"
fi

# 4. .claude/skills/ 配下 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/skills/ship/SKILL.md"}}' | "$HOOK")
assert_blocked ".claude/skills/ 配下 → deny" "$OUTPUT"

# 5. .claude/agents/ 配下 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/agents/cto.md"}}' | "$HOOK")
assert_blocked ".claude/agents/ 配下 → deny" "$OUTPUT"

# 6. .claude/rules/ 配下 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/rules/testing.md"}}' | "$HOOK")
assert_blocked ".claude/rules/ 配下 → deny" "$OUTPUT"

# 7. .claude/settings.json → deny
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/settings.json"}}' | "$HOOK")
assert_blocked ".claude/settings.json → deny" "$OUTPUT"

# 8. *.mcp.json → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"project.mcp.json"}}' | "$HOOK")
assert_blocked "*.mcp.json → deny" "$OUTPUT"

# --- スコープ外のテスト ---

# 9. src/ 配下 → allow（スコープ外）
OUTPUT=$(echo '{"tool_input":{"file_path":"src/main.ts"}}' | "$HOOK")
assert_allowed "src/ 配下 → allow（スコープ外）" "$OUTPUT"

# 10. docs/ 配下 → allow（スコープ外）
OUTPUT=$(echo '{"tool_input":{"file_path":"docs/specification.md"}}' | "$HOOK")
assert_allowed "docs/ 配下 → allow（スコープ外）" "$OUTPUT"

# 11. README.md → allow（スコープ外）
OUTPUT=$(echo '{"tool_input":{"file_path":"README.md"}}' | "$HOOK")
assert_allowed "README.md → allow（スコープ外）" "$OUTPUT"

# 12. .claude/knowledge/ 配下 → allow（スコープ外 — knowledge は監視対象外）
OUTPUT=$(echo '{"tool_input":{"file_path":".claude/knowledge/cpo/decisions.md"}}' | "$HOOK")
assert_allowed ".claude/knowledge/ 配下 → allow（スコープ外）" "$OUTPUT"

# --- 絶対パスでのテスト ---

# 13. 絶対パスで .claude/hooks/ 配下 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/project/.claude/hooks/test.sh"}}' | "$HOOK")
assert_blocked "絶対パスで .claude/hooks/ 配下 → deny" "$OUTPUT"

# 14. 絶対パスで .claude/settings.json → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/Users/me/repo/.claude/settings.json"}}' | "$HOOK")
assert_blocked "絶対パスで .claude/settings.json → deny" "$OUTPUT"

# --- extra_paths テスト ---

# 15. guide_gate.extra_paths に templates/claude/ を設定
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
guide_gate:
  extra_paths:
    - templates/claude/
    - install.sh
YAML

# 16. extra_paths に含まれるパス → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"templates/claude/hooks/sync-gate.sh"}}' | "$HOOK")
assert_blocked "extra_paths の templates/claude/ 配下 → deny" "$OUTPUT"

# 17. extra_paths に含まれるファイル → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"install.sh"}}' | "$HOOK")
assert_blocked "extra_paths の install.sh → deny" "$OUTPUT"

# 18. 絶対パスで extra_paths 配下 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/project/templates/claude/settings.json"}}' | "$HOOK")
assert_blocked "絶対パスで extra_paths 配下 → deny" "$OUTPUT"

# --- YAML 未設定時のテスト ---

# 19. guide_gate セクションなし → デフォルトスコープのみ
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
YAML

OUTPUT=$(echo '{"tool_input":{"file_path":"templates/claude/hooks/sync-gate.sh"}}' | "$HOOK")
assert_allowed "YAML 未設定時、templates/ はスコープ外 → allow" "$OUTPUT"

OUTPUT=$(echo '{"tool_input":{"file_path":".claude/hooks/test.sh"}}' | "$HOOK")
assert_blocked "YAML 未設定時、デフォルトスコープは有効 → deny" "$OUTPUT"

# --- vibecorp.yml 不在テスト ---

# 20. vibecorp.yml が存在しない場合 → デフォルトスコープのみ
rm -f "${TMPDIR_TEST}/.claude/vibecorp.yml"

OUTPUT=$(echo '{"tool_input":{"file_path":".claude/hooks/test.sh"}}' | "$HOOK")
assert_blocked "vibecorp.yml 不在でもデフォルトスコープは有効 → deny" "$OUTPUT"

OUTPUT=$(echo '{"tool_input":{"file_path":"templates/claude/test.sh"}}' | "$HOOK")
assert_allowed "vibecorp.yml 不在で extra_paths なし → allow" "$OUTPUT"

# --- file_path 空のテスト ---

# 21. file_path が空 → allow
OUTPUT=$(echo '{"tool_input":{"command":"echo hello"}}' | "$HOOK")
assert_allowed "file_path が空 → allow" "$OUTPUT"

# --- スタンプパスの確認 ---

# 22. STAMP_FILE が XDG_CACHE_HOME/vibecorp/state/<repo-id>/guide-ok に配置される
# vibecorp.yml を復元（スタンプパス解決に必要）
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
YAML

touch "$STAMP_FILE"
if [ -f "$STAMP_FILE" ]; then
  OUTPUT=$(echo '{"tool_input":{"file_path":".claude/hooks/test.sh"}}' | "$HOOK")
  assert_allowed "STAMP_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/guide-ok に配置される" "$OUTPUT"
else
  fail "STAMP_FILE が新パスに配置される (スタンプが見つからない: ${STAMP_FILE})"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
