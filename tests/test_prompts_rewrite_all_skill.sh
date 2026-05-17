#!/bin/bash
# test_prompts_rewrite_all_skill.sh — /vibecorp:prompts-rewrite-all スキル新設（Issue #594）の静的検証
# 使い方: bash tests/test_prompts_rewrite_all_skill.sh
# CI: GitHub Actions で自動実行
#
# 設計方針（PR #615 改修）: 構造検証中心（frontmatter / セクション / ステップ見出し / カウント / パス参照）。
# 具体文言の grep は最小限。Phase C の SKILL.md 書き直しで CI が壊れない構造に寄せる。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SCRIPT_DIR}/skills/prompts-rewrite-all/SKILL.md"
DIST_SKILL_FILE="${SCRIPT_DIR}/.claude/vibecorp-base/skills/prompts-rewrite-all/SKILL.md"
PROMPT_WRITING_RULE="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"

# ============================================
echo "=== skills/prompts-rewrite-all/SKILL.md が存在する ==="
# ============================================

assert_file_exists "skills/prompts-rewrite-all/SKILL.md が存在する" "$SKILL_FILE"

if [[ ! -f "$SKILL_FILE" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md 規約）
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "SKILL.md が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 配布版 .claude/vibecorp-base/skills/prompts-rewrite-all/SKILL.md の存在判定 ==="
# ============================================

# 配布版（.claude/vibecorp-base/skills/）は install.sh が install/update 時に
# 本体（skills/）から自動同期する snapshot。`.claude/.gitignore` で除外されており
# 直接コミットしない。ローカル dev 環境で手動配置されている場合のみ整合性を検証する。

DIST_AVAILABLE=0
if [[ -f "$DIST_SKILL_FILE" ]]; then
  DIST_AVAILABLE=1
  pass "配布版 SKILL.md がローカル配置されている（dev 環境向け検証を実行）"
else
  echo "  SKIP: 配布版 SKILL.md は未配置（gitignore 対象、install.sh が自動同期）"
fi

# ============================================
echo "=== 基準ルール .claude/rules/prompt-writing.md が実在する（前提整合） ==="
# ============================================

assert_file_exists "prompt-writing.md が実在する" "$PROMPT_WRITING_RULE"

# ============================================
echo "=== frontmatter 構造が最小限・正確 ==="
# ============================================

FIRST_LINE=$(sed -n '1p' "$SKILL_FILE")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "ファイル先頭が --- で始まる frontmatter（1 行目厳密一致）"
else
  fail "ファイル先頭が --- で始まる frontmatter（1 行目: '${FIRST_LINE}'）"
fi
assert_file_contains "name キーが prompts-rewrite-all" "$SKILL_FILE" "^name: prompts-rewrite-all$"
assert_file_contains "description キーが存在" "$SKILL_FILE" "^description:"

# ============================================
echo "=== description にトリガー語句が 2 個以上含まれている ==="
# ============================================

# description 行から「...」で囲まれたトリガー語句を抽出（先頭近辺）
TRIGGER_IN_DESC=$(awk '/^description:/,/^---$/' "$SKILL_FILE" | grep -o '「[^」]\+」' | wc -l | tr -d ' ')
if [[ "$TRIGGER_IN_DESC" -ge 2 ]]; then
  pass "description にトリガー語句が 2 個以上ある（${TRIGGER_IN_DESC} 個検出）"
else
  fail "description にトリガー語句が 2 個未満（${TRIGGER_IN_DESC} 個検出、2 個以上必要）"
fi

# ============================================
echo "=== 対象パス（skills / agents / rules）が記載されている ==="
# ============================================

# 構造検証: 対象パス文字列が SKILL.md のどこかに存在すれば OK（章立てや文言は問わない）
assert_file_contains "対象に skills/**/SKILL.md パス記載" "$SKILL_FILE" "skills/\*\*/SKILL\.md"
assert_file_contains "対象に .claude/agents/*.md パス記載" "$SKILL_FILE" "\.claude/agents/\*\.md"
assert_file_contains "対象に .claude/rules/*.md パス記載" "$SKILL_FILE" "\.claude/rules/\*\.md"

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
echo "=== H2 セクションが 6 個以上ある（構造検証） ==="
# ============================================

# 中核セクション（対象範囲 / 使用方法 / ワークフロー / 指針 / 禁止パターン / 関連 等）が
# 揃っているかを件数で構造検証する。個別の見出し文言には依存しない。
H2_COUNT=$(grep -c '^## ' "$SKILL_FILE" || true)
if [[ "$H2_COUNT" -ge 6 ]]; then
  pass "H2 セクションが 6 個以上ある（${H2_COUNT} 個検出）"
else
  fail "H2 セクションが 6 個未満（${H2_COUNT} 個検出、6 個以上必要）"
fi

# ============================================
echo "=== ワークフローステップ（番号付き H3）が 9 個以上ある ==="
# ============================================

# 番号付き H3（### 1. ... 〜 ### 9. ...）の件数で構造検証する。個別ステップ名には依存しない。
H3_NUMBERED_COUNT=$(grep -cE '^### [0-9]+\.' "$SKILL_FILE" || true)
if [[ "$H3_NUMBERED_COUNT" -ge 9 ]]; then
  pass "番号付き H3（ワークフローステップ）が 9 個以上ある（${H3_NUMBERED_COUNT} 個検出）"
else
  fail "番号付き H3 が 9 個未満（${H3_NUMBERED_COUNT} 個検出、9 個以上必要）"
fi

# ============================================
echo "=== claude-code-guide サブエージェントへの参照が存在する（構造検証） ==="
# ============================================

# 必須参照ルールの構造的存在のみ確認。具体文言（「完全省略は禁止」等）の grep は外す。
assert_file_contains "claude-code-guide への参照" "$SKILL_FILE" "claude-code-guide"

# ============================================
echo "=== スキル固有の指針（MUST）が 2 項目以上ある ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 2 ]]; then
  pass "スキル固有の指針（MUST）が 2 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "スキル固有の指針（MUST）が 2 項目未満（${MUST_COUNT} 個検出、2 個以上必要）"
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
echo "=== 関連ルールファイル名への参照（prompt-writing.md / communication.md / markdown.md） ==="
# ============================================

# ファイル名による参照存在のみ構造検証。参照テキスト・章立ては問わない。
assert_file_contains "prompt-writing.md への参照" "$SKILL_FILE" "prompt-writing\.md"
assert_file_contains "communication.md への参照" "$SKILL_FILE" "communication\.md"
assert_file_contains "markdown.md への参照" "$SKILL_FILE" "markdown\.md"

# ============================================
echo "=== Markdown フェンスに言語指定がある（markdown.md 整合） ==="
# ============================================

# 開きフェンス（奇数番目の ``` 行）に言語指定があるかを確認
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

if [[ "$DIST_AVAILABLE" -eq 1 ]]; then
  NAKED_OPEN_DIST=$(awk '
    /^```/ {
      count++
      if (count % 2 == 1 && $0 == "```") { bad++ }
    }
    END { print bad+0 }
  ' "$DIST_SKILL_FILE")
  if [[ "$NAKED_OPEN_DIST" -eq 0 ]]; then
    pass "全開きフェンスに言語指定がある（配布版）"
  else
    fail "言語指定なしの開きフェンスが ${NAKED_OPEN_DIST} 箇所ある（配布版）"
  fi
fi

# ============================================
echo "=== 配布版が本体と構造的に同期している（dev 環境配置時のみ） ==="
# ============================================

# 構造検証のみ（name 一致 / H2 件数 / 開きフェンス言語指定）。具体文言は問わない。
if [[ "$DIST_AVAILABLE" -eq 1 ]]; then
  assert_file_contains "配布版の name キーが prompts-rewrite-all" "$DIST_SKILL_FILE" "^name: prompts-rewrite-all$"

  DIST_H2_COUNT=$(grep -c '^## ' "$DIST_SKILL_FILE" || true)
  if [[ "$DIST_H2_COUNT" -ge 6 ]]; then
    pass "配布版に H2 セクションが 6 個以上ある（${DIST_H2_COUNT} 個検出）"
  else
    fail "配布版の H2 セクションが 6 個未満（${DIST_H2_COUNT} 個検出）"
  fi
fi

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
