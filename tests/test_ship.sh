#!/bin/bash
# test_ship.sh — /vibecorp:ship スキルのテスト（worktree モード対応含む）
# 使い方: bash tests/test_ship.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_DIR/skills/ship/SKILL.md"

echo "=== /vibecorp:ship スキル テスト ==="
echo ""

# --- テスト1: SKILL.md の存在 ---

echo "--- テスト1: SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない: $SKILL_FILE"
  echo ""
  echo "==========================="
  echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
  echo "==========================="
  exit 1
fi

echo ""

# --- テスト2: frontmatter の検証 ---

echo "--- テスト2: frontmatter の検証 ---"

FIRST_LINE=$(head -1 "$SKILL_FILE")
if [ "$FIRST_LINE" = "---" ]; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りがない（先頭行: $FIRST_LINE）"
fi

NAME_VALUE=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "$SKILL_FILE")
if [ "$NAME_VALUE" = "ship" ]; then
  pass "name フィールドが 'ship' である"
else
  fail "name フィールドが不正: '$NAME_VALUE'"
fi

DESC_EXISTS=$(awk '/^---$/{n++; next} n==1 && /^description:/{print "yes"; exit}' "$SKILL_FILE")
if [ "$DESC_EXISTS" = "yes" ]; then
  pass "description フィールドが存在する"
else
  fail "description フィールドが存在しない"
fi

echo ""

# --- テスト3: 必須セクションの存在 ---

echo "--- テスト3: 必須セクションの存在 ---"

if grep -q '## ワークフロー' "$SKILL_FILE"; then
  pass "ワークフローセクションが存在する"
else
  fail "ワークフローセクションが存在しない"
fi

if grep -q '## 使用方法' "$SKILL_FILE"; then
  pass "使用方法セクションが存在する"
else
  fail "使用方法セクションが存在しない"
fi

if grep -q '## 制約' "$SKILL_FILE"; then
  pass "制約セクションが存在する"
else
  fail "制約セクションが存在しない"
fi

if grep -q '## 介入ポイント' "$SKILL_FILE"; then
  pass "介入ポイントセクションが存在する"
else
  fail "介入ポイントセクションが存在しない"
fi

echo ""

# --- テスト4: worktree モードセクションの存在 ---

echo "--- テスト4: worktree モードセクション ---"

if grep -q '## worktree モード' "$SKILL_FILE"; then
  pass "worktree モードセクションが存在する"
else
  fail "worktree モードセクションが存在しない"
fi

if grep -q '\-\-worktree <path>' "$SKILL_FILE"; then
  pass "--worktree <path> パラメータの記載がある"
else
  fail "--worktree <path> パラメータの記載がない"
fi

echo ""

# --- テスト5: worktree モードの動作ルール ---

echo "--- テスト5: worktree モードの動作ルール ---"

# 5-1: Bash での cd <path> && command ルール
if grep -q 'cd <path> && command' "$SKILL_FILE"; then
  pass "Bash での cd <path> && command ルールがある"
else
  fail "Bash での cd <path> && command ルールがない"
fi

# 5-2: Read/Write/Edit の絶対パス使用ルール
if grep -q '<path>/.*絶対パス' "$SKILL_FILE"; then
  pass "Read/Write/Edit の絶対パス使用ルールがある"
else
  fail "Read/Write/Edit の絶対パス使用ルールがない"
fi

# 5-3: サブスキルへの --worktree 引き継ぎ
if grep -q 'worktree.*引き継ぐ' "$SKILL_FILE"; then
  pass "サブスキルへの --worktree 引き継ぎルールがある"
else
  fail "サブスキルへの --worktree 引き継ぎルールがない"
fi

# 5-4: 未指定時の後方互換
if grep -q '未指定時は従来通り' "$SKILL_FILE"; then
  pass "未指定時の後方互換記載がある"
else
  fail "未指定時の後方互換記載がない"
fi

echo ""

# --- テスト6: サブスキル伝播 ---

echo "--- テスト6: サブスキル伝播 ---"

# 6-1: /vibecorp:commit への --worktree 引き継ぎ
if grep -q '/vibecorp:commit.*worktree' "$SKILL_FILE"; then
  pass "/vibecorp:commit への worktree 引き継ぎ記載がある"
else
  fail "/vibecorp:commit への worktree 引き継ぎ記載がない"
fi

# 6-2: /vibecorp:review-loop への --worktree 引き継ぎ
if grep -q '/vibecorp:review-loop.*worktree' "$SKILL_FILE"; then
  pass "/vibecorp:review-loop への worktree 引き継ぎ記載がある"
else
  fail "/vibecorp:review-loop への worktree 引き継ぎ記載がない"
fi

# 6-3: /vibecorp:pr-fix-loop への --worktree 引き継ぎ
if grep -q '/vibecorp:pr-fix-loop.*worktree' "$SKILL_FILE"; then
  pass "/vibecorp:pr-fix-loop への worktree 引き継ぎ記載がある"
else
  fail "/vibecorp:pr-fix-loop への worktree 引き継ぎ記載がない"
fi

# 6-4: /vibecorp:plan-review-loop への --worktree 引き継ぎ
if grep -q '/vibecorp:plan-review-loop.*worktree' "$SKILL_FILE"; then
  pass "/vibecorp:plan-review-loop への worktree 引き継ぎ記載がある"
else
  fail "/vibecorp:plan-review-loop への worktree 引き継ぎ記載がない"
fi

echo ""

# --- テスト7: worktree モードでのステップ記載 ---

echo "--- テスト7: worktree モードでのステップ記載 ---"

# 7-1: worktree モードでのブランチリネーム
if grep -q 'git branch -m' "$SKILL_FILE"; then
  pass "worktree モードでのブランチリネーム手順がある"
else
  fail "worktree モードでのブランチリネーム手順がない"
fi

# 7-2: worktree モードでの push
if grep -q 'cd <path> && git push' "$SKILL_FILE"; then
  pass "worktree モードでの push 手順がある"
else
  fail "worktree モードでの push 手順がない"
fi

# 7-3: worktree モードでの PR 作成
if grep -q 'cd <path> && gh pr create' "$SKILL_FILE"; then
  pass "worktree モードでの PR 作成手順がある"
else
  fail "worktree モードでの PR 作成手順がない"
fi

echo ""

# --- テスト8: コードブロックの言語指定 ---

echo "--- テスト8: コードブロックの言語指定 ---"

BARE_OPEN_COUNT=$(awk '
  /^```/ {
    if (in_block) {
      in_block = 0
    } else {
      in_block = 1
      if ($0 == "```") bare++
    }
  }
  END { print bare+0 }
' "$SKILL_FILE")
if [ "$BARE_OPEN_COUNT" -eq 0 ]; then
  pass "全てのコードブロックに言語指定がある"
else
  fail "言語指定なしのコードブロックが ${BARE_OPEN_COUNT} 箇所ある"
fi

echo ""

# --- テスト9: 制約の検証 ---

echo "--- テスト9: 制約の検証 ---"

if grep -q 'jq.*string interpolation' "$SKILL_FILE"; then
  pass "jq の string interpolation 禁止制約がある"
else
  fail "jq の string interpolation 禁止制約がない"
fi

if grep -q 'コマンドをそのまま実行する' "$SKILL_FILE"; then
  pass "コマンド実行制約がある"
else
  fail "コマンド実行制約がない"
fi

# 制約セクションに compound command 分割指示がある（#258）
if grep -q '1 コマンド 1 呼び出し' "$SKILL_FILE"; then
  pass "制約セクションに compound command 分割指示がある"
else
  fail "制約セクションに compound command 分割指示がない"
fi

# 制約セクションに built-in check の禁止理由が明示されている（#258）
if grep -q 'path resolution bypass' "$SKILL_FILE"; then
  pass "制約セクションに path resolution bypass の禁止理由が明示されている"
else
  fail "制約セクションに path resolution bypass の禁止理由が明示されていない"
fi

echo ""

# --- テスト10: 互換スタブの廃止確認 ---

echo "--- テスト10: 互換スタブの廃止確認 ---"

if [ -d "$PROJECT_DIR/.claude/skills/ship" ]; then
  fail ".claude/skills/ship/ が残存している（Phase 3 で廃止済み）"
else
  pass ".claude/skills/ship/ が廃止されている"
fi

echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
