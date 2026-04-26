#!/bin/bash
# test_plan_review_agents.sh — 専門家エージェントによるプランレビュー機能のテスト
# 使い方: bash tests/test_plan_review_agents.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$PROJECT_DIR/templates/claude/agents"
SKILL_FILE="$PROJECT_DIR/skills/plan-review-loop/SKILL.md"
INSTALL_SCRIPT="$PROJECT_DIR/install.sh"

echo "=== 専門家エージェント プランレビュー テスト ==="
echo ""

# --- テスト1: エージェント定義ファイルの存在 ---

echo "--- テスト1: エージェント定義ファイルの存在 ---"

AGENT_FILES=(
  "plan-architect.md"
  "plan-security.md"
  "plan-testing.md"
  "plan-performance.md"
  "plan-dx.md"
  "plan-cost.md"
  "plan-legal.md"
)

for agent_file in "${AGENT_FILES[@]}"; do
  if [ -f "$AGENTS_DIR/$agent_file" ]; then
    pass "エージェント定義 ${agent_file} が存在する"
  else
    fail "エージェント定義 ${agent_file} が存在しない: $AGENTS_DIR/$agent_file"
  fi
done

echo ""

# --- テスト2: エージェント定義の frontmatter 検証 ---

echo "--- テスト2: エージェント定義の frontmatter 検証 ---"

for agent_file in "${AGENT_FILES[@]}"; do
  filepath="$AGENTS_DIR/$agent_file"
  [ -f "$filepath" ] || continue

  # frontmatter の開始/終了を確認
  first_line=$(head -n 1 "$filepath")
  if [ "$first_line" = "---" ]; then
    pass "${agent_file}: frontmatter が開始されている"
  else
    fail "${agent_file}: frontmatter が開始されていない（1行目: ${first_line}）"
  fi

  # name フィールドの存在確認
  if grep -q '^name:' "$filepath"; then
    pass "${agent_file}: name フィールドが存在する"
  else
    fail "${agent_file}: name フィールドが存在しない"
  fi

  # description フィールドの存在確認
  if grep -q '^description:' "$filepath"; then
    pass "${agent_file}: description フィールドが存在する"
  else
    fail "${agent_file}: description フィールドが存在しない"
  fi

  # tools フィールドの存在確認
  if grep -q '^tools:' "$filepath"; then
    pass "${agent_file}: tools フィールドが存在する"
  else
    fail "${agent_file}: tools フィールドが存在しない"
  fi

  # model フィールドの存在確認
  if grep -q '^model:' "$filepath"; then
    pass "${agent_file}: model フィールドが存在する"
  else
    fail "${agent_file}: model フィールドが存在しない"
  fi
done

echo ""

# --- テスト3: エージェント定義の出力形式セクション確認 ---

echo "--- テスト3: エージェント定義の出力形式セクション確認 ---"

for agent_file in "${AGENT_FILES[@]}"; do
  filepath="$AGENTS_DIR/$agent_file"
  [ -f "$filepath" ] || continue

  # 出力形式セクションの存在確認
  if grep -q '## 出力形式' "$filepath"; then
    pass "${agent_file}: 出力形式セクションが存在する"
  else
    fail "${agent_file}: 出力形式セクションが存在しない"
  fi

  # 「問題あり」「問題なし」のパターン確認
  if grep -q '### 問題あり' "$filepath"; then
    pass "${agent_file}: 問題あり出力パターンが存在する"
  else
    fail "${agent_file}: 問題あり出力パターンが存在しない"
  fi

  if grep -q '### 問題なし' "$filepath"; then
    pass "${agent_file}: 問題なし出力パターンが存在する"
  else
    fail "${agent_file}: 問題なし出力パターンが存在しない"
  fi
done

echo ""

# --- テスト4: plan-review-loop SKILL.md の専門家エージェント対応 ---

echo "--- テスト4: plan-review-loop SKILL.md の専門家エージェント対応 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "plan-review-loop SKILL.md が存在する"
else
  fail "plan-review-loop SKILL.md が存在しない: $SKILL_FILE"
fi

# 専門家エージェントモードのセクション確認
if grep -q '## 専門家エージェントモード' "$SKILL_FILE"; then
  pass "専門家エージェントモードセクションが存在する"
else
  fail "専門家エージェントモードセクションが存在しない"
fi

# vibecorp.yml の読み取り記述確認
if grep -q 'plan.review_agents' "$SKILL_FILE" || grep -q 'review_agents' "$SKILL_FILE"; then
  pass "review_agents 設定の読み取り記述が存在する"
else
  fail "review_agents 設定の読み取り記述が存在しない"
fi

# フォールバック記述確認
if grep -q 'フォールバック' "$SKILL_FILE"; then
  pass "フォールバック動作の記述が存在する"
else
  fail "フォールバック動作の記述が存在しない"
fi

# フィードバック統合セクション確認
if grep -q 'フィードバック統合' "$SKILL_FILE"; then
  pass "フィードバック統合セクションが存在する"
else
  fail "フィードバック統合セクションが存在しない"
fi

# エージェント名とファイルの対応表確認
if grep -q 'plan-architect.md' "$SKILL_FILE"; then
  pass "architect エージェントのファイル参照が存在する"
else
  fail "architect エージェントのファイル参照が存在しない"
fi

if grep -q 'plan-security.md' "$SKILL_FILE"; then
  pass "security エージェントのファイル参照が存在する"
else
  fail "security エージェントのファイル参照が存在しない"
fi

# 並列起動の記述確認
if grep -q '並列起動' "$SKILL_FILE"; then
  pass "並列起動の記述が存在する"
else
  fail "並列起動の記述が存在しない"
fi

# 調停ルールの記述確認
if grep -q '矛盾' "$SKILL_FILE" || grep -q '調停' "$SKILL_FILE"; then
  pass "矛盾解決・調停ルールの記述が存在する"
else
  fail "矛盾解決・調停ルールの記述が存在しない"
fi

# 最大5回ループの記述確認
if grep -q '最大5回' "$SKILL_FILE"; then
  pass "最大5回ループの記述が存在する"
else
  fail "最大5回ループの記述が存在しない"
fi

echo ""

# --- テスト5: vibecorp.yml テンプレートの plan.review_agents ---

echo "--- テスト5: vibecorp.yml テンプレートの plan.review_agents ---"

if grep -q 'review_agents' "$INSTALL_SCRIPT"; then
  pass "install.sh に review_agents の記述が存在する"
else
  fail "install.sh に review_agents の記述が存在しない"
fi

# コメントアウトされた plan セクションの確認
if grep -q '# plan:' "$INSTALL_SCRIPT" || grep -q 'plan:' "$INSTALL_SCRIPT"; then
  pass "install.sh に plan セクションの記述が存在する"
else
  fail "install.sh に plan セクションの記述が存在しない"
fi

echo ""

# --- テスト6: エージェント名の一致確認 ---

echo "--- テスト6: エージェント名の一致確認 ---"

# vibecorp.yml 設定名とエージェントファイル名の対応を確認
AGENT_NAMES=("architect" "security" "testing" "performance" "dx" "cost" "legal")

for name in "${AGENT_NAMES[@]}"; do
  agent_file="plan-${name}.md"
  if [ -f "$AGENTS_DIR/$agent_file" ]; then
    pass "設定名 '${name}' に対応するエージェント plan-${name}.md が存在する"
  else
    fail "設定名 '${name}' に対応するエージェント plan-${name}.md が存在しない"
  fi
done

# SKILL.md にエージェント名の対応表が存在するか
for name in "${AGENT_NAMES[@]}"; do
  if grep -q "\`${name}\`" "$SKILL_FILE"; then
    pass "SKILL.md に設定名 '${name}' の記述が存在する"
  else
    fail "SKILL.md に設定名 '${name}' の記述が存在しない"
  fi
done

echo ""

# --- テスト7: エージェント定義のコードブロック言語指定確認 ---

echo "--- テスト7: コードブロック言語指定確認（markdown ルール準拠） ---"

for agent_file in "${AGENT_FILES[@]}"; do
  filepath="$AGENTS_DIR/$agent_file"
  [ -f "$filepath" ] || continue

  # 言語指定なしの開始フェンスを検出する
  # 開始フェンスは ``` の後に言語名が続くべき（閉じフェンスは ``` のみで正常）
  # awk でフェンス内外を追跡し、外側の ``` のみ行（開始フェンスで言語指定なし）を検出
  bare_opens=$(awk '
    /^```[a-zA-Z]/ { in_fence = 1; next }
    /^```$/ {
      if (in_fence) { in_fence = 0 }
      else { count++ }
      next
    }
    END { print count + 0 }
  ' "$filepath")
  if [ "$bare_opens" -eq 0 ]; then
    pass "${agent_file}: 全てのコードブロックに言語指定がある"
  else
    fail "${agent_file}: 言語指定なしのコードブロックが ${bare_opens} 件ある"
  fi
done

# SKILL.md のコードブロックも確認
bare_opens=$(awk '
  /^```[a-zA-Z]/ { in_fence = 1; next }
  /^```$/ {
    if (in_fence) { in_fence = 0 }
    else { count++ }
    next
  }
  END { print count + 0 }
' "$SKILL_FILE")
if [ "$bare_opens" -eq 0 ]; then
  pass "plan-review-loop SKILL.md: 全てのコードブロックに言語指定がある"
else
  fail "plan-review-loop SKILL.md: 言語指定なしのコードブロックが ${bare_opens} 件ある"
fi

echo ""

# --- テスト8: 既存エージェント定義との共存確認 ---

echo "--- テスト8: 既存エージェント定義との共存確認 ---"

EXISTING_AGENTS=("cto.md" "cpo.md" "sm.md" "cfo.md" "ciso.md" "clo.md")

for existing in "${EXISTING_AGENTS[@]}"; do
  if [ -f "$AGENTS_DIR/$existing" ]; then
    pass "既存エージェント ${existing} が保持されている"
  else
    fail "既存エージェント ${existing} が失われている"
  fi
done

echo ""

# --- テスト9: plan-cost / plan-legal の権限境界記述 ---

echo "--- テスト9: plan-cost / plan-legal の権限境界記述 ---"

if [ -f "$AGENTS_DIR/plan-cost.md" ]; then
  if grep -q '## 権限境界' "$AGENTS_DIR/plan-cost.md"; then
    pass "plan-cost.md に権限境界セクションが存在する"
  else
    fail "plan-cost.md に権限境界セクションが存在しない"
  fi
  if grep -q 'CFO' "$AGENTS_DIR/plan-cost.md"; then
    pass "plan-cost.md に CFO 管轄区分の言及がある"
  else
    fail "plan-cost.md に CFO 管轄区分の言及がない"
  fi
fi

if [ -f "$AGENTS_DIR/plan-legal.md" ]; then
  if grep -q '## 権限境界' "$AGENTS_DIR/plan-legal.md"; then
    pass "plan-legal.md に権限境界セクションが存在する"
  else
    fail "plan-legal.md に権限境界セクションが存在しない"
  fi
  if grep -q 'CLO' "$AGENTS_DIR/plan-legal.md"; then
    pass "plan-legal.md に CLO 管轄区分の言及がある"
  else
    fail "plan-legal.md に CLO 管轄区分の言及がない"
  fi
fi

echo ""

# --- テスト10: SKILL.md の C*O メタレビュー層セクション ---

echo "--- テスト10: SKILL.md の C*O メタレビュー層セクション ---"

if grep -q 'C\*O メタレビュー層' "$SKILL_FILE" || grep -q 'C\\\*O メタレビュー層' "$SKILL_FILE"; then
  pass "SKILL.md に C*O メタレビュー層セクションが存在する"
else
  fail "SKILL.md に C*O メタレビュー層セクションが存在しない"
fi

# full プリセット限定の記述
if grep -q 'full プリセット' "$SKILL_FILE"; then
  pass "SKILL.md に full プリセット限定の記述がある"
else
  fail "SKILL.md に full プリセット限定の記述がない"
fi

# トリガー表の主要 C*O
META_COS=("CFO" "CISO" "CLO" "SM" "CPO" "CTO")
for co in "${META_COS[@]}"; do
  if grep -q "$co" "$SKILL_FILE"; then
    pass "SKILL.md にトリガー表の ${co} が存在する"
  else
    fail "SKILL.md にトリガー表の ${co} が存在しない"
  fi
done

# 平社員合議の言及
if grep -q 'accounting-analyst' "$SKILL_FILE"; then
  pass "SKILL.md に accounting-analyst×3 合議の言及がある"
else
  fail "SKILL.md に accounting-analyst×3 合議の言及がない"
fi

if grep -q 'security-analyst' "$SKILL_FILE"; then
  pass "SKILL.md に security-analyst×3 合議の言及がある"
else
  fail "SKILL.md に security-analyst×3 合議の言及がない"
fi

if grep -q 'legal-analyst' "$SKILL_FILE"; then
  pass "SKILL.md に legal-analyst×3 合議の言及がある"
else
  fail "SKILL.md に legal-analyst×3 合議の言及がない"
fi

echo ""

# --- テスト11: SKILL.md のプリセット別デフォルト記述 ---

echo "--- テスト11: SKILL.md のプリセット別デフォルト記述 ---"

# プリセット別デフォルト表
if grep -q 'プリセット別デフォルト' "$SKILL_FILE"; then
  pass "SKILL.md にプリセット別デフォルト記述が存在する"
else
  fail "SKILL.md にプリセット別デフォルト記述が存在しない"
fi

# full プリセットに cost, legal が含まれる記述
if grep -q 'architect, security, testing, performance, dx, cost, legal' "$SKILL_FILE"; then
  pass "SKILL.md に full プリセットのデフォルト review_agents 全列挙が存在する"
else
  fail "SKILL.md に full プリセットのデフォルト review_agents 全列挙が存在しない"
fi

echo ""

# --- 結果表示 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
