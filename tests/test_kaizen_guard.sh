#!/bin/bash
# kaizen-guard.sh のユニットテスト
# 使い方: bash tests/test_kaizen_guard.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/templates/claude/hooks/kaizen-guard.sh"
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

# --- テスト用の vibecorp.yml を準備 ---

TMPDIR_TEST=$(mktemp -d)
mkdir -p "${TMPDIR_TEST}/.claude"
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
kaizen:
  enabled: true
  max_issues_per_run: 5
  max_issues_per_day: 10
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
YAML

export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
STAMP_FILE="/tmp/.test-project-kaizen-active"

# --- クリーンアップ ---

cleanup() {
  rm -f "$STAMP_FILE"
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT
rm -f "$STAMP_FILE"

# ============================================
echo "=== kaizen-guard.sh ==="
# ============================================

# --- スタンプなし（通常時）---

echo "--- スタンプなし（通常動作）---"

# 1. スタンプなしで hooks/*.sh を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | "$HOOK")
assert_allowed "スタンプなしで hooks/*.sh 編集 → allow" "$OUTPUT"

# 2. スタンプなしで vibecorp.yml を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/vibecorp.yml"}}' | "$HOOK")
assert_allowed "スタンプなしで vibecorp.yml 編集 → allow" "$OUTPUT"

# 3. スタンプなしで MVV.md を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | "$HOOK")
assert_allowed "スタンプなしで MVV.md 編集 → allow" "$OUTPUT"

# --- スタンプあり（kaizen 実行中）---

echo "--- スタンプあり（kaizen 実行中）---"
touch "$STAMP_FILE"

# 4. hooks/*.sh への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | "$HOOK")
assert_blocked "kaizen 実行中に hooks/*.sh 編集 → deny" "$OUTPUT"

# 5. vibecorp.yml への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/vibecorp.yml"}}' | "$HOOK")
assert_blocked "kaizen 実行中に vibecorp.yml 編集 → deny" "$OUTPUT"

# 6. MVV.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | "$HOOK")
assert_blocked "kaizen 実行中に MVV.md 編集 → deny" "$OUTPUT"

# 7. kaizen-guard.sh 自体への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/kaizen-guard.sh"}}' | "$HOOK")
assert_blocked "kaizen 実行中に kaizen-guard.sh 自体の編集 → deny" "$OUTPUT"

# 8. SECURITY.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/SECURITY.md"}}' | "$HOOK")
assert_blocked "kaizen 実行中に SECURITY.md 編集 → deny" "$OUTPUT"

# 9. POLICY.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/POLICY.md"}}' | "$HOOK")
assert_blocked "kaizen 実行中に POLICY.md 編集 → deny" "$OUTPUT"

# 10. 通常のソースファイル → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/src/main.ts"}}' | "$HOOK")
assert_allowed "kaizen 実行中でも通常ファイル編集 → allow" "$OUTPUT"

# 11. docs/ 配下のファイル → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/docs/architecture.md"}}' | "$HOOK")
assert_allowed "kaizen 実行中でも docs/ 配下は → allow" "$OUTPUT"

# 12. file_path が空 → allow
OUTPUT=$(echo '{"tool_input":{}}' | "$HOOK")
assert_allowed "file_path が空 → allow" "$OUTPUT"

# --- スタンプ名のプロジェクト名動的生成テスト ---

echo "--- プロジェクト名動的生成テスト ---"

# スタンプを削除して別プロジェクトとして試す
rm -f "$STAMP_FILE"

# 13. 別のプロジェクト名のスタンプがあっても影響しない
WRONG_STAMP="/tmp/.other-project-kaizen-active"
touch "$WRONG_STAMP"
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | "$HOOK")
assert_allowed "別プロジェクトのスタンプでは反応しない → allow" "$OUTPUT"
rm -f "$WRONG_STAMP"

# --- デフォルト forbidden_targets テスト ---

echo "--- デフォルト forbidden_targets テスト ---"

# kaizen セクションなしの vibecorp.yml を作成
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
YAML

touch "$STAMP_FILE"

# 14. kaizen セクションなしでもデフォルトの保護が有効
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/sync-gate.sh"}}' | "$HOOK")
assert_blocked "kaizen セクションなしでもデフォルトの hooks/*.sh 保護 → deny" "$OUTPUT"

# 15. デフォルトで MVV.md も保護
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | "$HOOK")
assert_blocked "kaizen セクションなしでもデフォルトの MVV.md 保護 → deny" "$OUTPUT"

# 16. デフォルトで通常ファイルは通す
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/src/app.ts"}}' | "$HOOK")
assert_allowed "kaizen セクションなしでも通常ファイルは → allow" "$OUTPUT"

# --- クリーンアップ ---
rm -f "$STAMP_FILE"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
