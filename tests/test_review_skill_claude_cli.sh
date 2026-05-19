#!/bin/bash
# test_review_skill_claude_cli.sh
# ─────────────────────────────────────────────
# Issue #499: skills/review/SKILL.md が Claude Code CLI 直接呼び出しに置換されたかの静的検証
#
# 設計方針:
#   - **構造検証**を中心に据える（frontmatter / 必須見出し / bash 構文）
#   - **4 ガード仕様**は Issue #499 完了条件で明示されているため最小限の文言検証で確認する
#     （`--bare` 不在 / `ANTHROPIC_API_KEY` チェック / `claude -p` / `--allowed-tools`）
#   - cross-file の整合性は「セクション見出し存在」に絞り、特定文言依存を避ける
#
# 実機検証（claude -p 実起動）はコスト・OAuth 認証・ネットワーク依存のため対象外。
# 親エピック #455 検証フェーズ（Issue #475）で実施する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SKILL_FILE="${PROJECT_DIR}/skills/review/SKILL.md"
COST_DOC="${PROJECT_DIR}/docs/cost-analysis.md"
DEP_DOC="${PROJECT_DIR}/docs/ai-review-dependency.md"
KNOWLEDGE_DOC="${PROJECT_DIR}/.claude/knowledge/agents-vs-skills.md"

EXTRACTED_BASH="$(mktemp)"
cleanup() {
  rm -f "$EXTRACTED_BASH" || true
}
trap cleanup EXIT

# ============================================
# ヘルパー: SKILL.md から bash コードブロックを抽出
# ============================================
extract_bash_blocks() {
  awk '
    /^```bash$/ { in_block = 1; next }
    /^```$/ && in_block { in_block = 0; print ""; next }
    in_block { print }
  ' "$SKILL_FILE" > "$EXTRACTED_BASH"
}

echo ""
echo "=== Issue #499 ローカル cr → Claude Code CLI 直接呼び出し置換 静的検証 ==="

# ============================================
# 1. SKILL.md の構造検証
# ============================================
echo ""
echo "--- 1. SKILL.md の構造検証 ---"

assert_file_exists "skills/review/SKILL.md が存在する" "$SKILL_FILE"

# 前提ファイル不在 → 後続テストは全て無意味なので即終了
if [[ ! -f "$SKILL_FILE" ]]; then
  exit 1
fi

# frontmatter が存在する（先頭の `---`）
if [[ "$(head -1 "$SKILL_FILE")" == "---" ]]; then
  pass "SKILL.md が frontmatter で始まる"
else
  fail "SKILL.md が frontmatter で始まらない"
fi

assert_file_contains "frontmatter に name キーが存在する" "$SKILL_FILE" '^name: '

# bash コードブロックを抽出
extract_bash_blocks

if [[ ! -s "$EXTRACTED_BASH" ]]; then
  fail "SKILL.md に bash コードブロックが見つからない"
  exit 1
fi

# bash -n で構文エラーなし（重要な構造検証）
if bash -n "$EXTRACTED_BASH" 2>/dev/null; then
  pass "SKILL.md の bash コードブロックが構文エラーなし"
else
  fail "SKILL.md の bash コードブロックに構文エラーあり"
  bash -n "$EXTRACTED_BASH" >&2 || true
fi

# ============================================
# 2. Issue #499 4 ガード仕様の検証
# ============================================
echo ""
echo "--- 2. Issue #499 4 ガード仕様の検証 ---"

# ガード本体: claude -p 呼び出しが bash ブロックに存在する
if grep -q -e 'claude -p' "$EXTRACTED_BASH"; then
  pass "claude -p 呼び出しが bash ブロックに存在する"
else
  fail "claude -p 呼び出しが bash ブロックに存在しない"
fi

# REVIEW.md がプロンプト経路として参照される
if grep -q -e 'REVIEW\.md' "$EXTRACTED_BASH"; then
  pass "REVIEW.md 参照が bash ブロックに存在する"
else
  fail "REVIEW.md 参照が bash ブロックに存在しない"
fi

# --allowed-tools 指定が存在する
if grep -q -e 'allowed-tools' "$EXTRACTED_BASH"; then
  pass "--allowed-tools 指定が bash ブロックに存在する"
else
  fail "--allowed-tools 指定が bash ブロックに存在しない"
fi

# ガード 1: --bare が claude コマンドラインに含まれない
if grep -E -q '(^|[^a-zA-Z0-9_-])claude([[:space:]]|$).*--bare' "$EXTRACTED_BASH"; then
  fail "ガード1: claude コマンドラインに --bare フラグが含まれている"
else
  pass "ガード1: claude コマンドラインに --bare フラグが含まれない"
fi

# ガード 2: ANTHROPIC_API_KEY 混在 fail-fast（条件式 + exit 1）
if grep -q -e 'ANTHROPIC_API_KEY' "$EXTRACTED_BASH" && grep -q -e 'exit 1' "$EXTRACTED_BASH"; then
  pass "ガード2: ANTHROPIC_API_KEY チェックと exit 1 が bash ブロックに存在する"
else
  fail "ガード2: ANTHROPIC_API_KEY チェックまたは exit 1 が bash ブロックに見つからない"
fi

# 旧経路 `cr review --plain` が bash ブロック内に実行コマンドとして残っていない
# （説明文での歴史的言及は許容、bash 実行コマンドだけを検証）
if grep -q -e 'cr review --plain' "$EXTRACTED_BASH"; then
  fail "bash ブロックに 'cr review --plain' 実行コマンドが残っている"
else
  pass "bash ブロックから 'cr review --plain' 実行コマンドが削除されている"
fi

# ============================================
# 3. cross-file の整合性（セクション見出し存在のみ）
# ============================================
echo ""
echo "--- 3. cross-file セクション見出し存在の確認 ---"

# docs/cost-analysis.md に Issue #499 関連セクションが追加されている（見出し存在のみチェック）
assert_file_exists "docs/cost-analysis.md が存在する" "$COST_DOC"
if grep -E -q '^### .*Issue #499' "$COST_DOC"; then
  pass "docs/cost-analysis.md に Issue #499 関連の見出しが追加されている"
else
  fail "docs/cost-analysis.md に Issue #499 関連の見出しが見つからない"
fi

# docs/ai-review-dependency.md に移行パスセクションが追加されている
assert_file_exists "docs/ai-review-dependency.md が存在する" "$DEP_DOC"
if grep -E -q '^## .*移行パス' "$DEP_DOC"; then
  pass "docs/ai-review-dependency.md に移行パスセクションが追加されている"
else
  fail "docs/ai-review-dependency.md に移行パスセクションが見つからない"
fi

# .claude/knowledge/agents-vs-skills.md に旧 coderabbit-reviewer 能動定義が残っていない
# （Issue #499 完了条件で明示）
assert_file_exists ".claude/knowledge/agents-vs-skills.md が存在する" "$KNOWLEDGE_DOC"
if grep -E -q '^- coderabbit-reviewer:' "$KNOWLEDGE_DOC"; then
  fail "agents-vs-skills.md に旧 '- coderabbit-reviewer:' 能動定義が残っている"
else
  pass "agents-vs-skills.md から旧 '- coderabbit-reviewer:' 能動定義が削除されている"
fi

# ============================================
# 結果サマリ
# ============================================
print_test_summary
