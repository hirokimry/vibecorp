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
SKILL_FILE="$PROJECT_DIR/skills/ship-parallel/SKILL.md"
STUB_FILE="$PROJECT_DIR/.claude/skills/ship-parallel/SKILL.md"

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

# frontmatter 終端区切りの確認
FRONTMATTER_DELIMS=$(awk '$0=="---"{c++} END{print c+0}' "$SKILL_FILE")
if [ "$FRONTMATTER_DELIMS" -ge 2 ]; then
  pass "frontmatter 終端区切りが存在する"
else
  fail "frontmatter 終端区切りがない"
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

if grep -q 'SM' "$SKILL_FILE"; then
  pass "SM 分析への言及がある"
else
  fail "SM 分析への言及がない"
fi

if ! grep -q 'COO' "$SKILL_FILE"; then
  pass "COO への言及が残っていない（SM へ統一されている）"
else
  fail "COO への言及が残っている（SM へ統一されていない）"
fi

if grep -q 'worktree' "$SKILL_FILE"; then
  pass "worktree への言及がある"
else
  fail "worktree への言及がない"
fi

if grep -q 'TeamCreate' "$SKILL_FILE" && grep -q 'git worktree add' "$SKILL_FILE"; then
  pass "TeamCreate + 手動 worktree による並列実行への言及がある"
else
  fail "TeamCreate + 手動 worktree による並列実行への言及がない"
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

# --- テスト7: 方式I の worktree 事前作成手順 ---

echo "--- テスト7: worktree 事前作成手順（方式I） ---"

# 7-1: git worktree add コマンドがある
if grep -q 'git worktree add' "$SKILL_FILE"; then
  pass "git worktree add による worktree 作成手順がある"
else
  fail "git worktree add による worktree 作成手順がない"
fi

# 7-2: rsync による .claude/ 同期手順がある
if grep -q 'rsync.*\.claude/' "$SKILL_FILE"; then
  pass "rsync による .claude/ 同期手順がある"
else
  fail "rsync による .claude/ 同期手順がない"
fi

# 7-3: git worktree list による確認がある
if grep -q 'git worktree list' "$SKILL_FILE"; then
  pass "git worktree list による worktree 確認がある"
else
  fail "git worktree list による worktree 確認がない"
fi

# 7-4: worktree 作成失敗時のスキップ動作が明記されている
if grep -q 'worktree 作成.*失敗.*スキップ' "$SKILL_FILE"; then
  pass "worktree 作成失敗時のスキップ動作が明記されている"
else
  fail "worktree 作成失敗時のスキップ動作が明記されていない"
fi

echo ""

# --- テスト8: Agent プロンプトの方式I 対応 ---

echo "--- テスト8: Agent プロンプトの方式I 対応 ---"

# 8-1: /vibecorp:ship --worktree パラメータの使用
if grep -q '/vibecorp:ship.*--worktree' "$SKILL_FILE"; then
  pass "Agent プロンプトに /vibecorp:ship --worktree がある"
else
  fail "Agent プロンプトに /vibecorp:ship --worktree がない"
fi

# 8-2: Agent(isolation: "worktree") がパラメータとして使われていない
# 方式選定理由での「機能しない」という説明的言及は許容する
ISOLATION_COUNT=$(grep -c 'isolation.*worktree' "$SKILL_FILE" || true)
EXPLANATION_COUNT=$(grep -c 'isolation.*worktree.*機能しない' "$SKILL_FILE" || true)
if [ "$ISOLATION_COUNT" -eq "$EXPLANATION_COUNT" ]; then
  pass "isolation: \"worktree\" がパラメータとして使われていない"
else
  fail "isolation: \"worktree\" がパラメータとして使われている（方式I では不要）"
fi

# 8-3: Agent プロンプトに SendMessage での報告指示がある
if grep -q 'SendMessage.*チームリーダー' "$SKILL_FILE"; then
  pass "Agent プロンプトに SendMessage での報告指示がある"
else
  fail "Agent プロンプトに SendMessage での報告指示がない"
fi

# 8-4: Agent プロンプトに compound command 分割指示がある（#258）
if grep -q '1 コマンド 1 呼び出し' "$SKILL_FILE"; then
  pass "Agent プロンプトに compound command 分割指示がある"
else
  fail "Agent プロンプトに compound command 分割指示がない"
fi

# 8-5: Agent プロンプトに built-in check の禁止理由が明示されている（#258）
if grep -q 'path resolution bypass' "$SKILL_FILE"; then
  pass "Agent プロンプトに path resolution bypass の禁止理由が明示されている"
else
  fail "Agent プロンプトに path resolution bypass の禁止理由が明示されていない"
fi

# 8-6: Agent 起動に mode: "dontAsk" の指定がある（#260）
if grep -q 'dontAsk' "$SKILL_FILE"; then
  pass "Agent 起動に dontAsk mode の指定がある"
else
  fail "Agent 起動に dontAsk mode の指定がない"
fi

echo ""

# --- テスト9: アーキテクチャが方式I になっている ---

echo "--- テスト9: アーキテクチャの方式I 確認 ---"

# 9-1: 手動 worktree 方式の記載
if grep -q '手動 worktree' "$SKILL_FILE"; then
  pass "アーキテクチャに手動 worktree 方式の記載がある"
else
  fail "アーキテクチャに手動 worktree 方式の記載がない"
fi

# 9-2: 方式選定理由に #127 検証結果への言及がある
if grep -q '#127' "$SKILL_FILE"; then
  pass "方式選定理由に #127 検証結果への言及がある"
else
  fail "方式選定理由に #127 検証結果への言及がない"
fi

# 9-3: #128 の --worktree 実装への言及がある
if grep -q '#128' "$SKILL_FILE"; then
  pass "方式選定理由に #128 の --worktree 実装への言及がある"
else
  fail "方式選定理由に #128 の --worktree 実装への言及がない"
fi

echo ""

# --- テスト10: 介入ポイントの検証 ---

echo "--- テスト10: 介入ポイントの検証 ---"

# 10-1: worktree 作成失敗は介入ポイントに含まれていない（自動スキップのため）
if grep -q 'worktree 作成失敗.*ステップ 5c' "$SKILL_FILE"; then
  fail "介入ポイントに worktree 作成失敗が含まれている（自動スキップなので不要）"
else
  pass "介入ポイントに worktree 作成失敗が含まれていない（自動スキップで処理）"
fi

# 10-2: full プリセット確認の介入ポイントがある
if grep -q 'full プリセットでない.*ステップ 1' "$SKILL_FILE"; then
  pass "介入ポイントに full プリセット確認がある"
else
  fail "介入ポイントに full プリセット確認がない"
fi

echo ""

# --- テスト11: 制約セクションの検証 ---

echo "--- テスト11: 制約セクションの検証 ---"

# 11-1: worktree 作成失敗時のスキップ制約がある
if grep -q 'worktree 作成.*失敗.*スキップ' "$SKILL_FILE"; then
  pass "制約セクションに worktree 作成失敗時のスキップ制約がある"
else
  fail "制約セクションに worktree 作成失敗時のスキップ制約がない"
fi

# 11-2: 1つの Issue の失敗で他を中断しない制約がある
if grep -q '1つの Issue の失敗で他の並列実行を中断しない' "$SKILL_FILE"; then
  pass "1つの Issue の失敗で他を中断しない制約がある"
else
  fail "1つの Issue の失敗で他を中断しない制約がない"
fi

echo ""

# --- テスト12: スタブの検証 ---

echo "--- テスト12: スタブの検証 ---"

if [ -f "$STUB_FILE" ]; then
  pass "スタブファイルが存在する"
  if grep -q 'vibecorp:ship-parallel' "$STUB_FILE"; then
    pass "スタブが /vibecorp:ship-parallel へリダイレクトしている"
  else
    fail "スタブに /vibecorp:ship-parallel への参照がない"
  fi
else
  pass "スタブファイルなし（CI 環境）"
fi

echo ""

# --- テスト13: rsync 除外リストの検証 ---

echo "--- テスト13: rsync 除外リストの検証 ---"

rsync_line=$(grep -E '^rsync -a.*--exclude' "$SKILL_FILE" | head -1)

if echo "$rsync_line" | grep -q -- "--exclude=state/"; then
  pass "rsync に --exclude=state/ がある"
else
  fail "rsync に --exclude=state/ がない"
fi

if echo "$rsync_line" | grep -q -- "--exclude=plans/"; then
  pass "rsync に --exclude=plans/ がある（#372）"
else
  fail "rsync に --exclude=plans/ がない（#372）"
fi

echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
