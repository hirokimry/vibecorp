#!/bin/bash
# test_install_review_criteria_split.sh
# ─────────────────────────────────────────────
# Issue #470: review-criteria.md を 4 ファイルに分割
#
# 検証対象:
#   1. 旧 review-criteria.md が削除されている
#   2. 新 4 ファイルが templates と本体（vibecorp 自身）の両方に配置されている
#   3. install で 4 ファイルが利用者リポにも配布される（severity/ サブディレクトリ含む）
#   4. 各ファイルが議論内容を網羅している（severity 5 段階、捌き基準、観点）
#   5. REVIEW.md が新 4 ファイルへの参照に更新されている
#   6. 旧 review-criteria.md への参照が docs / skills / tests から消えている

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
echo "=== Issue #470 review-criteria.md 4 ファイル分割の検証 ==="

# ============================================
# 1. 旧 review-criteria.md が削除されている
# ============================================
echo ""
echo "--- 1. 旧 review-criteria.md が削除されている ---"
assert_file_not_exists "templates 旧ファイル不在" "${SCRIPT_DIR}/templates/claude/rules/review-criteria.md"
assert_file_not_exists "vibecorp 本体 旧ファイル不在" "${SCRIPT_DIR}/.claude/rules/review-criteria.md"

# ============================================
# 2. 新 4 ファイルが両方に存在
# ============================================
echo ""
echo "--- 2. 新 4 ファイル（SSOT rules/ 側） ---"
assert_file_exists "severity/coderabbit.md" "${SCRIPT_DIR}/rules/severity/coderabbit.md"
assert_file_exists "severity/claude-action.md" "${SCRIPT_DIR}/rules/severity/claude-action.md"
assert_file_exists "review-handling.md" "${SCRIPT_DIR}/rules/review-handling.md"
assert_file_exists "review-observations.md" "${SCRIPT_DIR}/rules/review-observations.md"

echo "--- 2b. 新 4 ファイル（vibecorp 本体側） ---"
assert_file_exists "severity/coderabbit.md" "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md"
assert_file_exists "severity/claude-action.md" "${SCRIPT_DIR}/.claude/rules/severity/claude-action.md"
assert_file_exists "review-handling.md" "${SCRIPT_DIR}/.claude/rules/review-handling.md"
assert_file_exists "review-observations.md" "${SCRIPT_DIR}/.claude/rules/review-observations.md"

# ============================================
# 3. install で 4 ファイルが配布される（severity/ サブディレクトリ含む）
# ============================================
echo ""
echo "--- 3. install で 4 ファイルが配布される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "配布: severity/coderabbit.md" "$R/.claude/rules/severity/coderabbit.md"
assert_file_exists "配布: severity/claude-action.md" "$R/.claude/rules/severity/claude-action.md"
assert_file_exists "配布: review-handling.md" "$R/.claude/rules/review-handling.md"
assert_file_exists "配布: review-observations.md" "$R/.claude/rules/review-observations.md"
assert_file_not_exists "配布: 旧 review-criteria.md は無い" "$R/.claude/rules/review-criteria.md"
cleanup

# ============================================
# 4. 各ファイルの内容検証
# ============================================
echo ""
echo "--- 4. severity/coderabbit.md 内容 ---"
assert_file_contains "Critical 定義"  "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "Critical"
assert_file_contains "Major 定義"     "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "Major"
assert_file_contains "Minor 定義"     "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "Minor"
assert_file_contains "Trivial 定義"   "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "Trivial"
assert_file_contains "Info 定義"      "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "Info"
assert_file_contains "外部仕様変更不可" "${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md" "変更不可"

echo "--- 4b. severity/claude-action.md 内容 ---"
assert_file_contains "実体保有版" "${SCRIPT_DIR}/.claude/rules/severity/claude-action.md" "実体"
assert_file_contains "Critical 定義" "${SCRIPT_DIR}/.claude/rules/severity/claude-action.md" "Critical"

echo "--- 4c. review-handling.md 内容 ---"
assert_file_contains "intent × severity 掛け合わせ" "${SCRIPT_DIR}/.claude/rules/review-handling.md" "intent"
assert_file_contains "Critical / Major intent 問わず" "${SCRIPT_DIR}/.claude/rules/review-handling.md" "intent 問わず"
assert_file_contains "重視軸該当のみ対応"          "${SCRIPT_DIR}/.claude/rules/review-handling.md" "重視軸該当"
assert_file_contains "intent/feature 重視軸"        "${SCRIPT_DIR}/.claude/rules/review-handling.md" "新機能を確実に動かす"
assert_file_contains "intent/security 重視軸"       "${SCRIPT_DIR}/.claude/rules/review-handling.md" "脆弱性を塞ぐ"

echo "--- 4d. review-observations.md 内容 ---"
assert_file_contains "intent/feature 観点"   "${SCRIPT_DIR}/.claude/rules/review-observations.md" "仕様逸脱"
assert_file_contains "intent/security 観点"  "${SCRIPT_DIR}/.claude/rules/review-observations.md" "脆弱性パターン"
assert_file_contains "挙動不変性の確認 必須"  "${SCRIPT_DIR}/.claude/rules/review-observations.md" "挙動不変性の確認"
assert_file_contains "影響を与えない系適用"   "${SCRIPT_DIR}/.claude/rules/review-observations.md" "影響を与えない系"

# ============================================
# 5. REVIEW.md.tpl が撤去されている（Issue #531）
#    REVIEW.md は claude-code-action のレビュープロンプトだった。レビュー機能の
#    vibehawk 移譲（Issue #531）により REVIEW.md.tpl テンプレートは撤去された。
#    分割した 4 ファイル（severity / review-handling / review-observations）は
#    rules/ SSOT に残り、ブロック 2・4 で検証済み。
# ============================================
echo ""
echo "--- 5. REVIEW.md.tpl が撤去されている（vibehawk 移譲） ---"
if [ -e "${SCRIPT_DIR}/templates/REVIEW.md.tpl" ]; then
  fail "REVIEW.md.tpl テンプレートが残存（Issue #531 で撤去済みのはず）"
else
  pass "REVIEW.md.tpl テンプレートが撤去されている（vibehawk 移譲）"
fi

# ============================================
# 6. 旧参照の残存チェック（docs / skills / tests から消えていること）
# ============================================
echo ""
echo "--- 6. 旧 review-criteria.md 参照の残存チェック ---"
# knowledge/ は判断記録の歴史なので除外（過去判断は残す）
# 本テストファイル自身と歴史言及（「旧 review-criteria.md」を述べているコメント）は除外
remaining=$(grep -rln "review-criteria" \
  "${SCRIPT_DIR}/docs" \
  "${SCRIPT_DIR}/skills" \
  "${SCRIPT_DIR}/tests" \
  "${SCRIPT_DIR}/README.md" \
  "${SCRIPT_DIR}/templates" \
  --include="*.md" --include="*.sh" --include="*.tpl" 2>/dev/null \
  | grep -v -F -- "tests/test_install_review_criteria_split.sh" \
  | grep -v -F -- "tests/test_review_loop_consensus.sh" \
  || true)
if [[ -z "$remaining" ]]; then
  pass "docs / skills / templates / README から旧 review-criteria.md 参照が消えている（本テストファイル自身と test_review_loop_consensus.sh の歴史コメントは許容）"
else
  fail "旧 review-criteria.md 参照が残っている: $remaining"
fi

print_test_summary
