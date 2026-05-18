#!/bin/bash
# test_diagnose_compliance.sh — /vibecorp:diagnose の Claude Code 仕様準拠観点（Issue #324）
# 使い方: bash tests/test_diagnose_compliance.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/diagnose/SKILL.md"
SPEC_MD="${SCRIPT_DIR}/docs/specification.md"
# Issue #642: プロンプト本体は skills/diagnose/prompts/*.md に切り出された
# SKILL.md + prompts/*.md を結合した検査対象ファイルを一時生成する
SKILL_ALL="$(mktemp -t diagnose_compliance_skill_all.XXXXXX)"
trap 'rm -f "$SKILL_ALL" || true' EXIT
cat "${SCRIPT_DIR}/skills/diagnose/SKILL.md" "${SCRIPT_DIR}"/skills/diagnose/prompts/*.md > "$SKILL_ALL" 2>/dev/null || true

# ============================================
echo "=== /vibecorp:diagnose Claude Code 仕様準拠観点 テスト（Issue #324） ==="
# ============================================

# 前提ファイル不在は後続テストを無意味にするため早期終了する（rules/testing.md 準拠）
if [[ ! -f "$SKILL_MD" ]]; then
  fail "SKILL.md が存在しない: $SKILL_MD"
  exit 1
fi
pass "SKILL.md が存在する"

# --- 受入基準 1: 4d セクションが SKILL.md に追加されている ---

echo "--- 4d セクション存在 ---"

assert_file_contains "ステップ 4d 見出しがある" \
  "$SKILL_MD" "4d. Claude Code 仕様準拠分析"

assert_file_contains "claude-code-guide エージェント呼び出し記述がある" \
  "$SKILL_MD" "claude-code-guide"

assert_file_contains "並行実行カウントが 4 に更新されている" \
  "$SKILL_MD" "4つを並行して実行する"

# --- 受入基準 2: 対象ファイル一覧（5 種）が記載されている ---

echo "--- 4d 対象ファイル一覧 ---"

assert_file_contains "対象: .claude/hooks/*.sh" \
  "$SKILL_ALL" '\.claude/hooks/\*\.sh'

assert_file_contains "対象: .claude/skills/*/SKILL.md" \
  "$SKILL_ALL" '\.claude/skills/\*/SKILL\.md'

assert_file_contains "対象: .claude/agents/*.md" \
  "$SKILL_ALL" '\.claude/agents/\*\.md'

assert_file_contains "対象: .claude/settings.json" \
  "$SKILL_ALL" '\.claude/settings\.json'

assert_file_contains "対象: *.mcp.json" \
  "$SKILL_ALL" '\*\.mcp\.json'

# --- 受入基準 3: 検出例が示されている ---

echo "--- 4d 検出例 ---"

assert_file_contains "検出例: 廃止イベント名" \
  "$SKILL_ALL" "廃止イベント名"

assert_file_contains "検出例: 非推奨設定キー" \
  "$SKILL_ALL" "非推奨設定キー"

assert_file_contains "検出例: 新規必須フィールドの未指定" \
  "$SKILL_ALL" "新規必須フィールドの未指定"

# --- 受入基準 4: フォールバック動作（claude-code-guide 利用不可時のスキップ）---

echo "--- 4d フォールバック動作 ---"

assert_file_contains "claude-code-guide 利用不可時のスキップ動作が記載されている" \
  "$SKILL_MD" "claude-code-guide.*利用不可"

assert_file_contains "スキップ時に 4a / 4b / 4c は継続する旨が記載されている" \
  "$SKILL_MD" "4a / 4b / 4c"

# --- 受入基準 5: 4d スコープ限定（仕様ドリフト検出に限定） ---

echo "--- 4d スコープ限定 ---"

assert_file_contains "スコープは仕様ドリフト検出に限定される" \
  "$SKILL_MD" "仕様ドリフト"

assert_file_contains "MVV / プロダクト方針整合は 4c の責務である旨が明記されている" \
  "$SKILL_MD" "4c CPO 分析の責務"

assert_file_contains "技術的負債は 4b の責務である旨が明記されている" \
  "$SKILL_MD" "4b CTO 分析の責務"

# --- 受入基準 6: データ取得方式（GitMCP 非依存・キャッシュなし）---

echo "--- 4d データ取得方式 ---"

assert_file_contains "GitMCP に依存しない旨が明記されている" \
  "$SKILL_MD" "GitMCP"

assert_file_contains "WebFetch / WebSearch で docs.claude.com を直接参照する旨が明記されている" \
  "$SKILL_MD" "docs\.claude\.com"

# --- 受入基準 7: docs/specification.md の更新 ---

echo "--- docs/specification.md の 4d 記述 ---"

if [[ -f "$SPEC_MD" ]]; then
  pass "specification.md が存在する"
  assert_file_contains "specification.md に /vibecorp:diagnose の分析観点セクションがある" \
    "$SPEC_MD" "diagnose\` の分析観点"
  assert_file_contains "specification.md に 4d Claude Code 仕様準拠が記載されている" \
    "$SPEC_MD" "Claude Code 仕様準拠"
  assert_file_contains "specification.md に claude-code-guide エージェント参照がある" \
    "$SPEC_MD" "claude-code-guide"
else
  fail "specification.md が存在しない: $SPEC_MD"
  exit 1
fi

# ============================================
print_test_summary
