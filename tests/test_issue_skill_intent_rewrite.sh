#!/bin/bash
# test_issue_skill_intent_rewrite.sh
# ─────────────────────────────────────────────
# Issue #485: /vibecorp:issue スキルが旧 type 14 種廃止 + COO 文脈判定 + intent ラベル付与に書き換わったことを検証

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== Issue #485 /vibecorp:issue 書き換え検証 ==="

SKILL="${SCRIPT_DIR}/skills/issue/SKILL.md"
# Issue #642: プロンプト本体は skills/issue/prompts/*.md に切り出された
# SKILL.md + prompts/*.md を結合した検査対象ファイルを一時生成する
SKILL_ALL="$(mktemp -t issue_skill_intent_skill_all.XXXXXX)"
trap 'rm -f "$SKILL_ALL" || true' EXIT
# プロンプトファイルの存在を事前検証（nullglob で glob リテラル残留を防ぐ）
shopt -s nullglob
ISSUE_PROMPT_FILES=("${SCRIPT_DIR}"/skills/issue/prompts/*.md)
shopt -u nullglob
if [ ${#ISSUE_PROMPT_FILES[@]} -eq 0 ]; then
  fail "skills/issue/prompts/*.md が 1 件も存在しない (Issue #642 切り出し前提が崩れている)"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi
cat "${SCRIPT_DIR}/skills/issue/SKILL.md" "${ISSUE_PROMPT_FILES[@]}" > "$SKILL_ALL"

# ============================================
# 1. 旧 type 14 種キーワード判定表が削除されている
# ============================================
echo ""
echo "--- 1. 旧 type 14 種キーワード判定表の廃止 ---"

# 旧テーブルにあったがなくなった type
if grep -q -E "\| \`design\` \| 📋 \|" "$SKILL"; then
  fail "旧 type 'design' のキーワード判定表行が残っている"
else
  pass "旧 type 'design' のキーワード判定表行が削除された"
fi

if grep -q -E "\| \`agent\` \| 🤖 \|" "$SKILL"; then
  fail "旧 type 'agent' のキーワード判定表行が残っている"
else
  pass "旧 type 'agent' のキーワード判定表行が削除された"
fi

if grep -q -E "\| \`integrate\` \| 🔌 \|" "$SKILL"; then
  fail "旧 type 'integrate' のキーワード判定表行が残っている"
else
  pass "旧 type 'integrate' のキーワード判定表行が削除された"
fi

if grep -q -E "\| \`release\` \| 🚀 \|" "$SKILL"; then
  fail "旧 type 'release' のキーワード判定表行が残っている"
else
  pass "旧 type 'release' のキーワード判定表行が削除された"
fi

if grep -q -E "\| \`template\` \| 📦 \|" "$SKILL"; then
  fail "旧 type 'template' のキーワード判定表行が残っている"
else
  pass "旧 type 'template' のキーワード判定表行が削除された"
fi

# ============================================
# 2. COO 主体の intent 判定が記載されている
# ============================================
echo ""
echo "--- 2. COO 主体の intent 判定 ---"
assert_file_contains "COO による intent 判定セクション" "$SKILL" "COO による intent 判定"
assert_file_contains "Issue #469 議論結論への参照"      "$SKILL" "#469"

# ============================================
# 3. intent ラベル 7 種すべての言及
# ============================================
echo ""
echo "--- 3. intent ラベル 7 種 ---"
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if grep -q -F -- "$intent" "$SKILL"; then
    pass "$intent への言及がある"
  else
    fail "$intent への言及がない"
  fi
done

# ============================================
# 4. CC prefix 11 種の絵文字マッピングが記載されている
# ============================================
echo ""
echo "--- 4. CC prefix 11 種の絵文字マッピング ---"
for prefix in feat fix perf refactor style docs test ci chore build revert; do
  if grep -q -E "^\| ${prefix} \|" "$SKILL"; then
    pass "CC prefix '$prefix' の絵文字マッピング行がある"
  else
    fail "CC prefix '$prefix' の絵文字マッピング行がない"
  fi
done

# ============================================
# 5. 主従関係の絶対条件
# ============================================
echo ""
echo "--- 5. 主従関係（intent → prefix）の絶対条件 ---"
assert_file_contains "1 Issue 1 intent 厳守"    "$SKILL" "1 Issue 1 intent"
assert_file_contains "intent → prefix 主従順"   "$SKILL" "intent → prefix"
assert_file_contains "逆引き禁止"               "$SKILL" "逆引き禁止"

# ============================================
# 6. SM フィルタ（不可領域 6 分類）
# ============================================
echo ""
echo "--- 6. SM フィルタの不可領域 6 分類 ---"
assert_file_contains "不可領域 6 分類" "$SKILL_ALL" "不可領域 6 分類"
assert_file_contains "CI エージェント領域追加" "$SKILL_ALL" "CI エージェント"

# ============================================
# 7. Issue 起票で intent/* ラベル必須
# ============================================
echo ""
echo "--- 7. Issue 起票で intent/* ラベル必須 ---"
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

assert_file_contains_fixed "gh issue create で intent/* 必須" "$SKILL" '--label "intent/<intent>"'
assert_file_contains_fixed "intent/* ラベルは必須" "$SKILL" "\`intent/*\` ラベルは必須"

# ============================================
# 8. 関連ドキュメント参照
# ============================================
echo ""
echo "--- 8. 関連ドキュメント参照 ---"
assert_file_contains "intent-labels.md 参照"          "$SKILL" "intent-labels.md"
assert_file_contains "conventional-commits.md 参照"   "$SKILL" "conventional-commits.md"

print_test_summary
