#!/bin/bash
# test_test_run_shard.sh
# ─────────────────────────────────────────────
# Issue #625: .github/scripts/test-run-shard.sh の挙動テスト。
# 環境変数 SHARD の値で実行対象が切り替わる分岐を検証する。
#
# 検証内容:
#   - SHARD=args/preset/lock/update → tests/test_install_${SHARD}.sh を呼ぶ
#   - SHARD=other → tests/test_*.sh を列挙し 4 シャード分を除外して全実行
#   - SHARD=未知 → exit 1 でエラーメッセージ出力
#
# 実装制約:
#   - 本物の tests/ を実行すると分単位で時間がかかるため、temp ディレクトリに
#     dummy test_install_*.sh を配置して挙動だけを検証する
#   - スクリプトをコピーしてサンドボックスから実行する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

TARGET="${SCRIPT_DIR}/.github/scripts/test-run-shard.sh"

if [ ! -x "$TARGET" ]; then
  fail "test-run-shard.sh が存在し実行可能である"
  exit 1
fi

TMP_ROOT=""

cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT" || true
  fi
}
trap cleanup EXIT

# サンドボックスを作成:
#   - tests/ にダミーの test_install_*.sh と test_other.sh を配置
#   - target スクリプトをコピー（実行は sandbox の tests/ を参照させる）
setup_sandbox() {
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-run-shard-test.XXXXXX")"
  mkdir -p "${TMP_ROOT}/tests" "${TMP_ROOT}/.github/scripts"

  # ダミーテスト: 単純に echo して exit 0 する
  for name in args preset lock update; do
    cat > "${TMP_ROOT}/tests/test_install_${name}.sh" <<EOF
#!/usr/bin/env bash
echo "ran test_install_${name}.sh"
EOF
    chmod +x "${TMP_ROOT}/tests/test_install_${name}.sh"
  done

  # other シャード対象（4 シャード以外）の dummy
  cat > "${TMP_ROOT}/tests/test_misc.sh" <<'EOF'
#!/usr/bin/env bash
echo "ran test_misc.sh"
EOF
  chmod +x "${TMP_ROOT}/tests/test_misc.sh"

  cp "$TARGET" "${TMP_ROOT}/.github/scripts/test-run-shard.sh"
  chmod +x "${TMP_ROOT}/.github/scripts/test-run-shard.sh"
}

run_with_shard() {
  local shard="$1"
  (
    cd "$TMP_ROOT"
    SHARD="$shard" bash .github/scripts/test-run-shard.sh 2>&1
  )
}

run_with_shard_get_rc() {
  local shard="$1"
  local rc=0
  ( cd "$TMP_ROOT" && SHARD="$shard" bash .github/scripts/test-run-shard.sh >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

echo "=== Issue #625: test-run-shard.sh の挙動テスト ==="
echo ""

setup_sandbox

# --- ケース 1〜4: 4 シャードはそれぞれ対応する test_install_*.sh を実行 ---
for shard in args preset lock update; do
  echo "--- ケース: SHARD=$shard → test_install_${shard}.sh のみ実行 ---"
  output=$(run_with_shard "$shard")
  if echo "$output" | grep -q "ran test_install_${shard}.sh"; then
    pass "SHARD=$shard で test_install_${shard}.sh が呼ばれる"
  else
    fail "SHARD=$shard で test_install_${shard}.sh が呼ばれない: $output"
  fi
  # 他のシャード固有テストは呼ばれていないこと
  for other in args preset lock update; do
    if [ "$other" = "$shard" ]; then continue; fi
    if echo "$output" | grep -q "ran test_install_${other}.sh"; then
      fail "SHARD=$shard で本来呼ばれないはずの test_install_${other}.sh も呼ばれている"
    fi
  done
done
pass "他のシャード固有テストは混入しない"

# --- ケース 5: other は 4 シャード以外を全実行 ---
echo "--- ケース: SHARD=other → 4 シャード以外を全実行 ---"
output=$(run_with_shard "other")
if echo "$output" | grep -q "ran test_misc.sh"; then
  pass "SHARD=other で test_misc.sh が実行される"
else
  fail "SHARD=other で test_misc.sh が実行されない: $output"
fi
# 4 シャード対象は other で実行されない
for excluded in args preset lock update; do
  if echo "$output" | grep -q "ran test_install_${excluded}.sh"; then
    fail "SHARD=other で除外対象 test_install_${excluded}.sh が実行された"
  fi
done
pass "SHARD=other で 4 シャード対象は除外される"

# --- ケース 6: 未知 SHARD → exit 1 ---
echo "--- ケース: SHARD=unknown → exit 1 ---"
rc=$(run_with_shard_get_rc "unknown")
assert_exit_code "未知 SHARD は exit 1" "1" "$rc"

# --- ケース 7: 未知 SHARD のメッセージ ---
output=$(run_with_shard "unknown" || true)
if echo "$output" | grep -q "未知の shard 値"; then
  pass "未知 SHARD でエラーメッセージが出力される"
else
  fail "未知 SHARD のエラーメッセージが見当たらない: $output"
fi

# --- ケース 8: SHARD=other でテスト失敗があれば exit 1 ---
echo "--- ケース: SHARD=other 内のテストが失敗したら exit 1 ---"
# 失敗するテストを追加
cat > "${TMP_ROOT}/tests/test_failing.sh" <<'EOF'
#!/usr/bin/env bash
echo "test_failing.sh は意図的に失敗します"
exit 1
EOF
chmod +x "${TMP_ROOT}/tests/test_failing.sh"
rc=$(run_with_shard_get_rc "other")
assert_exit_code "SHARD=other で失敗テストがあれば exit 1" "1" "$rc"
# 失敗があっても他のテストは試行される
output=$(run_with_shard "other" || true)
if echo "$output" | grep -q "ran test_misc.sh"; then
  pass "SHARD=other で失敗テストがあっても続行される"
else
  fail "SHARD=other で失敗時に他のテストが実行されない: $output"
fi

echo ""
print_test_summary
