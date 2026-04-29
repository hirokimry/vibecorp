#!/bin/bash
# test_sync_edit_buffer.sh — Issue #439: sync-edit の C*O 委任編集が buffer worktree 経由になることを検証

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SKILL_FILE="${PROJECT_DIR}/skills/sync-edit/SKILL.md"

echo "=== Issue #439: sync-edit buffer 化テスト ==="

# --- テスト1: ファイル存在 ---
if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  exit 1
fi

# --- テスト2: buffer worktree 統一パターン ---
echo ""
echo "--- テスト2: buffer worktree 統一パターン ---"
assert_file_contains "knowledge_buffer.sh の source がある" "$SKILL_FILE" "knowledge_buffer.sh"
assert_file_contains "knowledge_buffer_ensure 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_ensure"
assert_file_contains "knowledge_buffer_lock_acquire 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_lock_acquire"
assert_file_contains "BUFFER_DIR 変数が定義されている" "$SKILL_FILE" 'BUFFER_DIR='
assert_file_contains "knowledge_buffer_commit 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_commit"
assert_file_contains "knowledge_buffer_push 呼び出しがある" "$SKILL_FILE" "knowledge_buffer_push"

# --- テスト3: C*O プロンプトに BUFFER_DIR 注入 ---
echo ""
echo "--- テスト3: C*O プロンプトに BUFFER_DIR 注入 ---"
assert_file_contains "C*O プロンプトに BUFFER_DIR= が含まれる" "$SKILL_FILE" 'BUFFER_DIR=${BUFFER_DIR}'

# --- テスト4: 管轄表で knowledge/ が buffer worktree に変更されている ---
echo ""
echo "--- テスト4: 管轄表の書込先 ---"
assert_file_contains 'CTO 管轄に ${BUFFER_DIR}/.claude/knowledge/cto/ がある' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/cto'
assert_file_contains 'CPO 管轄に ${BUFFER_DIR}/.claude/knowledge/cpo/ がある' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/cpo'
assert_file_contains 'SM 管轄に ${BUFFER_DIR}/.claude/knowledge/sm/ がある' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/sm'
assert_file_contains 'legal 管轄に ${BUFFER_DIR}/.claude/knowledge/legal/ がある' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/legal'
assert_file_contains 'accounting 管轄に ${BUFFER_DIR}/.claude/knowledge/accounting/ がある' "$SKILL_FILE" '${BUFFER_DIR}/.claude/knowledge/accounting'

# --- テスト5: フォールバック警告検知 ---
echo ""
echo "--- テスト5: フォールバック警告検知ステップ ---"
assert_file_contains "判断記録（記録先取得失敗）の検知記述がある" "$SKILL_FILE" '### 判断記録（記録先取得失敗）'
assert_file_contains "ヘッダ名厳格指定の記述がある" "$SKILL_FILE" 'ヘッダ名は厳格指定'
assert_file_contains "手動反映ブロックがある" "$SKILL_FILE" '⚠️ 手動反映が必要な判断記録'
assert_file_contains "migration ドキュメントへの誘導がある" "$SKILL_FILE" 'docs/migration-knowledge-buffer.md'

# --- テスト6: 統合 commit ステップ ---
echo ""
echo "--- テスト6: 統合 commit ステップ ---"
assert_file_contains "全 C*O 完了後 1 回のみ commit する記述" "$SKILL_FILE" 'C*O 全員完了後 1 回のみ'

# --- テスト7: 制約欄の更新 ---
echo ""
echo "--- テスト7: 制約欄の更新 ---"
assert_file_contains "buffer worktree 経由限定の制約" "$SKILL_FILE" 'buffer worktree 経由限定'
assert_file_contains "protect-knowledge-direct-writes.sh への言及" "$SKILL_FILE" 'protect-knowledge-direct-writes.sh'

print_test_summary
