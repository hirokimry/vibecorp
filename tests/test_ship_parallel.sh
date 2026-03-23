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
TEMPLATE_FILE="$PROJECT_DIR/templates/claude/skills/ship-parallel/SKILL.md"

echo "=== 並列 ship オーケストレーションスキル テスト ==="
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

# --- テスト4: ワークフローステップの網羅性 ---

echo "--- テスト4: ワークフローステップの網羅性 ---"

if grep -q 'COO' "$SKILL_FILE"; then
  pass "COO 分析への言及がある"
else
  fail "COO 分析への言及がない"
fi

if grep -q 'worktree' "$SKILL_FILE"; then
  pass "worktree への言及がある"
else
  fail "worktree への言及がない"
fi

if grep -q 'TeamCreate' "$SKILL_FILE" && grep -q 'isolation.*worktree' "$SKILL_FILE"; then
  pass "TeamCreate + Agent worktree による並列実行への言及がある"
else
  fail "TeamCreate + Agent worktree による並列実行への言及がない"
fi

if grep -q '結果報告' "$SKILL_FILE"; then
  pass "結果報告セクションがある"
else
  fail "結果報告セクションがない"
fi

echo ""

# --- テスト5: 制約の検証 ---

echo "--- テスト5: 制約の検証 ---"

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

echo ""

# --- テスト6: コードブロックの言語指定 ---

echo "--- テスト6: コードブロックの言語指定 ---"

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

# --- テスト7: ワークツリー分離検証（安全装置） ---
# Issue #125: Agent worktree 分離が機能しない致命的バグへの対策

echo "--- テスト7: ワークツリー分離検証（安全装置） ---"

# 7-1: エージェントプロンプトにワークツリー自己検証が含まれている
if grep -q 'ワークツリー分離検証' "$SKILL_FILE"; then
  pass "エージェントプロンプトにワークツリー分離検証セクションがある"
else
  fail "エージェントプロンプトにワークツリー分離検証セクションがない（#125 安全装置欠如）"
fi

# 7-2: エージェントに「即座に作業を中断」の指示がある
if grep -q '即座に作業を中断' "$SKILL_FILE"; then
  pass "エージェントに分離失敗時の中断指示がある"
else
  fail "エージェントに分離失敗時の中断指示がない（#125 安全装置欠如）"
fi

# 7-3: エージェントプロンプトに pwd による作業ディレクトリ確認がある
if grep -q 'pwd' "$SKILL_FILE"; then
  pass "エージェントプロンプトに pwd による作業ディレクトリ確認がある"
else
  fail "エージェントプロンプトに pwd がない（分離検証不可）"
fi

# 7-4: エージェントプロンプトに git rev-parse による確認がある
if grep -q 'git rev-parse' "$SKILL_FILE"; then
  pass "エージェントプロンプトに git rev-parse による確認がある"
else
  fail "エージェントプロンプトに git rev-parse がない（分離検証不可）"
fi

# 7-5: メインリポジトリと異なることの確認指示がある
if grep -q 'メインリポジトリと同一' "$SKILL_FILE"; then
  pass "メインリポジトリとの同一性チェック指示がある"
else
  fail "メインリポジトリとの同一性チェック指示がない（分離検証不完全）"
fi

echo ""

# --- テスト8: オーケストレーター側の分離検証ステップ ---

echo "--- テスト8: オーケストレーター側の分離検証ステップ ---"

# 8-1: ステップ 5d の存在（オーケストレーター側の検証ステップ）
if grep -q '5d.*ワークツリー分離の検証' "$SKILL_FILE"; then
  pass "ステップ 5d: オーケストレーター側のワークツリー分離検証ステップがある"
else
  fail "ステップ 5d: オーケストレーター側のワークツリー分離検証ステップがない（#125 安全装置欠如）"
fi

# 8-2: git worktree list による検証コマンドがある
if grep -q 'git worktree list' "$SKILL_FILE"; then
  pass "git worktree list による検証コマンドがある"
else
  fail "git worktree list による検証コマンドがない（分離を検出する手段がない）"
fi

# 8-3: 出力が2行以上であることの確認条件がある
if grep -q '2行以上' "$SKILL_FILE"; then
  pass "worktree list の出力が2行以上であることの確認条件がある"
else
  fail "worktree list の出力行数の確認条件がない（1行＝分離なし を検出できない）"
fi

# 8-4: メインリポジトリのブランチ変更検知がある
if grep -q 'git branch --show-current' "$SKILL_FILE"; then
  pass "メインリポジトリのブランチ変更検知コマンドがある"
else
  fail "メインリポジトリのブランチ変更検知コマンドがない（ブランチ汚染を検出できない）"
fi

# 8-5: 検証失敗時のシャットダウン指示がある
if grep -q '検証失敗.*シャットダウン' "$SKILL_FILE"; then
  pass "検証失敗時の全 Agent シャットダウン指示がある"
else
  fail "検証失敗時の全 Agent シャットダウン指示がない（分離失敗時に暴走する）"
fi

# 8-6: 検証失敗時に作業続行禁止が明記されている
if grep -q '作業続行は.*禁止' "$SKILL_FILE"; then
  pass "ワークツリー分離なしでの作業続行禁止が明記されている"
else
  fail "ワークツリー分離なしでの作業続行禁止が明記されていない（最重要制約の欠如）"
fi

echo ""

# --- テスト9: 介入ポイントにワークツリー分離失敗が含まれている ---

echo "--- テスト9: 介入ポイントの検証 ---"

# 9-1: ワークツリー分離確認失敗が介入ポイントに含まれている
if grep -q 'ワークツリー分離が確認できない.*ステップ 5d' "$SKILL_FILE"; then
  pass "介入ポイントにワークツリー分離失敗（ステップ 5d）が含まれている"
else
  fail "介入ポイントにワークツリー分離失敗が含まれていない（#125 安全装置欠如）"
fi

# 9-2: full プリセット確認の介入ポイントがある
if grep -q 'full プリセットでない.*ステップ 1' "$SKILL_FILE"; then
  pass "介入ポイントに full プリセット確認がある"
else
  fail "介入ポイントに full プリセット確認がない"
fi

echo ""

# --- テスト10: 制約セクションにワークツリー分離制約がある ---

echo "--- テスト10: 制約セクションの安全装置 ---"

# 10-1: 制約セクションにワークツリー分離の絶対禁止ルールがある
if grep -q 'ワークツリー分離が確認できない状態での作業続行は絶対に禁止' "$SKILL_FILE"; then
  pass "制約セクションにワークツリー分離なし作業続行の絶対禁止ルールがある"
else
  fail "制約セクションにワークツリー分離の絶対禁止ルールがない（最重要制約の欠如）"
fi

# 10-2: 制約がスキル末尾の制約セクション内にある（プロンプト内ではなく）
CONSTRAINT_LINE=$(grep -n 'ワークツリー分離が確認できない状態での作業続行は絶対に禁止' "$SKILL_FILE" | head -1 | cut -d: -f1)
CONSTRAINT_SECTION_LINE=$(grep -n '^## 制約' "$SKILL_FILE" | head -1 | cut -d: -f1)
if [ -n "$CONSTRAINT_LINE" ] && [ -n "$CONSTRAINT_SECTION_LINE" ] && [ "$CONSTRAINT_LINE" -gt "$CONSTRAINT_SECTION_LINE" ]; then
  pass "ワークツリー分離制約が制約セクション内にある"
else
  fail "ワークツリー分離制約が制約セクション外にある（制約として機能しない可能性）"
fi

echo ""

# --- テスト11: テンプレートとソースの一致 ---

echo "--- テスト11: テンプレートとソースの一致 ---"

if [ -f "$TEMPLATE_FILE" ]; then
  pass "テンプレートファイルが存在する"
  if diff -q "$SKILL_FILE" "$TEMPLATE_FILE" > /dev/null 2>&1; then
    pass "ソースとテンプレートが一致する"
  else
    fail "ソースとテンプレートが一致しない（安全装置がテンプレートに反映されていない）"
  fi
else
  fail "テンプレートファイルが存在しない: $TEMPLATE_FILE"
fi

echo ""

# --- テスト12: 安全装置の二重防御（エージェント側 + オーケストレーター側） ---

echo "--- テスト12: 二重防御の検証 ---"

# エージェントプロンプト内の検証（エージェント自身が分離を確認する）
AGENT_SELF_CHECK=0
if grep -q 'ワークツリー分離検証.*最初に必ず実行' "$SKILL_FILE"; then
  AGENT_SELF_CHECK=1
  pass "エージェント側: 起動直後の自己検証指示がある（第1層防御）"
else
  fail "エージェント側: 起動直後の自己検証指示がない（第1層防御の欠如）"
fi

# オーケストレーター側の検証（スキル実行者が外部から分離を確認する）
ORCH_CHECK=0
if grep -q '最初の Agent 起動直後.*スキル実行者.*自身が分離を検証' "$SKILL_FILE"; then
  ORCH_CHECK=1
  pass "オーケストレーター側: Agent 起動後の外部検証指示がある（第2層防御）"
else
  fail "オーケストレーター側: Agent 起動後の外部検証指示がない（第2層防御の欠如）"
fi

# 二重防御の両方が存在すること
if [ "$AGENT_SELF_CHECK" -eq 1 ] && [ "$ORCH_CHECK" -eq 1 ]; then
  pass "二重防御: エージェント自己検証 + オーケストレーター外部検証の両方が存在する"
else
  fail "二重防御が不完全: エージェント側=$AGENT_SELF_CHECK, オーケストレーター側=$ORCH_CHECK"
fi

echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
