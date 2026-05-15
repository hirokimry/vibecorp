#!/bin/bash
# test_isolation_parity.sh — macOS / Linux 隔離レイヤ パリティテスト
#
# 目的:
#   macOS sandbox-exec と Linux bwrap が同じ「拒否すべき / 許可すべき」表に従うことを検証する。
#   OS 別の errno 差異（macOS=EPERM / Linux=EROFS）は許容し、「exit 0 / 非 0」の二値で比較する。
#
# 期待表（write 境界を中心に検証 — read 境界は OS 固有テストでカバー）:
#   write-ssh        — 非ゼロ（拒否されるべき）
#   write-worktree   — ゼロ（許可されるべき）
#   read-etc         — ゼロ（許可されるべき）
#   write-etc        — 非ゼロ（拒否されるべき）
#
# read-ssh をパリティ表に含めない理由:
#   macOS の sandbox プロファイルは /private/var/folders 配下を広く read 許可しており、
#   mktemp で作る FAKE_HOME（/var/folders/.../fake-home）もここに含まれる。
#   Linux 側は bwrap が --tmpfs /tmp で FAKE_HOME 全体を隠す。
#   両者の test mock 環境差異が大きいため、read 境界は OS 固有テスト
#   （test_isolation_macos.sh / test_isolation_linux.sh）で個別検証する。
#
# 非 macOS / 非 Linux では skip。各 OS で隔離レイヤが動作しない環境でも skip。
#
# 参照: #293 / #310

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  *)
    echo "SKIP: tests/test_isolation_parity.sh は Darwin / Linux 以外では実行しない（現在: $OS）"
    exit 0
    ;;
esac

# OS 別の前提チェック
case "$OS" in
  Linux)
    if ! command -v bwrap >/dev/null 2>&1; then
      echo "SKIP: bwrap がインストールされていないためスキップ"
      exit 0
    fi
    if ! bwrap --unshare-pid --proc /proc --dev /dev --tmpfs /tmp /bin/true >/dev/null 2>&1; then
      echo "SKIP: bwrap が動作しない環境のためスキップ"
      exit 0
    fi
    ;;
  Darwin)
    if ! command -v sandbox-exec >/dev/null 2>&1; then
      echo "SKIP: sandbox-exec が見つからないためスキップ"
      exit 0
    fi
    ;;
esac

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="${SCRIPT_DIR}/templates/claude/bin/claude"
DISPATCHER="${SCRIPT_DIR}/templates/claude/bin/vibecorp-sandbox"
PROBE="${SCRIPT_DIR}/tests/fixtures/isolation-probe.sh"

# ----- 前提ファイル確認 -----

prereq_ok=1
for f in "$SHIM" "$DISPATCHER" "$PROBE"; do
  if [[ ! -f "$f" ]]; then
    fail "前提ファイル不在: $f"
    prereq_ok=0
  fi
done

if [[ "$prereq_ok" -ne 1 ]]; then
  echo ""
  echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
  exit 1
fi

# ----- テスト環境構築 -----

TMPDIR_TEST=$(mktemp -d -t vibecorp-isolation-parity-XXXXXX)
STDERR_LOG="${TMPDIR_TEST}/stderr.log"
STDOUT_LOG="${TMPDIR_TEST}/stdout.log"

# OS 別の sandbox TMPDIR 分離
SANDBOX_TMPDIR="${TMPDIR_TEST}/sandbox-tmp"
mkdir -p "$SANDBOX_TMPDIR"

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT

FAKE_HOME="${TMPDIR_TEST}/fake-home"
FAKE_WORKTREE="${TMPDIR_TEST}/fake-worktree"
FAKE_BIN="${TMPDIR_TEST}/fake-bin"

mkdir -p "${FAKE_HOME}/.ssh"
mkdir -p "${FAKE_HOME}/.claude"
mkdir -p "$FAKE_WORKTREE"
mkdir -p "$FAKE_BIN"

# read-ssh プローブ用のファイル（sandbox は読取を拒否すべき）
echo "secret-content" > "${FAKE_HOME}/.ssh/probe-read.txt"

# probe を claude-real として FAKE_BIN にコピー
# 直接 exec すると probe の元パスが sandbox の read allowlist 外（プロジェクト repo）になる。
# FAKE_BIN は macOS では /private/var/folders 配下、Linux では bind 配下になり read 許可される。
cp "$PROBE" "${FAKE_BIN}/claude-real"
chmod +x "${FAKE_BIN}/claude-real"

# shim 経由起動ヘルパー
# bash 3.2 互換: 空配列の "${arr[@]}" は set -u で unbound 扱いになるため配列サイズで分岐
run_shim() {
  local -a probe_args=("$@")

  local status=0
  if [[ ${#probe_args[@]} -gt 0 ]]; then
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      VIBECORP_ISOLATION=1 \
      bash "$SHIM" "${probe_args[@]}" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  else
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      VIBECORP_ISOLATION=1 \
      bash "$SHIM" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  fi
  return "$status"
}

# 期待表に基づく検証ヘルパー
# expected: "success" or "denied"
assert_parity() {
  local desc="$1"
  local expected="$2"
  local actual_status="$3"

  case "$expected" in
    success)
      if [[ "$actual_status" -eq 0 ]]; then
        pass "${desc} [${OS}]"
      else
        fail "${desc} [${OS}] 期待: 成功 (exit 0), 実際: exit ${actual_status}, stderr=$(cat "$STDERR_LOG")"
      fi
      ;;
    denied)
      if [[ "$actual_status" -ne 0 ]]; then
        pass "${desc} [${OS}]"
      else
        fail "${desc} [${OS}] 期待: 拒否 (exit !=0), 実際: 成功 (exit 0)"
      fi
      ;;
    *)
      fail "assert_parity: 不明な expected: ${expected}"
      ;;
  esac
}

echo "=== パリティ表（${OS}）の検証 ==="

# write-ssh — 拒否されるべき
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim write-ssh) || status=$?
assert_parity "write-ssh は拒否" "denied" "$status"

# write-worktree — 成功すべき
worktree_file="${FAKE_WORKTREE}/parity-write.txt"
rm -f "$worktree_file"
status=0
(cd "$FAKE_WORKTREE" && run_shim write-worktree "$worktree_file") || status=$?
assert_parity "write-worktree は成功" "success" "$status"

# read-etc — 成功すべき
status=0
(cd "$FAKE_WORKTREE" && run_shim read-etc) || status=$?
assert_parity "read-etc は成功" "success" "$status"

# write-etc — 拒否されるべき
status=0
(cd "$FAKE_WORKTREE" && run_shim write-etc) || status=$?
assert_parity "write-etc は拒否" "denied" "$status"

echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
