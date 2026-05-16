#!/bin/bash
# test_document_writing_rule.sh — ドキュメント作成基準（Issue #591）の整合性テスト
# 使い方: bash tests/test_document_writing_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOC_WRITING="${SCRIPT_DIR}/.claude/rules/document-writing.md"
DOCUMENTATION="${SCRIPT_DIR}/.claude/rules/documentation.md"
COMMUNICATION="${SCRIPT_DIR}/.claude/rules/communication.md"

# ============================================
echo "=== .claude/rules/document-writing.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/document-writing.md が存在する" "$DOC_WRITING"

if [[ ! -f "$DOC_WRITING" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "document-writing.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== frontmatter で paths が指定されている ==="
# ============================================

# 先頭が --- で始まる YAML frontmatter
assert_file_contains "ファイル先頭が --- で始まる frontmatter" "$DOC_WRITING" "^---$"
# paths キーが配列形式で **/*.md を含む
assert_file_contains "paths に **/*.md が含まれる" "$DOC_WRITING" 'paths: \["\*\*/\*\.md"\]'
# description キーが存在（vibecorp 慣習）
assert_file_contains "description キーが存在" "$DOC_WRITING" "^description:"

# ============================================
echo "=== 中核 5 セクションが揃っている ==="
# ============================================

assert_file_contains "「読者像と動作主語」セクション" "$DOC_WRITING" "^## 読者像と動作主語"
assert_file_contains "「30 秒スキャン原則」セクション" "$DOC_WRITING" "^## 30 秒スキャン原則"
assert_file_contains "「指針（MUST）」セクション" "$DOC_WRITING" "^## 指針（MUST）"
assert_file_contains "「禁止パターン」セクション" "$DOC_WRITING" "^## 禁止パターン"
assert_file_contains "「ドキュメント種別ごとの差し分け」セクション" "$DOC_WRITING" "^## ドキュメント種別ごとの差し分け"

# ============================================
echo "=== 冒頭コールアウトが含まれる ==="
# ============================================

assert_file_contains "冒頭 IMPORTANT コールアウト" "$DOC_WRITING" '> \[!IMPORTANT\]'
assert_file_contains "可読性最優先の明示" "$DOC_WRITING" "可読性が最優先"

# ============================================
echo "=== 指針 MUST の 7 項目が含まれる ==="
# ============================================

assert_file_contains "指針1: 読者像を冒頭で固定する" "$DOC_WRITING" "読者像を冒頭で固定"
assert_file_contains "指針2: スキャンで要点が掴める構造" "$DOC_WRITING" "スキャンで要点が掴める構造"
assert_file_contains "指針3: マークダウン・絵文字活用" "$DOC_WRITING" "マークダウン・絵文字を最大限活用"
assert_file_contains "指針4: 汎用語彙で書く" "$DOC_WRITING" "汎用語彙で書く"
assert_file_contains "指針5: 設計判断は理由とセット" "$DOC_WRITING" "設計判断は理由とセットで残す"
assert_file_contains "指針6: 1 文 50 文字以下" "$DOC_WRITING" "50 文字以下"
assert_file_contains "指針7: 文末改行 / 箇条書きネスト" "$DOC_WRITING" "文末（句点）で必ず改行"

# ============================================
echo "=== 禁止パターンの 7 項目が含まれる ==="
# ============================================

assert_file_contains "禁止1: 実装詳細の羅列" "$DOC_WRITING" "実装詳細の羅列"
assert_file_contains "禁止2: 形容詞止まり" "$DOC_WRITING" "形容詞止まり"
assert_file_contains "禁止3: 1 段落に複数論点" "$DOC_WRITING" "1 段落に複数論点"
assert_file_contains "禁止4: 装飾だけの絵文字" "$DOC_WRITING" "装飾だけの絵文字"
assert_file_contains "禁止5: 暗黙の前提を残す" "$DOC_WRITING" "暗黙の前提を残す"
assert_file_contains "禁止6: 1 文 50 文字超の長文" "$DOC_WRITING" "1 文 50 文字超"
assert_file_contains "禁止7: 複数文を改行せず連結" "$DOC_WRITING" "複数文を改行せず連結"

# ============================================
echo "=== ドキュメント種別ごとの差し分けの主要項目が含まれる ==="
# ============================================

assert_file_contains "プロジェクト紹介 (README 等) の差し分け" "$DOC_WRITING" "プロジェクト紹介"
assert_file_contains "仕様書の差し分け" "$DOC_WRITING" "仕様書"
assert_file_contains "設計判断 (ADR 等) の差し分け" "$DOC_WRITING" "設計判断"
assert_file_contains "セキュリティ説明の差し分け" "$DOC_WRITING" "セキュリティ説明"
assert_file_contains "変更履歴 (CHANGELOG 等) の差し分け" "$DOC_WRITING" "変更履歴"
assert_file_contains "プロジェクト規範 (MVV 等) の差し分け" "$DOC_WRITING" "プロジェクト規範"

# ============================================
echo "=== documentation.md との相互参照が貼られている ==="
# ============================================

assert_file_exists ".claude/rules/documentation.md が存在する" "$DOCUMENTATION"
assert_file_contains "document-writing.md が documentation.md を参照" "$DOC_WRITING" "documentation.md"
assert_file_contains "documentation.md が document-writing.md を参照" "$DOCUMENTATION" "document-writing.md"

# ============================================
echo "=== communication.md との関連参照が貼られている ==="
# ============================================

assert_file_exists ".claude/rules/communication.md が存在する" "$COMMUNICATION"
assert_file_contains "document-writing.md が communication.md を参照" "$DOC_WRITING" "communication.md"

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
' "$DOC_WRITING" | wc -l | tr -d ' ')

if [[ "$LONG_LINES" -eq 0 ]]; then
  pass "本文中に 1 文 50 文字超の長文がない（自己適用 OK）"
else
  fail "本文中に 1 文 50 文字超の長文が ${LONG_LINES} 件残っている（自己適用違反）"
fi

# ============================================
print_test_summary
