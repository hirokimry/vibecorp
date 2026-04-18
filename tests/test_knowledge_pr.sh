#!/bin/bash
# test_knowledge_pr.sh — /knowledge-pr スキルの構造テスト
# LLM 駆動スキルのため、SKILL.md の必須要素と制約を検証する
# 使い方: bash tests/test_knowledge_pr.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SCRIPT_DIR}/templates/claude/skills/knowledge-pr/SKILL.md"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL: $1"; }

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then pass "$desc"; else fail "$desc ($path が存在しない)"; fi
}

assert_contains() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE -- "$pattern" "$file"; then pass "$desc"; else fail "$desc (パターン '$pattern' が $file に含まれない)"; fi
}

# ============================================
echo "=== /knowledge-pr SKILL.md 存在 ==="
# ============================================

assert_file_exists "SKILL.md が存在する" "$SKILL_FILE"

if [ ! -f "$SKILL_FILE" ]; then
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# ============================================
echo ""
echo "=== SKILL.md frontmatter ==="
# ============================================

assert_contains "name フィールドが knowledge-pr" '^name: knowledge-pr$' "$SKILL_FILE"
assert_contains "description フィールドがある" '^description: ' "$SKILL_FILE"

# ============================================
echo ""
echo "=== SKILL.md 必須要素 ==="
# ============================================

assert_contains "knowledge_buffer_ensure 呼出を記載" 'knowledge_buffer_ensure' "$SKILL_FILE"
assert_contains "knowledge_buffer_push 呼出を記載" 'knowledge_buffer_push' "$SKILL_FILE"

assert_contains "差分 0 件 skip 処理" 'DIFF_COUNT|差分なし' "$SKILL_FILE"
assert_contains "重複 Issue チェック" '既存 Issue|重複 Issue|gh issue list.*is:open' "$SKILL_FILE"
assert_contains "Issue 起票処理" 'gh issue create' "$SKILL_FILE"
assert_contains "PR 作成処理" 'gh pr create' "$SKILL_FILE"
assert_contains "base=main head=knowledge/buffer" 'knowledge/buffer' "$SKILL_FILE"
assert_contains "auto-merge 設定" 'gh pr merge.*--auto|--squash.*--auto' "$SKILL_FILE"

assert_contains "PR 本文に close #Issue を含む" 'close #' "$SKILL_FILE"

assert_contains "main 直接 push 禁止を明記" 'main への直接 push は発生しない|auto-merge 経由' "$SKILL_FILE"

assert_contains "介入ポイントが記載される" '介入ポイント|手動|人手' "$SKILL_FILE"

# ============================================
echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
