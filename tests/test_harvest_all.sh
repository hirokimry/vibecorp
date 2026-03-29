#!/bin/bash
# test_harvest_all.sh — /harvest-all スキルのテスト
# 使い方: bash tests/test_harvest_all.sh

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
TEMPLATE_FILE="$PROJECT_DIR/templates/claude/skills/harvest-all/SKILL.md"
SKILL_FILE="$TEMPLATE_FILE"

echo "=== /harvest-all スキル テスト ==="
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
if [ "$NAME_VALUE" = "harvest-all" ]; then
  pass "name フィールドが 'harvest-all' である"
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

if grep -q '## 使用方法' "$SKILL_FILE"; then
  pass "使用方法セクションが存在する"
else
  fail "使用方法セクションが存在しない"
fi

if grep -q '## ワークフロー' "$SKILL_FILE"; then
  pass "ワークフローセクションが存在する"
else
  fail "ワークフローセクションが存在しない"
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

if grep -q '### 1\. 走査対象の確定' "$SKILL_FILE"; then
  pass "ステップ1: 走査対象の確定が存在する"
else
  fail "ステップ1: 走査対象の確定が存在しない"
fi

if grep -q '### 2\. 既存ドキュメントの読み込み' "$SKILL_FILE"; then
  pass "ステップ2: 既存ドキュメントの読み込みが存在する"
else
  fail "ステップ2: 既存ドキュメントの読み込みが存在しない"
fi

if grep -q '### 3\. コードベースの走査・分析' "$SKILL_FILE"; then
  pass "ステップ3: コードベースの走査・分析が存在する"
else
  fail "ステップ3: コードベースの走査・分析が存在しない"
fi

if grep -q '### 4\. 重複検出・除外' "$SKILL_FILE"; then
  pass "ステップ4: 重複検出・除外が存在する"
else
  fail "ステップ4: 重複検出・除外が存在しない"
fi

if grep -q '### 5\. 優先度・カテゴリ別の整理' "$SKILL_FILE"; then
  pass "ステップ5: 優先度・カテゴリ別の整理が存在する"
else
  fail "ステップ5: 優先度・カテゴリ別の整理が存在しない"
fi

if grep -q '### 6\. ユーザーへの確認' "$SKILL_FILE"; then
  pass "ステップ6: ユーザーへの確認が存在する"
else
  fail "ステップ6: ユーザーへの確認が存在しない"
fi

if grep -q '### 7\. ドキュメントへの直接反映' "$SKILL_FILE"; then
  pass "ステップ7: ドキュメントへの直接反映が存在する"
else
  fail "ステップ7: ドキュメントへの直接反映が存在しない"
fi

if grep -q '### 8\. 結果報告' "$SKILL_FILE"; then
  pass "ステップ8: 結果報告が存在する"
else
  fail "ステップ8: 結果報告が存在しない"
fi

echo ""

# --- テスト5: 3観点の分析カテゴリ ---

echo "--- テスト5: 3観点の分析カテゴリ ---"

if grep -q 'docs/ 向け' "$SKILL_FILE"; then
  pass "docs/ 向けカテゴリが存在する"
else
  fail "docs/ 向けカテゴリが存在しない"
fi

if grep -q 'rules/ 向け' "$SKILL_FILE"; then
  pass "rules/ 向けカテゴリが存在する"
else
  fail "rules/ 向けカテゴリが存在しない"
fi

if grep -q 'knowledge/ 向け' "$SKILL_FILE"; then
  pass "knowledge/ 向けカテゴリが存在する"
else
  fail "knowledge/ 向けカテゴリが存在しない"
fi

echo ""

# --- テスト6: オプションの記載 ---

echo "--- テスト6: オプションの記載 ---"

if grep -q '\-\-scope' "$SKILL_FILE"; then
  pass "--scope オプションの記載がある"
else
  fail "--scope オプションの記載がない"
fi

if grep -q '\-\-dry-run' "$SKILL_FILE"; then
  pass "--dry-run オプションの記載がある"
else
  fail "--dry-run オプションの記載がない"
fi

echo ""

# --- テスト7: コードブロックの言語指定 ---

echo "--- テスト7: コードブロックの言語指定 ---"

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

# --- テスト8: 制約の検証 ---

echo "--- テスト8: 制約の検証 ---"

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

if grep -q 'ユーザーの承認を得る' "$SKILL_FILE"; then
  pass "ユーザー承認制約がある"
else
  fail "ユーザー承認制約がない"
fi

echo ""

# --- テスト9: ユーザー確認ステップの存在 ---

echo "--- テスト9: ユーザー確認ステップの存在 ---"

if grep -q '反映しますか' "$SKILL_FILE"; then
  pass "反映前の確認プロンプトがある"
else
  fail "反映前の確認プロンプトがない"
fi

echo ""

# --- テスト10: デフォルト即反映の設計 ---

echo "--- テスト10: デフォルト即反映の設計 ---"

if grep -q '直接反映' "$SKILL_FILE"; then
  pass "デフォルト動作が直接反映である"
else
  fail "デフォルト動作が直接反映でない"
fi


echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
