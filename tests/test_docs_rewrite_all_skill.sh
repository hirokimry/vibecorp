#!/bin/bash
# test_docs_rewrite_all_skill.sh — /vibecorp:docs-rewrite-all スキル（Issue #593）の構造テスト
# 使い方: bash tests/test_docs_rewrite_all_skill.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/docs-rewrite-all/SKILL.md"
BASE_SKILL_MD="${SCRIPT_DIR}/.claude/vibecorp-base/skills/docs-rewrite-all/SKILL.md"

# ============================================
echo "=== skills/docs-rewrite-all/SKILL.md が存在する ==="
# ============================================

assert_file_exists "skills/docs-rewrite-all/SKILL.md が存在する" "$SKILL_MD"

if [[ ! -f "$SKILL_MD" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "SKILL.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== frontmatter が正しく書かれている ==="
# ============================================

assert_file_contains "ファイル先頭が --- で始まる frontmatter" "$SKILL_MD" "^---$"
assert_file_contains "name キーが docs-rewrite-all" "$SKILL_MD" "^name: docs-rewrite-all$"
assert_file_contains "description キーが存在" "$SKILL_MD" "^description:"

# ============================================
echo "=== description にトリガー語句が 2 個以上含まれる ==="
# ============================================

# 日本語トリガー語句（prompt-writing.md 4 章の MUST: 2 個以上）
assert_file_contains "トリガー語句: /docs-rewrite-all" "$SKILL_MD" "/docs-rewrite-all"
assert_file_contains "トリガー語句: ドキュメント全書き直し" "$SKILL_MD" "ドキュメント全書き直し"
assert_file_contains "トリガー語句: ドキュメント棚卸し" "$SKILL_MD" "ドキュメント棚卸し"
assert_file_contains "「〜と言った時に使用」の定型文" "$SKILL_MD" "と言った時に使用"

# ============================================
echo "=== 7 段階動線（列挙→照合→委譲→提案→承認→書換→レポート）が記述されている ==="
# ============================================

assert_file_contains "ステップ 1: 列挙" "$SKILL_MD" "1️⃣.*列挙"
assert_file_contains "ステップ 2: 照合" "$SKILL_MD" "2️⃣.*照合"
assert_file_contains "ステップ 3: 委譲" "$SKILL_MD" "3️⃣.*委譲"
assert_file_contains "ステップ 4: 提案" "$SKILL_MD" "4️⃣.*提案"
assert_file_contains "ステップ 5: 承認" "$SKILL_MD" "5️⃣.*承認"
assert_file_contains "ステップ 6: 書換" "$SKILL_MD" "6️⃣.*書換"
assert_file_contains "ステップ 7: レポート" "$SKILL_MD" "7️⃣.*レポート"

# 各ステップの本文セクション見出しも存在する
assert_file_contains "## 1️⃣ 列挙 本体セクション" "$SKILL_MD" "^## 1️⃣ 列挙"
assert_file_contains "## 2️⃣ 照合 本体セクション" "$SKILL_MD" "^## 2️⃣ 照合"
assert_file_contains "## 3️⃣ 委譲 本体セクション" "$SKILL_MD" "^## 3️⃣ 委譲"
assert_file_contains "## 4️⃣ 提案 本体セクション" "$SKILL_MD" "^## 4️⃣ 提案"
assert_file_contains "## 5️⃣ 承認 本体セクション" "$SKILL_MD" "^## 5️⃣ 承認"
assert_file_contains "## 6️⃣ 書換 本体セクション" "$SKILL_MD" "^## 6️⃣ 書換"
assert_file_contains "## 7️⃣ レポート 本体セクション" "$SKILL_MD" "^## 7️⃣ レポート"

# ============================================
echo "=== 領域別 C*O 委譲が 5 役職分明示されている ==="
# ============================================

assert_file_contains "委譲先: CISO（セキュリティ）" "$SKILL_MD" "CISO"
assert_file_contains "委譲先: CFO（コスト）" "$SKILL_MD" "CFO"
assert_file_contains "委譲先: CTO（技術）" "$SKILL_MD" "CTO"
assert_file_contains "委譲先: CLO（法務）" "$SKILL_MD" "CLO"
assert_file_contains "委譲先: CPO（プロダクト）" "$SKILL_MD" "CPO"

# 領域 → C*O 対応表が明示されている
assert_file_contains "セキュリティ領域 → CISO" "$SKILL_MD" "セキュリティ.*CISO"
assert_file_contains "コスト領域 → CFO" "$SKILL_MD" "コスト.*CFO"
assert_file_contains "法務領域 → CLO" "$SKILL_MD" "法務.*CLO"

# ============================================
echo "=== 適用基準（document-writing.md）への参照が貼られている ==="
# ============================================

assert_file_contains "適用基準: document-writing.md" "$SKILL_MD" "document-writing.md"
assert_file_contains "動作主語ルール: communication.md" "$SKILL_MD" "communication.md"

# ============================================
echo "=== diff 提案 → CEO 承認 → 書換の 2 段階が必須化されている ==="
# ============================================

assert_file_contains "diff 提案の明示" "$SKILL_MD" "diff"
assert_file_contains "CEO 承認の明示" "$SKILL_MD" "CEO 承認"
assert_file_contains "2 段階必須の明示" "$SKILL_MD" "2 段階"
assert_file_contains "自動マージ禁止の明示" "$SKILL_MD" "自動マージ.*禁止"

# ============================================
echo "=== 対象パスが docs/**/*.md + README.md + CHANGELOG.md である ==="
# ============================================

assert_file_contains "対象パス: docs/**/*.md" "$SKILL_MD" 'docs/\*\*/\*\.md'
assert_file_contains "対象パス: README.md" "$SKILL_MD" "README.md"
assert_file_contains "対象パス: CHANGELOG.md" "$SKILL_MD" "CHANGELOG.md"

# ============================================
echo "=== LICENSE が除外対象として明示されている ==="
# ============================================

assert_file_contains "LICENSE 除外の明示" "$SKILL_MD" "LICENSE"
assert_file_contains "除外理由（法的文書）" "$SKILL_MD" "法的文書"

# ============================================
echo "=== レポート出力フォーマットが定義されている ==="
# ============================================

assert_file_contains "レポート: 集計セクション" "$SKILL_MD" "集計"
assert_file_contains "レポート: 採用された書き換え" "$SKILL_MD" "採用された書き換え"
assert_file_contains "レポート: スキップされた項目" "$SKILL_MD" "スキップされた項目"

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
  echo "  SKIP: .claude/vibecorp-base/skills/docs-rewrite-all/SKILL.md が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
print_test_summary
