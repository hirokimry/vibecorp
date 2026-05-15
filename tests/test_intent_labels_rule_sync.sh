#!/bin/bash
# test_intent_labels_rule_sync.sh
# ─────────────────────────────────────────────
# Issue #575: .claude/rules/intent-labels.md と templates/claude/rules/intent-labels.md の
# サイレント乖離を防ぐ。配布版（テンプレート）と本体版を完全一致させる。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== Issue #575 intent-labels.md の本体版とテンプレート版の同期検証 ==="

SOURCE="${SCRIPT_DIR}/.claude/rules/intent-labels.md"
TEMPLATE="${SCRIPT_DIR}/templates/claude/rules/intent-labels.md"

assert_file_exists "本体版 intent-labels.md" "$SOURCE"
assert_file_exists "テンプレート版 intent-labels.md" "$TEMPLATE"

if diff -q "$SOURCE" "$TEMPLATE" >/dev/null; then
  pass "本体版とテンプレート版が完全一致している"
else
  fail "本体版とテンプレート版に差分あり（サイレント乖離リスク）"
  echo "差分:"
  diff "$SOURCE" "$TEMPLATE" || true
fi

print_test_summary
