#!/usr/bin/env bash
# C*O エージェント定義が decisions-index.md の 2 段構成に対応していることを検証する
# 対象: templates/claude/agents/{ciso,cto,cpo,cfo,clo,sm}.md

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

pass() {
  PASSED=$((PASSED + 1))
  echo "  ✅ $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "  ❌ $1"
}

assert_file_contains_pattern() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  if grep -qE -- "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name (パターン「$pattern」が $file に見つからない)"
  fi
}

echo "=== C*O エージェント decisions-index.md 対応検証 ==="

for agent in ciso cto cpo cfo clo sm; do
  file="templates/claude/agents/${agent}.md"
  echo ""
  echo "--- ${agent} ---"

  if [[ ! -f "$file" ]]; then
    fail "${agent}: エージェント定義ファイルが存在しない"
    continue
  fi

  # 1. decisions-index.md 参照
  assert_file_contains_pattern "${agent}: decisions-index.md 参照を含む" \
    "$file" "decisions-index\.md"

  # 2. アーカイブファイルパス参照（decisions/YYYY-QN.md または {YYYY-QN}）
  assert_file_contains_pattern "${agent}: 四半期アーカイブパス参照を含む" \
    "$file" "decisions/(\{YYYY-QN\}|YYYY-QN)\.md"

  # 3. レガシー fallback 記述
  assert_file_contains_pattern "${agent}: レガシー互換 fallback 記述を含む" \
    "$file" "レガシー互換"

  # 4. decisions/ ディレクトリ自動作成の指示
  assert_file_contains_pattern "${agent}: decisions/ ディレクトリ自動作成指示を含む" \
    "$file" "decisions/\` が存在しなければ作成"

  # 5. 書き込み順序の記述（アーカイブ → インデックス）
  assert_file_contains_pattern "${agent}: 書き込み順序の記述を含む" \
    "$file" "アーカイブ → インデックス"
done

echo ""
echo "=== 結果 ==="
echo "PASS: $PASSED"
echo "FAIL: $FAILED"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
