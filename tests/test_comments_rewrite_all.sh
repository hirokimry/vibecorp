#!/bin/bash
# test_comments_rewrite_all.sh — /vibecorp:comments-rewrite-all スキル（Issue #633）の構造テスト
# 用途: skills/comments-rewrite-all/SKILL.md の存在・frontmatter・7 段階動線・基準参照・除外規定を静的検証する
# 使い方: bash tests/test_comments_rewrite_all.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/comments-rewrite-all/SKILL.md"
BASE_SKILL_MD="${SCRIPT_DIR}/.claude/vibecorp-base/skills/comments-rewrite-all/SKILL.md"
CODE_COMMENTS_RULE="${SCRIPT_DIR}/.claude/rules/code-comments.md"

# ============================================
echo "=== skills/comments-rewrite-all/SKILL.md が存在する ==="
# ============================================

assert_file_exists "skills/comments-rewrite-all/SKILL.md が存在する" "$SKILL_MD"

if [[ ! -f "$SKILL_MD" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "SKILL.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 基準ルール .claude/rules/code-comments.md が実在する（前提整合） ==="
# ============================================

assert_file_exists "code-comments.md が実在する" "$CODE_COMMENTS_RULE"

# ============================================
echo "=== frontmatter が正しく書かれている ==="
# ============================================

FIRST_LINE=$(sed -n '1p' "$SKILL_MD")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "ファイル先頭が --- で始まる frontmatter（1 行目厳密一致）"
else
  fail "ファイル先頭が --- で始まる frontmatter（1 行目: '${FIRST_LINE}'）"
fi
assert_file_contains "name キーが comments-rewrite-all" "$SKILL_MD" "^name: comments-rewrite-all$"
assert_file_contains "description キーが存在" "$SKILL_MD" "^description:"

# ============================================
echo "=== description にトリガー語句が 2 個以上含まれる ==="
# ============================================

# 日本語トリガー語句（prompt-writing.md 4 章の MUST: 2 個以上）
assert_file_contains "トリガー語句: /vibecorp:comments-rewrite-all" "$SKILL_MD" "/vibecorp:comments-rewrite-all"
assert_file_contains "トリガー語句: コメント全書き直し" "$SKILL_MD" "コメント全書き直し"
assert_file_contains "トリガー語句: コード内コメント棚卸し" "$SKILL_MD" "コード内コメント棚卸し"
assert_file_contains "「〜と言った時に使用」の定型文" "$SKILL_MD" "と言った時に使用"

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトが存在する ==="
# ============================================

PRE_H2_BLOCK=$(awk '
  /^---$/ { fm++; next }
  fm < 2 { next }
  /^## / { exit }
  { print }
' "$SKILL_MD")
if printf '%s\n' "$PRE_H2_BLOCK" | grep -q '^> \[!IMPORTANT\]'; then
  pass "冒頭（frontmatter 終了〜最初の H2 まで）に > [!IMPORTANT] コールアウト"
else
  fail "冒頭（frontmatter 終了〜最初の H2 まで）に > [!IMPORTANT] コールアウトが存在しない"
fi

# ============================================
echo "=== 中核セクション（絵文字付き）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$SKILL_MD" "^## 🎯 対象範囲"
assert_file_contains "「使用方法」セクション" "$SKILL_MD" "^## 📝 使用方法"
assert_file_contains "「指針（MUST）」セクション" "$SKILL_MD" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$SKILL_MD" "^## ❌ 禁止パターン"
assert_file_contains "「関連」セクション" "$SKILL_MD" "^## 🔗 関連"

# ============================================
echo "=== 7 段階動線（列挙→抽出→照合→提案→承認→書換→レポート）が記述されている ==="
# ============================================

assert_file_contains "ステップ 1: 列挙" "$SKILL_MD" "1️⃣.*列挙"
assert_file_contains "ステップ 2: 抽出" "$SKILL_MD" "2️⃣.*抽出"
assert_file_contains "ステップ 3: 照合" "$SKILL_MD" "3️⃣.*照合"
assert_file_contains "ステップ 4: 提案" "$SKILL_MD" "4️⃣.*提案"
assert_file_contains "ステップ 5: 承認" "$SKILL_MD" "5️⃣.*承認"
assert_file_contains "ステップ 6: 書換" "$SKILL_MD" "6️⃣.*書換"
assert_file_contains "ステップ 7: レポート" "$SKILL_MD" "7️⃣.*レポート"

# 各ステップの本文セクション見出しも存在する
assert_file_contains "## 1️⃣ 列挙 本体セクション" "$SKILL_MD" "^## 1️⃣ 列挙"
assert_file_contains "## 2️⃣ 抽出 本体セクション" "$SKILL_MD" "^## 2️⃣ 抽出"
assert_file_contains "## 3️⃣ 照合 本体セクション" "$SKILL_MD" "^## 3️⃣ 照合"
assert_file_contains "## 4️⃣ 提案 本体セクション" "$SKILL_MD" "^## 4️⃣ 提案"
assert_file_contains "## 5️⃣ 承認 本体セクション" "$SKILL_MD" "^## 5️⃣ 承認"
assert_file_contains "## 6️⃣ 書換 本体セクション" "$SKILL_MD" "^## 6️⃣ 書換"
assert_file_contains "## 7️⃣ レポート 本体セクション" "$SKILL_MD" "^## 7️⃣ レポート"

# ============================================
echo "=== 適用基準（code-comments.md）への参照が貼られている ==="
# ============================================

assert_file_contains "適用基準: code-comments.md" "$SKILL_MD" "code-comments.md"
assert_file_contains "動作主語ルール: communication.md" "$SKILL_MD" "communication.md"
assert_file_contains "shell 規約: shell.md" "$SKILL_MD" "shell\.md"
assert_file_contains "Single Source of Truth の言及" "$SKILL_MD" "Single Source of Truth"

# ============================================
echo "=== diff 提案 → CEO 承認 → 書換の 2 段階が必須化されている ==="
# ============================================

assert_file_contains "diff 提案の明示" "$SKILL_MD" "diff"
assert_file_contains "CEO 承認の明示" "$SKILL_MD" "CEO 承認"
assert_file_contains "2 段階必須の明示" "$SKILL_MD" "2 段階"
assert_file_contains "自動マージ禁止の明示" "$SKILL_MD" "自動マージ.*禁止"

# ============================================
echo "=== 対象拡張子が code-comments.md と整合している ==="
# ============================================

assert_file_contains "対象パス: .sh" "$SKILL_MD" '\*\.sh'
assert_file_contains "対象パス: .js" "$SKILL_MD" '\*\.js'
assert_file_contains "対象パス: .ts" "$SKILL_MD" '\*\.ts'
assert_file_contains "対象パス: .py" "$SKILL_MD" '\*\.py'

# ============================================
echo "=== 除外パスが明示されている ==="
# ============================================

assert_file_contains "除外: node_modules" "$SKILL_MD" "node_modules"
assert_file_contains "除外: vendor" "$SKILL_MD" "vendor"
assert_file_contains "除外: 生成コード" "$SKILL_MD" "生成"
assert_file_contains "除外: dist / build" "$SKILL_MD" "dist"

# ============================================
echo "=== full プリセット専用の明示 + autonomous-restrictions 準拠 ==="
# ============================================

assert_file_contains "full プリセット専用" "$SKILL_MD" "full プリセット専用"
assert_file_contains "autonomous-restrictions への参照" "$SKILL_MD" "autonomous-restrictions"

# ============================================
echo "=== コード本体への影響禁止が明文化されている ==="
# ============================================

assert_file_contains "コード挙動改変禁止" "$SKILL_MD" "コード挙動"
assert_file_contains "コメントのみが対象の明示" "$SKILL_MD" "コメントのみ"

# ============================================
echo "=== スキル固有の指針（MUST）が 2 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^### スキル固有の指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$SKILL_MD" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 2 ]]; then
  pass "スキル固有の指針（MUST）が 2 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "スキル固有の指針（MUST）が 2 項目未満（${MUST_COUNT} 個検出、2 個以上必要）"
fi

# ============================================
echo "=== スキル固有の禁止パターンが 3 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$SKILL_MD" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 3 ]]; then
  pass "スキル固有の禁止パターンが 3 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "スキル固有の禁止パターンが 3 項目未満（${FORBID_COUNT} 個検出、3 個以上必要）"
fi

# ============================================
echo "=== レポート出力フォーマットが定義されている ==="
# ============================================

assert_file_contains "レポート: 集計セクション" "$SKILL_MD" "集計"
assert_file_contains "レポート: 採用された書き換え" "$SKILL_MD" "採用された書き換え"
assert_file_contains "レポート: スキップされた項目" "$SKILL_MD" "スキップされた項目"

# ============================================
echo "=== 兄弟スキルへの参照（docs-rewrite-all / prompts-rewrite-all）がある ==="
# ============================================

assert_file_contains "兄弟スキル: /docs-rewrite-all" "$SKILL_MD" "/docs-rewrite-all"
assert_file_contains "兄弟スキル: /prompts-rewrite-all" "$SKILL_MD" "/prompts-rewrite-all"

# ============================================
echo "=== Markdown フェンスに言語指定がある（markdown.md 整合） ==="
# ============================================

NAKED_OPEN=$(awk '
  /^```/ {
    count++
    if (count % 2 == 1 && $0 == "```") { bad++ }
  }
  END { print bad+0 }
' "$SKILL_MD")
if [[ "$NAKED_OPEN" -eq 0 ]]; then
  pass "全開きフェンスに言語指定がある（本体）"
else
  fail "言語指定なしの開きフェンスが ${NAKED_OPEN} 箇所ある（本体）"
fi

# ============================================
echo "=== LLM 行動主語ルール（『〜してください』禁止）に従っている ==="
# ============================================

# 「〜してください」が本文の指示として残っていないか確認
# 除外: コードブロック内 / 日本語括弧「」内に引用された例
NON_CODE_COMMAND=$(awk '
  /^```/ { in_code = !in_code; next }
  in_code { next }
  /してください/ {
    if ($0 !~ /「[^」]*してください[^」]*」/) {
      print NR": "$0
    }
  }
' "$SKILL_MD" | wc -l | tr -d ' ')
if [[ "$NON_CODE_COMMAND" -eq 0 ]]; then
  pass "本体テキストに「〜してください」が残っていない（行動主語ルール準拠）"
else
  fail "本体テキストに「〜してください」が ${NON_CODE_COMMAND} 箇所残っている（行動主語ルール違反）"
fi

# ============================================
echo "=== 配布版（.claude/vibecorp-base/）の検証（ローカル self-install 時のみ） ==="
# ============================================

# .claude/vibecorp-base/ は .claude/.gitignore で除外されたローカルキャッシュ。
# 本体リポジトリで self-install 済みのローカル環境では存在、CI/fresh clone では未生成。
if [[ -f "$BASE_SKILL_MD" ]]; then
  if cmp -s "$SKILL_MD" "$BASE_SKILL_MD"; then
    pass "本体 ↔ 配布版 SKILL.md が完全一致"
  else
    fail "本体 ↔ 配布版 SKILL.md が一致しない（再同期が必要）"
  fi
else
  echo "  SKIP: .claude/vibecorp-base/skills/comments-rewrite-all/SKILL.md が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
print_test_summary
