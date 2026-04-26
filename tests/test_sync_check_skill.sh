#!/bin/bash
# sync-check SKILL.md の構造テスト
# 使い方: bash tests/test_sync_check_skill.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/sync-check/SKILL.md"

assert_contains() {
  local desc="$1"
  local pattern="$2"
  if grep -q "$pattern" "$SKILL_MD"; then
    pass "$desc"
  else
    fail "$desc (パターン未検出: $pattern)"
  fi
}

assert_not_contains() {
  local desc="$1"
  local pattern="$2"
  if grep -q "$pattern" "$SKILL_MD"; then
    fail "$desc (パターンが検出された: $pattern)"
  else
    pass "$desc"
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

# 4. CPO 管轄テーブルに README.md が含まれる
assert_contains "CPO 管轄テーブルに README.md が含まれる" \
  "| CPO.*README.md"

# 5. CTO 管轄テーブルに README.md が含まれない
assert_not_contains "CTO 管轄テーブルに README.md が含まれない" \
  "| CTO.*README.md"

# 6. CPO 起動条件に README が含まれる
assert_contains "CPO 起動条件に README 関連の変更が含まれる" \
  "| CPO.*README 関連の変更"

# 7. チェック観点に README 乖離（CPO）が含まれる
assert_contains "チェック観点に README 乖離（CPO）が含まれる" \
  "README 乖離（CPO）.*実装と README の記載に乖離がないか"

# 8. チェック観点に README 未反映（CPO）が含まれる
assert_contains "チェック観点に README 未反映（CPO）が含まれる" \
  "README 未反映（CPO）.*スキル・フック・エージェントが追加されたのに README に未反映"

# 9. 軽微な変更リストから README.md が除外されている
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
