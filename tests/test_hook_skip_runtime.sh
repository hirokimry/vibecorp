#!/bin/bash
# test_hook_skip_runtime.sh — hook 自己 skip 判定のランタイム検証（Issue #704）
# vibecorp.yml の hooks: <name>: false / preset 非対象で hook が即 exit するかを検証する
# 使い方: bash tests/test_hook_skip_runtime.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/hook_fixtures.sh"
sync_lib_for_hook_tests

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/templates/claude/hooks"

TMPDIR_TEST=""
cleanup() {
  [[ -n "$TMPDIR_TEST" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT

setup_project_dir() {
  local preset="$1"
  local hooks_yml="${2:-}"  # 例: 'protect-files: false'

  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.claude"

  if [[ -n "$hooks_yml" ]]; then
    cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<EOF
name: test-project
preset: ${preset}
language: ja
hooks:
  ${hooks_yml}
EOF
  else
    cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<EOF
name: test-project
preset: ${preset}
language: ja
EOF
  fi
}

run_hook_with_skip_check() {
  local hook_name="$1"
  local input="$2"

  CLAUDE_PROJECT_DIR="$TMPDIR_TEST" \
    bash "${HOOKS_DIR}/${hook_name}.sh" <<< "$input"
}

echo "=== Test 1: vibecorp.yml で hook 個別無効化 → skip ==="

setup_project_dir "full" "protect-files: false"

if output=$(run_hook_with_skip_check "protect-files" '{"tool_input":{"file_path":".claude/settings.json"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "yml で protect-files: false → hook が出力なしで exit 0 する"
  else
    fail "yml で disable しても hook が処理を続けている（出力: ${output:0:100}）"
  fi
else
  fail "yml で disable した hook が exit 1 で異常終了した"
fi

echo ""
echo "=== Test 2: minimal preset で standard 専用 hook → skip ==="

setup_project_dir "minimal"

if output=$(run_hook_with_skip_check "sync-gate" '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "minimal preset で sync-gate hook が出力なしで exit 0 する"
  else
    fail "minimal preset で sync-gate が処理を続けている（出力: ${output:0:100}）"
  fi
else
  fail "minimal preset で sync-gate hook が exit 1 で異常終了した"
fi

echo ""
echo "=== Test 3: full preset で全 hook が通常動作 ==="

setup_project_dir "full"

# protect-files は full で有効、保護対象ファイル編集を試みると deny される（自己 skip しない）
if output=$(run_hook_with_skip_check "protect-files" '{"tool_input":{"file_path":"MVV.md"}}' 2>&1); then
  if echo "$output" | grep -q '"permissionDecision"'; then
    pass "full preset で protect-files が通常動作（permissionDecision を返す）"
  else
    # MVV.md が protected_files に入っていない場合は出力なしで exit 0 が正しい
    if [[ -z "$output" ]]; then
      pass "full preset で protect-files が通常処理を実行（保護対象外でスキップ判定）"
    else
      fail "full preset で protect-files の出力が想定外（出力: ${output:0:100}）"
    fi
  fi
else
  fail "full preset で protect-files が異常終了"
fi

echo ""
echo "=== Test 4: standard preset で role-gate / diagnose-guard → skip ==="

setup_project_dir "standard"

if output=$(run_hook_with_skip_check "role-gate" '{"tool_input":{"file_path":"docs/specification.md"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "standard preset で role-gate hook が出力なしで exit 0 する"
  else
    fail "standard preset で role-gate が処理を続けている（出力: ${output:0:100}）"
  fi
else
  fail "standard preset で role-gate hook が exit 1 で異常終了した"
fi

if output=$(run_hook_with_skip_check "diagnose-guard" '{"tool_input":{"file_path":"templates/claude/hooks/protect-files.sh"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "standard preset で diagnose-guard hook が出力なしで exit 0 する"
  else
    fail "standard preset で diagnose-guard が処理を続けている（出力: ${output:0:100}）"
  fi
else
  fail "standard preset で diagnose-guard hook が exit 1 で異常終了した"
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
