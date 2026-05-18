#!/bin/bash
# test_code_comments_rule.sh — コード内コメント基準（Issue #652）の整合性テスト
# 使い方: bash tests/test_code_comments_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CC_RULE="${SCRIPT_DIR}/.claude/rules/code-comments.md"
OLD_RULE="${SCRIPT_DIR}/.claude/rules/comments.md"
DOC_WRITING="${SCRIPT_DIR}/.claude/rules/document-writing.md"
PROMPT_WRITING="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"
COMM_RULE="${SCRIPT_DIR}/.claude/rules/communication.md"

# ============================================
echo "=== .claude/rules/code-comments.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/code-comments.md が存在する" "$CC_RULE"

if [[ ! -f "$CC_RULE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "code-comments.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 旧 comments.md が削除されている ==="
# ============================================

if [[ ! -f "$OLD_RULE" ]]; then
  pass "旧 .claude/rules/comments.md が削除されている"
else
  fail "旧 .claude/rules/comments.md がまだ残っている（リネーム未完了）"
fi

# templates 側も削除されているか
TEMPLATE_OLD="${SCRIPT_DIR}/templates/claude/rules/comments.md"
TEMPLATE_NEW="${SCRIPT_DIR}/templates/claude/rules/code-comments.md"
if [[ ! -f "$TEMPLATE_OLD" ]]; then
  pass "旧 templates/claude/rules/comments.md が削除されている"
else
  fail "旧 templates/claude/rules/comments.md がまだ残っている"
fi
assert_file_exists "templates/claude/rules/code-comments.md が存在する" "$TEMPLATE_NEW"

# ============================================
echo "=== frontmatter で paths が指定されている ==="
# ============================================

assert_file_contains "ファイル先頭が --- で始まる frontmatter" "$CC_RULE" "^---$"
assert_file_contains "description キーが存在" "$CC_RULE" "^description:"
assert_file_contains "paths キーが存在" "$CC_RULE" "^paths:"

# 主要な言語パスが含まれる（最低 5 言語）
assert_file_contains "paths に **/*.sh が含まれる" "$CC_RULE" '"\*\*/\*\.sh"'
assert_file_contains "paths に **/*.ts が含まれる" "$CC_RULE" '"\*\*/\*\.ts"'
assert_file_contains "paths に **/*.js が含まれる" "$CC_RULE" '"\*\*/\*\.js"'
assert_file_contains "paths に **/*.py が含まれる" "$CC_RULE" '"\*\*/\*\.py"'
assert_file_contains "paths に **/*.rb が含まれる" "$CC_RULE" '"\*\*/\*\.rb"'

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトに default to no comments が含まれる ==="
# ============================================

assert_file_contains "冒頭に > [!IMPORTANT] コールアウト" "$CC_RULE" "^> \[!IMPORTANT\]"
assert_file_contains "default to no comments の MUST 化" "$CC_RULE" "デフォルトはコメントを書かない"
assert_file_contains "WHY が非自明な時のみ" "$CC_RULE" "WHY が非自明"

# ============================================
echo "=== 中核セクション（絵文字付き）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$CC_RULE" "^## 🎯 対象範囲"
assert_file_contains "「動作主語と WHY」セクション" "$CC_RULE" "^## 🗣️ 動作主語と WHY"
assert_file_contains "「指針（MUST）」セクション" "$CC_RULE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$CC_RULE" "^## ❌ 禁止パターン"
assert_file_contains "「言語別の節」セクション" "$CC_RULE" "^## 📚 言語別"

# ============================================
echo "=== 言語別節に主要言語が含まれている ==="
# ============================================

assert_file_contains "bash / shell の節" "$CC_RULE" "^### 🐚 bash"
assert_file_contains "TypeScript / JavaScript の節" "$CC_RULE" "^### 📜 TypeScript"
assert_file_contains "Python の節" "$CC_RULE" "^### 🐍 Python"
assert_file_contains "Ruby の節" "$CC_RULE" "^### 💎 Ruby"
assert_file_contains "Rust / Go その他の節" "$CC_RULE" "^### 🦀 Rust"
assert_file_contains "設定ファイルの節" "$CC_RULE" "^### ⚙️ 設定ファイル"

# ============================================
echo "=== 指針（MUST）が 6 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$CC_RULE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 6 ]]; then
  pass "指針（MUST）が 6 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "指針（MUST）が 6 項目未満（${MUST_COUNT} 個検出、6 個以上必要）"
fi

# ============================================
echo "=== 指針 MUST の中核項目が含まれる ==="
# ============================================

assert_file_contains "指針: default to no comments" "$CC_RULE" "default to no comments"
assert_file_contains "指針: WHY を書く（WHAT を書かない）" "$CC_RULE" "WHY を書く"
assert_file_contains "指針: 出所をリンクする" "$CC_RULE" "出所をリンクする"
assert_file_contains "指針: コードと一致させる" "$CC_RULE" "コードと一致させる"
assert_file_contains "指針: 言語は日本語で書く" "$CC_RULE" "日本語で書く"

# ============================================
echo "=== 禁止パターンが 6 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$CC_RULE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 6 ]]; then
  pass "禁止パターンが 6 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "禁止パターンが 6 項目未満（${FORBID_COUNT} 個検出、6 個以上必要）"
fi

# ============================================
echo "=== 禁止パターンの中核項目が含まれる ==="
# ============================================

assert_file_contains "禁止: WHAT の繰り返し" "$CC_RULE" "WHAT の繰り返し"
assert_file_contains "禁止: 誤解を招くコメント" "$CC_RULE" "誤解を招くコメント"
assert_file_contains "禁止: コメントアウトされたコード" "$CC_RULE" "コメントアウトされたコード"

# ============================================
echo "=== 関連ルールへの参照が貼られている ==="
# ============================================

assert_file_contains "document-writing.md への参照" "$CC_RULE" "document-writing\.md"
assert_file_contains "prompt-writing.md への参照" "$CC_RULE" "prompt-writing\.md"
assert_file_contains "communication.md への参照" "$CC_RULE" "communication\.md"
assert_file_contains "markdown.md への参照" "$CC_RULE" "markdown\.md"
assert_file_contains "shell.md への参照" "$CC_RULE" "shell\.md"

# ============================================
echo "=== 関連ルールが実在する（前提整合） ==="
# ============================================

assert_file_exists "document-writing.md が実在する" "$DOC_WRITING"
assert_file_exists "prompt-writing.md が実在する" "$PROMPT_WRITING"
assert_file_exists "communication.md が実在する" "$COMM_RULE"

# ============================================
echo "=== 本体 ↔ 配布元 templates が完全一致する ==="
# ============================================

if cmp -s "$CC_RULE" "$TEMPLATE_NEW"; then
  pass "本体 ↔ 配布元 templates の code-comments.md が完全一致"
else
  fail "本体 ↔ 配布元 templates の code-comments.md が一致しない（同期されていない）"
fi

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
' "$CC_RULE")
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
' "$CC_RULE" | wc -l | tr -d ' ')

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
