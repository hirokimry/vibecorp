#!/bin/bash
# review-gate.sh のユニットテスト
# 使い方: bash tests/test_review_gate.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/templates/claude/hooks/review-gate.sh"
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

# --- テスト用の vibecorp.yml を準備 ---

TMPDIR_TEST=$(mktemp -d)
mkdir -p "${TMPDIR_TEST}/.claude"
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
YAML

# CLAUDE_PROJECT_DIR を設定してスタンプ名の動的生成をテスト
export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
STAMP_FILE="/tmp/.test-project-review-ok"

# --- クリーンアップ ---

cleanup() {
  rm -f "$STAMP_FILE"
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT
# スタンプだけ削除（TMPDIR_TEST はフック実行に必要なので残す）
rm -f "$STAMP_FILE"

# ============================================
echo "=== review-gate.sh ==="
# ============================================

# 1. スタンプなしで gh pr create → deny
OUTPUT=$(echo '{"tool_input":{"command":"gh pr create --title test --body test"}}' | "$HOOK")
assert_blocked "スタンプなしで gh pr create → deny" "$OUTPUT"

# 2. スタンプありで gh pr create → allow
touch "$STAMP_FILE"
OUTPUT=$(echo '{"tool_input":{"command":"gh pr create --title test --body test"}}' | "$HOOK")
assert_allowed "スタンプありで gh pr create → allow" "$OUTPUT"

# 3. allow 後にスタンプ削除される
if [ ! -f "$STAMP_FILE" ]; then
  pass "allow 後にスタンプが削除される"
else
  fail "allow 後にスタンプが削除される (ファイルが残っている)"
fi

# 4. gh pr create 以外のコマンド (git status) → allow
OUTPUT=$(echo '{"tool_input":{"command":"git status"}}' | "$HOOK")
assert_allowed "git status → allow" "$OUTPUT"

# 5. gh pr view → allow（review-gate は create のみ）
OUTPUT=$(echo '{"tool_input":{"command":"gh pr view 123"}}' | "$HOOK")
assert_allowed "gh pr view → allow" "$OUTPUT"

# 6. gh pr merge → allow（review-gate は create のみ）
OUTPUT=$(echo '{"tool_input":{"command":"gh pr merge --squash --auto"}}' | "$HOOK")
assert_allowed "gh pr merge → allow" "$OUTPUT"

# 7. 環境変数プレフィックス付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"GH_TOKEN=xxx gh pr create --title test"}}' | "$HOOK")
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 8. 絶対パス付き (/usr/bin/gh pr create) → deny
OUTPUT=$(echo '{"tool_input":{"command":"/usr/bin/gh pr create --title test"}}' | "$HOOK")
assert_blocked "絶対パス付き (/usr/bin/gh pr create) → deny" "$OUTPUT"

# 9. env ラッパー付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"env gh pr create --title test"}}' | "$HOOK")
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 10. gh pr list → allow
OUTPUT=$(echo '{"tool_input":{"command":"gh pr list"}}' | "$HOOK")
assert_allowed "gh pr list → allow" "$OUTPUT"

# 11. スタンプ名が vibecorp.yml の name から動的生成される
touch "$STAMP_FILE"
if [ -f "$STAMP_FILE" ]; then
  OUTPUT=$(echo '{"tool_input":{"command":"gh pr create --title test"}}' | "$HOOK")
  assert_allowed "スタンプ名が vibecorp.yml の name から動的生成される" "$OUTPUT"
else
  fail "スタンプ名が vibecorp.yml の name から動的生成される (スタンプが見つからない)"
fi

# 12. command ラッパー付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"command gh pr create --title test"}}' | "$HOOK")
assert_blocked "command ラッパー付き → deny" "$OUTPUT"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
