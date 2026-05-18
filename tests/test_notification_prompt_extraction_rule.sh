#!/bin/bash
# test_notification_prompt_extraction_rule.sh — 通知文・プロンプト切り出しルール（Issue #637）の整合性テスト
# 使い方: bash tests/test_notification_prompt_extraction_rule.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NPE_RULE="${SCRIPT_DIR}/.claude/rules/notification-prompt-extraction.md"
COMM_RULE="${SCRIPT_DIR}/.claude/rules/communication.md"
DOC_RULE="${SCRIPT_DIR}/.claude/rules/document-writing.md"
PW_RULE="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"

# ============================================
echo "=== .claude/rules/notification-prompt-extraction.md が存在する ==="
# ============================================

assert_file_exists ".claude/rules/notification-prompt-extraction.md が存在する" "$NPE_RULE"

if [[ ! -f "$NPE_RULE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "notification-prompt-extraction.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== frontmatter で paths が複数指定されている ==="
# ============================================

FIRST_LINE="$(head -n1 "$NPE_RULE")"
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "ファイル先頭が --- で始まる frontmatter"
else
  fail "ファイル先頭が --- ではありません（先頭: ${FIRST_LINE}）"
fi
assert_file_contains "description キーが存在" "$NPE_RULE" "^description:"
assert_file_contains "paths キーが存在" "$NPE_RULE" "^paths:"
# 必須エントリ群（対象範囲: yaml workflow / hook / SKILL.md）
assert_file_contains "paths に .github/workflows/**/*.yml が含まれる" "$NPE_RULE" '"\.github/workflows/\*\*/\*\.yml"'
assert_file_contains "paths に .github/workflows/**/*.yaml が含まれる" "$NPE_RULE" '"\.github/workflows/\*\*/\*\.yaml"'
assert_file_contains "paths に hooks/**/*.sh が含まれる" "$NPE_RULE" '"hooks/\*\*/\*\.sh"'
assert_file_contains "paths に skills/**/SKILL.md が含まれる" "$NPE_RULE" '"skills/\*\*/SKILL\.md"'

# ============================================
echo "=== 冒頭 IMPORTANT コールアウトに本ルールの主旨が含まれる ==="
# ============================================

assert_file_contains "冒頭に > [!IMPORTANT] コールアウト" "$NPE_RULE" "^> \[!IMPORTANT\]"
assert_file_contains "通知文を切り出す主旨が明記されている" "$NPE_RULE" "通知文"
assert_file_contains "プロンプトテンプレを切り出す主旨が明記されている" "$NPE_RULE" "プロンプトテンプレ"
assert_file_contains "兄弟ルール workflow-shell.md への言及" "$NPE_RULE" "workflow-shell\.md"

# ============================================
echo "=== 中核セクション（切り出し閾値 / 配置先 / 命名規約 / 例外 / 禁止パターン）が揃っている ==="
# ============================================

assert_file_contains "「対象範囲」セクション" "$NPE_RULE" "^## 🎯 対象範囲"
assert_file_contains "「切り出し閾値」セクション" "$NPE_RULE" "^## 📏 切り出し閾値"
assert_file_contains "「配置先パスの規約」セクション" "$NPE_RULE" "^## 📂 配置先パス"
assert_file_contains "「命名規約」セクション" "$NPE_RULE" "^## 📝 命名規約"
assert_file_contains "「例外」セクション" "$NPE_RULE" "^## 🚧 例外"
assert_file_contains "「Before / After」セクション" "$NPE_RULE" "^## 🔄 Before / After"
assert_file_contains "「指針（MUST）」セクション" "$NPE_RULE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$NPE_RULE" "^## ❌ 禁止パターン"
assert_file_contains "「テスト可能性」セクション" "$NPE_RULE" "^## 🧪 テスト可能性"
assert_file_contains "「兄弟ルール」セクション" "$NPE_RULE" "^## 🔗 兄弟ルール"

# ============================================
echo "=== 切り出し閾値（行数軸 + 用途軸）が定義されている ==="
# ============================================

assert_file_contains "行数軸の言及" "$NPE_RULE" "行数軸"
assert_file_contains "用途軸の言及" "$NPE_RULE" "用途軸"
assert_file_contains "通知文 3 行以上の閾値" "$NPE_RULE" "3 行以上"
assert_file_contains "プロンプトテンプレ 5 行以上の閾値" "$NPE_RULE" "5 行以上"
assert_file_contains "CEO 通知文の用途軸該当" "$NPE_RULE" "CEO 通知"
assert_file_contains "エージェント呼出プロンプトの用途軸該当" "$NPE_RULE" "エージェント呼出"

# ============================================
echo "=== 規定パス（messages/*.md / prompts/*.md / hooks/messages/*.md）が定義されている ==="
# ============================================

assert_file_contains "GHA workflow 通知文の規定パス" "$NPE_RULE" "\.github/workflows/messages/"
assert_file_contains "スキルプロンプトの規定パス" "$NPE_RULE" "skills/<skill>/prompts/"
assert_file_contains "hook 通知文の規定パス" "$NPE_RULE" "hooks/messages/"

# ============================================
echo "=== 命名プレフィックス（notify- / agent-call- / error-）が定義されている ==="
# ============================================

assert_file_contains "命名プレフィックス notify-" "$NPE_RULE" "notify-"
assert_file_contains "命名プレフィックス agent-call-" "$NPE_RULE" "agent-call-"
assert_file_contains "命名プレフィックス error-" "$NPE_RULE" "error-"
assert_file_contains "命名例 notify-intent-label-missing.md" "$NPE_RULE" "notify-intent-label-missing\.md"
assert_file_contains "命名例 agent-call-cpo.md" "$NPE_RULE" "agent-call-cpo\.md"

# ============================================
echo "=== 例外節（切り出さない対象）が明示されている ==="
# ============================================

assert_file_contains "1〜2 行の単純通知が例外として明示" "$NPE_RULE" "1〜2 行"
assert_file_contains "動的生成文が例外として明示" "$NPE_RULE" "動的生成"
assert_file_contains "デバッグ出力が例外として明示" "$NPE_RULE" "デバッグ"

# ============================================
echo "=== 指針（MUST）が 5 項目ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$NPE_RULE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 5 ]]; then
  pass "指針（MUST）が 5 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "指針（MUST）が 5 項目未満（${MUST_COUNT} 個検出、5 個以上必要）"
fi

# ============================================
echo "=== 禁止パターンが 5 項目以上ある ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$NPE_RULE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 5 ]]; then
  pass "禁止パターンが 5 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "禁止パターンが 5 項目未満（${FORBID_COUNT} 個検出、5 個以上必要）"
fi

# ============================================
echo "=== 関連ルールへの整合宣言（communication.md / document-writing.md / prompt-writing.md） ==="
# ============================================

assert_file_contains "communication.md への参照" "$NPE_RULE" "communication\.md"
assert_file_contains "document-writing.md への参照" "$NPE_RULE" "document-writing\.md"
assert_file_contains "prompt-writing.md への参照" "$NPE_RULE" "prompt-writing\.md"
assert_file_contains "workflow-shell.md への参照（兄弟ルール）" "$NPE_RULE" "workflow-shell\.md"

# ============================================
echo "=== 関連ルールが実在する（前提整合） ==="
# ============================================

assert_file_exists "communication.md が実在する" "$COMM_RULE"
assert_file_exists "document-writing.md が実在する" "$DOC_RULE"
assert_file_exists "prompt-writing.md が実在する" "$PW_RULE"
# 注: workflow-shell.md は本 base ブランチ（feature/epic-636）には未取り込み（main 由来）。
# 将来 main 取り込み or リリース時に解決される前提のため、ここでは存在チェックを行わない。

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
' "$NPE_RULE")
if [[ "$NAKED_OPEN" -eq 0 ]]; then
  pass "全開きフェンスに言語指定がある"
else
  fail "言語指定なしの開きフェンスが ${NAKED_OPEN} 箇所ある"
fi

# ============================================
echo "=== 結果サマリ ==="
# ============================================

print_test_summary
