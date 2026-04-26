#!/bin/bash
# test_claude_gitignore.sh — .claude/.gitignore の必須エントリ検証
#
# 検証対象:
#   - .claude/.gitignore: install.sh デプロイファイルの ignore エントリが存在する
#   - templates/claude/.gitignore.tpl: 同上（Source of Truth）
#   - 回帰防止: PR #370 で削除された hooks/ skills/ agents/ 等が復活していること
#
# 目的:
#   Issue #389 の再発防止。PR #370 のリファクタで .claude/.gitignore から
#   hooks/ skills/ agents/ settings.json vibecorp.lock settings.local.json の
#   ignore エントリが削除され、VS Code で 53 件の untracked ファイルが表示された。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GITIGNORE="${SCRIPT_DIR}/.claude/.gitignore"
TEMPLATE="${SCRIPT_DIR}/templates/claude/.gitignore.tpl"

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    pass "${desc}"
  else
    fail "${desc} (ファイル不在: ${path})"
  fi
}

assert_entry_exists() {
  local desc="$1"
  local path="$2"
  local entry="$3"
  if [[ ! -f "$path" ]]; then
    fail "${desc} (ファイル不在: ${path})"
    return
  fi
  if grep -v '^#' "$path" | grep -Fqx -- "${entry}"; then
    pass "${desc}"
  else
    fail "${desc} (エントリ '${entry}' が '${path}' に見つからない)"
  fi
}

# ============================================
echo "=== .claude/.gitignore が存在する ==="
# ============================================

assert_file_exists ".claude/.gitignore が存在する" "$GITIGNORE"

if [[ ! -f "$GITIGNORE" ]]; then
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo ".claude/.gitignore が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== templates/claude/.gitignore.tpl が存在する ==="
# ============================================

assert_file_exists "templates/claude/.gitignore.tpl が存在する" "$TEMPLATE"

if [[ ! -f "$TEMPLATE" ]]; then
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "templates/claude/.gitignore.tpl が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== .claude/.gitignore に必須エントリが含まれる ==="
# ============================================

REQUIRED_ENTRIES=(
  "hooks/"
  "skills/"
  "agents/"
  "settings.json"
  "vibecorp.lock"
  "scheduled_tasks.json"
  "scheduled_tasks.lock"
  "settings.local.json"
)

for entry in "${REQUIRED_ENTRIES[@]}"; do
  assert_entry_exists ".claude/.gitignore に ${entry}" "$GITIGNORE" "$entry"
done

# ============================================
echo "=== templates/claude/.gitignore.tpl に必須エントリが含まれる ==="
# ============================================

for entry in "${REQUIRED_ENTRIES[@]}"; do
  assert_entry_exists ".gitignore.tpl に ${entry}" "$TEMPLATE" "$entry"
done

# ============================================
echo "=== テンプレートと installed copy の必須エントリ一致 ==="
# ============================================

extract_entries() {
  grep -v '^#' "$1" | grep -v '^$' | sort
}

GITIGNORE_ENTRIES="$(extract_entries "$GITIGNORE")"
TEMPLATE_ENTRIES="$(extract_entries "$TEMPLATE")"

if [[ "$GITIGNORE_ENTRIES" = "$TEMPLATE_ENTRIES" ]]; then
  pass "テンプレートと installed copy のエントリが一致する"
else
  fail "テンプレートと installed copy のエントリが不一致"
  echo "    --- .claude/.gitignore ---"
  echo "$GITIGNORE_ENTRIES" | while IFS= read -r line; do echo "    ${line}"; done
  echo "    --- templates/claude/.gitignore.tpl ---"
  echo "$TEMPLATE_ENTRIES" | while IFS= read -r line; do echo "    ${line}"; done
fi

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
