#!/bin/bash
# test_install_isolation.sh — install.sh 経由での隔離レイヤ配置を検証する
#
# 対象:
#   - install.sh が full プリセットで .claude/bin/{claude, vibecorp-sandbox, activate.sh} を配置する
#   - install.sh が full プリセットで .claude/sandbox/claude.sb を配置する
#   - minimal/standard プリセットで隔離レイヤが配置されない
#   - --update で preset を下げたとき隔離レイヤが削除される
#   - ユーザー独自配置の .claude/bin/custom.sh は保持される
#   - activate.sh を bash で source すると PATH 先頭に .claude/bin が追加される
#   - check_isolation_deps の sandbox-exec 不在時 exit 1
#
# 既存 tests/test_isolation_macos.sh との役割分担:
#   - test_isolation_macos.sh: templates/claude/bin/ 配下ファイル自体の挙動を検証
#   - test_install_isolation.sh: install.sh 経由で導入先に配置されるかを検証
#
# 非 Darwin では早期 skip。

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: tests/test_install_isolation.sh は Darwin 以外では実行しない（現在: $(uname -s)）"
  exit 0
fi

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
TMPDIR_ROOT=""

# --- セットアップ / クリーンアップ ---

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
  # trap cleanup EXIT 内での cd 失敗が set -e 下でテスト結果に影響しないよう無害化する
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# ============================================
echo "=== A. full プリセット: 隔離レイヤの配置 ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"

assert_file_exists "A1: .claude/bin/claude が配置される" "$R/.claude/bin/claude"
assert_file_executable "A2: .claude/bin/claude に実行権限" "$R/.claude/bin/claude"
assert_file_exists "A3: .claude/bin/vibecorp-sandbox が配置される" "$R/.claude/bin/vibecorp-sandbox"
assert_file_executable "A4: .claude/bin/vibecorp-sandbox に実行権限" "$R/.claude/bin/vibecorp-sandbox"
assert_file_exists "A5: .claude/bin/activate.sh が生成される" "$R/.claude/bin/activate.sh"
assert_file_executable "A6: .claude/bin/activate.sh に実行権限" "$R/.claude/bin/activate.sh"
assert_file_exists "A7: .claude/sandbox/claude.sb が配置される" "$R/.claude/sandbox/claude.sb"
cleanup

# ============================================
echo ""
echo "=== B. minimal プリセット: 隔離レイヤは配置しない ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1
R="$TMPDIR_ROOT"

assert_file_not_exists "B1: minimal で .claude/bin/claude は存在しない" "$R/.claude/bin/claude"
assert_file_not_exists "B2: minimal で .claude/bin/vibecorp-sandbox は存在しない" "$R/.claude/bin/vibecorp-sandbox"
assert_file_not_exists "B3: minimal で .claude/bin/activate.sh は存在しない" "$R/.claude/bin/activate.sh"
assert_file_not_exists "B4: minimal で .claude/sandbox/claude.sb は存在しない" "$R/.claude/sandbox/claude.sb"
cleanup

# ============================================
echo ""
echo "=== C. standard プリセット: 隔離レイヤは配置しない ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard > /dev/null 2>&1
R="$TMPDIR_ROOT"

assert_file_not_exists "C1: standard で .claude/bin/claude は存在しない" "$R/.claude/bin/claude"
assert_file_not_exists "C2: standard で .claude/sandbox/claude.sb は存在しない" "$R/.claude/sandbox/claude.sb"
cleanup

# ============================================
echo ""
echo "=== D. ダウングレード: full → minimal で隔離レイヤが削除される ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"
# 前提確認
if [ ! -f "$R/.claude/bin/claude" ]; then
  fail "D-setup: full インストール後に .claude/bin/claude が存在するはず"
  exit 1
fi

# --update --preset minimal でダウングレード
bash "$INSTALL_SH" --update --preset minimal > /dev/null 2>&1

assert_file_not_exists "D1: ダウングレード後 .claude/bin/claude が削除" "$R/.claude/bin/claude"
assert_file_not_exists "D2: ダウングレード後 .claude/bin/vibecorp-sandbox が削除" "$R/.claude/bin/vibecorp-sandbox"
assert_file_not_exists "D3: ダウングレード後 .claude/bin/activate.sh が削除" "$R/.claude/bin/activate.sh"
assert_file_not_exists "D4: ダウングレード後 .claude/sandbox/claude.sb が削除" "$R/.claude/sandbox/claude.sb"
cleanup

# ============================================
echo ""
echo "=== E. ダウングレード時、ユーザー独自ファイルは保持される ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"

# ユーザー独自ファイルを .claude/bin に配置
echo "#!/bin/bash" > "$R/.claude/bin/my-custom-tool.sh"
chmod +x "$R/.claude/bin/my-custom-tool.sh"

# --update --preset minimal でダウングレード
bash "$INSTALL_SH" --update --preset minimal > /dev/null 2>&1

# vibecorp 配置分は削除される
assert_file_not_exists "E1: vibecorp 配置の claude は削除" "$R/.claude/bin/claude"
# ユーザー配置分は保持される
assert_file_exists "E2: ユーザー独自 my-custom-tool.sh は保持" "$R/.claude/bin/my-custom-tool.sh"
# ディレクトリも保持される（rmdir が非空で失敗するため）
if [ -d "$R/.claude/bin" ]; then
  pass "E3: 非空の .claude/bin ディレクトリは保持される"
else
  fail "E3: .claude/bin ディレクトリが誤って削除されている"
fi
cleanup

# ============================================
echo ""
echo "=== F. activate.sh の動作: bash で source すると PATH に .claude/bin が入る ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"

# サブシェルで source → PATH の冒頭に .claude/bin 絶対パスが入ることを確認
EXPECTED_PATH_PREFIX="$R/.claude/bin"
ACTUAL_PATH=$(bash -c "source '$R/.claude/bin/activate.sh' && echo \"\$PATH\"")
if [[ "$ACTUAL_PATH" == "$EXPECTED_PATH_PREFIX:"* ]]; then
  pass "F1: source activate.sh で PATH 先頭に .claude/bin が追加される"
else
  fail "F1: PATH 先頭に .claude/bin がない (actual: $ACTUAL_PATH)"
fi

# 2 回 source しても PATH に重複しない
ACTUAL_PATH2=$(bash -c "source '$R/.claude/bin/activate.sh' && source '$R/.claude/bin/activate.sh' && echo \"\$PATH\"")
OCCURRENCES=$(echo "$ACTUAL_PATH2" | tr ':' '\n' | grep -c -F "$EXPECTED_PATH_PREFIX" || true)
if [ "$OCCURRENCES" = "1" ]; then
  pass "F2: 2 回 source しても PATH に重複しない"
else
  fail "F2: PATH に .claude/bin が $OCCURRENCES 回含まれる (期待: 1 回)"
fi
cleanup

# ============================================
echo ""
echo "=== G. sandbox-exec 不在時: check_isolation_deps が exit 1 ==="
# ============================================
# PATH をモックして sandbox-exec 非存在環境を作る。
# install.sh は check_isolation_deps で command -v sandbox-exec を使うため、
# PATH を限定すれば非存在化できる。

create_test_repo
R="$TMPDIR_ROOT"

# sandbox-exec を含まない最小 PATH を構成
# 必要なコマンド: bash, git, jq, grep, sed, awk, cat, cp, rm, mv, mkdir, basename, dirname, uname, chmod, find, command, tr
FAKE_BIN="$R/_fake_bin_no_sandbox"
mkdir -p "$FAKE_BIN"
for cmd in bash git jq grep sed awk cat cp rm mv mkdir basename dirname uname chmod find tr mktemp cut sort head tail wc date pwd ls rmdir printf; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ln -sf "$(command -v "$cmd")" "$FAKE_BIN/$cmd"
  fi
done
# sandbox-exec を意図的にリンクしない

EXIT_CODE=0
ERR_LOG="$R/g_err.log"
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>"$ERR_LOG" || EXIT_CODE=$?
assert_exit_code "G1: sandbox-exec 不在時に exit 1" "1" "$EXIT_CODE"
assert_file_contains "G2: エラーメッセージに sandbox-exec が含まれる" "$ERR_LOG" "sandbox-exec"
cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
