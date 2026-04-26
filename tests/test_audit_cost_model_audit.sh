#!/bin/bash
# test_audit_cost_model_audit.sh — Issue #354: /audit-cost のモデル指定監査機能テスト
# 使い方: bash tests/test_audit_cost_model_audit.sh

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
SKILL_FILE="$PROJECT_DIR/skills/audit-cost/SKILL.md"
TEMPLATE_FILE="$PROJECT_DIR/templates/claude/knowledge/accounting/cost-audit-template.md"
COST_DOC="$PROJECT_DIR/docs/cost-analysis.md"

echo "=== Issue #354: /audit-cost モデル指定監査 テスト ==="

# --- テスト1: 前提ファイルの存在 ---

echo ""
echo "--- テスト1: 前提ファイル ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "skills/audit-cost/SKILL.md が存在する"
else
  fail "skills/audit-cost/SKILL.md が存在しない"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

if [[ -f "$TEMPLATE_FILE" ]]; then
  pass "cost-audit-template.md が存在する"
else
  fail "cost-audit-template.md が存在しない"
  exit 1
fi

if [[ -f "$COST_DOC" ]]; then
  pass "docs/cost-analysis.md が存在する"
else
  fail "docs/cost-analysis.md が存在しない"
  exit 1
fi

# --- テスト2: SKILL.md にモデル指定監査の記述がある ---

echo ""
echo "--- テスト2: SKILL.md モデル指定監査 ---"

if grep -q "モデル指定" "$SKILL_FILE"; then
  pass "SKILL.md に「モデル指定」の記述がある"
else
  fail "SKILL.md に「モデル指定」の記述がない"
fi

if grep -q "templates/claude/agents" "$SKILL_FILE"; then
  pass "SKILL.md が templates/claude/agents 走査対象を指示している"
else
  fail "SKILL.md が templates/claude/agents を指示していない"
fi

if grep -q "\.claude/agents" "$SKILL_FILE"; then
  pass "SKILL.md が .claude/agents 走査対象を指示している"
else
  fail "SKILL.md が .claude/agents を指示していない"
fi

# --- テスト3: SKILL.md に役割別判定ガイドがある ---

echo ""
echo "--- テスト3: 役割別判定ガイド ---"

# C-suite + 合議分析員ロール
for role in cfo cto cpo clo ciso accounting-analyst legal-analyst security-analyst; do
  if grep -q -e "\`${role}\`" "$SKILL_FILE"; then
    pass "SKILL.md が C-suite/分析員ロール ${role} を列挙している"
  else
    fail "SKILL.md が C-suite/分析員ロール ${role} を列挙していない"
  fi
done

# 定型作業ロール
for role in branch commit pr sm plan-architect; do
  if grep -q -e "\`${role}\`" "$SKILL_FILE"; then
    pass "SKILL.md が定型作業ロール ${role} を列挙している"
  else
    fail "SKILL.md が定型作業ロール ${role} を列挙していない"
  fi
done

# Opus / Sonnet / Haiku 言及
for model in Opus Sonnet Haiku; do
  if grep -q "$model" "$SKILL_FILE"; then
    pass "SKILL.md が ${model} を判定対象として言及している"
  else
    fail "SKILL.md が ${model} を判定対象として言及していない"
  fi
done

# --- テスト4: SKILL.md に Major / Minor 判定区分がある ---

echo ""
echo "--- テスト4: 判定区分 ---"

if grep -q "Major" "$SKILL_FILE" && grep -q "Haiku" "$SKILL_FILE"; then
  pass "SKILL.md に Haiku → Major の判定がある"
else
  fail "SKILL.md に Haiku → Major の判定がない"
fi

if grep -q "Major" "$SKILL_FILE" && grep -q "過剰指定" "$SKILL_FILE"; then
  pass "SKILL.md に Opus 過剰指定 → Major の判定がある"
else
  fail "SKILL.md に Opus 過剰指定 → Major の判定がない"
fi

# --- テスト5: SKILL.md に「警告のみ・自動変更しない」制約がある ---

echo ""
echo "--- テスト5: 自動変更禁止の制約 ---"

if grep -q "モデル指定の自動変更は行わない" "$SKILL_FILE"; then
  pass "SKILL.md に「モデル指定の自動変更は行わない」制約がある"
else
  fail "SKILL.md に「モデル指定の自動変更は行わない」制約がない"
fi

# --- テスト6: SKILL.md に Diff 抽出コマンドがある ---

echo ""
echo "--- テスト6: Diff 抽出 ---"

if grep -q "7 days ago" "$SKILL_FILE" && grep -q "model:" "$SKILL_FILE"; then
  pass "SKILL.md に直近7日間 model: 行 Diff 抽出の記述がある"
else
  fail "SKILL.md に直近7日間 model: 行 Diff 抽出の記述がない"
fi

# --- テスト7: テンプレートに「モデル指定監査」節がある ---

echo ""
echo "--- テスト7: テンプレート モデル指定監査節 ---"

if grep -q "## モデル指定監査" "$TEMPLATE_FILE"; then
  pass "テンプレートに「## モデル指定監査」節がある"
else
  fail "テンプレートに「## モデル指定監査」節がない"
fi

for sub in "走査対象" "役割別判定" "Diff" "警告サマリ"; do
  if grep -q "$sub" "$TEMPLATE_FILE"; then
    pass "テンプレートに「${sub}」小見出しがある"
  else
    fail "テンプレートに「${sub}」小見出しがない"
  fi
done

# テンプレートの判定区分
for label in "判断品質が存在意義のロール" "定型作業ロール"; do
  if grep -q "$label" "$TEMPLATE_FILE"; then
    pass "テンプレートに「${label}」の判定区分がある"
  else
    fail "テンプレートに「${label}」の判定区分がない"
  fi
done

# --- テスト8: docs/cost-analysis.md の事後監査観点にモデル指定が追加されている ---

echo ""
echo "--- テスト8: docs/cost-analysis.md 監査観点 ---"

if awk '/^## 事後監査/,0' "$COST_DOC" | grep -q "モデル指定"; then
  pass "docs/cost-analysis.md の事後監査セクションに「モデル指定」が追加されている"
else
  fail "docs/cost-analysis.md の事後監査セクションに「モデル指定」が追加されていない"
fi

if awk '/^## 事後監査/,0' "$COST_DOC" | grep -q "Opus" && \
   awk '/^## 事後監査/,0' "$COST_DOC" | grep -q "Sonnet" && \
   awk '/^## 事後監査/,0' "$COST_DOC" | grep -q "Haiku"; then
  pass "docs/cost-analysis.md の事後監査セクションに Opus/Sonnet/Haiku が言及されている"
else
  fail "docs/cost-analysis.md の事後監査セクションに Opus/Sonnet/Haiku の言及が不足している"
fi

# --- テスト9: コードブロック言語指定（markdown.md ルール） ---

echo ""
echo "--- テスト9: コードブロック言語指定 ---"

for f in "$SKILL_FILE" "$TEMPLATE_FILE"; do
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

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
