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

# 7-3: worktree モードでの PR 作成（Issue #519: /vibecorp:pr へ委譲、--close 必須）
# CodeRabbit #520 Minor 指摘: --close と --worktree の **両方** が必須（順序不問）
if grep -qE '/vibecorp:pr.*--close.*--worktree <path>|/vibecorp:pr.*--worktree <path>.*--close' "$SKILL_FILE"; then
  pass "worktree モードでの PR 作成手順がある（/vibecorp:pr --close --worktree <path>）"
else
  fail "worktree モードでの PR 作成手順が不完全（--close と --worktree <path> の両方が必須）"
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

# --- テスト10: sub-issue ベースブランチ検知 ---

echo "--- テスト10: sub-issue ベースブランチ検知 ---"

# 10-1: ベースブランチ決定ステップの存在
if grep -q '### 1\. ベースブランチの決定' "$SKILL_FILE"; then
  pass "ベースブランチ決定ステップが存在する"
else
  fail "ベースブランチ決定ステップが存在しない"
fi

# 10-2: parent issue 取得 API の記載
if grep -q 'issues/.*/parent' "$SKILL_FILE"; then
  pass "parent issue 取得 API の記載がある"
else
  fail "parent issue 取得 API の記載がない"
fi

# 10-3: feature/epic- ブランチの探索
if grep -q 'feature/epic-' "$SKILL_FILE"; then
  pass "feature/epic- ブランチの探索記載がある"
else
  fail "feature/epic- ブランチの探索記載がない"
fi

# 10-4: sub-issue でない場合の default branch フォールバック
if grep -q 'defaultBranchRef' "$SKILL_FILE"; then
  pass "sub-issue でない場合の default branch フォールバック記載がある"
else
  fail "sub-issue でない場合の default branch フォールバック記載がない"
fi

# 10-5: PR 作成は /vibecorp:pr に委譲する（Issue #519、責務分離）
# ship 自身は gh pr create --base を直接呼ばない。base 判定は ステップ 1 で行い、
# /vibecorp:pr は内部で merge-base 推定により親 feature ブランチを base に選ぶ。
if grep -qE '/vibecorp:pr --close' "$SKILL_FILE"; then
  pass "PR 作成は /vibecorp:pr --close 呼び出しに委譲されている"
else
  fail "PR 作成が /vibecorp:pr --close 呼び出しに委譲されていない"
fi

# 10-5b: ship 自身が gh pr create を直接呼んでいない（責務分離の退行防止）
# /vibecorp:pr --close と gh pr create が同居していると責務分離違反。負検証で防止する。
# 注: 説明文中のインラインコード（`gh pr create`）は対象外。**コード行**（行頭スペース、または cd <path> && を経由したコマンド呼び出し）のみを負検証する。
# CodeRabbit 指摘: 行頭マッチだけだと `cd <path> && gh pr create ...` 形式を見逃すため、cd-and-chain も検出対象に含める。
if grep -qE '^[[:space:]]*(cd[[:space:]]+<path>[[:space:]]*&&[[:space:]]*)?gh pr create([[:space:]]|$)' "$SKILL_FILE"; then
  fail "ship スキルに gh pr create の直接呼び出しが残存（責務違反、/vibecorp:pr に完全委譲すべき）"
else
  pass "ship スキルにコード行レベルの gh pr create 直接呼び出しが無い（/vibecorp:pr に完全委譲）"
fi

# 10-6: git ls-remote による親ブランチ探索
if grep -q 'git ls-remote' "$SKILL_FILE"; then
  pass "git ls-remote による親ブランチ探索記載がある"
else
  fail "git ls-remote による親ブランチ探索記載がない"
fi

# 10-7: 親ブランチ 0 件時の中断（介入ポイント）
if grep -q '親エピックの feature ブランチが見つかりません' "$SKILL_FILE"; then
  pass "親ブランチ 0 件時の中断記載がある"
else
  fail "親ブランチ 0 件時の中断記載がない"
fi

# 10-8: ベースブランチからの派生
if grep -q 'origin/<ステップ1で決定したベースブランチ>' "$SKILL_FILE"; then
  pass "ベースブランチからのブランチ派生記載がある"
else
  fail "ベースブランチからのブランチ派生記載がない"
fi

# 10-9: 結果報告にベース記載
if grep -q 'ベース:.*feature/epic-' "$SKILL_FILE"; then
  pass "結果報告にベースブランチの記載がある"
else
  fail "結果報告にベースブランチの記載がない"
fi

# 10-10: 介入ポイントにエピック関連の記載
if grep -q '親エピックの feature ブランチが見つからない' "$SKILL_FILE"; then
  pass "介入ポイントにエピック関連の中断条件がある"
else
  fail "介入ポイントにエピック関連の中断条件がない"
fi

echo ""

# --- テスト11: 互換スタブの廃止確認 ---

echo "--- テスト11: 互換スタブの廃止確認 ---"

if [ -d "$PROJECT_DIR/.claude/skills/ship" ]; then
  fail ".claude/skills/ship/ が残存している（Phase 3 で廃止済み）"
else
  pass ".claude/skills/ship/ が廃止されている"
fi

echo ""

# --- テスト12: ステップ 3 plan 委譲 (#564) ---
# CodeRabbit #565 Major 指摘: prose 文言依存の grep を構造検証中心に変更
# （セクションヘッダー・コードブロック存在・負検証で検証する）

echo "--- テスト12: ステップ 3 plan 委譲 ---"

SHIP_STEP3=$(awk '/^### 3\. 実装計画の策定/{flag=1; next} /^### 4\./{flag=0} flag' "$SKILL_FILE")

# 12-1: ステップ 3 のセクションヘッダーが存在する（構造検証）
if grep -q '^### 3\. 実装計画の策定' "$SKILL_FILE"; then
  pass "ship/SKILL.md にステップ 3 のセクションヘッダーが存在する"
else
  fail "ship/SKILL.md にステップ 3 のセクションヘッダーが存在しない"
fi

# 12-2: ステップ 3 が /vibecorp:plan への委譲を明記している（コマンド名検証）
if printf '%s\n' "$SHIP_STEP3" | grep -q '/vibecorp:plan'; then
  pass "ステップ 3 で /vibecorp:plan への委譲が記載されている"
else
  fail "ステップ 3 で /vibecorp:plan への委譲が記載されていない"
fi

# 12-3: ship 自身が gh api でコメント取得を直接呼ばない（負検証、既存テスト 10-5b と同じスタイル）
# ステップ 3 のスコープ内で `gh api ...issues/.../comments` がコード行として現れないことを確認する。
# CodeRabbit #565 Major 指摘を反映: `cd <path> && gh api ...` チェイン形式も検出対象に含める。
if printf '%s\n' "$SHIP_STEP3" | grep -qE '^[[:space:]]*(cd[[:space:]]+<path>[[:space:]]*&&[[:space:]]*)?gh api.*issues/.*comments'; then
  fail "ship/SKILL.md ステップ 3 に gh api によるコメント直接取得が残存（plan に委譲すべき）"
else
  pass "ship/SKILL.md ステップ 3 に gh api によるコメント直接取得が無い（plan に委譲）"
fi

echo ""

# --- テスト13: plan/SKILL.md 全コメント取得 (#564) ---
# CodeRabbit #565 Major 指摘: prose 文言依存の grep を構造検証中心に変更
# - サブセクションヘッダー（#### 1-X. ...）の存在
# - コードブロック内のコマンド存在
# - 負検証（禁止パターン不在）

echo "--- テスト13: plan/SKILL.md 全コメント取得 ---"

PLAN_FILE="$PROJECT_DIR/skills/plan/SKILL.md"

if [ ! -f "$PLAN_FILE" ]; then
  fail "plan/SKILL.md が存在しない: $PLAN_FILE"
  exit 1
fi

# 13-1: 親セクション「### 1. Issue 情報の取得」が存在する（構造検証）
if grep -q '^### 1\. Issue 情報の取得' "$PLAN_FILE"; then
  pass "plan/SKILL.md に親セクション「### 1. Issue 情報の取得」が存在する"
else
  fail "plan/SKILL.md に親セクション「### 1. Issue 情報の取得」が存在しない"
fi

# 13-2: 9 つのサブセクション（#### 1-1 〜 #### 1-9）がそれぞれ欠番なく存在する（構造検証）
# 各サブセクションは独立した責務を表す。ヘッダーの欠落 = 機能の欠落として検出する。
# CodeRabbit #565 Major 指摘を反映: 件数判定では重複見出しで欠番を見逃すため、各番号の存在を個別検証する。
MISSING_SUBSECTIONS=""
for i in 1 2 3 4 5 6 7 8 9; do
  if ! grep -qE "^#### 1-${i}\. " "$PLAN_FILE"; then
    MISSING_SUBSECTIONS="${MISSING_SUBSECTIONS} 1-${i}"
  fi
done
if [ -z "${MISSING_SUBSECTIONS# }" ]; then
  pass "plan/SKILL.md にサブセクション #### 1-1 〜 #### 1-9 が欠番なく存在する"
else
  fail "plan/SKILL.md に欠けているサブセクションがある:${MISSING_SUBSECTIONS}"
fi

# 13-3: コード行で gh api ... /comments --paginate が存在する（コードブロック検証）
# 行頭スペース許容。インラインコード（バッククォート内の言及）は対象外。
if grep -qE '^[[:space:]]*gh api.*issues.*/comments.*--paginate' "$PLAN_FILE"; then
  pass "plan/SKILL.md にコード行レベルの gh api ... /comments --paginate が存在する"
else
  fail "plan/SKILL.md にコード行レベルの gh api ... /comments --paginate が存在しない"
fi

# 13-4: --json comments をコード行で使わない（負検証）
# 既存テスト 10-5b と同じ負検証スタイル。説明文中のインラインコード（`...` 内）は対象外。
# CodeRabbit #565 Major 指摘を反映: 行頭 `gh` 限定だと `VAR=$(gh ...)` 代入形式や
# `cd <path> && gh ...` チェイン形式を取りこぼすため、それらも検出対象に含める。
if grep -qE '^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*=.*)?([[:space:]]*cd[[:space:]]+<path>[[:space:]]*&&[[:space:]]*)?gh[[:space:]].*\-\-json[[:space:]]+comments([[:space:]]|$)' "$PLAN_FILE"; then
  fail "plan/SKILL.md にコード行レベルの --json comments 使用が残存（30 件制限の混入経路）"
else
  pass "plan/SKILL.md にコード行レベルの --json comments 使用が無い（30 件制限を回避）"
fi

# 13-5: bot 除外フィルタの jq テストパターンが存在する（コードブロック検証）
# 既知の bot ユーザー名 4 種のうち 2 種以上がコード行に存在することを検証する。
# （特定 1 種のスペル変更で偽失敗にならないよう冗長性を持たせる）
BOT_HIT_COUNT=0
for bot in coderabbitai github-actions codecov dependabot; do
  if grep -qE "^[[:space:]]*\|*[[:space:]]*[\.{}]*.*${bot}" "$PLAN_FILE"; then
    BOT_HIT_COUNT=$((BOT_HIT_COUNT + 1))
  fi
done
if [ "$BOT_HIT_COUNT" -ge 2 ]; then
  pass "plan/SKILL.md に bot 除外フィルタの既知 bot 名が ${BOT_HIT_COUNT} 件存在する（2 件以上必須）"
else
  fail "plan/SKILL.md の bot 除外フィルタに既知 bot 名が ${BOT_HIT_COUNT} 件しか存在しない（2 件以上必須）"
fi

# 13-6: owner/repo 動的解決のコマンドがコード行に存在する（コードブロック検証）
if grep -qE '^[[:space:]]*[a-zA-Z_]+=.*gh repo view.*nameWithOwner' "$PLAN_FILE"; then
  pass "plan/SKILL.md にコード行レベルの gh repo view ... nameWithOwner が存在する"
else
  fail "plan/SKILL.md にコード行レベルの gh repo view ... nameWithOwner が存在しない"
fi

echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
