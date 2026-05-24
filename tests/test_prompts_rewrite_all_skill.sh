#!/bin/bash
# test_prompts_rewrite_all_skill.sh — /vibecorp:prompts-rewrite-all スキル新設（Issue #594）の静的検証
# 使い方: bash tests/test_prompts_rewrite_all_skill.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SCRIPT_DIR}/skills/prompts-rewrite-all/SKILL.md"
DIST_SKILL_FILE="${SCRIPT_DIR}/.claude/vibecorp-base/skills/prompts-rewrite-all/SKILL.md"
PROMPT_WRITING_RULE="${SCRIPT_DIR}/.claude/rules/prompt-writing.md"
# Issue #642: claude-code-guide 呼出プロンプト本体は skills/prompts-rewrite-all/prompts/agent-call-claude-code-guide-check.md に切り出された
SKILL_ALL="$(mktemp -t prompts_rewrite_all_skill_all.XXXXXX)"
trap 'rm -f "$SKILL_ALL" || true' EXIT
cat "${SCRIPT_DIR}/skills/prompts-rewrite-all/SKILL.md" "${SCRIPT_DIR}"/skills/prompts-rewrite-all/prompts/*.md > "$SKILL_ALL" 2>/dev/null || true

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
echo "=== 配布版 .claude/vibecorp-base/skills/prompts-rewrite-all/SKILL.md の同期確認 ==="
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
echo "=== frontmatter が最小限・正確に書かれている ==="
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
# grep -o は 0 件時に exit 1 を返す。set -euo pipefail 配下では pipefail で
# パイプ全体が失敗扱いとなり、件数判定の if に到達する前にスクリプトが終了する。
# || true でパイプ全体の失敗を無害化し、0 件を正常に fail 判定へ流す。
TRIGGER_IN_DESC=$(awk '/^description:/,/^---$/' "$SKILL_FILE" | grep -o '「[^」]\+」' | wc -l | tr -d ' ' || true)
if [[ "$TRIGGER_IN_DESC" -ge 2 ]]; then
  pass "description にトリガー語句が 2 個以上ある（${TRIGGER_IN_DESC} 個検出）"
else
  fail "description にトリガー語句が 2 個未満（${TRIGGER_IN_DESC} 個検出、2 個以上必要）"
fi

assert_file_contains "description に対象オブジェクト 'skills'" "$SKILL_FILE" "skills/\*\*/SKILL\.md"
assert_file_contains "description に主務動詞「書き直し」" "$SKILL_FILE" "書き直し"

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
assert_file_contains "「ワークフロー」セクション" "$SKILL_FILE" "^## 🔁 ワークフロー"
assert_file_contains "「指針（MUST）」セクション" "$SKILL_FILE" "^## ✅ 指針"
assert_file_contains "「禁止パターン」セクション" "$SKILL_FILE" "^## ❌ 禁止パターン"
assert_file_contains "「関連」セクション" "$SKILL_FILE" "^## 🔗 関連"

# ============================================
echo "=== ワークフロー 9 ステップが揃っている ==="
# ============================================

assert_file_contains "ステップ 1: 対象ファイル列挙" "$SKILL_FILE" "^### 1\. 対象ファイル列挙"
assert_file_contains "ステップ 2: 基準ファイル特定" "$SKILL_FILE" "^### 2\. 基準ファイル特定"
assert_file_contains "ステップ 3: claude-code-guide サブエージェント呼出" "$SKILL_FILE" "^### 3\. 📡 claude-code-guide サブエージェント呼出"
assert_file_contains "ステップ 4: 基準照合" "$SKILL_FILE" "^### 4\. 🔍 基準照合"
assert_file_contains "ステップ 5: 書き直し提案" "$SKILL_FILE" "^### 5\. 書き直し提案"
assert_file_contains "ステップ 6: diff を CEO に提示" "$SKILL_FILE" "^### 6\. 🛑 diff を CEO に提示"
assert_file_contains "ステップ 7: 承認後にファイル書き換え" "$SKILL_FILE" "^### 7\. 承認後にファイル書き換え"
assert_file_contains "ステップ 8: 配布版同期チェック" "$SKILL_FILE" "^### 8\. 📦 配布版同期チェック"
assert_file_contains "ステップ 9: レポート出力" "$SKILL_FILE" "^### 9\. レポート出力"

# ============================================
echo "=== claude-code-guide サブエージェント呼出が MUST 化されている ==="
# ============================================

assert_file_contains "claude-code-guide への参照" "$SKILL_FILE" "claude-code-guide"
assert_file_contains "ステップ 3 で MUST 表記" "$SKILL_FILE" "claude-code-guide サブエージェント呼出（MUST）"
assert_file_contains "docs.claude.com 公式仕様への参照" "$SKILL_FILE" "docs\.claude\.com"
assert_file_contains "確認トピックは prompt-writing.md の参照に集約" "$SKILL_ALL" "確認必須トピック"
assert_file_contains "claude-code-guide フォールバック（WebFetch 直参照）" "$SKILL_FILE" "WebFetch"
assert_file_contains "完全省略禁止の宣言" "$SKILL_FILE" "完全省略は禁止"

# ============================================
echo "=== 基準照合がスキル動線に含まれている（prompt-writing.md を SoT として参照） ==="
# ============================================

assert_file_contains "基準照合セクション" "$SKILL_FILE" "基準照合"
assert_file_contains "prompt-writing.md の指針 MUST を SoT として参照" "$SKILL_FILE" "指針 MUST"
assert_file_contains "prompt-writing.md の禁止パターンを SoT として参照" "$SKILL_FILE" "禁止パターン"
assert_file_contains "スキル側で照合項目を重複定義しないことを明文化" "$SKILL_FILE" "Single Source of Truth"

# ============================================
echo "=== diff 提案 → CEO 承認 → 書き換えの 2 段階が明示されている ==="
# ============================================

assert_file_contains "diff 提案の言及" "$SKILL_FILE" "diff 提案"
assert_file_contains "CEO 承認の言及" "$SKILL_FILE" "CEO 承認"
assert_file_contains "承認ゲートの宣言" "$SKILL_FILE" "承認ゲート"
assert_file_contains "自動マージ禁止の宣言" "$SKILL_FILE" "自動マージ"
assert_file_contains "「CEO 承認なしに本体ファイルを書き換えない」明文化" "$SKILL_FILE" "CEO 承認なしに本体ファイルを書き換えない"

# ============================================
echo "=== 配布版同期チェックが動線に含まれている ==="
# ============================================

assert_file_contains "配布版同期セクション" "$SKILL_FILE" "配布版同期"
assert_file_contains ".claude/vibecorp-base/skills への同期" "$SKILL_FILE" "\.claude/vibecorp-base/skills"
assert_file_contains "agents への同期" "$SKILL_FILE" "agents/\*\.md"
assert_file_contains "templates/claude/rules への同期" "$SKILL_FILE" "templates/claude/rules"

# ============================================
echo "=== 対象ファイル列挙（skills / agents / rules）が動線に含まれている ==="
# ============================================

assert_file_contains "対象に skills/**/SKILL.md" "$SKILL_FILE" "skills/\*\*/SKILL\.md"
assert_file_contains "対象に .claude/agents/*.md" "$SKILL_FILE" "\.claude/agents/\*\.md"
assert_file_contains "対象に .claude/rules/*.md" "$SKILL_FILE" "\.claude/rules/\*\.md"

# ============================================
echo "=== スキル固有の指針（MUST）が 2 項目以上ある（プロンプト本体規約は prompt-writing.md 参照） ==="
# ============================================

MUST_COUNT=$(awk '/^## ✅ 指針/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\. /' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$MUST_COUNT" -ge 2 ]]; then
  pass "スキル固有の指針（MUST）が 2 項目以上ある（${MUST_COUNT} 個検出）"
else
  fail "スキル固有の指針（MUST）が 2 項目未満（${MUST_COUNT} 個検出、2 個以上必要）"
fi

assert_file_contains "指針セクションが prompt-writing.md を参照" "$SKILL_FILE" "プロンプト書き方そのものの指針.*prompt-writing\.md"

# ============================================
echo "=== スキル固有の禁止パターンが 3 項目以上ある（プロンプト本体規約は prompt-writing.md 参照） ==="
# ============================================

FORBID_COUNT=$(awk '/^## ❌ 禁止パターン/{flag=1; next} /^## /{flag=0} flag && /^- ❌/' "$SKILL_FILE" | wc -l | tr -d ' ')
if [[ "$FORBID_COUNT" -ge 3 ]]; then
  pass "スキル固有の禁止パターンが 3 項目以上ある（${FORBID_COUNT} 個検出）"
else
  fail "スキル固有の禁止パターンが 3 項目未満（${FORBID_COUNT} 個検出、3 個以上必要）"
fi

# ============================================
echo "=== 関連ルールへの参照（prompt-writing.md / communication.md / markdown.md） ==="
# ============================================

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
echo "=== 配布版が本体とほぼ同期している（dev 環境配置時のみ検証） ==="
# ============================================

if [[ "$DIST_AVAILABLE" -eq 1 ]]; then
  assert_file_contains "配布版の name キーが prompts-rewrite-all" "$DIST_SKILL_FILE" "^name: prompts-rewrite-all$"
  assert_file_contains "配布版にも claude-code-guide MUST 参照" "$DIST_SKILL_FILE" "claude-code-guide サブエージェント呼出（MUST）"
  assert_file_contains "配布版にも 基準照合" "$DIST_SKILL_FILE" "基準照合"
  assert_file_contains "配布版にも 配布版同期" "$DIST_SKILL_FILE" "配布版同期"
  assert_file_contains "配布版にも 自動マージ禁止" "$DIST_SKILL_FILE" "自動マージ"
  assert_file_contains "配布版コマンド表記は /prompts-rewrite-all（vibecorp 接頭辞なし）" "$DIST_SKILL_FILE" "^/prompts-rewrite-all"
fi

# ============================================
echo "=== LLM 行動主語ルール（『〜してください』禁止）に従っている ==="
# ============================================

# 「〜してください」が本文の指示として残っていないか確認
# 除外: コードブロック内（claude-code-guide 依頼テンプレ等）
# 除外: 日本語括弧「」内に引用された例（禁止パターン説明等）
NON_CODE_COMMAND=$(awk '
  /^```/ { in_code = !in_code; next }
  in_code { next }
  /してください/ {
    # 「〜してください」が日本語括弧「」内に引用されている場合は除外
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
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
