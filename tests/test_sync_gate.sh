#!/bin/bash
# sync-gate.sh のユニットテスト
# 使い方: bash tests/test_sync_gate.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/templates/claude/hooks/sync-gate.sh"
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
# git リポジトリ初期化（vibecorp_stamp_dir が toplevel を引けるように）
( cd "$TMPDIR_TEST" && git init -q . && git config user.email t@example.com && git config user.name t )

# CLAUDE_PROJECT_DIR と XDG_CACHE_HOME を分離して
# ホスト側の ~/.cache を汚染せずスタンプを TMPDIR 配下に隔離
export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
export XDG_CACHE_HOME="${TMPDIR_TEST}/cache"

# 共通ヘルパーから新スタンプパスを動的に取得
# shellcheck source=../templates/claude/lib/common.sh
source "${SCRIPT_DIR}/templates/claude/lib/common.sh"
STAMP_FILE="$(vibecorp_stamp_path sync)"
mkdir -p "$(dirname "$STAMP_FILE")"

# --- クリーンアップ ---

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT
# スタンプだけ削除（TMPDIR_TEST はフック実行に必要なので残す）
rm -f "$STAMP_FILE"

# ============================================
echo "=== sync-gate.sh ==="
# ============================================

# 1. スタンプなしで push → deny
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | "$HOOK")
assert_blocked "スタンプなしで push → deny" "$OUTPUT"

# 2. スタンプありで push → allow
touch "$STAMP_FILE"
OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | "$HOOK")
assert_allowed "スタンプありで push → allow" "$OUTPUT"

# 3. push 後にスタンプ削除される
if [ ! -f "$STAMP_FILE" ]; then
  pass "push 後にスタンプが削除される"
else
  fail "push 後にスタンプが削除される (ファイルが残っている)"
fi

# 4. push 以外のコマンド (git status) → allow
OUTPUT=$(echo '{"tool_input":{"command":"git status"}}' | "$HOOK")
assert_allowed "git status → allow" "$OUTPUT"

# 5. push --force → deny
OUTPUT=$(echo '{"tool_input":{"command":"git push --force origin main"}}' | "$HOOK")
assert_blocked "git push --force → deny" "$OUTPUT"

# 6. push -u → deny
OUTPUT=$(echo '{"tool_input":{"command":"git push -u origin feature"}}' | "$HOOK")
assert_blocked "git push -u → deny" "$OUTPUT"

# 7. git pull → allow
OUTPUT=$(echo '{"tool_input":{"command":"git pull origin main"}}' | "$HOOK")
assert_allowed "git pull → allow" "$OUTPUT"

# 8. push --delete → allow
OUTPUT=$(echo '{"tool_input":{"command":"git push origin --delete dev/old-branch"}}' | "$HOOK")
assert_allowed "git push --delete → allow" "$OUTPUT"

# 9. push -d → allow
OUTPUT=$(echo '{"tool_input":{"command":"git push origin -d dev/old-branch"}}' | "$HOOK")
assert_allowed "git push -d → allow" "$OUTPUT"

# 10. 環境変数プレフィックス付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"GIT_SSH_COMMAND=ssh git push origin main"}}' | "$HOOK")
assert_blocked "環境変数プレフィックス付き → deny" "$OUTPUT"

# 11. 絶対パス付き (/usr/bin/git push) → deny
OUTPUT=$(echo '{"tool_input":{"command":"/usr/bin/git push origin main"}}' | "$HOOK")
assert_blocked "絶対パス付き (/usr/bin/git push) → deny" "$OUTPUT"

# 12. env ラッパー付き → deny
OUTPUT=$(echo '{"tool_input":{"command":"env git push origin main"}}' | "$HOOK")
assert_blocked "env ラッパー付き → deny" "$OUTPUT"

# 13. STAMP_FILE は XDG_CACHE_HOME/vibecorp/state/<repo-id>/sync-ok に配置される
touch "$STAMP_FILE"
if [ -f "$STAMP_FILE" ]; then
  OUTPUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | "$HOOK")
  assert_allowed "STAMP_FILE が \$XDG_CACHE_HOME/vibecorp/state/<repo-id>/sync-ok に配置される" "$OUTPUT"
else
  fail "STAMP_FILE が新パスに配置される (スタンプが見つからない: ${STAMP_FILE})"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
