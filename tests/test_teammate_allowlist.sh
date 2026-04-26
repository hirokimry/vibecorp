#!/bin/bash
# test_teammate_allowlist.sh — settings.json の permissions.allow が
# teammate 書込 stuck 緩和パターンを含むことを検証する (#369)
# 使い方: bash tests/test_teammate_allowlist.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

assert_allow_contains() {
  local settings_path="$1"
  local pattern="$2"
  local desc="allowlist: ${settings_path#"$REPO_ROOT"/} に $pattern"

  if [[ ! -f "$settings_path" ]]; then
    fail "$desc (ファイル不在)"
    return
  fi

  if jq -e --arg p "$pattern" '.permissions.allow | index($p)' "$settings_path" > /dev/null; then
    pass "$desc"
  else
    fail "$desc (allow に未登録)"
  fi
}

# #369 で追加する 12 パターン
# macOS (/Users) と Linux (/home) を両方カバーすることで
# 配布テンプレートが全対応 OS で機能するようにする（public-ready.md 準拠）
REQUIRED_PATTERNS=(
  "Write(.claude/knowledge/**)"
  "Edit(.claude/knowledge/**)"
  "Write(.claude/plans/**)"
  "Edit(.claude/plans/**)"
  "Write(//Users/**/.cache/vibecorp/plans/**)"
  "Edit(//Users/**/.cache/vibecorp/plans/**)"
  "Write(//Users/**/.cache/vibecorp/state/**)"
  "Edit(//Users/**/.cache/vibecorp/state/**)"
  "Write(//home/**/.cache/vibecorp/plans/**)"
  "Edit(//home/**/.cache/vibecorp/plans/**)"
  "Write(//home/**/.cache/vibecorp/state/**)"
  "Edit(//home/**/.cache/vibecorp/state/**)"
)

# 検証対象: 本体と配布テンプレート両方に同一 allowlist が必要
# （templates は新規導入先に配布される雛形、.claude は本プロジェクト自身の設定）
SETTINGS_FILES=(
  "$REPO_ROOT/.claude/settings.json"
  "$REPO_ROOT/templates/claude/settings.json"
)

echo "=== teammate allowlist 検証 (#369) ==="

for settings_path in "${SETTINGS_FILES[@]}"; do
  echo ""
  echo "--- ${settings_path#"$REPO_ROOT"/} ---"
  for pattern in "${REQUIRED_PATTERNS[@]}"; do
    assert_allow_contains "$settings_path" "$pattern"
  done
done

echo ""
echo "=== 結果 ==="
echo "PASS: $PASSED / $TOTAL"
echo "FAIL: $FAILED / $TOTAL"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
