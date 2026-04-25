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
SKILL_FILE="$PROJECT_DIR/skills/autopilot/SKILL.md"

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
if awk '/^---$/{c++; next} c==1' "$SKILL_FILE" | grep -Eq '^name:[[:space:]]*autopilot[[:space:]]*$'; then
  pass "frontmatter の name が autopilot である"
else
  fail "frontmatter の name が autopilot ではない"
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

# --- テスト5: knowledge/buffer 収集フローの参照 ---

echo ""
echo "--- テスト5: knowledge/buffer 収集フローの参照 ---"

if grep -q '/vibecorp:review-harvest' "$SKILL_FILE"; then
  pass "/vibecorp:review-harvest が参照されている"
else
  fail "/vibecorp:review-harvest が参照されていない"
fi

if grep -q '/vibecorp:knowledge-pr' "$SKILL_FILE"; then
  pass "/vibecorp:knowledge-pr が参照されている"
else
  fail "/vibecorp:knowledge-pr が参照されていない"
fi

# /vibecorp:review-harvest が /vibecorp:knowledge-pr より先に記述されていることを確認
# （同一行内も許容: `/vibecorp:review-harvest` → `/vibecorp:knowledge-pr` の順であれば OK）
if awk '
  /\/vibecorp:review-harvest.*\/vibecorp:knowledge-pr/ { print "order_ok"; exit }
  /vibecorp:review-harvest/ && !seen_harvest { seen_harvest = NR }
  /vibecorp:knowledge-pr/ && !seen_pr { seen_pr = NR }
  END {
    if (seen_harvest && seen_pr && seen_harvest < seen_pr) print "order_ok"
  }
' "$SKILL_FILE" | grep -q '^order_ok$'; then
  pass "/vibecorp:review-harvest が /vibecorp:knowledge-pr より先に記述されている"
else
  fail "/vibecorp:review-harvest → /vibecorp:knowledge-pr の順序になっていない"
fi

# knowledge/buffer への言及
if grep -q 'knowledge/buffer' "$SKILL_FILE"; then
  pass "knowledge/buffer フローが言及されている"
else
  fail "knowledge/buffer フローが言及されていない"
fi

# main への直接 push が発生しない旨の明記
if grep -q 'main' "$SKILL_FILE" && grep -Eq 'auto-merge|直接 push は(一切)?発生しない' "$SKILL_FILE"; then
  pass "main 反映は auto-merge 経由である旨が明記されている"
else
  fail "main 反映経路の明記が不足している"
fi

# --- テスト6: ラベル縛り撤廃（Issue #361） ---

echo ""
echo "--- テスト6: ラベル縛り撤廃（Issue #361） ---"

# 6-1: `--label "diagnose"` がコマンドから削除されている
if grep -q 'gh issue list --label "diagnose"' "$SKILL_FILE"; then
  fail "ラベル縛り撤廃: gh issue list から --label \"diagnose\" が削除されていない"
else
  pass "ラベル縛り撤廃: gh issue list に --label \"diagnose\" がない"
fi

# 6-2: 「ラベル問わず」が明記されている
if grep -q 'ラベル問わず' "$SKILL_FILE"; then
  pass "ラベル問わず全 open Issue を対象とする旨が明記されている"
else
  fail "ラベル問わず全 open Issue を対象とする旨が明記されていない"
fi

# 6-3: diagnose ラベルが「起票経路の識別用途」として記載されている
if grep -q '起票経路の識別用途' "$SKILL_FILE"; then
  pass "diagnose ラベルが「起票経路の識別用途」として明記されている"
else
  fail "diagnose ラベルの位置付け（起票経路の識別用途）が明記されていない"
fi

# 6-4: 起票側（/vibecorp:diagnose と /issue）の3者承認ゲートへの言及がある
if grep -q '起票側' "$SKILL_FILE" && grep -q '3者承認ゲート' "$SKILL_FILE"; then
  pass "起票側の3者承認ゲートへの言及がある"
else
  fail "起票側の3者承認ゲートへの言及が不足している"
fi

# --- テスト7: 互換スタブの廃止確認 ---

echo ""
echo "--- テスト7: 互換スタブの廃止確認 ---"

if [[ -d "$PROJECT_DIR/.claude/skills/autopilot" ]]; then
  fail ".claude/skills/autopilot/ が残存している（Phase 3 で廃止済み）"
else
  pass ".claude/skills/autopilot/ が廃止されている"
fi

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
