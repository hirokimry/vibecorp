#!/bin/bash
# test_prompt_writing_rule.sh — プロンプト作成基準（Issue #592）の整合性テスト
# 使い方: bash tests/test_prompt_writing_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PW_RULE="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"
COMM_RULE="${SCRIPT_DIR}/.claude/rules/communication.md"
SELF_CONTAINED_RULE="${SCRIPT_DIR}/.claude/rules/self-contained.md"
USE_SKILLS_RULE="${SCRIPT_DIR}/.claude/rules/use-skills.md"

# ============================================
echo "=== .claude/rules/prompt-writing.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/prompt-writing.md が存在する" "$PW_RULE"

if [[ ! -f "$PW_RULE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "prompt-writing.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== frontmatter で paths が複数指定されている ==="
# ============================================

assert_file_contains "ファイル先頭が --- で始まる frontmatter" "$PW_RULE" "^---$"
assert_file_contains "description キーが存在（vibecorp 慣習）" "$PW_RULE" "^description:"
assert_file_contains "paths キーが存在" "$PW_RULE" "^paths:"
# 必須エントリ群
assert_file_contains "paths に CLAUDE.md（ルート）が含まれる" "$PW_RULE" '"CLAUDE\.md"'
assert_file_contains "paths に .claude/CLAUDE.md が含まれる" "$PW_RULE" '"\.claude/CLAUDE\.md"'
assert_file_contains "paths に MVV.md が含まれる" "$PW_RULE" '"MVV\.md"'
assert_file_contains "paths に .claude/rules/**/*.md が含まれる" "$PW_RULE" '"\.claude/rules/\*\*/\*\.md"'
assert_file_contains "paths に .claude/agents/**/*.md が含まれる" "$PW_RULE" '"\.claude/agents/\*\*/\*\.md"'
assert_file_contains "paths に .claude/knowledge/**/*.md が含まれる" "$PW_RULE" '"\.claude/knowledge/\*\*/\*\.md"'
assert_file_contains "paths に skills/**/SKILL.md が含まれる" "$PW_RULE" '"skills/\*\*/SKILL\.md"'
# 配布版
assert_file_contains "paths に .claude/vibecorp-base/CLAUDE.md が含まれる" "$PW_RULE" '"\.claude/vibecorp-base/CLAUDE\.md"'
assert_file_contains "paths に .claude/vibecorp-base/rules/**/*.md が含まれる" "$PW_RULE" '"\.claude/vibecorp-base/rules/\*\*/\*\.md"'
assert_file_contains "paths に .claude/vibecorp-base/skills/**/SKILL.md が含まれる" "$PW_RULE" '"\.claude/vibecorp-base/skills/\*\*/SKILL\.md"'
# プラグインルート SSOT（Issue #747 で rules も agents 同様にルート SSOT 化）+ 配布元 templates
assert_file_contains "paths に agents/**/*.md が含まれる" "$PW_RULE" '"agents/\*\*/\*\.md"'
assert_file_contains "paths に rules/**/*.md が含まれる" "$PW_RULE" '"rules/\*\*/\*\.md"'
assert_file_contains "paths に templates/claude/knowledge/**/*.md が含まれる" "$PW_RULE" '"templates/claude/knowledge/\*\*/\*\.md"'

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトに claude-code-guide MUST 化が含まれる ==="
# ============================================

assert_file_contains "冒頭に > [!IMPORTANT] コールアウト" "$PW_RULE" "^> \[!IMPORTANT\]"
assert_file_contains "claude-code-guide サブエージェント参照の MUST 化が明記されている" "$PW_RULE" "claude-code-guide"
assert_file_contains "docs.claude.com 公式仕様への参照が明記されている" "$PW_RULE" "docs\.claude\.com"

# ============================================
echo "=== 中核セクション（絵文字付き）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$PW_RULE" "^## 🎯 対象範囲"
assert_file_contains "「claude-code-guide 参照（MUST）」セクション" "$PW_RULE" "^## 📡 claude-code-guide 参照"
assert_file_contains "「YAML frontmatter の書き方」セクション" "$PW_RULE" "^## 📝 YAML frontmatter"
assert_file_contains "「description triggering 設計」セクション" "$PW_RULE" "^## 🪝 description triggering"
assert_file_contains "「役割境界」セクション" "$PW_RULE" "^## 🚧 役割境界"
assert_file_contains "「LLM 行動主語ルール」セクション" "$PW_RULE" "^## 🗣️ LLM 行動主語"
assert_file_contains "「指針（MUST）」セクション" "$PW_RULE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$PW_RULE" "^## ❌ 禁止パターン"
assert_file_contains "「テスト可能性」セクション" "$PW_RULE" "^## 🧪 テスト可能性"

# ============================================
echo "=== claude-code-guide 確認必須トピックが列挙されている ==="
# ============================================

assert_file_contains "Skill triggering トピック" "$PW_RULE" "Skill triggering"
assert_file_contains "Hook event types トピック" "$PW_RULE" "Hook event types"
assert_file_contains "PreToolUse 正式イベント名" "$PW_RULE" "PreToolUse"
assert_file_contains "PostToolUse 正式イベント名" "$PW_RULE" "PostToolUse"
assert_file_contains "UserPromptSubmit 正式イベント名" "$PW_RULE" "UserPromptSubmit"
assert_file_contains "SubAgent context トピック" "$PW_RULE" "SubAgent context"
assert_file_contains "MCP server 設定トピック" "$PW_RULE" "MCP server"
assert_file_contains "mcpServers 正式キー" "$PW_RULE" "mcpServers"
assert_file_contains "settings.json 構造トピック" "$PW_RULE" "settings\.json"

# ============================================
echo "=== 指針（MUST）が 5 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$PW_RULE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 5 ]]; then
  pass "指針（MUST）が 5 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "指針（MUST）が 5 項目未満（${MUST_COUNT} 個検出、5 個以上必要）"
fi

# ============================================
echo "=== 指針 MUST の並び順（重要度順）が反映されている ==="
# ============================================

# 並び順: 1=claude-code-guide, 2=役割境界, 3=frontmatter, 4=triggering, 5=行動主語
assert_file_contains "指針1: claude-code-guide で仕様確認" "$PW_RULE" "^1\. 📡 \*\*claude-code-guide で仕様確認してから書く\*\*"
assert_file_contains "指針2: 役割境界を超えない" "$PW_RULE" "^2\. 🚧 \*\*役割境界を超えない\*\*"
assert_file_contains "指針3: frontmatter は最小限・正確に書く" "$PW_RULE" "^3\. 📝 \*\*frontmatter は最小限・正確に書く\*\*"
assert_file_contains "指針4: description には具体トリガー語句を含める" "$PW_RULE" "^4\. 🪝 \*\*description には具体トリガー語句を含める\*\*"
assert_file_contains "指針5: LLM の行動を主語にする" "$PW_RULE" "^5\. 🗣️ \*\*LLM の行動を主語にする\*\*"

# ============================================
echo "=== 禁止パターンが 5 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$PW_RULE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 5 ]]; then
  pass "禁止パターンが 5 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "禁止パターンが 5 項目未満（${FORBID_COUNT} 個検出、5 個以上必要）"
fi

# ============================================
echo "=== 関連ルールへの整合宣言（communication.md / self-contained.md / use-skills.md） ==="
# ============================================

assert_file_contains "communication.md への参照" "$PW_RULE" "communication\.md"
assert_file_contains "self-contained.md への参照" "$PW_RULE" "self-contained\.md"
assert_file_contains "use-skills.md への参照" "$PW_RULE" "use-skills\.md"

# ============================================
echo "=== 関連ルールが実在する（前提整合） ==="
# ============================================

assert_file_exists "communication.md が実在する" "$COMM_RULE"
assert_file_exists "self-contained.md が実在する" "$SELF_CONTAINED_RULE"
assert_file_exists "use-skills.md が実在する" "$USE_SKILLS_RULE"

# ============================================
echo "=== Markdown フェンスに言語指定がある（markdown.md 整合） ==="
# ============================================

# 開きフェンス（奇数番目の ``` 行）に言語指定があるかを確認
# 閉じフェンスは ``` 単独で正常。1, 3, 5... 番目が開きフェンス
NAKED_OPEN=$(awk '
  /^```/ {
    count++
    if (count % 2 == 1 && $0 == "```") { bad++ }
  }
  END { print bad+0 }
' "$PW_RULE")
if [[ "$NAKED_OPEN" -eq 0 ]]; then
  pass "全開きフェンスに言語指定がある"
else
  fail "言語指定なしの開きフェンスが ${NAKED_OPEN} 箇所ある"
fi

# ============================================
echo "=== 自己適用: 1 文 50 文字超の長文がないことを検証 ==="
# ============================================

# 文字数カウントは perl -CSD で UTF-8 codepoint 数を数える
# （macOS BSD awk は length() がバイト数になるため非互換）
LONG_LINES=$(perl -CSD -nE '
  BEGIN { our ($fm, $code) = (0, 0); }
  chomp;
  if (/^---$/) { $fm = !$fm; next }
  next if $fm;
  if (/^```/) { $code = !$code; next }
  next if $code;
  next if /^[|#>]/;
  next if /^\s*$/;
  my @sents = split /。/, $_, -1;
  for my $i (0 .. $#sents - 1) {
    my $s = $sents[$i];
    $s =~ s/^\s*[-*]\s*//;
    $s =~ s/^\s+//;
    if (length($s) > 50) {
      say "$.: " . length($s) . " chars: " . $s;
    }
  }
' "$PW_RULE" | wc -l | tr -d ' ')

if [[ "$LONG_LINES" -eq 0 ]]; then
  pass "本文中に 1 文 50 文字超の長文がない（自己適用 OK）"
else
  fail "本文中に 1 文 50 文字超の長文が ${LONG_LINES} 件残っている（自己適用違反）"
fi

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
