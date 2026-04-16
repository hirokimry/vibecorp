#!/bin/bash
# test_autopilot_approval_gate.sh — Phase 5: 3者承認ゲート（CISO + CPO + SM）のテスト
# 使い方: bash tests/test_autopilot_approval_gate.sh

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
RULES_FILE="$PROJECT_DIR/templates/claude/rules/autonomous-restrictions.md"
DIAGNOSE_FILE="$PROJECT_DIR/templates/claude/skills/diagnose/SKILL.md"
AUTOPILOT_FILE="$PROJECT_DIR/templates/claude/skills/autopilot/SKILL.md"

echo "=== Phase 5: 3者承認ゲート テスト ==="

# --- テスト1: rules/autonomous-restrictions.md の存在 ---

echo ""
echo "--- テスト1: rules ファイル ---"

if [[ -f "$RULES_FILE" ]]; then
  pass "autonomous-restrictions.md が存在する"
else
  fail "autonomous-restrictions.md が存在しない"
  exit 1
fi

# --- テスト2: 不可領域5カテゴリの明記 ---

echo ""
echo "--- テスト2: 不可領域5カテゴリ ---"

for category in '認証' '暗号' '課金構造' 'ガードレール' 'MVV'; do
  if grep -q "$category" "$RULES_FILE"; then
    pass "不可領域「${category}」が記載されている"
  else
    fail "不可領域「${category}」が記載されていない"
  fi
done

# --- テスト3: 不可領域のキーワード ---

echo ""
echo "--- テスト3: 不可領域キーワード ---"

if grep -q 'ANTHROPIC_API_KEY' "$RULES_FILE"; then
  pass "課金構造キーワード ANTHROPIC_API_KEY が記載されている"
else
  fail "課金構造キーワード ANTHROPIC_API_KEY が記載されていない"
fi

if grep -q 'protect-files' "$RULES_FILE"; then
  pass "ガードレールキーワード protect-files が記載されている"
else
  fail "ガードレールキーワード protect-files が記載されていない"
fi

if grep -q -E 'permission|auth' "$RULES_FILE"; then
  pass "認証キーワード（permission/auth）が記載されている"
else
  fail "認証キーワード（permission/auth）が記載されていない"
fi

# --- テスト4: diagnose SKILL.md の SM フィルタ ---

echo ""
echo "--- テスト4: diagnose SM フィルタ ---"

if grep -q 'SM フィルタリング' "$DIAGNOSE_FILE"; then
  pass "diagnose に SM フィルタリングセクションが存在する"
else
  fail "diagnose に SM フィルタリングセクションが存在しない"
fi

if grep -q 'autonomous-restrictions.md' "$DIAGNOSE_FILE"; then
  pass "diagnose が autonomous-restrictions.md を参照している"
else
  fail "diagnose が autonomous-restrictions.md を参照していない"
fi

if grep -q '3者承認ゲート' "$DIAGNOSE_FILE"; then
  pass "diagnose に「3者承認ゲート」の記述が存在する"
else
  fail "diagnose に「3者承認ゲート」の記述が存在しない"
fi

# --- テスト5: 既存 CISO/CPO フィルタの保持 ---

echo ""
echo "--- テスト5: 既存フィルタの保持 ---"

if grep -q 'CISO フィルタリング' "$DIAGNOSE_FILE"; then
  pass "既存の CISO フィルタリングが保持されている"
else
  fail "既存の CISO フィルタリングが削除されている"
fi

if grep -q 'CPO フィルタリング' "$DIAGNOSE_FILE"; then
  pass "既存の CPO フィルタリングが保持されている"
else
  fail "既存の CPO フィルタリングが削除されている"
fi

# --- テスト6: 3者承認ゲートでの SM 除外カウント表示 ---

echo ""
echo "--- テスト6: 3者除外カウント ---"

if grep -q 'SM 除外' "$DIAGNOSE_FILE"; then
  pass "diagnose に「SM 除外」の表示項目が存在する"
else
  fail "diagnose に「SM 除外」の表示項目が存在しない"
fi

# --- テスト7: autopilot の3者承認ゲート言及 ---

echo ""
echo "--- テスト7: autopilot ---"

if grep -q '3者承認ゲート' "$AUTOPILOT_FILE"; then
  pass "autopilot に「3者承認ゲート」の記述が存在する"
else
  fail "autopilot に「3者承認ゲート」の記述が存在しない"
fi

if grep -q 'autonomous-restrictions.md' "$AUTOPILOT_FILE"; then
  pass "autopilot が autonomous-restrictions.md を参照している"
else
  fail "autopilot が autonomous-restrictions.md を参照していない"
fi

# --- テスト8: 前提条件に SM 追加 ---

echo ""
echo "--- テスト8: 前提条件 ---"

if awk '/^## 前提条件/{f=1; next} f && /^## /{f=0} f' "$DIAGNOSE_FILE" | grep -q 'SM'; then
  pass "diagnose 前提条件に SM が追加されている"
else
  fail "diagnose 前提条件に SM が追加されていない"
fi

# --- テスト9: コードブロック言語指定 ---

echo ""
echo "--- テスト9: コードブロック言語指定 ---"

for f in "$RULES_FILE" "$DIAGNOSE_FILE" "$AUTOPILOT_FILE"; do
  name=$(basename "$f")
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
  ' "$f")
  if [[ "$BARE_OPEN_COUNT" -eq 0 ]]; then
    pass "${name} 全コードブロックに言語指定がある"
  else
    fail "${name} 言語指定なしコードブロックが ${BARE_OPEN_COUNT} 箇所"
  fi
done

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
