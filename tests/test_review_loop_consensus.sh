#!/bin/bash
# test_review_loop_consensus.sh — /review-loop の合議制 + C*O メタレビュー層のテスト
# 使い方: bash tests/test_review_loop_consensus.sh

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
SKILL_FILE="$PROJECT_DIR/templates/claude/skills/review-loop/SKILL.md"
AGENTS_DIR="$PROJECT_DIR/templates/claude/agents"

echo "=== /review-loop 合議制 + C*O メタレビュー テスト ==="
echo ""

# --- テスト1: SKILL.md の存在 ---

echo "--- テスト1: SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "review-loop SKILL.md が存在する"
else
  fail "review-loop SKILL.md が存在しない: $SKILL_FILE"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

echo ""

# --- テスト2: C*O メタレビュー層セクション ---

echo "--- テスト2: C*O メタレビュー層セクション ---"

if grep -q -e '合議制レビュー' "$SKILL_FILE"; then
  pass "合議制レビューセクションが存在する"
else
  fail "合議制レビューセクションが存在しない"
fi

if grep -q -e 'full プリセット' "$SKILL_FILE"; then
  pass "full プリセット限定の記述が存在する"
else
  fail "full プリセット限定の記述が存在しない"
fi

# preset 取得コマンド
if grep -q -e '/\^preset:/' "$SKILL_FILE"; then
  pass "preset 取得の awk コマンドが存在する"
else
  fail "preset 取得の awk コマンドが存在しない"
fi

echo ""

# --- テスト3: トリガー表の C*O と analyst ---

echo "--- テスト3: トリガー表の C*O と平社員合議 ---"

COS=("CFO" "CISO" "CLO")
for co in "${COS[@]}"; do
  if grep -q -e "$co" "$SKILL_FILE"; then
    pass "トリガー表に $co が存在する"
  else
    fail "トリガー表に $co が存在しない"
  fi
done

ANALYSTS=("accounting-analyst" "security-analyst" "legal-analyst")
for analyst in "${ANALYSTS[@]}"; do
  if grep -q -e "$analyst" "$SKILL_FILE"; then
    pass "SKILL.md に $analyst の参照が存在する"
  else
    fail "SKILL.md に $analyst の参照が存在しない"
  fi

  if grep -q -e "${analyst}×3" "$SKILL_FILE" || grep -q -e "${analyst} を ×3" "$SKILL_FILE"; then
    pass "$analyst の ×3 独立実行記述が存在する"
  else
    fail "$analyst の ×3 独立実行記述が存在しない"
  fi
done

# 複数領域ヒット時の並列起動要件
if grep -q -e '複数該当.*並列起動' "$SKILL_FILE"; then
  pass "複数領域ヒット時の並列起動記述が存在する"
else
  fail "複数領域ヒット時の並列起動記述が存在しない"
fi

# 複数該当時に該当全 C*O を並列起動する明示的記述
if grep -q -e '複数該当時は該当全 C\*O を並列起動' "$SKILL_FILE"; then
  pass "複数該当時に該当全 C*O を並列起動する記述が存在する"
else
  fail "複数該当時に該当全 C*O を並列起動する記述が存在しない"
fi

# 複数領域該当時の analyst×3 並列実行（実装セクション）
if grep -q -e '複数領域が該当.*analyst×3.*並列' "$SKILL_FILE" || grep -q -e '複数領域.*同時並列' "$SKILL_FILE"; then
  pass "複数領域該当時の analyst×3 並列実行記述が存在する"
else
  fail "複数領域該当時の analyst×3 並列実行記述が存在しない"
fi

echo ""

# --- テスト4: 領域別キーワード ---

echo "--- テスト4: 領域別キーワード ---"

BILLING_KEYS=("ANTHROPIC_API_KEY" "rate limit" "トークン消費")
for key in "${BILLING_KEYS[@]}"; do
  if grep -q -e "$key" "$SKILL_FILE"; then
    pass "課金領域キーワード '$key' が存在する"
  else
    fail "課金領域キーワード '$key' が存在しない"
  fi
done

SECURITY_KEYS=("auth" "token" "secret" "credential")
for key in "${SECURITY_KEYS[@]}"; do
  if grep -q -e "$key" "$SKILL_FILE"; then
    pass "セキュリティ領域キーワード '$key' が存在する"
  else
    fail "セキュリティ領域キーワード '$key' が存在しない"
  fi
done

LEGAL_KEYS=("LICENSE" "third-party" "package.json")
for key in "${LEGAL_KEYS[@]}"; do
  if grep -q -e "$key" "$SKILL_FILE"; then
    pass "法務領域キーワード '$key' が存在する"
  else
    fail "法務領域キーワード '$key' が存在しない"
  fi
done

echo ""

# --- テスト5: PR コメント upsert ---

echo "--- テスト5: PR コメント upsert ---"

if grep -q -e 'consensus-review' "$SKILL_FILE"; then
  pass "コメントマーカー consensus-review が存在する"
else
  fail "コメントマーカー consensus-review が存在しない"
fi

if grep -q -e 'existing_id' "$SKILL_FILE"; then
  pass "upsert の existing_id 検索ロジックが存在する"
else
  fail "upsert の existing_id 検索ロジックが存在しない"
fi

if grep -q -e 'gh pr comment' "$SKILL_FILE" && grep -q -e 'PATCH' "$SKILL_FILE"; then
  pass "upsert の新規投稿 / 更新パスが両方存在する"
else
  fail "upsert の新規投稿 / 更新パスが揃っていない"
fi

# Major 以上の判定基準
if grep -q -e 'Major 以上' "$SKILL_FILE"; then
  pass "Major 以上で PR コメント投稿の記述が存在する"
else
  fail "Major 以上で PR コメント投稿の記述が存在しない"
fi

# review-criteria.md への参照
if grep -q -e 'review-criteria.md' "$SKILL_FILE"; then
  pass "review-criteria.md への参照が存在する"
else
  fail "review-criteria.md への参照が存在しない"
fi

echo ""

# --- テスト6: CodeRabbit との位置づけ ---

echo "--- テスト6: CodeRabbit との位置づけ ---"

if grep -q -e 'CodeRabbit' "$SKILL_FILE" || grep -q -e '/review' "$SKILL_FILE"; then
  pass "/review / CodeRabbit との関係記述が存在する"
else
  fail "/review / CodeRabbit との関係記述が存在しない"
fi

if grep -q -e '置き換えではなく追加' "$SKILL_FILE"; then
  pass "合議制が追加レイヤーである記述が存在する"
else
  fail "合議制が追加レイヤーである記述が存在しない"
fi

echo ""

# --- テスト7: standard / minimal フォールバック ---

echo "--- テスト7: standard / minimal フォールバック ---"

if grep -q -e '既存挙動を維持' "$SKILL_FILE" || grep -q -e 'standard 以下' "$SKILL_FILE"; then
  pass "standard / minimal でのフォールバック記述が存在する"
else
  fail "standard / minimal でのフォールバック記述が存在しない"
fi

if grep -q -e 'ヒットなし' "$SKILL_FILE" || grep -q -e '起動しない' "$SKILL_FILE"; then
  pass "キーワード未ヒット時のスキップ記述が存在する"
else
  fail "キーワード未ヒット時のスキップ記述が存在しない"
fi

echo ""

# --- テスト8: 参照エージェント定義の存在 ---

echo "--- テスト8: 参照エージェント定義の存在 ---"

REQUIRED_AGENTS=(
  "cfo.md"
  "ciso.md"
  "clo.md"
  "accounting-analyst.md"
  "security-analyst.md"
  "legal-analyst.md"
)

for agent in "${REQUIRED_AGENTS[@]}"; do
  if [ -f "$AGENTS_DIR/$agent" ]; then
    pass "参照エージェント $agent が存在する"
  else
    fail "参照エージェント $agent が存在しない: $AGENTS_DIR/$agent"
  fi
done

echo ""

# --- テスト9: コードブロック言語指定（rules/markdown.md 準拠） ---

echo "--- テスト9: コードブロック言語指定 ---"

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
  pass "review-loop SKILL.md: 全てのコードブロックに言語指定がある"
else
  fail "review-loop SKILL.md: 言語指定なしのコードブロックが ${bare_opens} 件ある"
fi

echo ""

# --- 結果表示 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
