#!/bin/bash
# test_install_args.sh — install.sh の引数パース / バリデーションテスト
# 使い方: bash tests/test_install_args.sh
# 元ファイル: tests/test_install.sh を Issue #340 で 4 シャードに分割した

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# ============================================
echo "=== A. 引数パース ==="
# ============================================

create_test_repo

# A1. --name のみで成功
EXIT_CODE=$(run_install --name test-proj)
assert_exit_code "--name のみで成功" "0" "$EXIT_CODE"
cleanup

# A2. --name 未指定でエラー
create_test_repo
EXIT_CODE=$(run_install 2>/dev/null || echo $?)
# run_install は exit code を echo するが、引数なしの場合はエラー
EXIT_CODE=0; bash "$INSTALL_SH" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--name 未指定でエラー" "1" "$EXIT_CODE"
cleanup

# A3. --name の値欠落でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--name の値欠落でエラー" "1" "$EXIT_CODE"
cleanup

# A4. --preset 指定で成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--preset 指定で成功" "0" "$EXIT_CODE"
cleanup

# A5. --language 指定で成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--language 指定で成功" "0" "$EXIT_CODE"
cleanup

# A6. 不明オプションでエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --unknown 2>/dev/null || EXIT_CODE=$?
assert_exit_code "不明オプションでエラー" "1" "$EXIT_CODE"
cleanup

# A7. --help でヘルプ表示・正常終了
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --help 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--help でヘルプ表示・正常終了" "0" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== B. プロジェクト名バリデーション ==="
# ============================================

# B1. 正常な名前(my-project) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name my-project 2>/dev/null || EXIT_CODE=$?
assert_exit_code "正常な名前(my-project) → 成功" "0" "$EXIT_CODE"
cleanup

# B2. 1文字(a) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name a 2>/dev/null || EXIT_CODE=$?
assert_exit_code "1文字(a) → 成功" "0" "$EXIT_CODE"
cleanup

# B3. 2文字(ab) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name ab 2>/dev/null || EXIT_CODE=$?
assert_exit_code "2文字(ab) → 成功" "0" "$EXIT_CODE"
cleanup

# B4. 50文字 → 成功
create_test_repo
NAME50=$(printf 'a%.0s' $(seq 1 50))
EXIT_CODE=0; bash "$INSTALL_SH" --name "$NAME50" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "50文字 → 成功" "0" "$EXIT_CODE"
cleanup

# B5. 51文字 → エラー
create_test_repo
NAME51=$(printf 'a%.0s' $(seq 1 51))
EXIT_CODE=0; bash "$INSTALL_SH" --name "$NAME51" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "51文字 → エラー" "1" "$EXIT_CODE"
cleanup

# B6. ハイフン始まり → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "-bad" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ハイフン始まり → エラー" "1" "$EXIT_CODE"
cleanup

# B7. ハイフン終わり → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "bad-" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ハイフン終わり → エラー" "1" "$EXIT_CODE"
cleanup

# B8. アンダースコア含む → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "bad_name" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "アンダースコア含む → エラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== C. プリセットバリデーション ==="
# ============================================

# C1. minimal → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null || EXIT_CODE=$?
assert_exit_code "minimal → 成功" "0" "$EXIT_CODE"
cleanup

# C2. full → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null || EXIT_CODE=$?
assert_exit_code "full → 成功" "0" "$EXIT_CODE"
R="$TMPDIR_ROOT"
assert_file_contains "full: vibecorp.yml に preset: full" "$R/.claude/vibecorp.yml" "preset: full"
assert_dir_exists "full: agents ディレクトリ存在" "$R/.claude/agents"
# skills/ は作成されない（プラグインキャッシュに移行済み）
if [ -d "$R/skills" ]; then
  fail "full: skills/ が作成されている（プラグインキャッシュに移行済み）"
else
  pass "full: skills/ が作成されていない"
fi
assert_file_exists "full: sync-gate.sh 配置" "$R/.claude/hooks/sync-gate.sh"
# --update --preset full の冪等性確認
EXIT_CODE=0; bash "$INSTALL_SH" --update --preset full 2>/dev/null || EXIT_CODE=$?
assert_exit_code "full → update 成功" "0" "$EXIT_CODE"
assert_file_contains "full: update 後も preset: full" "$R/.claude/vibecorp.yml" "preset: full"
cleanup

# ============================================
echo ""
echo "=== D. 言語バリデーション ==="
# ============================================

# D1. ja → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language ja 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ja → 成功" "0" "$EXIT_CODE"
cleanup

# D2. en → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null || EXIT_CODE=$?
assert_exit_code "en → 成功" "0" "$EXIT_CODE"
cleanup

# D3. 特殊文字含む → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language 'ja;rm' 2>/dev/null || EXIT_CODE=$?
assert_exit_code "特殊文字含む → エラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== AC. --version オプション ==="
# ============================================

# AC1. --version のバリデーション: 不正な形式でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "1.0.0" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC1: --version v なしでエラー" "1" "$EXIT_CODE"
cleanup

# AC2. --version のバリデーション: 不正な形式でエラー（文字列）
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "latest" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC2: --version 不正文字列でエラー" "1" "$EXIT_CODE"
cleanup

# AC3. --version の値欠落でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC3: --version の値欠落でエラー" "1" "$EXIT_CODE"
cleanup

# AC4. --version に存在しないタグを指定してエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "v99.99.99" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC4: 存在しないタグでエラー" "1" "$EXIT_CODE"
cleanup

# AC5. --version に存在するタグを指定して成功する
# 一時 clone にタグを打ち、そのタグでインストールが成功することを検証
create_test_repo
# SCRIPT_DIR リポジトリ（vibecorp 本体）にテスト用タグを作成
VIBECORP_REPO_DIR="$(cd "$(dirname "$INSTALL_SH")" && pwd)"
ORIGINAL_BRANCH=$(git -C "$VIBECORP_REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$VIBECORP_REPO_DIR" rev-parse HEAD)
TEST_TAG="v0.0.99"
git -C "$VIBECORP_REPO_DIR" tag "$TEST_TAG"

EXIT_CODE=0
VIBECORP_REEXEC=1 bash "$INSTALL_SH" --name test-proj --version "$TEST_TAG" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC5: --version に存在するタグを指定して成功" "0" "$EXIT_CODE"

# テスト用タグを削除して元に戻す
# テスト用タグを削除して元のブランチに戻す
git -C "$VIBECORP_REPO_DIR" tag -d "$TEST_TAG" >/dev/null 2>&1 || true
git -C "$VIBECORP_REPO_DIR" checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
cleanup

# ============================================
echo ""
echo "=== BILLING. 課金警告（Issue #286） ==="
# ============================================

# BILLING1. full プリセット install 時に課金警告が stderr に表示される
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset full 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデル"; then
  pass "BILLING1: full → stderr に課金警告が表示される"
else
  fail "BILLING1: full → stderr に課金警告が表示されない"
fi
if echo "$STDERR_OUT" | grep -q "ANTHROPIC_API_KEY"; then
  pass "BILLING1b: full → 警告に ANTHROPIC_API_KEY の言及がある"
else
  fail "BILLING1b: full → 警告に ANTHROPIC_API_KEY の言及がない"
fi
cleanup

# BILLING2. minimal プリセットでは課金警告が出ない
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset minimal 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデルに関する注意"; then
  fail "BILLING2: minimal → 課金警告が誤って表示されている"
else
  pass "BILLING2: minimal → 課金警告は表示されない"
fi
cleanup

# BILLING3. standard プリセットでは課金警告が出ない
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset standard 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデルに関する注意"; then
  fail "BILLING3: standard → 課金警告が誤って表示されている"
else
  pass "BILLING3: standard → 課金警告は表示されない"
fi
cleanup

# BILLING4. docs/cost-analysis.md に「実行モード別の課金モデル」セクションが存在する
assert_file_contains "BILLING4: cost-analysis.md に実行モード別の課金モデル見出しが存在" "$SCRIPT_DIR/docs/cost-analysis.md" "実行モード別の課金モデル"

# BILLING5. README.md のプリセット比較表に「課金モデル」列が追加されている
assert_file_contains "BILLING5: README.md に課金モデル列が追加されている" "$SCRIPT_DIR/README.md" "課金モデル"

# ============================================
echo ""
echo "=== T. OS 判定（Windows / unknown 非対応） ==="
# ============================================
# detect_os / check_unsupported_os の挙動を uname モックで検証する。
# install.sh は set -e の下で uname -s を外部コマンドとして呼ぶため、
# PATH 先頭にダミー uname を置けばモック可能。

# T1. uname -s = Darwin なら続行（既存セットアップで動くことで検証済みだが、明示テスト）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_darwin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "Darwin"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T1: uname=Darwin で install が成功する" "0" "$EXIT_CODE"

# T2. uname -s = Linux なら続行
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_linux"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "Linux"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T2: uname=Linux で install が成功する" "0" "$EXIT_CODE"

# T3. uname -s = MINGW64_NT-10.0-19045 なら exit 2（Windows ネイティブ）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_mingw"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "MINGW64_NT-10.0-19045"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
ERR_LOG="$TMPDIR_ROOT/t3_err.log"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>"$ERR_LOG" || EXIT_CODE=$?
assert_exit_code "T3: uname=MINGW64 で exit 2" "2" "$EXIT_CODE"
assert_file_contains "T3: エラーメッセージに WSL2 案内が含まれる" "$ERR_LOG" "WSL2"

# T4. uname -s = MSYS_NT-10.0 なら exit 2
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_msys"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "MSYS_NT-10.0"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T4: uname=MSYS_NT で exit 2" "2" "$EXIT_CODE"

# T5. uname -s = CYGWIN_NT-10.0 なら exit 2
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_cygwin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "CYGWIN_NT-10.0"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T5: uname=CYGWIN_NT で exit 2" "2" "$EXIT_CODE"

# T6. uname -s = FreeBSD なら exit 2（unknown OS）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_freebsd"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "FreeBSD"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
ERR_LOG="$TMPDIR_ROOT/t6_err.log"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>"$ERR_LOG" || EXIT_CODE=$?
assert_exit_code "T6: uname=FreeBSD で exit 2" "2" "$EXIT_CODE"
assert_file_contains "T6: エラーメッセージにサポート外の表記" "$ERR_LOG" "サポート外の OS"
cleanup

print_test_summary
