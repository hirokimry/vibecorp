#!/bin/bash
# test_prompts_extract_all_skill.sh — /vibecorp:prompts-extract-all スキル新設（Issue #645）の静的検証
# 使い方: bash tests/test_prompts_extract_all_skill.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SCRIPT_DIR}/skills/prompts-extract-all/SKILL.md"
DIST_SKILL_FILE="${SCRIPT_DIR}/.claude/vibecorp-base/skills/prompts-extract-all/SKILL.md"
EXTRACTION_RULE="${SCRIPT_DIR}/.claude/rules/notification-prompt-extraction.md"

# ============================================
echo "=== skills/prompts-extract-all/SKILL.md が存在する ==="
# ============================================

assert_file_exists "skills/prompts-extract-all/SKILL.md が存在する" "$SKILL_FILE"

if [[ ! -f "$SKILL_FILE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "SKILL.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 基準ルール .claude/rules/notification-prompt-extraction.md が実在する（前提整合） ==="
# ============================================

assert_file_exists "notification-prompt-extraction.md が実在する" "$EXTRACTION_RULE"

# ============================================
echo "=== frontmatter が正しく書かれている ==="
# ============================================

FIRST_LINE=$(sed -n '1p' "$SKILL_FILE")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "ファイル先頭が --- で始まる frontmatter（1 行目厳密一致）"
else
  fail "ファイル先頭が --- で始まる frontmatter（1 行目: '${FIRST_LINE}'）"
fi
assert_file_contains "name キーが prompts-extract-all" "$SKILL_FILE" "^name: prompts-extract-all$"
assert_file_contains "description キーが存在" "$SKILL_FILE" "^description:"

# ============================================
echo "=== description にトリガー語句が 2 個以上含まれる ==="
# ============================================

TRIGGER_IN_DESC=$(awk '/^description:/,/^---$/' "$SKILL_FILE" | grep -o '「[^」]\+」' | wc -l | tr -d ' ' || true)
if [[ "$TRIGGER_IN_DESC" -ge 2 ]]; then
  pass "description にトリガー語句が 2 個以上ある（${TRIGGER_IN_DESC} 個検出）"
else
  fail "description にトリガー語句が 2 個未満（${TRIGGER_IN_DESC} 個検出、2 個以上必要）"
fi

assert_file_contains "トリガー語句: /prompts-extract-all" "$SKILL_FILE" "/prompts-extract-all"
assert_file_contains "description に主務動詞「切り出す」または「切り出し」" "$SKILL_FILE" "切り出"

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトが存在する ==="
# ============================================

PRE_H2_BLOCK=$(awk '
  /^---$/ { fm++; next }
  fm < 2 { next }
  /^## / { exit }
  { print }
' "$SKILL_FILE")
if printf '%s\n' "$PRE_H2_BLOCK" | grep -q '^> \[!IMPORTANT\]'; then
  pass "冒頭（frontmatter 終了〜最初の H2 まで）に > [!IMPORTANT] コールアウト"
else
  fail "冒頭（frontmatter 終了〜最初の H2 まで）に > [!IMPORTANT] コールアウトが存在しない"
fi

# ============================================
echo "=== 中核セクション（絵文字付き）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$SKILL_FILE" "^## 🎯 対象範囲"
assert_file_contains "「使用方法」セクション" "$SKILL_FILE" "^## 📝 使用方法"
assert_file_contains "「8 段階動線」セクション" "$SKILL_FILE" "^## 🧭 8 段階動線"
assert_file_contains "「除外ルール」セクション" "$SKILL_FILE" "^## 🚧 除外ルール"
assert_file_contains "「自律ループ対象外宣言」セクション" "$SKILL_FILE" "^## 🛡️ 自律ループ対象外宣言"
assert_file_contains "「委譲先エージェント」セクション" "$SKILL_FILE" "^## 🤝 委譲先エージェント"
assert_file_contains "「指針（MUST）」セクション" "$SKILL_FILE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$SKILL_FILE" "^## ❌ 禁止パターン"
assert_file_contains "「関連」セクション" "$SKILL_FILE" "^## 🔗 関連"

# ============================================
echo "=== 8 段階動線（列挙→照合→委譲→提案→承認→書換→配布版同期→レポート）が記述されている ==="
# ============================================

assert_file_contains "ステップ 1: 列挙" "$SKILL_FILE" "1️⃣.*列挙"
assert_file_contains "ステップ 2: 照合" "$SKILL_FILE" "2️⃣.*照合"
assert_file_contains "ステップ 3: 委譲" "$SKILL_FILE" "3️⃣.*委譲"
assert_file_contains "ステップ 4: 提案" "$SKILL_FILE" "4️⃣.*提案"
assert_file_contains "ステップ 5: 承認" "$SKILL_FILE" "5️⃣.*承認"
assert_file_contains "ステップ 6: 書換" "$SKILL_FILE" "6️⃣.*書換"
assert_file_contains "ステップ 7: 配布版同期" "$SKILL_FILE" "7️⃣.*配布版同期"
assert_file_contains "ステップ 8: レポート" "$SKILL_FILE" "8️⃣.*レポート"

# 各ステップの本文セクション見出しも存在する
assert_file_contains "### 1️⃣ 列挙 本体セクション" "$SKILL_FILE" "^### 1️⃣ 列挙"
assert_file_contains "### 2️⃣ 照合 本体セクション" "$SKILL_FILE" "^### 2️⃣ 照合"
assert_file_contains "### 3️⃣ 委譲 本体セクション" "$SKILL_FILE" "^### 3️⃣ 委譲"
assert_file_contains "### 4️⃣ 提案 本体セクション" "$SKILL_FILE" "^### 4️⃣ 提案"
assert_file_contains "### 5️⃣ 承認 本体セクション" "$SKILL_FILE" "^### 5️⃣ 承認"
assert_file_contains "### 6️⃣ 書換 本体セクション" "$SKILL_FILE" "^### 6️⃣ 書換"
assert_file_contains "### 7️⃣ 配布版同期 本体セクション" "$SKILL_FILE" "^### 7️⃣ 配布版同期"
assert_file_contains "### 8️⃣ レポート 本体セクション" "$SKILL_FILE" "^### 8️⃣ レポート"

# ============================================
echo "=== 検出対象（skills/**/SKILL.md）が記述されている ==="
# ============================================

assert_file_contains "検出対象: skills/**/SKILL.md" "$SKILL_FILE" "skills/\*\*/SKILL\.md"
assert_file_contains "検出パターン: text フェンスブロック" "$SKILL_FILE" '```text'
assert_file_contains "検出パターン: markdown フェンスブロック" "$SKILL_FILE" '```markdown'
assert_file_contains "検出手段: awk への言及" "$SKILL_FILE" "awk"
assert_file_contains "検出手段: 行数カウントへの言及" "$SKILL_FILE" "行数"

# ============================================
echo "=== 切り出し先パス規約 skills/<skill>/prompts/<name>.md が記述されている ==="
# ============================================

assert_file_contains "切り出し先: skills/<skill>/prompts/<name>.md" "$SKILL_FILE" "skills/<skill>/prompts/<name>\.md"

# ============================================
echo "=== 除外ルールが明示されている ==="
# ============================================

assert_file_contains "除外: 短いプロンプト（行数閾値未満）" "$SKILL_FILE" "閾値"
assert_file_contains "除外: 動的生成プロンプト" "$SKILL_FILE" "動的生成"
assert_file_contains "除外: 構造要素" "$SKILL_FILE" "構造要素"
assert_file_contains "除外: frontmatter" "$SKILL_FILE" "frontmatter"

# ============================================
echo "=== 自律ループ対象外宣言が記述されている ==="
# ============================================

assert_file_contains "autonomous-restrictions.md への参照" "$SKILL_FILE" "autonomous-restrictions\.md"
assert_file_contains "不可領域 4（ガードレール）への言及" "$SKILL_FILE" "不可領域 4"
assert_file_contains "diagnose-active スタンプへの言及" "$SKILL_FILE" "diagnose-active"
assert_file_contains "CEO 明示起動時のみ動作" "$SKILL_FILE" "CEO 明示起動時のみ動作"
assert_file_contains "自律改善ループの自動実行対象外" "$SKILL_FILE" "自律改善ループ"

# ============================================
echo "=== diff 提案 → CEO 承認 → 書換の 2 段階が必須化されている ==="
# ============================================

assert_file_contains "diff 提案の明示" "$SKILL_FILE" "diff"
assert_file_contains "CEO 承認の明示" "$SKILL_FILE" "CEO 承認"
assert_file_contains "2 段階必須の明示" "$SKILL_FILE" "2 段階"
assert_file_contains "自動マージ禁止の明示" "$SKILL_FILE" "自動マージ.*禁止"
assert_file_contains "「CEO 承認なしに本体ファイルを書き換えない」明文化" "$SKILL_FILE" "CEO 承認なしに本体ファイルを書き換えない"

# ============================================
echo "=== 挙動不変性検証（文字列厳密一致 + テスト全件通過）が動線に含まれている ==="
# ============================================

assert_file_contains "挙動不変性検証の明示" "$SKILL_FILE" "挙動不変性検証"
assert_file_contains "文字列厳密一致への言及" "$SKILL_FILE" "厳密一致"
assert_file_contains "テスト全件通過への言及" "$SKILL_FILE" "テスト全件"

# ============================================
echo "=== 委譲先 CTO が明示されている ==="
# ============================================

assert_file_contains "委譲先: CTO" "$SKILL_FILE" "CTO"
assert_file_contains "CTO 委譲の理由（エージェント呼出 / 技術的判断）" "$SKILL_FILE" "技術"

# ============================================
echo "=== 関連ルールへの参照（notification-prompt-extraction.md / prompt-writing.md / markdown.md） ==="
# ============================================

assert_file_contains "notification-prompt-extraction.md への参照" "$SKILL_FILE" "notification-prompt-extraction\.md"
assert_file_contains "prompt-writing.md への参照" "$SKILL_FILE" "prompt-writing\.md"
assert_file_contains "markdown.md への参照" "$SKILL_FILE" "markdown\.md"
assert_file_contains "兄弟スキル /notifications-extract-all への参照" "$SKILL_FILE" "/notifications-extract-all"

# ============================================
echo "=== スキル固有の指針（MUST）が 3 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 3 ]]; then
  pass "スキル固有の指針（MUST）が 3 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "スキル固有の指針（MUST）が 3 項目未満（${MUST_COUNT} 個検出、3 個以上必要）"
fi

# ============================================
echo "=== スキル固有の禁止パターンが 3 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 3 ]]; then
  pass "スキル固有の禁止パターンが 3 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "スキル固有の禁止パターンが 3 項目未満（${FORBID_COUNT} 個検出、3 個以上必要）"
fi

# ============================================
echo "=== Markdown フェンスに言語指定がある（markdown.md 整合） ==="
# ============================================

NAKED_OPEN=$(awk '
  /^```/ {
    count++
    if (count % 2 == 1 && $0 == "```") { bad++ }
  }
  END { print bad+0 }
' "$SKILL_FILE")
if [[ "$NAKED_OPEN" -eq 0 ]]; then
  pass "全開きフェンスに言語指定がある（本体）"
else
  fail "言語指定なしの開きフェンスが ${NAKED_OPEN} 箇所ある（本体）"
fi

# ============================================
echo "=== LLM 行動主語ルール（『〜してください』禁止）に従っている ==="
# ============================================

NON_CODE_COMMAND=$(awk '
  /^```/ { in_code = !in_code; next }
  in_code { next }
  /してください/ {
    if ($0 !~ /「[^」]*してください[^」]*」/) {
      print NR": "$0
    }
  }
' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$NON_CODE_COMMAND" -eq 0 ]]; then
  pass "本体テキストに「〜してください」が残っていない（行動主語ルール準拠）"
else
  fail "本体テキストに「〜してください」が ${NON_CODE_COMMAND} 箇所残っている（行動主語ルール違反）"
fi

# ============================================
echo "=== 配布版（.claude/vibecorp-base/）の検証（ローカル self-install 時のみ） ==="
# ============================================

if [[ -f "$DIST_SKILL_FILE" ]]; then
  if cmp -s "$SKILL_FILE" "$DIST_SKILL_FILE"; then
    pass "本体 ↔ 配布版 SKILL.md が完全一致"
  else
    fail "本体 ↔ 配布版 SKILL.md が一致しない（再同期が必要）"
  fi
else
  echo "  SKIP: .claude/vibecorp-base/skills/prompts-extract-all/SKILL.md が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
