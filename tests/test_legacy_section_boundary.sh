#!/bin/bash
# test_legacy_section_boundary.sh — Issue #439 Phase 7: awk セクション境界判定の検証
# test_no_direct_knowledge_writes.sh の C*O 定義スキャンで使う「レガシー互換」セクション除外ロジックをテスト

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

echo "=== Issue #439 Phase 7: awk セクション境界判定テスト ==="

# 検査対象の awk スクリプト
filter_text() {
  awk '
    /^### [0-9]+\. 判断の記録$/ { in_section = 1; next }
    in_section && /^### / { in_section = 0 }
    in_section && /\*\*レガシー互換\*\*:/ { in_legacy = 1; next }
    in_section && in_legacy && /^\*\*[^*]+\*\*:/ { in_legacy = 0; print; next }
    in_section && in_legacy { next }
    in_section { print }
  '
}

# --- ケース 1: レガシー互換セクション内のヒットがスキップされる ---
echo ""
echo "--- ケース 1: レガシー互換セクション内のヒット除外 ---"

input_case1="$(cat <<'EOF'
### 4. 判断の記録

通常の書込み: `${BUFFER_DIR}/.claude/knowledge/cfo/decisions/2026-Q2.md`

**レガシー互換**: `.claude/knowledge/cfo/decisions.md` 旧形式は ${BUFFER_DIR} 配下で判定。

### 5. エスカレーション

法的リスクは即時上申。
EOF
)"

filtered_case1="$(echo "$input_case1" | filter_text)"
if echo "$filtered_case1" | grep -q '通常の書込み'; then
  pass "ケース 1: 通常の書込みは検出される"
else
  fail "ケース 1: 通常の書込みが除外されている"
fi

if echo "$filtered_case1" | grep -q 'レガシー互換'; then
  fail "ケース 1: レガシー互換セクションが除外されていない"
else
  pass "ケース 1: レガシー互換セクションが除外される"
fi

# --- ケース 2: レガシー互換セクション外のヒットは検出される ---
echo ""
echo "--- ケース 2: セクション外のヒットは検出される ---"

input_case2="$(cat <<'EOF'
### 4. 判断の記録

書込み: `.claude/knowledge/cfo/decisions/2026-Q2.md`

### 5. その他

別セクションのヒット: `.claude/knowledge/cto/decisions/2026-Q2.md`
EOF
)"

filtered_case2="$(echo "$input_case2" | filter_text)"
if echo "$filtered_case2" | grep -q 'cfo/decisions/2026-Q2.md'; then
  pass "ケース 2: 判断の記録節内のヒットは出力される"
else
  fail "ケース 2: 判断の記録節内のヒットが除外されている"
fi

if echo "$filtered_case2" | grep -q 'cto/decisions/2026-Q2.md'; then
  fail "ケース 2: 別セクションのヒットが含まれている（節境界判定が失敗）"
else
  pass "ケース 2: 別セクション「### 5. その他」は除外される"
fi

# --- ケース 3: ファイル末尾までレガシー互換が続く ---
echo ""
echo "--- ケース 3: 末尾までレガシー互換が続くケース ---"

input_case3="$(cat <<'EOF'
### 4. 判断の記録

書込み: `${BUFFER_DIR}/.claude/knowledge/cfo/decisions/2026-Q2.md`

**レガシー互換**: `.claude/knowledge/cfo/decisions.md` 旧形式
EOF
)"

filtered_case3="$(echo "$input_case3" | filter_text)"
if echo "$filtered_case3" | grep -q 'BUFFER_DIR'; then
  pass "ケース 3: BUFFER_DIR を含む書込みは出力される"
else
  fail "ケース 3: BUFFER_DIR を含む書込みが除外されている"
fi

if echo "$filtered_case3" | grep -q 'レガシー互換'; then
  fail "ケース 3: 末尾までのレガシー互換が除外されていない"
else
  pass "ケース 3: 末尾までのレガシー互換が除外される"
fi

# --- ケース 4: 「判断の記録」セクション以外のテキストは無視される ---
echo ""
echo "--- ケース 4: セクション外のテキスト無視 ---"

input_case4="$(cat <<'EOF'
### 1. 情報収集

`.claude/knowledge/cfo/decisions-index.md` を Read する。

### 4. 判断の記録

書込み: `${BUFFER_DIR}/.claude/knowledge/cfo/decisions/2026-Q2.md`
EOF
)"

filtered_case4="$(echo "$input_case4" | filter_text)"
if echo "$filtered_case4" | grep -q 'を Read する'; then
  fail "ケース 4: 別セクションの内容が含まれている"
else
  pass "ケース 4: 別セクション「### 1. 情報収集」は除外される"
fi

print_test_summary
