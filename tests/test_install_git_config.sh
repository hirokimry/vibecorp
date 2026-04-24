#!/bin/bash
# test_install_git_config.sh — install.sh の git config 推奨設定適用テスト（Issue #383）
# 使い方: bash tests/test_install_git_config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# ヘルパー: REPO_ROOT の local git config から key の値を返す（未設定なら空）
get_local_config() {
  local repo="$1"
  local key="$2"
  git -C "$repo" config --local --get "$key" 2>/dev/null || true
}

# ============================================
echo "=== GITCONFIG. install.sh が推奨 git config を適用する（Issue #383） ==="
# ============================================

# G1. 初回 install 後に merge.ff=only が設定される
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G1: install 成功" "0" "$EXIT_CODE"
MERGE_FF=$(get_local_config "$TMPDIR_ROOT" merge.ff)
if [[ "$MERGE_FF" == "only" ]]; then
  pass "G1: merge.ff=only が設定される"
else
  fail "G1: merge.ff=only が設定されていない（実際: '$MERGE_FF'）"
fi
cleanup

# G2. 初回 install 後に pull.ff=only が設定される
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G2: install 成功" "0" "$EXIT_CODE"
PULL_FF=$(get_local_config "$TMPDIR_ROOT" pull.ff)
if [[ "$PULL_FF" == "only" ]]; then
  pass "G2: pull.ff=only が設定される"
else
  fail "G2: pull.ff=only が設定されていない（実際: '$PULL_FF'）"
fi
cleanup

# G3. 初回 install 後、local pull.rebase は未設定のまま（事前も未設定のケース）
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G3: install 成功" "0" "$EXIT_CODE"
PULL_REBASE=$(get_local_config "$TMPDIR_ROOT" pull.rebase)
if [[ -z "$PULL_REBASE" ]]; then
  pass "G3: local pull.rebase は未設定のまま"
else
  fail "G3: local pull.rebase が設定されている（実際: '$PULL_REBASE'）"
fi
cleanup

# G4. 事前に local pull.rebase=false を設定 → install 後に unset される
create_test_repo
git -C "$TMPDIR_ROOT" config --local pull.rebase false
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G4: install 成功（事前設定あり）" "0" "$EXIT_CODE"
PULL_REBASE=$(get_local_config "$TMPDIR_ROOT" pull.rebase)
if [[ -z "$PULL_REBASE" ]]; then
  pass "G4: 事前設定済み pull.rebase が unset される"
else
  fail "G4: pull.rebase が unset されていない（実際: '$PULL_REBASE'）"
fi
cleanup

# G5. 冪等性: 2 回実行しても成功し、全設定が維持される
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G5-1: 1 回目 install 成功" "0" "$EXIT_CODE"
EXIT_CODE=0; bash "$INSTALL_SH" --update 2>/dev/null || EXIT_CODE=$?
assert_exit_code "G5-2: 2 回目 install --update 成功" "0" "$EXIT_CODE"
MERGE_FF=$(get_local_config "$TMPDIR_ROOT" merge.ff)
PULL_FF=$(get_local_config "$TMPDIR_ROOT" pull.ff)
PULL_REBASE=$(get_local_config "$TMPDIR_ROOT" pull.rebase)
if [[ "$MERGE_FF" == "only" && "$PULL_FF" == "only" && -z "$PULL_REBASE" ]]; then
  pass "G5-3: 2 回実行後も設定が保持される"
else
  fail "G5-3: 2 回実行後の設定が壊れている (merge.ff='$MERGE_FF' pull.ff='$PULL_FF' pull.rebase='$PULL_REBASE')"
fi
cleanup

# G6. 事前に pull.rebase が未設定のまま実行しても install 自体は成功する（unset 対象なしでもエラーにならない）
create_test_repo
# pull.rebase は未設定のままにする
STDERR_LOG="$(mktemp)"
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>"$STDERR_LOG" || EXIT_CODE=$?
assert_exit_code "G6: pull.rebase 未設定でも install 成功" "0" "$EXIT_CODE"
# unset スキップのログが出力される
if grep -q "local pull.rebase は未設定" "$STDERR_LOG"; then
  pass "G6: unset スキップのログが出力される"
else
  fail "G6: unset スキップのログが出力されない"
fi
rm -f "$STDERR_LOG"
cleanup

print_test_summary
