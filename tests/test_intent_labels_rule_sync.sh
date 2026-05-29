#!/bin/bash
# test_intent_labels_rule_sync.sh
# ─────────────────────────────────────────────
# Issue #575: intent-labels.md の本体版と配布版のサイレント乖離を防ぐ。
# Issue #747: SSOT をプラグインルート rules/ に一元化し、.claude/rules/ は rules/ への symlink にした。
# 乖離は symlink により構造的に起こり得ないため、本テストは「.claude/rules/ が SSOT rules/ に解決される」ことを検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== Issue #747 intent-labels.md の SSOT 整合検証（symlink dogfooding） ==="

# .claude/rules/ は dogfooding 用の symlink、rules/ が SSOT 実体。
SYMLINK="${SCRIPT_DIR}/.claude/rules/intent-labels.md"
SSOT="${SCRIPT_DIR}/rules/intent-labels.md"

assert_file_exists "SSOT rules/intent-labels.md" "$SSOT"
assert_file_exists ".claude/rules/intent-labels.md（symlink 経由で解決）" "$SYMLINK"

if [[ -L "$SYMLINK" ]]; then
  pass ".claude/rules/intent-labels.md が symlink である"
else
  fail ".claude/rules/intent-labels.md が symlink でない（SSOT 化未完了）"
fi

# symlink 経由の読込内容が SSOT 実体と一致することを確認する（cmp は symlink を解決する）。
if cmp -s "$SYMLINK" "$SSOT"; then
  pass ".claude/rules/intent-labels.md が SSOT rules/intent-labels.md に解決される"
else
  fail ".claude/rules/intent-labels.md が SSOT rules/intent-labels.md に解決されない"
fi

print_test_summary
