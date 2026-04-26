#!/bin/bash
# test_approve_audit.sh — approve-audit スキルのテスト
# 使い方: bash tests/test_approve_audit.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_DIR/skills/approve-audit/SKILL.md"

echo "=== approve-audit スキル テスト ==="
echo ""

# --- テスト1: テンプレート SKILL.md の存在 ---

echo "--- テスト1: テンプレート SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "テンプレート SKILL.md が存在する"
else
  fail "テンプレート SKILL.md が存在しない: $SKILL_FILE"
  echo ""
  echo "==========================="
  echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
  echo "==========================="
  exit 1
fi

echo ""

# --- テスト2: frontmatter の検証 ---

echo "--- テスト2: frontmatter の検証 ---"

# frontmatter 開始区切りの確認
FIRST_LINE=$(head -1 "$SKILL_FILE")
if [ "$FIRST_LINE" = "---" ]; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りがない（先頭行: $FIRST_LINE）"
fi

# name フィールドの確認
NAME_VALUE=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "$SKILL_FILE")
if [ "$NAME_VALUE" = "approve-audit" ]; then
  pass "name フィールドが 'approve-audit' である"
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

# --- テスト3: テンプレートファイルの存在確認 ---

echo "--- テスト3: テンプレートファイルの存在確認 ---"

if [ -s "$SKILL_FILE" ]; then
  pass "テンプレートファイルが空でない"
else
  fail "テンプレートファイルが空または存在しない"
fi

echo ""

# --- テスト4: 制約セクションの検証 ---

echo "--- テスト4: 制約セクションの検証 ---"

if grep -q '## 制約' "$SKILL_FILE"; then
  pass "制約セクションが存在する"
else
  fail "制約セクションが存在しない"
fi

# jq string interpolation 禁止
if grep -q 'jq.*string interpolation' "$SKILL_FILE"; then
  pass "jq の string interpolation 禁止制約がある"
else
  fail "jq の string interpolation 禁止制約がない"
fi

# リダイレクト禁止
if grep -q 'コマンドをそのまま実行する' "$SKILL_FILE"; then
  pass "リダイレクト禁止制約がある"
else
  fail "リダイレクト禁止制約がない"
fi

# settings.local.json の無断変更禁止
if grep -q '承認なしに.*settings.local.json.*変更しない' "$SKILL_FILE"; then
  pass "settings.local.json の無断変更禁止制約がある"
else
  fail "settings.local.json の無断変更禁止制約がない"
fi

echo ""

# --- テスト5: 必須セクションの存在 ---

echo "--- テスト5: 必須セクションの存在 ---"

if grep -q '## 1\. ログファイルの読み込み' "$SKILL_FILE"; then
  pass "ログファイル読み込みセクションが存在する"
else
  fail "ログファイル読み込みセクションが存在しない"
fi

if grep -q '## 2\. settings.local.json の allow パターン取得' "$SKILL_FILE"; then
  pass "allow パターン取得セクションが存在する"
else
  fail "allow パターン取得セクションが存在しない"
fi

if grep -q '## 3\. 未許可コマンドの抽出' "$SKILL_FILE"; then
  pass "未許可コマンド抽出セクションが存在する"
else
  fail "未許可コマンド抽出セクションが存在しない"
fi

if grep -q '## 4\. パターン化と提案' "$SKILL_FILE"; then
  pass "パターン化と提案セクションが存在する"
else
  fail "パターン化と提案セクションが存在しない"
fi

if grep -q '## 5\. ユーザー承認' "$SKILL_FILE"; then
  pass "ユーザー承認セクションが存在する"
else
  fail "ユーザー承認セクションが存在しない"
fi

if grep -q '## 6\. settings.local.json への書き込み' "$SKILL_FILE"; then
  pass "書き込みセクションが存在する"
else
  fail "書き込みセクションが存在しない"
fi

if grep -q '## 8\. 結果報告' "$SKILL_FILE"; then
  pass "結果報告セクションが存在する"
else
  fail "結果報告セクションが存在しない"
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

# --- テスト7: worktree モード対応 ---

echo "--- テスト7: worktree モード対応 ---"

if grep -q '## worktree モード' "$SKILL_FILE"; then
  pass "worktree モードセクションが存在する"
else
  fail "worktree モードセクションが存在しない"
fi

if grep -q 'CLAUDE_PROJECT_DIR' "$SKILL_FILE"; then
  pass "CLAUDE_PROJECT_DIR への言及がある"
else
  fail "CLAUDE_PROJECT_DIR への言及がない"
fi

echo ""

# --- 結果 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[ "$FAILED" -eq 0 ] || exit 1
