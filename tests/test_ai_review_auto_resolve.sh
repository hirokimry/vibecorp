#!/bin/bash
# test_ai_review_auto_resolve.sh
# ─────────────────────────────────────────────
# Issue #466: 修正済みコメントの auto-resolve / dismiss
#
# 検証対象:
#   1. ai-review.yml claude-review ジョブに timeout-minutes: 10 が設定されている
#   2. REVIEW.md.tpl に auto-resolve 動作の指示（claude-action 自身のコメントのみ等）が含まれる
#   3. docs/ai-review-auth.md に「dismiss の責任分担」セクションが追加されている

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

assert_file_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

echo ""
echo "=== Issue #466 auto-resolve / dismiss の検証 ==="

# ============================================
# 1. ai-review.yml claude-review に timeout-minutes: 10
# ============================================
echo ""
echo "--- 1. claude-review ジョブの timeout-minutes: 10 ---"
WF="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
assert_file_contains_fixed "timeout-minutes: 10 設定" "$WF" "timeout-minutes: 10"
# claude-review ジョブブロック内に配置されていることを確認
# awk で claude-review: 〜 ファイル末まで抽出（最後のジョブなので EOF まで）
claude_review_block=$(awk '/^  claude-review:/{flag=1} flag' "$WF")
if echo "$claude_review_block" | grep -q -F -- "timeout-minutes: 10"; then
  pass "timeout-minutes: 10 が claude-review ジョブ内に配置されている"
else
  fail "timeout-minutes: 10 が claude-review ジョブ内に配置されていない"
fi

# ============================================
# 2. REVIEW.md.tpl に auto-resolve 動作指示
# ============================================
echo ""
echo "--- 2. REVIEW.md.tpl に auto-resolve 指示 ---"
TPL="${SCRIPT_DIR}/templates/REVIEW.md.tpl"
assert_file_contains "auto-resolve 動作セクション" "$TPL" "auto-resolve 動作"
assert_file_contains "claude-action 自身のコメントのみ dismiss" "$TPL" "claude-action 自身が過去に出したインラインコメントのみ"
assert_file_contains "CodeRabbit / 人間コメントは触らない（越権禁止）" "$TPL" "越権行為禁止"
assert_file_contains "修正済み判定したコメントのみ dismiss" "$TPL" "修正されたと判定したコメントだけを dismiss"
assert_file_contains "インクリメンタルレビュー（前回以降の差分）" "$TPL" "前回レビュー以降の差分"

# ============================================
# 3. docs/ai-review-auth.md に dismiss 責任分担セクション
# ============================================
echo ""
echo "--- 3. docs/ai-review-auth.md に責任分担セクション ---"
DOC="${SCRIPT_DIR}/docs/ai-review-auth.md"
assert_file_contains "7. dismiss の責任分担 セクション" "$DOC" "dismiss の責任分担"
assert_file_contains "approve dismiss / review thread dismiss 表" "$DOC" "approve dismiss"
assert_file_contains "review thread dismiss 行" "$DOC" "review thread dismiss"

# ============================================
# 4. ワークフロー構成表に timeout-minutes が反映
# ============================================
echo ""
echo "--- 4. docs/ai-review-auth.md ワークフロー構成表 ---"
assert_file_contains "timeout-minutes 行" "$DOC" "timeout-minutes"
assert_file_contains "10 (中規模 PR 完走)" "$DOC" "中規模 PR"

# ============================================
# 5. 配布版でも同じ内容が届く（install で利用者リポに配布）
# ============================================
echo ""
echo "--- 5. install で 配布版にも反映 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "配布: ai-review.yml に timeout-minutes: 10" "$R/.github/workflows/ai-review.yml" "timeout-minutes: 10"
assert_file_contains "配布: REVIEW.md に auto-resolve 動作" "$R/REVIEW.md" "auto-resolve 動作"
cleanup

print_test_summary
