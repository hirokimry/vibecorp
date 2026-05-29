#!/bin/bash
# test_install_intent_labels.sh
# ─────────────────────────────────────────────
# install.sh の create_labels に intent/* ラベル 7 種が含まれることを検証
# Issue #469: intent/* ラベル機構整備
#
# 注: gh CLI が動かないテスト環境向けに、install.sh の VIBECORP_LABELS 配列の
# 静的検証を行う（実際にラベルを作る gh label create は呼ばない）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== intent/* ラベル機構のテスト ==="

# install.sh から create_labels 関数のブロックを抽出して検証
INSTALL_SH="${SCRIPT_DIR}/install.sh"

# ============================================
# 1. install.sh の VIBECORP_LABELS に intent/* 7 種が含まれる
# ============================================
echo ""
echo "--- 1. VIBECORP_LABELS に intent/* 7 種が登録されている ---"

# install.sh 全体ではなく VIBECORP_LABELS=( ... ) ブロック内だけを対象に検証する
# （他箇所の文字列出現で偽陽性が出るのを防ぐ）
vibecorp_labels_block=$(awk '/VIBECORP_LABELS=\(/,/^[[:space:]]*\)/' "$INSTALL_SH")

for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  if echo "$vibecorp_labels_block" | grep -q -F -- "\"$intent:"; then
    pass "intent ラベル '$intent' が VIBECORP_LABELS ブロック内に含まれる"
  else
    fail "intent ラベル '$intent' が VIBECORP_LABELS ブロック内に含まれない"
  fi
done

# ============================================
# 2. intent ラベルの色が定義されている（GitHub の hex 色コード）
# ============================================
echo ""
echo "--- 2. intent ラベルの色定義 ---"
labels_block=$(awk '/^create_labels\(\)/,/^}/' "$INSTALL_SH")

# 各 intent ラベルに 6 桁 hex 色コードと description が付いていることを検証
for intent in "intent/feature" "intent/bugfix" "intent/performance" "intent/security" "intent/refactor" "intent/infra" "intent/docs"; do
  if echo "$labels_block" | grep -E -q "\"${intent}:[0-9a-f]{6}:[^\"]+\""; then
    pass "$intent: 色コード + description が付与されている"
  else
    fail "$intent: 色コード + description が欠けている"
  fi
done

# ============================================
# 3. .claude/rules/intent-labels.md が配布される
# ============================================
echo ""
echo "--- 3. intent-labels.md が SSOT rules/ に存在する ---"
assert_file_exists "rules/intent-labels.md" "${SCRIPT_DIR}/rules/intent-labels.md"

# 主要記述の存在
assert_file_contains "主従関係の明記"           "${SCRIPT_DIR}/rules/intent-labels.md" "主従関係"
assert_file_contains "1 Issue / 1 PR / 1 intent" "${SCRIPT_DIR}/rules/intent-labels.md" "1 つだけ"
assert_file_contains "判定主体: COO"            "${SCRIPT_DIR}/rules/intent-labels.md" "COO"

# テンプレート内に 7 種すべてが含まれることを確認
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  assert_file_contains "テンプレートに $intent が含まれる" "${SCRIPT_DIR}/rules/intent-labels.md" "$intent"
done

# ============================================
# 4. install で .claude/rules/intent-labels.md が配置される
# ============================================
echo ""
echo "--- 4. install で intent-labels.md が利用者リポに配布される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists ".claude/rules/intent-labels.md が配布される" "$R/.claude/rules/intent-labels.md"
# 配布版にも 7 種すべてが含まれることを確認
for intent in intent/feature intent/bugfix intent/performance intent/security intent/refactor intent/infra intent/docs; do
  assert_file_contains "配布版に $intent が含まれる" "$R/.claude/rules/intent-labels.md" "$intent"
done
cleanup

# ============================================
# 5. docs/conventional-commits.md が vibecorp 本体に存在する
# ============================================
echo ""
echo "--- 5. docs/conventional-commits.md が vibecorp 本体に存在 ---"
assert_file_exists "docs/conventional-commits.md" "${SCRIPT_DIR}/docs/conventional-commits.md"
assert_file_contains "CC 11 種を網羅"     "${SCRIPT_DIR}/docs/conventional-commits.md" "feat — 新機能追加"
assert_file_contains "絵文字マッピング"   "${SCRIPT_DIR}/docs/conventional-commits.md" "✨"
assert_file_contains "intent → CC 対応表" "${SCRIPT_DIR}/docs/conventional-commits.md" "intent ラベル → CC prefix 対応表"

print_test_summary
