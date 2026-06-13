#!/bin/bash
# test_golden_test_framework.sh
# ─────────────────────────────────────────────
# Issue #473: golden test フレームワークの検証

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== Issue #473 golden test フレームワークの検証 ==="

# ============================================
# 1. tests/golden/ ディレクトリと README, _example.json
# ============================================
echo ""
echo "--- 1. tests/golden ディレクトリ構造 ---"
assert_dir_exists "tests/golden ディレクトリ"      "${SCRIPT_DIR}/tests/golden"
assert_file_exists "tests/golden/README.md"        "${SCRIPT_DIR}/tests/golden/README.md"
assert_file_exists "tests/golden/_example.json"    "${SCRIPT_DIR}/tests/golden/_example.json"

# ============================================
# 2. README 記述
# ============================================
echo ""
echo "--- 2. README の主要記述 ---"
README="${SCRIPT_DIR}/tests/golden/README.md"
assert_file_contains "目的セクション"              "$README" "目的"
assert_file_contains "JSON スキーマ"                "$README" "JSON スキーマ"
assert_file_contains "判定方法"                    "$README" "判定方法"
assert_file_contains "実行タイミング"              "$README" "実行タイミング"
for intent in feature bugfix performance security refactor infra docs; do
  if grep -q -F -- "intent/${intent}" "$README"; then
    pass "README に intent/${intent} の言及がある"
  else
    fail "README に intent/${intent} の言及がない"
  fi
done

# ============================================
# 3. _example.json の JSON 構造
# ============================================
echo ""
echo "--- 3. _example.json のスキーマ ---"
EX="${SCRIPT_DIR}/tests/golden/_example.json"
# jq -e '.a, .b' は最後の式のみで終了コードが決まり、先頭欠落を検知できないため
# has() の論理積で各キーの存在を厳密検証する
if jq -e '
  has("pr_number") and
  has("pr_url") and
  has("intent") and
  has("description") and
  has("expected_severity_counts") and
  has("expected_keywords") and
  has("expected_keyword_min_match")
' "$EX" >/dev/null 2>&1; then
  pass "_example.json が必須フィールドを全て持つ"
else
  fail "_example.json が必須フィールドを欠いている"
fi

# ============================================
# 4. ワークフロー定義（Issue #531 で撤去済み）
#    golden test は claude-code-action のレビュー回帰検証用だった。レビュー機能の
#    vibehawk 移譲（Issue #531）により ai-review-golden-test.yml テンプレートは撤去された。
#    フレームワーク本体（tests/golden/ / scripts/run-golden-test.sh）は残置されるため
#    後続ブロックで検証を継続する。
# ============================================
echo ""
echo "--- 4. ai-review-golden-test.yml ワークフローが撤去されている（vibehawk 移譲） ---"
WF="${SCRIPT_DIR}/templates/.github/workflows/ai-review-golden-test.yml"
if [ -e "$WF" ]; then
  fail "ai-review-golden-test.yml テンプレートが残存（Issue #531 で撤去済みのはず）"
else
  pass "ai-review-golden-test.yml テンプレートが撤去されている（vibehawk 移譲）"
fi

# ============================================
# 5. ランナースクリプト
# ============================================
echo ""
echo "--- 5. scripts/run-golden-test.sh ---"
RUNNER="${SCRIPT_DIR}/scripts/run-golden-test.sh"
assert_file_exists "scripts/run-golden-test.sh" "$RUNNER"
assert_file_executable "実行権限あり"             "$RUNNER"
assert_file_contains "_example.json 除外"         "$RUNNER" "_example.json"
assert_file_contains "expected_severity_counts パース" "$RUNNER" "expected_severity_counts"
assert_file_contains "expected_keyword_min_match パース" "$RUNNER" "expected_keyword_min_match"

# ============================================
# 6. ランナーの動作確認（_example.json のみで PASS スキップ）
# ============================================
echo ""
echo "--- 6. ランナーが _example.json のみで安全にスキップする ---"
output=$(bash "$RUNNER" 2>&1 || true)
if echo "$output" | grep -q -F -- "実機検証期間 (#475)"; then
  pass "_example.json のみの状態で安全にスキップする"
else
  fail "ランナーが安全にスキップしない（出力: ${output}）"
fi

print_test_summary
