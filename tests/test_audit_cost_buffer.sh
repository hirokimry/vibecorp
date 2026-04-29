#!/bin/bash
# test_audit_cost_buffer.sh — Issue #439: audit-cost が buffer worktree 経由で書き込むことを検証
# 使い方: bash tests/test_audit_cost_buffer.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SKILL_FILE="${PROJECT_DIR}/skills/audit-cost/SKILL.md"

echo "=== Issue #439: audit-cost buffer 化テスト ==="

# --- テスト1: ファイル存在 ---
echo ""
echo "--- テスト1: ファイル存在 ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  exit 1
fi

# --- テスト2: buffer worktree 統一パターンの存在 ---
echo ""
echo "--- テスト2: buffer worktree 統一パターン ---"

assert_file_contains "knowledge_buffer.sh の source がある" "$SKILL_FILE" "knowledge_buffer.sh"
assert_file_contains "knowledge_buffer_ensure 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_ensure"
assert_file_contains "knowledge_buffer_lock_acquire 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_lock_acquire"
assert_file_contains "BUFFER_DIR 変数が定義されている" "$SKILL_FILE" 'BUFFER_DIR='
assert_file_contains "knowledge_buffer_commit 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_commit"
assert_file_contains "knowledge_buffer_push 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_push"

# --- テスト3: CFO プロンプトに BUFFER_DIR 注入 ---
echo ""
echo "--- テスト3: CFO プロンプトに BUFFER_DIR 注入 ---"

assert_file_contains "CFO プロンプトに BUFFER_DIR= が含まれる" "$SKILL_FILE" 'BUFFER_DIR=${BUFFER_DIR}'

# --- テスト4: 書込先が buffer worktree 内 ---
echo ""
echo "--- テスト4: 書込先が buffer worktree 内 ---"

assert_file_contains 'cp 先が ${BUFFER_DIR}/.claude/knowledge/accounting/ である' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/accounting'

# --- テスト5: 旧パターン（作業ブランチ直書き）が無いこと ---
echo ""
echo "--- テスト5: 作業ブランチ直書きパターンの除去 ---"

# cp 行の宛先（2 行目）に ${BUFFER_DIR} を含まず .claude/knowledge/accounting/audit- を含む行が無いこと
if grep -n -E '^\s*"\.claude/knowledge/accounting/audit-' "$SKILL_FILE" >/dev/null 2>&1; then
  fail "cp 宛先が作業ブランチを指している（${BUFFER_DIR} 経由になっていない）"
else
  pass "cp 宛先が作業ブランチ直書きパターンを含まない"
fi

# --- テスト6: フォールバック警告検知 ---
echo ""
echo "--- テスト6: フォールバック警告検知ステップ ---"

assert_file_contains "判断記録（記録先取得失敗）の検知記述がある" "$SKILL_FILE" '### 判断記録（記録先取得失敗）'
assert_file_contains "手動反映ブロックがある" "$SKILL_FILE" '⚠️ 手動反映が必要な判断記録'
assert_file_contains "migration ドキュメントへの誘導がある" "$SKILL_FILE" 'docs/migration-knowledge-buffer.md'

# --- テスト7: 出力ステータスブロック ---
echo ""
echo "--- テスト7: 出力ステータスブロック ---"

assert_file_contains "出力ステータスセクションがある" "$SKILL_FILE" '### 出力ステータス'
assert_file_contains "buffer push の成否を出力する記述がある" "$SKILL_FILE" 'buffer push: 成功 / 失敗'

# --- テスト8: 制約欄の更新 ---
echo ""
echo "--- テスト8: 制約欄の更新 ---"

assert_file_contains "knowledge_buffer_* ヘルパー経由制約がある" "$SKILL_FILE" 'knowledge_buffer_*'
assert_file_contains "作業ブランチ直書き禁止の記述がある" "$SKILL_FILE" 'protect-knowledge-direct-writes.sh'

print_test_summary
