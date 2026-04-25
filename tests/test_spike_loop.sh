#!/bin/bash
# test_spike_loop.sh — spike-loop スキルのテスト
# 使い方: bash tests/test_spike_loop.sh

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
SKILL_FILE="$PROJECT_DIR/skills/spike-loop/SKILL.md"

echo "=== spike-loop スキル テスト ==="

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
  exit 1
fi

# --- テスト2: frontmatter の検証 ---

echo ""
echo "--- テスト2: frontmatter の検証 ---"

if head -1 "$SKILL_FILE" | grep -q '^---$'; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りが存在しない"
fi

if grep -q "^name: spike-loop$" "$SKILL_FILE"; then
  pass "name フィールドが 'spike-loop' である"
else
  fail "name フィールドが 'spike-loop' でない"
fi

if grep -q '^description:' "$SKILL_FILE"; then
  pass "description フィールドが存在する"
else
  fail "description フィールドが存在しない"
fi

# --- テスト3: 必須セクションの存在 ---

echo ""
echo "--- テスト3: 必須セクションの存在 ---"

if grep -q '## 使用方法' "$SKILL_FILE"; then
  pass "使用方法セクションが存在する"
else
  fail "使用方法セクションが存在しない"
fi

if grep -q '## ワークフロー\|## フロー' "$SKILL_FILE"; then
  pass "ワークフローセクションが存在する"
else
  fail "ワークフローセクションが存在しない"
fi

# --- テスト4: コア機能の検証 ---

echo ""
echo "--- テスト4: コア機能の検証 ---"

# 4-1: ヘッドレス Claude 起動に claude -p を使用
if grep -q 'claude.*-p\|claude.*--print' "$SKILL_FILE"; then
  pass "ヘッドレス Claude 起動に claude -p を使用している"
else
  fail "ヘッドレス Claude 起動に claude -p を使用していない"
fi

# 4-2: permission-mode dontAsk の指定
if grep -q 'permission-mode.*dontAsk\|dontAsk' "$SKILL_FILE"; then
  pass "permission-mode dontAsk の指定がある"
else
  fail "permission-mode dontAsk の指定がない"
fi

# 4-3: stuck 判定ロジックへの言及
if grep -q 'stuck' "$SKILL_FILE"; then
  pass "stuck 判定への言及がある"
else
  fail "stuck 判定への言及がない"
fi

# 4-4: command-log を使用した監視
if grep -q 'command-log' "$SKILL_FILE"; then
  pass "command-log を使用した監視への言及がある"
else
  fail "command-log を使用した監視への言及がない"
fi

# 4-5: 成功判定（PR 作成の確認）
if grep -q 'gh pr\|PR.*作成\|成功判定' "$SKILL_FILE"; then
  pass "成功判定（PR 確認）への言及がある"
else
  fail "成功判定（PR 確認）への言及がない"
fi

# 4-6: kill + cleanup への言及
if grep -q 'kill\|cleanup\|クリーンアップ' "$SKILL_FILE"; then
  pass "kill + cleanup への言及がある"
else
  fail "kill + cleanup への言及がない"
fi

# 4-7: findings の保存
if grep -q 'findings\|スナップショット\|snapshot' "$SKILL_FILE"; then
  pass "findings/スナップショット保存への言及がある"
else
  fail "findings/スナップショット保存への言及がない"
fi

# 4-8: 最大ループ回数の制限
if grep -q 'max.*run\|最大.*回\|ループ.*上限' "$SKILL_FILE"; then
  pass "最大ループ回数の制限がある"
else
  fail "最大ループ回数の制限がない"
fi

# --- テスト5: コードブロックの言語指定 ---

echo ""
echo "--- テスト5: コードブロックの言語指定 ---"

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

# --- テスト6: 互換スタブの廃止確認 ---

echo ""
echo "--- テスト6: 互換スタブの廃止確認 ---"

if [[ -d "$PROJECT_DIR/.claude/skills/spike-loop" ]]; then
  fail ".claude/skills/spike-loop/ が残存している（Phase 3 で廃止済み）"
else
  pass ".claude/skills/spike-loop/ が廃止されている"
fi

# --- 結果出力 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
