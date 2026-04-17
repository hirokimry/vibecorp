#!/bin/bash
# review-to-rules-gate.sh のユニットテスト
# 使い方: bash tests/test_review_to_rules_gate.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/templates/claude/hooks/review-to-rules-gate.sh"
PASSED=0
FAILED=0
TOTAL=0

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
( cd "$TMPDIR_TEST" && git init -q . && git config user.email t@example.com && git config user.name t )

# CLAUDE_PROJECT_DIR と XDG_CACHE_HOME を分離して
# ホスト側の ~/.cache を汚染せずスタンプを TMPDIR 配下に隔離
export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
export XDG_CACHE_HOME="${TMPDIR_TEST}/cache"

# 共通ヘルパーから新スタンプパスを動的に取得
# shellcheck source=../templates/claude/lib/common.sh
source "${SCRIPT_DIR}/templates/claude/lib/common.sh"
STAMP_FILE="$(vibecorp_stamp_path review-to-rules)"
mkdir -p "$(dirname "$STAMP_FILE")"

# --- クリーンアップ ---

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT
# スタンプだけ削除（TMPDIR_TEST はフック実行に必要なので残す）
rm -f "$STAMP_FILE"

# ============================================
echo "=== review-to-rules-gate.sh ==="
# ============================================

# 1. スタンプなしで gh pr merge → deny
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge"}}' | "$HOOK")
assert_blocked "スタンプなしで gh pr merge → deny" "$OUTPUT"

# 2. スタンプありで gh pr merge → allow
touch "$STAMP_FILE"
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge"}}' | "$HOOK")
assert_allowed "スタンプありで gh pr merge → allow" "$OUTPUT"

# 3. merge 後にスタンプが削除される
if [ ! -f "$STAMP_FILE" ]; then
  pass "merge 後にスタンプが削除される"
else
  fail "merge 後にスタンプが削除される (ファイルが残っている)"
fi

# 4. gh pr merge 以外のコマンド (gh pr view) → allow
OUTPUT=$(echo '{"tool_input":{"command":"gh pr view"}}' | "$HOOK")
assert_allowed "gh pr view → allow" "$OUTPUT"

# 5. git status → allow
OUTPUT=$(echo '{"tool_input":{"command":"git status"}}' | "$HOOK")
assert_allowed "git status → allow" "$OUTPUT"

# 6. gh pr merge --squash → deny
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge --squash"}}' | "$HOOK")
assert_blocked "gh pr merge --squash → deny" "$OUTPUT"

# 7. 環境変数プレフィックス付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"GH_TOKEN=xxx gh pr merge"}}' | "$HOOK")
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 8. 絶対パス付き (/usr/local/bin/gh pr merge) → deny
OUTPUT=$(echo '{"tool_input":{"command":"/usr/local/bin/gh pr merge"}}' | "$HOOK")
assert_blocked "絶対パス付き → deny" "$OUTPUT"

# 9. env ラッパー付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"env gh pr merge"}}' | "$HOOK")
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 10. STAMP_FILE が新パス (XDG_CACHE_HOME/vibecorp/state/<repo-id>/review-to-rules-ok) に配置される
touch "$STAMP_FILE"
if [ -f "$STAMP_FILE" ]; then
  OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge"}}' | "$HOOK")
  assert_allowed "STAMP_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/review-to-rules-ok に配置される" "$OUTPUT"
else
  fail "STAMP_FILE が新パスに配置される (スタンプが見つからない: ${STAMP_FILE})"
fi

# 11. git push → allow（無関係なコマンド）
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | "$HOOK")
assert_allowed "git push → allow" "$OUTPUT"

# 12. command ラッパー付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"command gh pr merge"}}' | "$HOOK")
assert_blocked "command ラッパー付き → deny" "$OUTPUT"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
