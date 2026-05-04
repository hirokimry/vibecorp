#!/bin/bash
# test_commit_skill_cc_emoji.sh
# ─────────────────────────────────────────────
# Issue #486: /vibecorp:commit が CC 11 種 + 絵文字 1:1 マッピングを適用するように書き換わったことを検証

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
echo "=== Issue #486 /vibecorp:commit 書き換え検証 ==="

SKILL="${SCRIPT_DIR}/skills/commit/SKILL.md"

# ============================================
# 1. CC 11 種すべてが prefix 一覧テーブルに含まれる
# ============================================
echo ""
echo "--- 1. CC 11 種の prefix 一覧 ---"
for prefix in feat fix perf refactor style docs test ci chore build revert; do
  if grep -q -E "^\| \`${prefix}\` \|" "$SKILL"; then
    pass "CC prefix '$prefix' の一覧行がある"
  else
    fail "CC prefix '$prefix' の一覧行がない"
  fi
done

# ============================================
# 2. 絵文字 1:1 マッピング 11 種
# ============================================
echo ""
echo "--- 2. 絵文字 1:1 マッピング ---"
declare -a emoji_pairs=(
  "feat ✨"
  "fix 🐛"
  "perf ⚡"
  "refactor 🔄"
  "style 💄"
  "docs 📖"
  "test 🧪"
  "ci 🔧"
  "chore ⚙️"
  "build 📦"
  "revert ⏪"
)
for pair in "${emoji_pairs[@]}"; do
  prefix="${pair% *}"
  emoji="${pair#* }"
  if grep -q -E "^\| ${prefix} \| ${emoji} \|" "$SKILL"; then
    pass "CC prefix '${prefix}' → 絵文字 '${emoji}' マッピング行がある"
  else
    fail "CC prefix '${prefix}' → 絵文字 '${emoji}' マッピング行がない"
  fi
done

# ============================================
# 3. 厳格定義の参照
# ============================================
echo ""
echo "--- 3. vibecorp 厳格定義への参照 ---"
assert_file_contains_fixed "docs/conventional-commits.md 参照" "$SKILL" "docs/conventional-commits.md"
assert_file_contains "refactor 挙動不変厳格化" "$SKILL" "挙動不変"
assert_file_contains "chore 依存メジャー更新不可"     "$SKILL" "依存メジャー更新"
assert_file_contains "build ランタイム挙動変更不可"   "$SKILL" "ランタイム挙動"

# ============================================
# 4. 主従関係（intent → CC prefix）
# ============================================
echo ""
echo "--- 4. 主従関係（intent → CC prefix） ---"
assert_file_contains_fixed "intent → CC prefix の主従順" "$SKILL" "intent → CC prefix"
assert_file_contains_fixed "逆引き禁止" "$SKILL" "逆引き禁止"
assert_file_contains_fixed ".claude/rules/intent-labels.md 参照" "$SKILL" ".claude/rules/intent-labels.md"

# ============================================
# 5. タイトル形式
# ============================================
echo ""
echo "--- 5. タイトル形式 ---"
assert_file_contains_fixed "タイトル形式 <emoji> <CC prefix>: <subject>" "$SKILL" "<emoji> <CC prefix>: <subject>"
assert_file_contains_fixed "scope 付き形式" "$SKILL" "<emoji> <CC prefix>(<scope>): <subject>"
assert_file_contains       "件名にピリオドなしルール"   "$SKILL" "ピリオドなし"
assert_file_contains       "件名 50 文字推奨ルール"    "$SKILL" "50 文字"

# ============================================
# 6. revert の扱い（intent/bugfix）
# ============================================
echo ""
echo "--- 6. revert の扱い ---"
assert_file_contains "revert は intent/bugfix" "$SKILL" "intent/bugfix"
assert_file_contains_fixed "revert 絵文字 ⏪" "$SKILL" "⏪"

# ============================================
# 7. 旧 7 種限定タイプ表記の廃止
# ============================================
echo ""
echo "--- 7. 旧表記の廃止 ---"
# 旧テキスト: "feat(新機能) / fix(修正) / docs(文書) / style(整形) / refactor(改善) / test(テスト) / chore(雑務)"
if grep -q -F -- "feat(新機能) / fix(修正) / docs(文書)" "$SKILL"; then
  fail "旧 7 種限定タイプ表記が残っている"
else
  pass "旧 7 種限定タイプ表記が削除された"
fi

print_test_summary
