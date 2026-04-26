#!/bin/bash
# test_context7.sh — Context7 スキルのテスト
# 使い方: bash tests/test_context7.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""

# --- ヘルパー ---

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

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: $path)"
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在する: $path)"
  fi
}

assert_dir_exists() {
  local desc="$1"
  local path="$2"
  if [ -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在しない: $path)"
  fi
}

assert_dir_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在する: $path)"
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
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

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
  cd "$SCRIPT_DIR"
}
trap cleanup EXIT

# ============================================
echo "=== A. テンプレートファイルの存在確認 ==="
# ============================================

# A1. SKILL.md テンプレートが存在する
assert_file_exists "context7 SKILL.md テンプレートが存在する" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md"

# A2. SKILL.md に name: context7 が含まれる
assert_file_contains "SKILL.md に name: context7 が含まれる" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "name: context7"

# A3. SKILL.md に c7 コマンドの記述がある
assert_file_contains "SKILL.md に c7 コマンドの記述がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "c7"

# A4. SKILL.md に未インストール時のフォールバック案内がある
assert_file_contains "SKILL.md に未インストール時のフォールバック案内がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "インストール"

# ============================================
echo "=== B. skills/ 非作成確認（プラグインキャッシュに移行済み） ==="
# ============================================

# B1. install.sh は skills/ を作成しない
for preset in minimal standard full; do
  create_test_repo
  bash "$INSTALL_SH" --name test-proj --preset "$preset" 2>/dev/null
  if [[ -d "$TMPDIR_ROOT/skills" ]]; then
    fail "${preset}: skills/ が作成されている（プラグインキャッシュに移行済み）"
  else
    pass "${preset}: skills/ が作成されていない"
  fi
  cleanup
done

# ============================================
echo "=== C. ソーステンプレートの SKILL.md 内容検証 ==="
# ============================================

# C1-C5: ソーステンプレートの内容を直接検証
assert_file_contains "SKILL.md に description がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "description:"

assert_file_contains "SKILL.md に c7 resolve の記述がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "c7 resolve"

assert_file_contains "SKILL.md に c7 get の記述がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "c7 get"

assert_file_contains "SKILL.md にエラーハンドリングの記述がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "エラーハンドリング"

assert_file_contains "SKILL.md にインストール方法の記載がある" \
  "${SCRIPT_DIR}/skills/context7/SKILL.md" \
  "npm install"

# ============================================
echo ""
echo "=== 結果 ==="
echo "合計: $TOTAL  成功: $PASSED  失敗: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
