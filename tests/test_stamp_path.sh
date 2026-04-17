#!/bin/bash
# vibecorp_stamp_dir / vibecorp_stamp_path / vibecorp_stamp_mkdir のユニットテスト
# 使い方: bash tests/test_stamp_path.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/common.sh"

PASSED=0
FAILED=0
TOTAL=0

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (expected: ${expected}, got: ${actual})"
  fi
}

assert_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*) pass "$desc" ;;
    *) fail "$desc (expected to contain: ${needle}, got: ${haystack})" ;;
  esac
}

assert_not_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*) fail "$desc (expected to NOT contain: ${needle}, got: ${haystack})" ;;
    *) pass "$desc" ;;
  esac
}

assert_starts_with() {
  local desc="$1"
  local prefix="$2"
  local actual="$3"
  case "$actual" in
    "$prefix"*) pass "$desc" ;;
    *) fail "$desc (expected prefix: ${prefix}, got: ${actual})" ;;
  esac
}

# --- 前提確認 ---

if [ ! -f "$LIB" ]; then
  fail "common.sh が存在しない: ${LIB}"
  exit 1
fi

# common.sh を source
# shellcheck source=../templates/claude/lib/common.sh
source "$LIB"

# --- テスト用の git リポジトリを準備 ---

TMPDIR_ROOT=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

REPO_DIR="${TMPDIR_ROOT}/test-repo"
mkdir -p "$REPO_DIR"
( cd "$REPO_DIR" && git init -q . && git config user.email t@example.com && git config user.name t )

# --- ケース 1: XDG_CACHE_HOME 絶対パス設定時 ---

echo "Test 1: XDG_CACHE_HOME 絶対パス指定で cache_root が反映される"
RESULT=$( cd "$REPO_DIR" && XDG_CACHE_HOME="${TMPDIR_ROOT}/xdg" CLAUDE_PROJECT_DIR="$REPO_DIR" vibecorp_stamp_dir )
assert_starts_with "XDG_CACHE_HOME=絶対パス で cache_root 反映" "${TMPDIR_ROOT}/xdg/vibecorp/state/" "$RESULT"

# --- ケース 2: XDG_CACHE_HOME 未設定で $HOME/.cache フォールバック ---

echo "Test 2: XDG_CACHE_HOME 未設定 → \$HOME/.cache フォールバック"
RESULT=$( cd "$REPO_DIR" && env -u XDG_CACHE_HOME HOME="${TMPDIR_ROOT}/home" CLAUDE_PROJECT_DIR="$REPO_DIR" bash -c "source ${LIB} && vibecorp_stamp_dir" )
assert_starts_with "XDG_CACHE_HOME 未設定 で \$HOME/.cache 使用" "${TMPDIR_ROOT}/home/.cache/vibecorp/state/" "$RESULT"

# --- ケース 3: XDG_CACHE_HOME 相対パスは XDG 仕様により無視 ---

echo "Test 3: XDG_CACHE_HOME 相対パス → \$HOME/.cache フォールバック（XDG 仕様）"
RESULT=$( cd "$REPO_DIR" && XDG_CACHE_HOME="relative/path" HOME="${TMPDIR_ROOT}/home" CLAUDE_PROJECT_DIR="$REPO_DIR" bash -c "source ${LIB} && vibecorp_stamp_dir" )
assert_starts_with "XDG_CACHE_HOME=相対 → \$HOME/.cache フォールバック" "${TMPDIR_ROOT}/home/.cache/vibecorp/state/" "$RESULT"

# --- ケース 4: vibecorp_stamp_path の出力形式 ---

echo "Test 4: vibecorp_stamp_path <name> が <dir>/<name>-ok 形式"
DIR=$( cd "$REPO_DIR" && CLAUDE_PROJECT_DIR="$REPO_DIR" vibecorp_stamp_dir )
PATH_RESULT=$( cd "$REPO_DIR" && CLAUDE_PROJECT_DIR="$REPO_DIR" vibecorp_stamp_path sync )
assert_eq "vibecorp_stamp_path sync = <dir>/sync-ok" "${DIR}/sync-ok" "$PATH_RESULT"

# --- ケース 5: 別 repo で異なる sha8 が生成されること ---

echo "Test 5: 異なる repo パスで sha8 が異なる"
REPO_A="${TMPDIR_ROOT}/repo-a"
REPO_B="${TMPDIR_ROOT}/repo-b"
mkdir -p "$REPO_A" "$REPO_B"
( cd "$REPO_A" && git init -q . )
( cd "$REPO_B" && git init -q . )
DIR_A=$( cd "$REPO_A" && CLAUDE_PROJECT_DIR="$REPO_A" vibecorp_stamp_dir )
DIR_B=$( cd "$REPO_B" && CLAUDE_PROJECT_DIR="$REPO_B" vibecorp_stamp_dir )
if [ "$DIR_A" != "$DIR_B" ]; then
  pass "別 repo で異なるディレクトリ生成 (A=${DIR_A##*/}, B=${DIR_B##*/})"
else
  fail "別 repo で同じディレクトリが生成された (${DIR_A})"
fi

# --- ケース 5b: 同 basename・別パスで衝突回避（sanitized-basename + sha8 仕様の肝） ---

echo "Test 5b: 同 basename・別パスでも異なるディレクトリが生成される"
SAME_BASE_A="${TMPDIR_ROOT}/proj-a/repo"
SAME_BASE_B="${TMPDIR_ROOT}/proj-b/repo"
mkdir -p "$SAME_BASE_A" "$SAME_BASE_B"
( cd "$SAME_BASE_A" && git init -q . )
( cd "$SAME_BASE_B" && git init -q . )
DIR_SA=$( cd "$SAME_BASE_A" && CLAUDE_PROJECT_DIR="$SAME_BASE_A" vibecorp_stamp_dir )
DIR_SB=$( cd "$SAME_BASE_B" && CLAUDE_PROJECT_DIR="$SAME_BASE_B" vibecorp_stamp_dir )
if [ "$DIR_SA" != "$DIR_SB" ]; then
  pass "同 basename・別パスで異なるディレクトリ生成 (A=${DIR_SA##*/}, B=${DIR_SB##*/})"
else
  fail "同 basename・別パスで同じディレクトリが生成された (${DIR_SA})"
fi

# --- ケース 6: git 外（git toplevel 取得失敗）でフォールバック + stderr 警告 ---

echo "Test 6: git 外で stderr 警告が出る"
NON_GIT_DIR="${TMPDIR_ROOT}/non-git"
mkdir -p "$NON_GIT_DIR"
STDERR_OUT=$( cd "$NON_GIT_DIR" && CLAUDE_PROJECT_DIR="$NON_GIT_DIR" vibecorp_stamp_dir 2>&1 >/dev/null )
assert_contains "git 外で stderr 警告" "git toplevel 取得に失敗" "$STDERR_OUT"

STDOUT_OUT=$( cd "$NON_GIT_DIR" && CLAUDE_PROJECT_DIR="$NON_GIT_DIR" vibecorp_stamp_dir 2>/dev/null )
assert_starts_with "git 外でもパスは生成される" "${HOME}/.cache/vibecorp/state/non-git-" "$STDOUT_OUT"

# --- ケース 7: 特殊文字を含む repo basename はサニタイズされる ---

echo "Test 7: 特殊文字を含む basename がサニタイズ"
SPECIAL_REPO="${TMPDIR_ROOT}/test repo (with special!)"
mkdir -p "$SPECIAL_REPO"
( cd "$SPECIAL_REPO" && git init -q . )
DIR_SPECIAL=$( cd "$SPECIAL_REPO" && CLAUDE_PROJECT_DIR="$SPECIAL_REPO" vibecorp_stamp_dir )
# サニタイズ後はスペース・括弧・! が _ に置換され、連続は squeeze される
assert_not_contains "サニタイズ後にスペースが残らない" " " "$DIR_SPECIAL"
assert_not_contains "サニタイズ後に括弧が残らない" "(" "$DIR_SPECIAL"
assert_not_contains "サニタイズ後に ! が残らない" "!" "$DIR_SPECIAL"

# --- ケース 8: vibecorp_stamp_mkdir がディレクトリを作成し chmod 700 を適用 ---

echo "Test 8: vibecorp_stamp_mkdir が dir 作成 + chmod 700"
MKDIR_REPO="${TMPDIR_ROOT}/mkdir-test"
mkdir -p "$MKDIR_REPO"
( cd "$MKDIR_REPO" && git init -q . )
CREATED_DIR=$( cd "$MKDIR_REPO" && XDG_CACHE_HOME="${TMPDIR_ROOT}/xdg-mkdir" CLAUDE_PROJECT_DIR="$MKDIR_REPO" bash -c "source ${LIB} && vibecorp_stamp_mkdir" )
if [ -d "$CREATED_DIR" ]; then
  pass "vibecorp_stamp_mkdir でディレクトリ作成"
else
  fail "vibecorp_stamp_mkdir でディレクトリが作成されない: ${CREATED_DIR}"
fi

# パーミッション確認（macOS / Linux 両対応）
PERM=$(stat -c '%a' "$CREATED_DIR" 2>/dev/null || stat -f '%Lp' "$CREATED_DIR" 2>/dev/null || echo "unknown")
assert_eq "chmod 700 が適用される" "700" "$PERM"

# --- ケース 9: _vibecorp_sha256_short のフォールバック挙動 ---

echo "Test 9: _vibecorp_sha256_short が shasum 系コマンドで 8 文字を返す"
HASH=$( _vibecorp_sha256_short "test-input" )
HASH_LEN=${#HASH}
assert_eq "ハッシュ長が 8 文字" "8" "$HASH_LEN"

# 同一入力で同じハッシュ
HASH2=$( _vibecorp_sha256_short "test-input" )
assert_eq "同一入力で同じハッシュ" "$HASH" "$HASH2"

# 異なる入力で異なるハッシュ
HASH3=$( _vibecorp_sha256_short "different-input" )
if [ "$HASH" != "$HASH3" ]; then
  pass "異なる入力で異なるハッシュ"
else
  fail "異なる入力で同じハッシュが生成された"
fi

# --- ケース 10: _vibecorp_sha256_short のフォールバック分岐を強制検証 ---
# 実環境の /usr/bin/shasum 等に邪魔されないよう、PATH を FAKEBIN のみに限定する。
# _vibecorp_sha256_short が内部で使う cut/awk/cat は symlink 経由で利用可能にする。

echo "Test 10: shasum→sha256sum→openssl フォールバック分岐"

# FAKEBIN を作成し、基本コマンド (cat/cut/awk) のみを symlink で利用可能にする
setup_fakebin() {
  local dir="$1"
  mkdir -p "$dir"
  local tool src
  for tool in cat cut awk; do
    src=""
    if [ -x "/usr/bin/$tool" ]; then
      src="/usr/bin/$tool"
    elif [ -x "/bin/$tool" ]; then
      src="/bin/$tool"
    fi
    if [ -n "$src" ]; then
      ln -sf "$src" "${dir}/${tool}"
    fi
  done
}

write_fake_cmd() {
  local path="$1" body="$2"
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$body"
  } > "$path"
  chmod +x "$path"
}

# 10-1: shasum が最優先で使われる
FB_SHASUM="${TMPDIR_ROOT}/fb_shasum"
setup_fakebin "$FB_SHASUM"
write_fake_cmd "${FB_SHASUM}/shasum" 'cat >/dev/null; printf "aaaaaaaarest  -\n"'
HASH_A=$( PATH="$FB_SHASUM" _vibecorp_sha256_short "x" )
assert_eq "shasum 優先分岐" "aaaaaaaa" "$HASH_A"

# 10-2: shasum 不在 → sha256sum フォールバック
FB_SHA256SUM="${TMPDIR_ROOT}/fb_sha256sum"
setup_fakebin "$FB_SHA256SUM"
write_fake_cmd "${FB_SHA256SUM}/sha256sum" 'cat >/dev/null; printf "bbbbbbbbrest  -\n"'
HASH_B=$( PATH="$FB_SHA256SUM" _vibecorp_sha256_short "x" )
assert_eq "sha256sum フォールバック分岐" "bbbbbbbb" "$HASH_B"

# 10-3: shasum・sha256sum 不在 → openssl フォールバック
FB_OPENSSL="${TMPDIR_ROOT}/fb_openssl"
setup_fakebin "$FB_OPENSSL"
write_fake_cmd "${FB_OPENSSL}/openssl" 'cat >/dev/null; printf "SHA2-256(stdin)= ccccccccrest\n"'
HASH_C=$( PATH="$FB_OPENSSL" _vibecorp_sha256_short "x" )
assert_eq "openssl フォールバック分岐" "cccccccc" "$HASH_C"

# 10-4: 3 つ全て不在 → "00000000" を返す（テストで検出可能な固定値）
FB_NONE="${TMPDIR_ROOT}/fb_none"
setup_fakebin "$FB_NONE"
HASH_NONE=$( PATH="$FB_NONE" _vibecorp_sha256_short "x" )
assert_eq "全コマンド不在で 00000000 返却" "00000000" "$HASH_NONE"

# --- 結果 ---

echo ""
echo "================================================================"
echo "  Total: ${TOTAL}, Passed: ${PASSED}, Failed: ${FAILED}"
echo "================================================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
