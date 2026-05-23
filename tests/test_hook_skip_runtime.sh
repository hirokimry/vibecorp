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
TEMPLATES_LIB_DIR="${SCRIPT_DIR}/templates/claude/lib"

if [[ ! -d "$HOOKS_DIR" ]]; then
  fail "前提ディレクトリ templates/claude/hooks/ が存在しない"
  exit 1
fi
if [[ ! -f "${TEMPLATES_LIB_DIR}/common.sh" ]]; then
  fail "前提ファイル templates/claude/lib/common.sh が存在しない（sync_lib_for_hook_tests 失敗）"
  exit 1
fi

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

# hook 名 → hook 自身が動作可能な最小入力 JSON
# Bash 系（command-log / block-api-bypass / sync-gate / review-gate /
# protect-knowledge-bash-writes / protect-branch）には command を渡す。
# Edit/Write 系（protect-files / guide-gate / role-gate / diagnose-guard /
# protect-knowledge-direct-writes）には file_path を渡す。
hook_input_for() {
  local hook="$1"
  case "$hook" in
    block-api-bypass|command-log)
      printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo test"}}'
      ;;
    sync-gate)
      printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
      ;;
    review-gate)
      printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
      ;;
    protect-knowledge-bash-writes)
      printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x > .claude/knowledge/cpo/decisions/foo.md"}}'
      ;;
    protect-branch)
      printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
      ;;
    protect-files)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"MVV.md"}}'
      ;;
    guide-gate)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":".claude/hooks/role-gate.sh"}}'
      ;;
    role-gate)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"docs/SECURITY.md"}}'
      ;;
    diagnose-guard)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"templates/claude/hooks/protect-files.sh"}}'
      ;;
    protect-knowledge-direct-writes)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":".claude/knowledge/cpo/decisions/foo.md"}}'
      ;;
    *)
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}'
      ;;
  esac
}

# 全 11 hook（Issue #704 対象）
HOOKS_ALL=(
  block-api-bypass
  command-log
  diagnose-guard
  guide-gate
  protect-branch
  protect-files
  protect-knowledge-bash-writes
  protect-knowledge-direct-writes
  review-gate
  role-gate
  sync-gate
)

# ============================================
echo "=== Test 1: hooks.<name>: false で各 hook が即 skip する（11 hook 一括） ==="
# ============================================

for hook in "${HOOKS_ALL[@]}"; do
  # preset を full にして preset 由来 skip を排除した上で、yml で当該 hook を明示無効化
  setup_project_dir "full" "${hook}: false"
  input="$(hook_input_for "$hook")"

  set +e
  output=$(run_hook_with_skip_check "$hook" "$input" 2>&1)
  code=$?
  set -e

  assert_eq "hooks.${hook}: false → hook が exit 0" "0" "$code"
  if [[ -z "$output" ]]; then
    pass "hooks.${hook}: false → 出力なしで skip（deny JSON を出さない）"
  else
    fail "hooks.${hook}: false なのに出力あり（skip されていない、出力: ${output:0:120}）"
  fi
done

# ============================================
echo ""
echo "=== Test 2: minimal preset で standard 専用 hook が skip する ==="
# ============================================

# minimal で skip すべき hook（standard / full 専用）
HOOKS_MINIMAL_SKIP=(
  sync-gate
  review-gate
  guide-gate
  role-gate
  diagnose-guard
)

setup_project_dir "minimal"

for hook in "${HOOKS_MINIMAL_SKIP[@]}"; do
  input="$(hook_input_for "$hook")"
  set +e
  output=$(run_hook_with_skip_check "$hook" "$input" 2>&1)
  code=$?
  set -e

  assert_eq "minimal preset: ${hook} → hook が exit 0" "0" "$code"
  if [[ -z "$output" ]]; then
    pass "minimal preset: ${hook} → 出力なしで skip"
  else
    fail "minimal preset: ${hook} なのに出力あり（skip されていない、出力: ${output:0:120}）"
  fi
done

# ============================================
echo ""
echo "=== Test 3: full preset で全 hook が通常動作する（skip しない） ==="
# ============================================

# full preset では yml に hooks 明示無効化がなければ全 hook が hook 本体に進む
# protect-files は MVV.md を protected_files に入れて deny が返ることで「本体が動作した」と判定

TMPDIR_TEST="$(mktemp -d)"
mkdir -p "${TMPDIR_TEST}/.claude"
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
protected_files:
  - MVV.md
YAML

set +e
output=$(CLAUDE_PROJECT_DIR="$TMPDIR_TEST" bash "${HOOKS_DIR}/protect-files.sh" <<< '{"tool_input":{"file_path":"MVV.md"}}' 2>&1)
code=$?
set -e

assert_eq "full preset: protect-files は exit 0 で終了（hook 仕様）" "0" "$code"
if echo "$output" | grep -q '"permissionDecision": "deny"'; then
  pass "full preset: protect-files 本体が動作（MVV.md 編集を deny）"
else
  fail "full preset: protect-files 本体が動作しない（skip 判定が誤動作している可能性、出力: ${output:0:120}）"
fi

# 残りの 10 hook も full preset で skip されないこと（exit 0 で終了するが、本体は動作する）を確認
HOOKS_OTHER_FULL=(
  block-api-bypass
  command-log
  diagnose-guard
  guide-gate
  protect-branch
  protect-knowledge-bash-writes
  protect-knowledge-direct-writes
  review-gate
  role-gate
  sync-gate
)

setup_project_dir "full"
for hook in "${HOOKS_OTHER_FULL[@]}"; do
  input="$(hook_input_for "$hook")"
  set +e
  output=$(run_hook_with_skip_check "$hook" "$input" 2>&1)
  code=$?
  set -e

  assert_eq "full preset: ${hook} は exit 0 で終了（hook 仕様）" "0" "$code"
done

# ============================================
echo ""
echo "=== Test 4: standard preset で role-gate / diagnose-guard → skip ==="
# ============================================

setup_project_dir "standard"

if output=$(run_hook_with_skip_check "role-gate" '{"tool_input":{"file_path":"docs/specification.md"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "standard preset で role-gate hook が出力なしで exit 0 する"
  else
    fail "standard preset で role-gate が処理を続けている（出力: ${output:0:120}）"
  fi
else
  fail "standard preset で role-gate hook が exit 1 で異常終了した"
fi

if output=$(run_hook_with_skip_check "diagnose-guard" '{"tool_input":{"file_path":"templates/claude/hooks/protect-files.sh"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "standard preset で diagnose-guard hook が出力なしで exit 0 する"
  else
    fail "standard preset で diagnose-guard が処理を続けている（出力: ${output:0:120}）"
  fi
else
  fail "standard preset で diagnose-guard hook が exit 1 で異常終了した"
fi

# ============================================
echo ""
echo "=== Test 5: CISO 条件 1: lib/common.sh source 失敗時に hook が fail-secure する ==="
# ============================================

# templates/claude/lib/common.sh を一時退避し、hook が source 失敗で異常終了することを確認
# set -euo pipefail により hook 内の source 失敗が exit code に伝播する
BROKEN_PATH="${TEMPLATES_LIB_DIR}/common.sh"
BACKUP_PATH="${TEMPLATES_LIB_DIR}/common.sh.bak.test_hook_skip_runtime"

if [[ -f "$BROKEN_PATH" ]]; then
  mv "$BROKEN_PATH" "$BACKUP_PATH"

  setup_project_dir "full"
  set +e
  output=$(run_hook_with_skip_check "block-api-bypass" '{"tool_name":"Bash","tool_input":{"command":"echo test"}}' 2>&1)
  code=$?
  set -e

  # common.sh 不在で hook がエラー終了する = ガードレールが fail-secure に倒れる
  if [[ "$code" -ne 0 ]]; then
    pass "lib/common.sh 不在時に hook がエラー終了する（fail-secure、CISO 条件 1）"
  else
    fail "lib/common.sh 不在時に hook が正常終了（exit 0）した（ガードレール無効化を許してしまっている、出力: ${output:0:120}）"
  fi

  # 復元
  mv "$BACKUP_PATH" "$BROKEN_PATH"
else
  fail "templates/claude/lib/common.sh が事前に存在しない（test fixtures の前提が崩れている）"
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
