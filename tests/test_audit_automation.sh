#!/bin/bash
# test_audit_automation.sh — Phase 6: 事後監査自動化（/vibecorp:audit-cost, /vibecorp:audit-security）のテスト
# 使い方: bash tests/test_audit_automation.sh

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
AUDIT_COST_FILE="$PROJECT_DIR/skills/audit-cost/SKILL.md"
AUDIT_SECURITY_FILE="$PROJECT_DIR/skills/audit-security/SKILL.md"
COST_TEMPLATE="$PROJECT_DIR/templates/claude/knowledge/accounting/cost-audit-template.md"
SECURITY_TEMPLATE="$PROJECT_DIR/templates/claude/knowledge/security/security-audit-template.md"
COST_DOC="$PROJECT_DIR/docs/cost-analysis.md"
SECURITY_DOC="$PROJECT_DIR/docs/SECURITY.md"

echo "=== Phase 6: 事後監査自動化 テスト ==="

# --- テスト1: スキルファイルの存在 ---

echo ""
echo "--- テスト1: スキルファイル ---"

if [[ -f "$AUDIT_COST_FILE" ]]; then
  pass "audit-cost/SKILL.md が存在する"
else
  fail "audit-cost/SKILL.md が存在しない"
  exit 1
fi

if [[ -f "$AUDIT_SECURITY_FILE" ]]; then
  pass "audit-security/SKILL.md が存在する"
else
  fail "audit-security/SKILL.md が存在しない"
  exit 1
fi

# --- テスト2: knowledge テンプレート ---

echo ""
echo "--- テスト2: knowledge テンプレート ---"

if [[ -f "$COST_TEMPLATE" ]]; then
  pass "cost-audit-template.md が存在する"
else
  fail "cost-audit-template.md が存在しない"
fi

if [[ -f "$SECURITY_TEMPLATE" ]]; then
  pass "security-audit-template.md が存在する"
else
  fail "security-audit-template.md が存在しない"
fi

# --- テスト3: full プリセット限定 ---

echo ""
echo "--- テスト3: full プリセット限定 ---"

for f in "$AUDIT_COST_FILE" "$AUDIT_SECURITY_FILE"; do
  name=$(basename "$(dirname "$f")")
  if grep -q 'full プリセット専用' "$f"; then
    pass "${name} に full プリセット専用記述がある"
  else
    fail "${name} に full プリセット専用記述がない"
  fi

  if grep -q "awk '/\^preset:" "$f"; then
    pass "${name} に preset 検出 awk がある"
  else
    fail "${name} に preset 検出 awk がない"
  fi
done

# --- テスト4: エージェント参照 ---

echo ""
echo "--- テスト4: エージェント参照 ---"

if grep -q 'CFO' "$AUDIT_COST_FILE"; then
  pass "audit-cost が CFO を参照している"
else
  fail "audit-cost が CFO を参照していない"
fi

if grep -q 'cfo.md' "$AUDIT_COST_FILE"; then
  pass "audit-cost が cfo.md を参照している"
else
  fail "audit-cost が cfo.md を参照していない"
fi

if grep -q 'CISO' "$AUDIT_SECURITY_FILE"; then
  pass "audit-security が CISO を参照している"
else
  fail "audit-security が CISO を参照していない"
fi

if grep -q 'ciso.md' "$AUDIT_SECURITY_FILE"; then
  pass "audit-security が ciso.md を参照している"
else
  fail "audit-security が ciso.md を参照していない"
fi

# --- テスト5: 保存パス ---

echo ""
echo "--- テスト5: 保存パス ---"

if grep -q 'knowledge/accounting/audit-' "$AUDIT_COST_FILE"; then
  pass "audit-cost が knowledge/accounting/ への保存を指示している"
else
  fail "audit-cost が knowledge/accounting/ への保存を指示していない"
fi

if grep -q 'knowledge/security/audit-' "$AUDIT_SECURITY_FILE"; then
  pass "audit-security が knowledge/security/ への保存を指示している"
else
  fail "audit-security が knowledge/security/ への保存を指示していない"
fi

# --- テスト6: 監査範囲 ---

echo ""
echo "--- テスト6: 監査範囲 ---"

if grep -q '7 days ago' "$AUDIT_COST_FILE"; then
  pass "audit-cost が直近7日間を対象としている"
else
  fail "audit-cost が直近7日間を対象としていない"
fi

if grep -q '30 days ago' "$AUDIT_SECURITY_FILE"; then
  pass "audit-security が直近30日間を対象としている"
else
  fail "audit-security が直近30日間を対象としていない"
fi

# --- テスト7: Issue 起票 ---

echo ""
echo "--- テスト7: Issue 起票 ---"

for f in "$AUDIT_COST_FILE" "$AUDIT_SECURITY_FILE"; do
  name=$(basename "$(dirname "$f")")
  if grep -q 'audit' "$f" && grep -q '/vibecorp:issue' "$f"; then
    pass "${name} に Issue 起票の記述がある"
  else
    fail "${name} に Issue 起票の記述がない"
  fi
done

# --- テスト8: docs への追記 ---

echo ""
echo "--- テスト8: docs 追記 ---"

if grep -q '/vibecorp:audit-cost' "$COST_DOC"; then
  pass "docs/cost-analysis.md に /vibecorp:audit-cost の記述がある"
else
  fail "docs/cost-analysis.md に /vibecorp:audit-cost の記述がない"
fi

if grep -q '/vibecorp:audit-security' "$SECURITY_DOC"; then
  pass "docs/SECURITY.md に /vibecorp:audit-security の記述がある"
else
  fail "docs/SECURITY.md に /vibecorp:audit-security の記述がない"
fi

if grep -q '事後監査' "$COST_DOC"; then
  pass "docs/cost-analysis.md に事後監査セクションがある"
else
  fail "docs/cost-analysis.md に事後監査セクションがない"
fi

if grep -q '事後監査' "$SECURITY_DOC"; then
  pass "docs/SECURITY.md に事後監査セクションがある"
else
  fail "docs/SECURITY.md に事後監査セクションがない"
fi

# --- テスト9: 定期実行例 ---

echo ""
echo "--- テスト9: 定期実行例 ---"

for f in "$AUDIT_COST_FILE" "$AUDIT_SECURITY_FILE"; do
  name=$(basename "$(dirname "$f")")
  if grep -q '/schedule' "$f"; then
    pass "${name} に /schedule 定期実行例がある"
  else
    fail "${name} に /schedule 定期実行例がない"
  fi
done

# --- テスト10: テンプレート内容 ---

echo ""
echo "--- テスト10: テンプレート内容 ---"

for f in "$COST_TEMPLATE" "$SECURITY_TEMPLATE"; do
  name=$(basename "$f")
  for section in 'Critical' 'Major' 'Minor' '実施日' '監査範囲'; do
    if grep -q "$section" "$f"; then
      pass "${name} に「${section}」が含まれる"
    else
      fail "${name} に「${section}」が含まれない"
    fi
  done
done

# --- テスト11: コードブロック言語指定 ---

echo ""
echo "--- テスト11: コードブロック言語指定 ---"

for f in "$AUDIT_COST_FILE" "$AUDIT_SECURITY_FILE" "$COST_TEMPLATE" "$SECURITY_TEMPLATE"; do
  name=$(basename "$f")
  BARE_OPEN_COUNT=$(awk '
    /^```/ {
      if (in_block) { in_block = 0 }
      else {
        in_block = 1
        if ($0 == "```") bare++
      }
    }
    END { print bare+0 }
  ' "$f")
  if [[ "$BARE_OPEN_COUNT" -eq 0 ]]; then
    pass "${name} 全コードブロックに言語指定あり"
  else
    fail "${name} 言語指定なしコードブロック ${BARE_OPEN_COUNT} 箇所"
  fi
done

# --- テスト12: 参照エージェントファイル存在 ---

echo ""
echo "--- テスト12: 参照エージェントファイル ---"

for agent in cfo ciso; do
  agent_file="$PROJECT_DIR/templates/claude/agents/${agent}.md"
  if [[ -f "$agent_file" ]]; then
    pass "${agent}.md が存在する"
  else
    fail "${agent}.md が存在しない"
  fi
done

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
