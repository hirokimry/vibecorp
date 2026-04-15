#!/bin/bash
# test_autopilot.sh — autopilot スキルのテスト
# 使い方: bash tests/test_autopilot.sh

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
TEMPLATE_FILE="$PROJECT_DIR/templates/claude/skills/autopilot/SKILL.md"
LOCAL_FILE="$PROJECT_DIR/.claude/skills/autopilot/SKILL.md"
# テンプレートを正とする（.claude/skills/ は gitignored で CI に存在しない場合がある）
SKILL_FILE="$TEMPLATE_FILE"

echo "=== autopilot スキル テスト ==="

# --- テスト1: SKILL.md の存在 ---

echo ""
echo "--- テスト1: SKILL.md の存在 ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  echo ""
  echo "==========================="
  echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
  echo "==========================="
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

# --- テスト2: frontmatter の検証 ---

echo ""
echo "--- テスト2: frontmatter の検証 ---"

# 2-1: frontmatter 開始区切り
if head -1 "$SKILL_FILE" | grep -q '^---$'; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りが存在しない"
fi

# 2-2: name フィールド
if awk '/^---$/{c++; next} c==1' "$SKILL_FILE" | grep -q '^name:'; then
  pass "frontmatter に name フィールドがある"
else
  fail "frontmatter に name フィールドがない"
fi

# 2-3: description フィールド
if awk '/^---$/{c++; next} c==1' "$SKILL_FILE" | grep -q '^description:'; then
  pass "frontmatter に description フィールドがある"
else
  fail "frontmatter に description フィールドがない"
fi

# --- テスト3: 必須セクションの存在 ---

echo ""
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

# --- テスト4: コードブロックの言語指定 ---

echo ""
echo "--- テスト4: コードブロックの言語指定 ---"

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
if [[ "$BARE_OPEN_COUNT" -eq 0 ]]; then
  pass "全てのコードブロックに言語指定がある"
else
  fail "言語指定なしのコードブロックが ${BARE_OPEN_COUNT} 箇所ある"
fi

# --- テスト5: テンプレートとローカルの一致 ---

echo ""
echo "--- テスト5: テンプレートとローカルの一致 ---"

if [[ -f "$TEMPLATE_FILE" ]]; then
  pass "テンプレートファイルが存在する"
else
  fail "テンプレートファイルが存在しない"
fi

if [[ -f "$LOCAL_FILE" ]]; then
  if diff -q "$TEMPLATE_FILE" "$LOCAL_FILE" > /dev/null 2>&1; then
    pass "ローカルとテンプレートが一致する"
  else
    fail "ローカルとテンプレートが一致しない"
  fi
else
  pass "ローカルファイルなし（CI 環境 — テンプレートのみで検証）"
fi

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
