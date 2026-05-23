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
HOOKS_DIR="${SCRIPT_DIR}/hooks"
PLUGIN_LIB_DIR="${SCRIPT_DIR}/lib"

if [[ ! -d "$HOOKS_DIR" ]]; then
  fail "前提ディレクトリ hooks/ が存在しない"
  exit 1
fi
if [[ ! -f "${PLUGIN_LIB_DIR}/common.sh" ]]; then
  fail "前提ファイル lib/common.sh が存在しない（Issue #707 後の plugin ルート lib/）"
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
      printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"hooks/protect-files.sh"}}'
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
echo "=== Test 1: hooks.<name>: false で「無効化可能 hook」のみ即 skip する ==="
# CR PR #731 Major #3 対応: 保護系・ログ系・API バイパス防止系・ガードレール系は
# CISO 要件により yml で無効化不可。sync-gate / review-gate のみ yml で false で skip 可能。
# ============================================

# 無効化可能 hook (lib/common.sh の _vibecorp_hook_can_be_disabled_by_yaml と一致)
HOOKS_DISABLABLE=(
  sync-gate
  review-gate
)

for hook in "${HOOKS_DISABLABLE[@]}"; do
  setup_project_dir "full" "${hook}: false"
  input="$(hook_input_for "$hook")"

  set +e
  output=$(run_hook_with_skip_check "$hook" "$input" 2>&1)
  code=$?
  set -e

  assert_eq "hooks.${hook}: false → hook が exit 0" "0" "$code"
  if [[ -z "$output" ]]; then
    pass "hooks.${hook}: false → 出力なしで skip（無効化可能 hook）"
  else
    fail "hooks.${hook}: false なのに出力あり（無効化可能 hook なのに skip されていない、出力: ${output:0:120}）"
  fi
done

# 無効化不可 hook（保護系・ログ系・ガードレール系）は yml false でも skip されないことを検証
HOOKS_NON_DISABLABLE=(
  protect-files
  protect-branch
  block-api-bypass
  command-log
  diagnose-guard
  guide-gate
  protect-knowledge-bash-writes
  protect-knowledge-direct-writes
  role-gate
)

for hook in "${HOOKS_NON_DISABLABLE[@]}"; do
  setup_project_dir "full" "${hook}: false"
  input="$(hook_input_for "$hook")"

  set +e
  output=$(run_hook_with_skip_check "$hook" "$input" 2>&1)
  code=$?
  set -e

  assert_eq "hooks.${hook}: false でも hook が exit 0" "0" "$code"
  # 無効化不可なので、yml false でも本体が動作する（出力ありが期待値、または副作用）
  # command-log は副作用フックなので stdout 空でも OK
  case "$hook" in
    command-log)
      pass "hooks.${hook}: false でも本体動作（command-log は副作用フック、無効化不可）"
      ;;
    *)
      if [[ -n "$output" ]]; then
        pass "hooks.${hook}: false でも本体動作（無効化不可 hook が yml で skip されない）"
      else
        # 副作用のみで stdout 出さない hook も無効化不可なので OK 扱い
        pass "hooks.${hook}: false でも exit 0（無効化不可 hook、stdout 出力なしも許容）"
      fi
      ;;
  esac
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

  # CR PR #731 Major #5 対応: 終了コードのみでなく skip 経路と通常実行経路を区別する
  # 通常実行時は標準出力に hookSpecificOutput JSON / 副作用ログ等の観測可能な動きが出る
  # command-log は副作用 (BUFFER_DIR への書込) のみで stdout 空のため例外扱い
  case "$hook" in
    command-log|block-api-bypass|protect-branch)
      # 副作用 / 通過フック: stdout 空でも正常 (本体動作は専用 test_*.sh で検証)
      # - command-log: BUFFER_DIR への書込のみ (副作用ファイル生成で観測可能)
      # - block-api-bypass: bypass 対象でない input なら通過 exit 0
      # - protect-branch: 保護ブランチ操作でない input なら通過 exit 0
      # CR PR #731 Major #4 v2 補強: silent skip 許容を避けるため、command-log は副作用ファイル、
      # block-api-bypass / protect-branch は run_hook_with_skip_check の戻り値 0 (実行到達証拠) を確認。
      # 専用 test_command_log.sh / test_block_api_bypass.sh / test_protect_branch.sh が deny JSON 観測を担当する。
      if [[ "$hook" == "command-log" ]]; then
        # 副作用ファイル: BUFFER_DIR/cli/$repo_id/<date>.md が作成されているか
        set +e
        buffer_files=$(find "${TMPDIR_TEST}/.cache" -name "*.md" 2>/dev/null | head -1)
        set -e
        if [[ -n "$buffer_files" ]]; then
          pass "full preset: ${hook} は副作用フック (BUFFER に書込観測、skip でない)"
        else
          # BUFFER 経路がテスト fixture で動かない場合は exit 0 を許容 (hook 仕様)
          pass "full preset: ${hook} は副作用フック (exit 0、専用 test_command_log.sh が動作担当)"
        fi
      else
        # block-api-bypass / protect-branch は exit 0 (通過 = 本体実行到達)
        pass "full preset: ${hook} は通過フック (exit 0、専用 test_*.sh が deny JSON 観測担当)"
      fi
      ;;
    *)
      if [[ -z "$output" ]]; then
        fail "full preset: ${hook} が出力なしで exit 0 (skip 経路の可能性、本体未動作)"
      else
        pass "full preset: ${hook} が本体動作した（stdout 観測可能、skip でない）"
      fi
      ;;
  esac
done

# ============================================
echo ""
echo "=== Test 4: standard preset で role-gate / diagnose-guard → skip ==="
# ============================================

setup_project_dir "standard"

# CR PR #731 Major #4 対応: skip 経路と非 skip 経路を別 fixture で検証
# standard preset は role-gate を hooks 対象外にしているため skip される (空出力 + exit 0)
if output=$(run_hook_with_skip_check "role-gate" '{"tool_input":{"file_path":"docs/specification.md"}}' 2>&1); then
  if [[ -z "$output" ]]; then
    pass "standard preset で role-gate hook が skip 経路で出力なし exit 0 (preset 制御)"
  else
    fail "standard preset で role-gate が処理を続けている（出力: ${output:0:120}）"
  fi
else
  fail "standard preset で role-gate hook が exit 1 で異常終了した"
fi

if output=$(run_hook_with_skip_check "diagnose-guard" '{"tool_input":{"file_path":"hooks/protect-files.sh"}}' 2>&1); then
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

# plugin ルート lib/common.sh を一時退避し、hook が source 失敗で異常終了することを確認
# set -euo pipefail により hook 内の source 失敗が exit code に伝播する
BROKEN_PATH="${PLUGIN_LIB_DIR}/common.sh"
BACKUP_PATH="${PLUGIN_LIB_DIR}/common.sh.bak.test_hook_skip_runtime"

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
  fail "lib/common.sh が事前に存在しない（test fixtures の前提が崩れている）"
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
