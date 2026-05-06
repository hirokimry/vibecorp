#!/bin/bash
# test_intent_label_ci_race.sh
# ─────────────────────────────────────────────
# Issue #517: PR 作成時の intent ラベル数チェックが必ず fail するレースを解消する。
#
# 旧設計では別 workflow である pr-intent-inherit.yml と ai-review.yml の
# intent-label-check が並列実行され、継承前のラベル状態で数チェックが走り
# 永久に FAILURE のままになる致命的レースが発生していた。
#
# 本テストは ai-review.yml の intent-label-check ジョブが以下を満たすことを
# 静的検証する:
#   1. 「対応 Issue から intent ラベルを継承」ステップが存在する
#   2. 継承ステップが「1 PR 1 intent 厳守チェック」ステップ **より前** にある
#   3. 自リポ版（.github/workflows/）と配布版（templates/.github/workflows/）が
#      完全一致する（同期 drift 検知）
#   4. 旧 pr-intent-inherit.yml が両側から削除されている

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF_AI_REVIEW="${SCRIPT_DIR}/.github/workflows/ai-review.yml"
TEMPLATE_AI_REVIEW="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
SELF_INHERIT="${SCRIPT_DIR}/.github/workflows/pr-intent-inherit.yml"
TEMPLATE_INHERIT="${SCRIPT_DIR}/templates/.github/workflows/pr-intent-inherit.yml"

assert_file_exists "vibecorp 自リポ ai-review.yml が存在する" "$SELF_AI_REVIEW"
assert_file_exists "templates 配布版 ai-review.yml が存在する" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 1: 旧 pr-intent-inherit.yml が両側から削除されている
# ============================================
echo ""
echo "--- Case 1: 旧 pr-intent-inherit.yml が削除されている ---"

if [ -e "$SELF_INHERIT" ]; then
  fail "自リポ版 pr-intent-inherit.yml が残存（Issue #517 で削除済みのはず）"
else
  pass "自リポ版 pr-intent-inherit.yml が削除されている"
fi

if [ -e "$TEMPLATE_INHERIT" ]; then
  fail "配布版 pr-intent-inherit.yml が残存（Issue #517 で削除済みのはず）"
else
  pass "配布版 pr-intent-inherit.yml が削除されている"
fi

# ============================================
# Case 2: intent-label-check ジョブに継承ステップが存在する
# ============================================
echo ""
echo "--- Case 2: 継承ステップが intent-label-check ジョブに統合されている ---"

check_inherit_step_exists() {
  local label="$1"
  local file="$2"
  if grep -q -F "対応 Issue から intent ラベルを継承" "$file"; then
    pass "${label}: 「対応 Issue から intent ラベルを継承」ステップが存在"
  else
    fail "${label}: 継承ステップが見つからない（intent-label-check ジョブに統合されていない）"
  fi
}

check_inherit_step_exists "自リポ版" "$SELF_AI_REVIEW"
check_inherit_step_exists "配布版" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 3: 継承ステップが数チェックステップより前に存在する
# ============================================
echo ""
echo "--- Case 3: 継承ステップが数チェックより前にある（直列化検証） ---"

check_step_order() {
  local label="$1"
  local file="$2"
  # awk で intent-label-check ジョブ内の各ステップの行番号を取得
  local inherit_line
  local check_line
  inherit_line=$(awk '
    /^  intent-label-check:/ { in_job = 1 }
    in_job && /^  [a-zA-Z]/ && !/^  intent-label-check:/ { in_job = 0 }
    in_job && /name: 対応 Issue から intent ラベルを継承/ { print NR; exit }
  ' "$file")
  check_line=$(awk '
    /^  intent-label-check:/ { in_job = 1 }
    in_job && /^  [a-zA-Z]/ && !/^  intent-label-check:/ { in_job = 0 }
    in_job && /name: 1 PR 1 intent 厳守チェック/ { print NR; exit }
  ' "$file")

  if [ -z "$inherit_line" ]; then
    fail "${label}: 継承ステップが intent-label-check ジョブ内に見つからない"
    return
  fi
  if [ -z "$check_line" ]; then
    fail "${label}: 数チェックステップが intent-label-check ジョブ内に見つからない"
    return
  fi

  if [ "$inherit_line" -lt "$check_line" ]; then
    pass "${label}: 継承ステップ（行 ${inherit_line}）が数チェック（行 ${check_line}）より前にある"
  else
    fail "${label}: 継承ステップ（行 ${inherit_line}）が数チェック（行 ${check_line}）より後にある（順序逆）"
  fi
}

check_step_order "自リポ版" "$SELF_AI_REVIEW"
check_step_order "配布版" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 4: claude-review ジョブが intent-label-check に依存（needs:）
# ============================================
echo ""
echo "--- Case 4: claude-review ジョブが intent-label-check に依存している ---"

check_needs_dependency() {
  local label="$1"
  local file="$2"
  if grep -q -E '^[[:space:]]+needs:[[:space:]]*intent-label-check' "$file"; then
    pass "${label}: claude-review が needs: intent-label-check で待機している"
  else
    fail "${label}: claude-review に needs: intent-label-check が見つからない"
  fi
}

check_needs_dependency "自リポ版" "$SELF_AI_REVIEW"
check_needs_dependency "配布版" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 5: 自リポ版と配布版が完全一致
# ============================================
echo ""
echo "--- Case 5: 自リポ版と配布版の ai-review.yml が完全一致 ---"

if diff -q "$SELF_AI_REVIEW" "$TEMPLATE_AI_REVIEW" >/dev/null; then
  pass "自リポ版と配布版の ai-review.yml が完全一致（同期 drift なし）"
else
  fail "自リポ版と配布版の ai-review.yml が乖離している"
fi

# ============================================
# Case 6: ホワイトリスト 7 種の継承ロジック側でも参照されている
# ============================================
echo ""
echo "--- Case 6: 継承ステップでホワイトリスト 7 種を参照している ---"

for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -c -F -- "\"$intent\"" "$SELF_AI_REVIEW" | awk '$1 >= 2 { exit 0 } { exit 1 }'; then
    pass "ホワイトリスト '$intent' が継承+数チェックの両方で参照されている（>= 2 回出現）"
  else
    fail "ホワイトリスト '$intent' の参照回数が不足（継承または数チェックのどちらかで欠落）"
  fi
done

print_test_summary
