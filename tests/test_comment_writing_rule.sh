#!/bin/bash
# test_comment_writing_rule.sh — GitHub コメント作成基準（Issue #631）の整合性テスト
# 使い方: bash tests/test_comment_writing_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CW_RULE="${SCRIPT_DIR}/.claude/rules/comment-writing.md"
COMM_RULE="${SCRIPT_DIR}/.claude/rules/communication.md"
DOC_WRITING="${SCRIPT_DIR}/.claude/rules/document-writing.md"
PROMPT_WRITING="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"
REVIEW_HANDLING="${SCRIPT_DIR}/.claude/rules/review-handling.md"
SEVERITY_CR="${SCRIPT_DIR}/.claude/rules/severity/coderabbit.md"

# ============================================
echo "=== .claude/rules/comment-writing.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/comment-writing.md が存在する" "$CW_RULE"

if [[ ! -f "$CW_RULE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "comment-writing.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== frontmatter で description と paths が指定されている ==="
# ============================================

FIRST_LINE=$(sed -n '1p' "$CW_RULE")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "ファイル先頭が --- で始まる frontmatter（1 行目厳密一致）"
else
  fail "ファイル先頭が --- で始まる frontmatter（1 行目: '${FIRST_LINE}'）"
fi
assert_file_contains "description キーが存在（vibecorp 慣習）" "$CW_RULE" "^description:"
assert_file_contains "paths キーが存在" "$CW_RULE" "^paths:"

# ============================================
echo "=== paths で 3 経路（テンプレ / ワークフロー / スキル）がカバーされている ==="
# ============================================

assert_file_contains "paths に Issue テンプレ (.github/ISSUE_TEMPLATE) が含まれる" "$CW_RULE" '\.github/ISSUE_TEMPLATE/\*\*/\*\.md'
assert_file_contains "paths に PR テンプレ (.github/PULL_REQUEST_TEMPLATE) が含まれる" "$CW_RULE" '\.github/PULL_REQUEST_TEMPLATE/\*\*/\*\.md'
assert_file_contains "paths に PR テンプレ (.github/pull_request_template.md) が含まれる" "$CW_RULE" '\.github/pull_request_template\.md'
assert_file_contains "paths にワークフロー .yml (.github/workflows/**) が含まれる" "$CW_RULE" '\.github/workflows/\*\*/\*\.yml'
assert_file_contains "paths にワークフロー .yaml (.github/workflows/**) が含まれる" "$CW_RULE" '\.github/workflows/\*\*/\*\.yaml'
assert_file_contains "paths にスクリプト (.github/scripts/**/*.sh) が含まれる" "$CW_RULE" '\.github/scripts/\*\*/\*\.sh'
assert_file_contains "paths にスキル (skills/**/SKILL.md) が含まれる" "$CW_RULE" 'skills/\*\*/SKILL\.md'
assert_file_contains "paths に配布版スキル (.claude/skills/**/SKILL.md) が含まれる" "$CW_RULE" '\.claude/skills/\*\*/SKILL\.md'
assert_file_contains "paths に vibecorp-base 配布版スキル (.claude/vibecorp-base/skills/**/SKILL.md) が含まれる" "$CW_RULE" '\.claude/vibecorp-base/skills/\*\*/SKILL\.md'

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトに動作主語と 30 秒ルールが含まれる ==="
# ============================================

assert_file_contains "冒頭に > [!IMPORTANT] コールアウト" "$CW_RULE" "^> \[!IMPORTANT\]"
assert_file_contains "動作主語の明示" "$CW_RULE" "動作主語"
assert_file_contains "30 秒ルールの明示" "$CW_RULE" "30 秒ルール"
assert_file_contains "GitHub コメントが対象であることが明示されている" "$CW_RULE" "GitHub コメント"
assert_file_contains "コード内コメント基準への分離参照" "$CW_RULE" "code-comments\.md"

# ============================================
echo "=== 中核セクション（絵文字付き）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$CW_RULE" "^## 🎯 対象範囲"
assert_file_contains "「読者像」セクション" "$CW_RULE" "^## 👥 読者像"
assert_file_contains "「状態絵文字」セクション" "$CW_RULE" "^## 🎨 状態絵文字"
assert_file_contains "「30 秒ルール」セクション" "$CW_RULE" "^## ⏱️ 30 秒ルール"
assert_file_contains "「判定フロー」セクション" "$CW_RULE" "^## 🧭 判定フロー"
assert_file_contains "「指針（MUST）」セクション" "$CW_RULE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$CW_RULE" "^## ❌ 禁止パターン"

# ============================================
echo "=== GitHub コメント 3 種の節がすべて揃っている ==="
# ============================================

assert_file_contains "「Issue / PR コメント」節" "$CW_RULE" "^## 💬 Issue / PR コメント"
assert_file_contains "「レビューコメント」節" "$CW_RULE" "^## 🔍 レビューコメント"
assert_file_contains "「Bot 通知コメント」節" "$CW_RULE" "^## 🤖 Bot 通知コメント"

# ============================================
echo "=== Bot 通知の機械生成テンプレ例外節がある ==="
# ============================================

assert_file_contains "機械生成テンプレートの例外節がある" "$CW_RULE" "機械生成テンプレート"
assert_file_contains "動作主語適用の対象外であることが明示されている" "$CW_RULE" "動作主語.*対象外\|構造化通知"
assert_file_contains "GitHub ネイティブ自動投稿への言及" "$CW_RULE" "Closes #N via PR"

# ============================================
echo "=== severity マーカー 5 段階がレビュー節に含まれる ==="
# ============================================

assert_file_contains "レビュー節に Critical マーカー" "$CW_RULE" "🔴"
assert_file_contains "レビュー節に Major マーカー" "$CW_RULE" "🟠"
assert_file_contains "レビュー節に Minor マーカー" "$CW_RULE" "🟡"
assert_file_contains "レビュー節に Trivial マーカー" "$CW_RULE" "🔵"
assert_file_contains "レビュー節に Info マーカー" "$CW_RULE" "⚪"

# ============================================
echo "=== 指針（MUST）が 6 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$CW_RULE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 6 ]]; then
  pass "指針（MUST）が 6 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "指針（MUST）が 6 項目未満（${MUST_COUNT} 個検出、6 個以上必要）"
fi

# ============================================
echo "=== 禁止パターンが 6 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$CW_RULE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 6 ]]; then
  pass "禁止パターンが 6 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "禁止パターンが 6 項目未満（${FORBID_COUNT} 個検出、6 個以上必要）"
fi

# ============================================
echo "=== 関連ルールへの参照が貼られている ==="
# ============================================

assert_file_contains "communication.md への参照（動作主語土台）" "$CW_RULE" "communication\.md"
assert_file_contains "document-writing.md への参照（兄弟ルール）" "$CW_RULE" "document-writing\.md"
assert_file_contains "prompt-writing.md への参照（兄弟ルール）" "$CW_RULE" "prompt-writing\.md"
assert_file_contains "review-handling.md への参照（レビュー判定）" "$CW_RULE" "review-handling\.md"
assert_file_contains "severity/coderabbit.md への参照（severity SoT）" "$CW_RULE" "severity/coderabbit\.md"
assert_file_contains "対象外として code-comments.md への参照" "$CW_RULE" "code-comments\.md"
assert_file_contains "markdown.md への参照（フェンス言語指定）" "$CW_RULE" "markdown\.md"

# ============================================
echo "=== 関連ルールが実在する（前提整合） ==="
# ============================================

assert_file_exists "communication.md が実在する" "$COMM_RULE"
assert_file_exists "document-writing.md が実在する" "$DOC_WRITING"
assert_file_exists "prompt-writing.md が実在する" "$PROMPT_WRITING"
assert_file_exists "review-handling.md が実在する" "$REVIEW_HANDLING"
assert_file_exists "severity/coderabbit.md が実在する" "$SEVERITY_CR"

# ============================================
echo "=== コード内コメント基準が code-comments.md に分離されている（#652 完了） ==="
# ============================================

# Issue #652 で comments.md は code-comments.md にリネーム + 拡充されたため、
# GitHub コメント基準（本ルール）とは別ファイルに分離されていることを保証する。
CODE_COMMENTS="${SCRIPT_DIR}/.claude/rules/code-comments.md"
COMMENTS_OLD="${SCRIPT_DIR}/.claude/rules/comments.md"
assert_file_exists "code-comments.md が存在する（#652 のリネーム後）" "$CODE_COMMENTS"
if [[ ! -f "$COMMENTS_OLD" ]]; then
  pass "旧 comments.md が削除されている（#652 のリネーム後）"
else
  fail "旧 comments.md がまだ残っている（#652 のリネーム未完了）"
fi

# ============================================
echo "=== 本体 ↔ 配布元 templates が完全一致する ==="
# ============================================

# `.claude/rules/comment-writing.md`（本体）と `templates/claude/rules/comment-writing.md`
# （配布元）の同期ドリフトを検知する。片方の更新漏れがあると `install.sh --update`
# で利用先プロジェクトに不整合が配布されるため、CI で必ず byte 一致を強制する。
CW_TEMPLATE="${SCRIPT_DIR}/templates/claude/rules/comment-writing.md"
assert_file_exists "templates/claude/rules/comment-writing.md が存在する" "$CW_TEMPLATE"
if cmp -s "$CW_RULE" "$CW_TEMPLATE"; then
  pass "本体 ↔ 配布元 templates の comment-writing.md が完全一致"
else
  fail "本体 ↔ 配布元 templates の comment-writing.md が一致しない（同期されていない）"
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
' "$CW_RULE")
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
' "$CW_RULE" | wc -l | tr -d ' ')

if [[ "$LONG_LINES" -eq 0 ]]; then
  pass "本文中に 1 文 50 文字超の長文がない（自己適用 OK）"
else
  fail "本文中に 1 文 50 文字超の長文が ${LONG_LINES} 件残っている（自己適用違反）"
fi

# ============================================
print_test_summary
