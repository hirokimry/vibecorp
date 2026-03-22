#!/bin/bash
# test_ship_parallel.sh — 並列 ship オーケストレーションスキルのテスト
# 使い方: bash tests/test_ship_parallel.sh

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$PROJECT_DIR/.claude/skills/ship-parallel"
SKILL_FILE="$SKILL_DIR/SKILL.md"

echo "=== 並列 ship オーケストレーションスキル テスト ==="
echo ""

# --- テスト1: SKILL.md の存在 ---

echo "--- テスト1: SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない: $SKILL_FILE"
fi

echo ""

# --- テスト2: frontmatter の検証 ---

echo "--- テスト2: frontmatter の検証 ---"

# frontmatter 開始・終了の確認
FIRST_LINE=$(head -1 "$SKILL_FILE")
if [ "$FIRST_LINE" = "---" ]; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りがない（先頭行: $FIRST_LINE）"
fi

# name フィールドの確認
NAME_VALUE=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "$SKILL_FILE")
if [ "$NAME_VALUE" = "ship-parallel" ]; then
  pass "name フィールドが 'ship-parallel' である"
else
  fail "name フィールドが不正: '$NAME_VALUE'"
fi

# description フィールドの確認
DESC_EXISTS=$(awk '/^---$/{n++; next} n==1 && /^description:/{print "yes"; exit}' "$SKILL_FILE")
if [ "$DESC_EXISTS" = "yes" ]; then
  pass "description フィールドが存在する"
else
  fail "description フィールドが存在しない"
fi

echo ""

# --- テスト3: 必須セクションの存在 ---

echo "--- テスト3: 必須セクションの存在 ---"

# ワークフローセクション
if grep -q '## ワークフロー' "$SKILL_FILE"; then
  pass "ワークフローセクションが存在する"
else
  fail "ワークフローセクションが存在しない"
fi

# 使用方法セクション
if grep -q '## 使用方法' "$SKILL_FILE"; then
  pass "使用方法セクションが存在する"
else
  fail "使用方法セクションが存在しない"
fi

# 制約セクション
if grep -q '## 制約' "$SKILL_FILE"; then
  pass "制約セクションが存在する"
else
  fail "制約セクションが存在しない"
fi

# 介入ポイントセクション
if grep -q '## 介入ポイント' "$SKILL_FILE"; then
  pass "介入ポイントセクションが存在する"
else
  fail "介入ポイントセクションが存在しない"
fi

echo ""

# --- テスト4: ワークフローステップの網羅性 ---

echo "--- テスト4: ワークフローステップの網羅性 ---"

# COO 分析ステップの存在
if grep -q 'COO' "$SKILL_FILE"; then
  pass "COO 分析への言及がある"
else
  fail "COO 分析への言及がない"
fi

# worktree 作成ステップの存在
if grep -q 'worktree' "$SKILL_FILE"; then
  pass "worktree への言及がある"
else
  fail "worktree への言及がない"
fi

# TeamCreate + Agent worktree による並列実行への言及
if grep -q 'TeamCreate' "$SKILL_FILE" && grep -q 'isolation.*worktree' "$SKILL_FILE"; then
  pass "TeamCreate + Agent worktree による並列実行への言及がある"
else
  fail "TeamCreate + Agent worktree による並列実行への言及がない"
fi

# 結果報告セクション
if grep -q '結果報告' "$SKILL_FILE"; then
  pass "結果報告セクションがある"
else
  fail "結果報告セクションがない"
fi

echo ""

# --- テスト5: 制約の検証 ---

echo "--- テスト5: 制約の検証 ---"

# jq 制約
if grep -q 'jq.*string interpolation' "$SKILL_FILE"; then
  pass "jq の string interpolation 禁止制約がある"
else
  fail "jq の string interpolation 禁止制約がない"
fi

# コマンド実行制約
if grep -q 'コマンドをそのまま実行する' "$SKILL_FILE"; then
  pass "コマンド実行制約がある"
else
  fail "コマンド実行制約がない"
fi

echo ""

# --- テスト6: コードブロックの言語指定 ---

echo "--- テスト6: コードブロックの言語指定 ---"

# 言語指定なしのコードブロック開始行がないか確認
# コードブロックの開始行は ``` の後に言語名が続く（例: ```bash）
# 閉じタグ ``` は言語指定不要なので除外する
# 方法: awk で開始/終了を交互に追跡し、開始行で言語指定がないものをカウント
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

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
