#!/bin/bash
# sync-check SKILL.md の構造テスト
# 使い方: bash tests/test_sync_check_skill.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/templates/claude/skills/sync-check/SKILL.md"
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

assert_contains() {
  local desc="$1"
  local pattern="$2"
  if grep -q "$pattern" "$SKILL_MD"; then
    pass "$desc"
  else
    fail "$desc (パターン未検出: $pattern)"
  fi
}

# ============================================
echo "=== sync-check SKILL.md 構造テスト ==="
# ============================================

# 1. SKILL.md が存在する
if [ -f "$SKILL_MD" ]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在する"
  echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
  exit 1
fi

# 2. description に README.md が含まれる
assert_contains "description に README.md が含まれる" "README.md"

# 3. 対象外判定に README.md が含まれる
assert_contains "対象外判定に docs/ や knowledge/ や README.md が含まれる" \
  "docs/.*knowledge/.*README.md.*のみの変更"

# 4. CTO 管轄テーブルに README.md が含まれる
assert_contains "CTO 管轄テーブルに README.md が含まれる" \
  "| CTO.*README.md"

# 5. CTO 起動条件に README が含まれる
assert_contains "CTO 起動条件に README が含まれる" \
  "README 関連の変更"

# 6. チェック観点に README 乖離が含まれる
assert_contains "チェック観点に README 乖離が含まれる" \
  "README 乖離.*実装と README の記載に乖離がないか"

# 7. チェック観点に README 未反映が含まれる
assert_contains "チェック観点に README 未反映が含まれる" \
  "README 未反映.*スキル・フック・エージェントが追加されたのに README に未反映"

# 8. 軽微な変更リストから README.md が除外されている
#    （.gitignore 等の軽微な変更に README.md が含まれていないこと）
if grep -q '\.gitignore.*README\.md.*軽微な変更' "$SKILL_MD"; then
  fail "軽微な変更リストから README.md が除外されている (まだ含まれている)"
else
  pass "軽微な変更リストから README.md が除外されている"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
