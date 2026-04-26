#!/bin/bash
# test_install_claude_real.sh — install.sh の setup_claude_real_symlink() を検証する
#
# 対象:
#   - full + Darwin で .claude/bin/claude-real symlink が PATH 上の本物 claude を指す
#   - PATH 上に本物 claude が無い場合、SKIP ログを出してインストールは止まらない
#   - 既存の非 symlink ファイル（ユーザーが手動配置）は保持される
#   - minimal/standard プリセットへのダウングレード時に claude-real が削除される
#   - PATH 上の claude がラッパー自身を指す symlink の場合、検出から除外される
#
# 非 Darwin では早期 skip。

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: tests/test_install_claude_real.sh は Darwin 以外では実行しない（現在: $(uname -s)）"
  exit 0
fi

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
TMPDIR_ROOT=""

assert_symlink_to() {
  local desc="$1"
  local link="$2"
  local expected_target="$3"
  if [ -L "$link" ]; then
    local actual
    actual=$(readlink "$link")
    if [ "$actual" = "$expected_target" ]; then
      pass "$desc"
    else
      fail "$desc (symlink target 不一致: 期待=$expected_target, 実際=$actual)"
    fi
  else
    fail "$desc (symlink ではない: $link)"
  fi
}

assert_file_exists_not_symlink() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    pass "$desc"
  else
    fail "$desc (通常ファイルとして存在しない: $path)"
  fi
}

# --- セットアップ / クリーンアップ ---

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

# 偽 claude バイナリを配置するヘルパー（PATH に追加するための bin ディレクトリを返す）
create_fake_claude() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
echo "fake claude $@"
EOF
  chmod +x "$fake_bin/claude"
}

# 必須コマンドを含む最小 PATH を構成（sandbox-exec も含める）
build_minimal_path() {
  local fake_bin="$1"
  for cmd in bash git jq grep sed awk cat cp rm mv mkdir basename dirname uname chmod find tr mktemp cut sort head tail wc date pwd ls rmdir printf readlink ln sandbox-exec; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$fake_bin/$cmd"
    fi
  done
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# ============================================
echo "=== A. full + PATH 上に偽 claude → claude-real symlink が作られる ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
create_fake_claude "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1

assert_symlink_to "A1: claude-real が PATH 上の偽 claude を指す symlink になっている" \
  "$R/.claude/bin/claude-real" \
  "$FAKE_BIN/claude"
cleanup

# ============================================
echo ""
echo "=== B. full + PATH に claude 無し → SKIP ログでインストールは続行 ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
mkdir -p "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"
# claude を意図的に配置しない

OUT_LOG="$R/install_b.log"
EXIT_CODE=0
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > "$OUT_LOG" 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" = "0" ]; then
  pass "B1: PATH に claude 無しでもインストールは exit 0 で完了"
else
  fail "B1: インストールが失敗した (exit $EXIT_CODE)"
fi

if grep -q "本物の claude が PATH 上に見つかりません" "$OUT_LOG"; then
  pass "B2: SKIP ログに「本物の claude が PATH 上に見つかりません」が含まれる"
else
  fail "B2: 期待した SKIP ログが出ていない (log=$OUT_LOG)"
fi

assert_file_not_exists "B3: claude-real symlink は作成されない" "$R/.claude/bin/claude-real"
cleanup

# ============================================
echo ""
echo "=== C. 既存の非 symlink ファイルは保持される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
create_fake_claude "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"

# 先に full インストールして .claude/bin を作る（symlink 経路）
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1

# 既存 symlink を通常ファイルに置き換える（ユーザーが手動配置したケースを模擬）
rm -f "$R/.claude/bin/claude-real"
echo "user-managed binary" > "$R/.claude/bin/claude-real"
chmod +x "$R/.claude/bin/claude-real"

# 再度 install.sh を走らせる
OUT_LOG="$R/install_c.log"
PATH="$FAKE_BIN" bash "$INSTALL_SH" --update --preset full > "$OUT_LOG" 2>&1

assert_file_exists_not_symlink "C1: 既存の通常ファイル claude-real は保持される" "$R/.claude/bin/claude-real"

if grep -q "claude-real は既存ファイル（非 symlink）のため変更しません" "$OUT_LOG"; then
  pass "C2: SKIP ログに「既存ファイル（非 symlink）のため変更しません」が含まれる"
else
  fail "C2: 期待した SKIP ログが出ていない (log=$OUT_LOG)"
fi
cleanup

# ============================================
echo ""
echo "=== D. minimal プリセット: claude-real が削除される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
create_fake_claude "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1

# 前提確認: full で symlink が作られている
if [ ! -L "$R/.claude/bin/claude-real" ]; then
  fail "D-setup: full インストール後に claude-real symlink が存在するはず"
  exit 1
fi

# minimal にダウングレード
PATH="$FAKE_BIN" bash "$INSTALL_SH" --update --preset minimal > /dev/null 2>&1

assert_file_not_exists "D1: ダウングレード後 claude-real symlink が削除" "$R/.claude/bin/claude-real"
cleanup

# ============================================
echo ""
echo "=== E. standard プリセット: claude-real が削除される ==="
# ============================================

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
create_fake_claude "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1

# standard にダウングレード
PATH="$FAKE_BIN" bash "$INSTALL_SH" --update --preset standard > /dev/null 2>&1

assert_file_not_exists "E1: standard ダウングレード後 claude-real symlink が削除" "$R/.claude/bin/claude-real"
cleanup

# ============================================
echo ""
echo "=== F. PATH 上の claude がラッパー symlink を指す場合は除外される ==="
# ============================================
#
# シナリオ: install 後に .claude/bin が PATH に追加されており、
# 別の bin ディレクトリにも .claude/bin/claude を指す symlink が置かれている。
# この場合、ラッパー（claude-real を exec する）を再帰的に指してしまう経路を
# 防ぐため、検出から除外されることを確認する。

create_test_repo
R="$TMPDIR_ROOT"
FAKE_BIN="$R/_fake_bin"
mkdir -p "$FAKE_BIN"
build_minimal_path "$FAKE_BIN"
# 本物の claude は配置しない

# 先に full をインストール（この時点で claude-real は存在しない = SKIP される）
PATH="$FAKE_BIN" bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1

# .claude/bin/claude（ラッパー本体）が配置されている前提を確認
if [ ! -f "$R/.claude/bin/claude" ]; then
  fail "F-setup: .claude/bin/claude が配置されていない"
  exit 1
fi

# ラッパーを指す symlink を別の bin に配置
ALT_BIN="$R/_alt_bin"
mkdir -p "$ALT_BIN"
ln -s "$R/.claude/bin/claude" "$ALT_BIN/claude"

# ALT_BIN を PATH に含めて再 install
OUT_LOG="$R/install_f.log"
PATH="$ALT_BIN:$FAKE_BIN" bash "$INSTALL_SH" --update --preset full > "$OUT_LOG" 2>&1

# ラッパー symlink は本物 claude として検出されないため、claude-real は作られず SKIP になる
assert_file_not_exists "F1: ラッパーを指す symlink は検出から除外され claude-real は作成されない" "$R/.claude/bin/claude-real"

if grep -q "本物の claude が PATH 上に見つかりません" "$OUT_LOG"; then
  pass "F2: ラッパー symlink を除外した結果、SKIP ログが出る"
else
  fail "F2: 期待した SKIP ログが出ていない (log=$OUT_LOG)"
fi
cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
