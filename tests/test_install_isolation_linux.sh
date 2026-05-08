#!/bin/bash
# test_install_isolation_linux.sh — install.sh の Linux bwrap 不在時誘導メッセージを検証する
#
# 対象:
#   - check_isolation_deps が Linux で bwrap を検出できないとき exit 1 する
#   - distro 別 (Ubuntu / Fedora / Alpine) のインストール手順が表示される
#   - /etc/os-release 不在時は全 distro 例が併記される
#
# mock 戦略:
#   - PATH 偽装で uname を Linux に書き換える（Darwin 上でも実行可能）
#   - bwrap を含まない最小 PATH を構成して非存在化する
#   - VIBECORP_OS_RELEASE_PATH で /etc/os-release を一時ファイルに差し替える
#
# OS 制約: Darwin / Linux どちらでも実行可能（uname を mock するため）

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
TMPDIR_ROOT=""

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# bwrap を含まない最小 PATH を構成する
# uname は Linux を返す mock を配置する
setup_mock_bin() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  for cmd in bash git jq grep sed awk cat cp rm mv mkdir basename dirname chmod find tr mktemp cut sort head tail wc date pwd ls rmdir printf env; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$mock_bin/$cmd"
    fi
  done
  # uname は Linux を返す mock スクリプト
  cat > "$mock_bin/uname" <<'UNAME_EOF'
#!/bin/bash
if [[ "$1" == "-s" ]]; then
  echo "Linux"
else
  echo "Linux mock-host 5.15.0 #1 SMP x86_64 GNU/Linux"
fi
UNAME_EOF
  chmod +x "$mock_bin/uname"
  # bwrap は意図的に配置しない
}

# distro mock 用 os-release ファイルを作成する
make_os_release() {
  local path="$1" id="$2" id_like="$3"
  cat > "$path" <<OS_EOF
NAME="${id} mock"
ID=${id}
ID_LIKE=${id_like}
OS_EOF
}

# ============================================
echo "=== H1. Ubuntu mock: apt-get install bubblewrap が表示される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
MOCK_BIN="$R/_mock_bin"
setup_mock_bin "$MOCK_BIN"

OS_RELEASE_FILE="$R/os-release-ubuntu"
make_os_release "$OS_RELEASE_FILE" "ubuntu" "debian"

ERR_LOG="$R/h1_err.log"
EXIT_CODE=0
PATH="$MOCK_BIN" VIBECORP_OS_RELEASE_PATH="$OS_RELEASE_FILE" \
  bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>"$ERR_LOG" \
  || EXIT_CODE=$?

assert_exit_code "H1-a: Ubuntu mock + bwrap 不在で exit 1" "1" "$EXIT_CODE"
assert_file_contains "H1-b: bwrap 不在のエラーメッセージ" "$ERR_LOG" "bwrap"
assert_file_contains "H1-c: apt-get install bubblewrap が表示される" "$ERR_LOG" "apt-get install bubblewrap"
cleanup

# ============================================
echo ""
echo "=== H2. Fedora mock: dnf install bubblewrap が表示される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
MOCK_BIN="$R/_mock_bin"
setup_mock_bin "$MOCK_BIN"

OS_RELEASE_FILE="$R/os-release-fedora"
make_os_release "$OS_RELEASE_FILE" "fedora" "rhel"

ERR_LOG="$R/h2_err.log"
EXIT_CODE=0
PATH="$MOCK_BIN" VIBECORP_OS_RELEASE_PATH="$OS_RELEASE_FILE" \
  bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>"$ERR_LOG" \
  || EXIT_CODE=$?

assert_exit_code "H2-a: Fedora mock + bwrap 不在で exit 1" "1" "$EXIT_CODE"
assert_file_contains "H2-b: dnf install bubblewrap が表示される" "$ERR_LOG" "dnf install bubblewrap"
cleanup

# ============================================
echo ""
echo "=== H3. Alpine mock: apk add bubblewrap が表示される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
MOCK_BIN="$R/_mock_bin"
setup_mock_bin "$MOCK_BIN"

OS_RELEASE_FILE="$R/os-release-alpine"
make_os_release "$OS_RELEASE_FILE" "alpine" ""

ERR_LOG="$R/h3_err.log"
EXIT_CODE=0
PATH="$MOCK_BIN" VIBECORP_OS_RELEASE_PATH="$OS_RELEASE_FILE" \
  bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>"$ERR_LOG" \
  || EXIT_CODE=$?

assert_exit_code "H3-a: Alpine mock + bwrap 不在で exit 1" "1" "$EXIT_CODE"
assert_file_contains "H3-b: apk add bubblewrap が表示される" "$ERR_LOG" "apk add bubblewrap"
cleanup

# ============================================
echo ""
echo "=== H4. /etc/os-release 不在時: 全 distro 例が併記される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
MOCK_BIN="$R/_mock_bin"
setup_mock_bin "$MOCK_BIN"

# os-release を意図的に存在しないパスに向ける
NONEXISTENT_OS_RELEASE="$R/os-release-missing"

ERR_LOG="$R/h4_err.log"
EXIT_CODE=0
PATH="$MOCK_BIN" VIBECORP_OS_RELEASE_PATH="$NONEXISTENT_OS_RELEASE" \
  bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>"$ERR_LOG" \
  || EXIT_CODE=$?

assert_exit_code "H4-a: os-release 不在で exit 1" "1" "$EXIT_CODE"
assert_file_contains "H4-b: Debian/Ubuntu の例が含まれる" "$ERR_LOG" "apt-get install bubblewrap"
assert_file_contains "H4-c: Fedora/RHEL の例が含まれる" "$ERR_LOG" "dnf install bubblewrap"
assert_file_contains "H4-d: Alpine の例が含まれる" "$ERR_LOG" "apk add bubblewrap"
cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
