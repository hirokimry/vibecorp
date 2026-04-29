#!/bin/bash
# test_migration_doc_exists.sh — Issue #439: docs/migration-knowledge-buffer.md と specification.md 補強の検証

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
MIG_FILE="${PROJECT_DIR}/docs/migration-knowledge-buffer.md"
SPEC_FILE="${PROJECT_DIR}/docs/specification.md"

echo "=== Issue #439: migration ドキュメントと specification 補強テスト ==="

# --- テスト1: migration ドキュメントの存在 ---
echo ""
echo "--- テスト1: ファイル存在 ---"

if [[ -f "$MIG_FILE" ]]; then
  pass "docs/migration-knowledge-buffer.md が存在する"
else
  fail "docs/migration-knowledge-buffer.md が存在しない"
  exit 1
fi

# --- テスト2: 機密情報スキャンの必須化 ---
echo ""
echo "--- テスト2: 機密情報スキャンの必須化 ---"

assert_file_contains "機密情報スキャンの必須化" "$MIG_FILE" "機密情報スキャン（必須）"
assert_file_contains "gitleaks 推奨" "$MIG_FILE" "gitleaks"
assert_file_contains "git stash show -p の手順" "$MIG_FILE" "git stash show -p"

# --- テスト3: 方法 A → 方法 B のフォールバック順序 ---
echo ""
echo "--- テスト3: 方法 A / 方法 B 優先順位 ---"

assert_file_contains "優先順位の明示" "$MIG_FILE" "まず方法 A"
assert_file_contains "方法 A 推奨ヘッダー" "$MIG_FILE" "推奨・最初に試す"
assert_file_contains "方法 B フォールバック" "$MIG_FILE" "方法 A が失敗した場合のみ"
assert_file_contains "mktemp で改ざん対策" "$MIG_FILE" "mktemp -t vibecorp-knowledge-migration"
assert_file_contains "apply 直前の最終スキャン" "$MIG_FILE" "apply 直前の最終スキャン"

# --- テスト4: knowledge_buffer ヘルパーの呼び出し ---
echo ""
echo "--- テスト4: knowledge_buffer 利用 ---"

assert_file_contains "knowledge_buffer_ensure 呼び出し" "$MIG_FILE" "knowledge_buffer_ensure"
assert_file_contains "knowledge_buffer_commit 呼び出し" "$MIG_FILE" "knowledge_buffer_commit"
assert_file_contains "knowledge_buffer_push 呼び出し" "$MIG_FILE" "knowledge_buffer_push"

# --- テスト5: 省略記号「...」が手順本文に無いこと（具体性担保） ---
echo ""
echo "--- テスト5: 省略記号「...」が無い ---"

# 「...」が手順コードブロック内に登場しないことを確認
# ただし `${BUFFER_DIR}/.claude/knowledge/...` のような明示的な省略表記は許容（コメントの一部）
# シェルコマンドとしての省略（`...` 単体）が無いことをチェック
if grep -E '^[[:space:]]*\.\.\.[[:space:]]*$' "$MIG_FILE" >/dev/null 2>&1; then
  fail "手順本文に「...」単体行が含まれている（具体性が欠落）"
else
  pass "手順本文に「...」単体行が無い"
fi

# --- テスト6: knowledge-pr スキルへの誘導 ---
echo ""
echo "--- テスト6: knowledge-pr 誘導 ---"

assert_file_contains "/vibecorp:knowledge-pr 誘導" "$MIG_FILE" "/vibecorp:knowledge-pr"

# --- テスト7: specification.md に自動反映フロー表 ---
echo ""
echo "--- テスト7: specification.md 補強 ---"

assert_file_contains "session-harvest 行" "$SPEC_FILE" "/vibecorp:session-harvest"
assert_file_contains "audit-cost 行" "$SPEC_FILE" "/vibecorp:audit-cost"
assert_file_contains "audit-security 行" "$SPEC_FILE" "/vibecorp:audit-security"
assert_file_contains "sync-edit 行" "$SPEC_FILE" "/vibecorp:sync-edit"
# `*` を grep のメタ文字として誤認しないよう、固定文字列として検査する
if grep -F 'C*O 決定記録' "$SPEC_FILE" >/dev/null 2>&1; then
  pass "C*O 決定記録 行（固定文字列マッチ）"
else
  fail "C*O 決定記録 行が見つからない"
fi
# Issue #439 完了条件: cycle-metrics / harvest-all は例外として明文化されているか
assert_file_contains "cycle-metrics 行" "$SPEC_FILE" "/vibecorp:cycle-metrics"
assert_file_contains "harvest-all 行" "$SPEC_FILE" "/vibecorp:harvest-all"
assert_file_contains "ガードレールへの言及" "$SPEC_FILE" "protect-knowledge-direct-writes.sh"
assert_file_contains "migration ドキュメントへのリンク" "$SPEC_FILE" "migration-knowledge-buffer.md"
assert_file_contains "Issue #439 の記載" "$SPEC_FILE" "Issue #439"

print_test_summary
