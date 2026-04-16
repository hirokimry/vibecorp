#!/bin/bash
# test_sync_check_expansion.sh — Phase 4: sync-check 管轄 C*O 拡張のテスト
# 使い方: bash tests/test_sync_check_expansion.sh

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
SKILL_FILE="$PROJECT_DIR/templates/claude/skills/sync-check/SKILL.md"

echo "=== sync-check 管轄 C*O 拡張 テスト ==="

# --- テスト1: SKILL.md の存在 ---

echo ""
echo "--- テスト1: SKILL.md の存在 ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  exit 1
fi

# --- テスト2: プリセット検出 ---

echo ""
echo "--- テスト2: プリセット検出 ---"

if grep -q 'プリセット検出' "$SKILL_FILE"; then
  pass "プリセット検出セクションが存在する"
else
  fail "プリセット検出セクションが存在しない"
fi

if grep -q "awk '/\^preset:/" "$SKILL_FILE"; then
  pass "preset 取得 awk コマンドが記載されている"
else
  fail "preset 取得 awk コマンドが記載されていない"
fi

# --- テスト3: full プリセット自動起動 ---

echo ""
echo "--- テスト3: full プリセット自動起動 ---"

if grep -q 'full プリセット時の自動起動' "$SKILL_FILE"; then
  pass "full プリセット自動起動セクションが存在する"
else
  fail "full プリセット自動起動セクションが存在しない"
fi

if grep -q 'preset: full' "$SKILL_FILE"; then
  pass "preset: full の条件記述が存在する"
else
  fail "preset: full の条件記述が存在しない"
fi

# --- テスト4: デフォルト管轄（CTO / CPO 常時起動） ---

echo ""
echo "--- テスト4: デフォルト管轄 ---"

if grep -q 'デフォルト管轄' "$SKILL_FILE"; then
  pass "デフォルト管轄セクションが存在する"
else
  fail "デフォルト管轄セクションが存在しない"
fi

if grep -q '全プリセット共通' "$SKILL_FILE"; then
  pass "全プリセット共通の記述が存在する"
else
  fail "全プリセット共通の記述が存在しない"
fi

# --- テスト5: C*O トリガー表 ---

echo ""
echo "--- テスト5: C*O トリガー表 ---"

for role in CFO CISO CLO SM; do
  if grep -q "| $role |" "$SKILL_FILE"; then
    pass "トリガー表に $role が記載されている"
  else
    fail "トリガー表に $role が記載されていない"
  fi
done

# --- テスト6: 領域別キーワード ---

echo ""
echo "--- テスト6: 領域別キーワード ---"

# 課金領域
if grep -q 'ANTHROPIC_API_KEY' "$SKILL_FILE"; then
  pass "課金領域キーワード ANTHROPIC_API_KEY が記載されている"
else
  fail "課金領域キーワード ANTHROPIC_API_KEY が記載されていない"
fi

# セキュリティ領域
if grep -q -E '`auth`|`token`|`secret`' "$SKILL_FILE"; then
  pass "セキュリティ領域キーワードが記載されている"
else
  fail "セキュリティ領域キーワードが記載されていない"
fi

# 法務領域
if grep -q 'LICENSE' "$SKILL_FILE"; then
  pass "法務領域キーワード LICENSE が記載されている"
else
  fail "法務領域キーワード LICENSE が記載されていない"
fi

# 組織運営領域
if grep -q '.claude/agents/' "$SKILL_FILE"; then
  pass "組織運営領域キーワード .claude/agents/ が記載されている"
else
  fail "組織運営領域キーワード .claude/agents/ が記載されていない"
fi

# --- テスト7: 差分検知コマンド ---

echo ""
echo "--- テスト7: 差分検知コマンド ---"

if grep -q 'git diff main\.\.\.HEAD -U0' "$SKILL_FILE"; then
  pass "差分検知コマンド git diff main...HEAD -U0 が記載されている"
else
  fail "差分検知コマンド git diff main...HEAD -U0 が記載されていない"
fi

if grep -q 'grep -iE' "$SKILL_FILE"; then
  pass "キーワード検出 grep -iE が記載されている"
else
  fail "キーワード検出 grep -iE が記載されていない"
fi

# --- テスト8: C*O 管轄ファイル ---

echo ""
echo "--- テスト8: C*O 管轄ファイル ---"

for doc in 'cost-analysis.md' 'SECURITY.md' 'POLICY.md' 'ai-organization.md'; do
  if grep -q "$doc" "$SKILL_FILE"; then
    pass "$doc への参照が存在する"
  else
    fail "$doc への参照が存在しない"
  fi
done

# --- テスト9: standard / minimal フォールバック ---

echo ""
echo "--- テスト9: standard / minimal フォールバック ---"

if grep -q -E 'standard.*minimal|minimal.*standard' "$SKILL_FILE"; then
  pass "standard / minimal のフォールバック記述が存在する"
else
  fail "standard / minimal のフォールバック記述が存在しない"
fi

if grep -q '既存挙動' "$SKILL_FILE"; then
  pass "既存挙動維持の記述が存在する"
else
  fail "既存挙動維持の記述が存在しない"
fi

# --- テスト10: コードブロック言語指定 ---

echo ""
echo "--- テスト10: コードブロック言語指定 ---"

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

# --- テスト11: 参照エージェントファイルの存在 ---

echo ""
echo "--- テスト11: 参照エージェントファイルの存在 ---"

for agent in cfo ciso clo sm cpo cto; do
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
