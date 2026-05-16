#!/bin/bash
# test_pr_skill_overview_guide.sh
# ─────────────────────────────────────────────
# Issue #588: /pr スキルの概要欄プロンプトが「指針＋禁止パターン」型の 3 層構造に
# 置き換わっていることを静的検証する。
#
# 検証項目:
#   1. ステップ4 配下に「変化の主役を見極める」サブセクションが存在する
#   2. 「概要の書き方」が 3 層構造（指針 MUST / 使える見出し要素 / 禁止パターン）になっている
#   3. communication.md の動作主語ルールへの参照が残っている（整合担保）
#   4. 旧体裁の薄い 3 行ガイドのみで完結する状態に戻っていない

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

assert_file_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path"; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

assert_file_not_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path"; then
    fail "$desc (パターン '${pattern}' がファイルに残存: ${path})"
  else
    pass "$desc"
  fi
}

echo ""
echo "=== Issue #588 /pr スキルの概要欄プロンプトが 3 層構造になっていることを検証 ==="

PR_SKILL="${SCRIPT_DIR}/skills/pr/SKILL.md"

if [[ ! -f "$PR_SKILL" ]]; then
  fail "skills/pr/SKILL.md が存在しない"
  exit 1
fi
pass "skills/pr/SKILL.md が存在する"

# ============================================
# 1. ステップ4 配下に「変化の主役を見極める」サブセクションが存在する
# ============================================
echo ""
echo "--- 1. ステップ4 配下のサブセクション「変化の主役を見極める」 ---"
assert_file_contains_fixed "「変化の主役を見極める」見出しが存在する" \
  "$PR_SKILL" "#### 変化の主役を見極める"
assert_file_contains_fixed "主役の典型例「人」が列挙されている" \
  "$PR_SKILL" "**人**"
assert_file_contains_fixed "主役の典型例「外向きの挙動」が列挙されている" \
  "$PR_SKILL" "**外向きの挙動**"
assert_file_contains_fixed "主役の典型例「コードの内部品質軸」が列挙されている" \
  "$PR_SKILL" "**コードの内部品質軸**"
assert_file_contains_fixed "主役の典型例「再現していた事象」が列挙されている" \
  "$PR_SKILL" "**再現していた事象**"
assert_file_contains_fixed "「列挙したものに縛られなくてよい」の旨が含まれる" \
  "$PR_SKILL" "列挙したものに縛られなくてよい"
assert_file_contains_fixed "「最も支配的なものを 1 つ」選ぶ指示が含まれる" \
  "$PR_SKILL" "最も支配的なものを 1 つ"

# ============================================
# 2. 「概要の書き方」が 3 層構造になっている
# ============================================
echo ""
echo "--- 2. 「概要の書き方」が 3 層構造（指針 / 使える見出し要素 / 禁止パターン） ---"
assert_file_contains_fixed "「指針（MUST）」見出しが存在する" \
  "$PR_SKILL" "#### 指針（MUST）"
assert_file_contains_fixed "「使える見出し要素」見出しが存在する" \
  "$PR_SKILL" "#### 使える見出し要素"
assert_file_contains_fixed "「禁止パターン」見出しが存在する" \
  "$PR_SKILL" "#### 禁止パターン"
assert_file_contains_fixed "冒頭 IMPORTANT コールアウトが存在する" \
  "$PR_SKILL" "> [!IMPORTANT]"
assert_file_contains_fixed "禁止パターン: 実装詳細の羅列が明示されている" \
  "$PR_SKILL" "実装詳細の羅列"
assert_file_contains_fixed "禁止パターン: 形容詞だけの記述が明示されている" \
  "$PR_SKILL" "形容詞だけで具体性のない記述"
assert_file_contains_fixed "禁止パターン: 装飾目的だけの絵文字が明示されている" \
  "$PR_SKILL" "装飾目的だけの絵文字"

# ============================================
# 3. communication.md の動作主語ルールへの参照が残っている（整合担保）
# ============================================
echo ""
echo "--- 3. communication.md の動作主語ルールへの参照が残っている ---"
assert_file_contains_fixed "communication.md への参照が残っている" \
  "$PR_SKILL" ".claude/rules/communication.md"
assert_file_contains_fixed "動作主語の運用ルールが残っている" \
  "$PR_SKILL" "動作主語"

# ============================================
# 4. 旧体裁の薄い 3 行ガイドのみで完結する状態に戻っていない
# ============================================
echo ""
echo "--- 4. 旧体裁の薄い 3 行ガイドだけが残る状態ではない ---"
# 旧体裁の典型句「動作の変化を中心に書く。実装詳細の優先度は低く」は 3 層構造に
# 置き換わっているはず（旧体裁の固有文言が消えていることを確認）
assert_file_not_contains_fixed "旧体裁の薄い指針「動作の変化を中心に書く。実装詳細の優先度は低く」が消えている" \
  "$PR_SKILL" "動作の変化を中心に書く。実装詳細の優先度は低く"

print_test_summary
