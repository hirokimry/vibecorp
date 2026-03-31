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
  "${SCRIPT_DIR}/templates/claude/skills/context7/SKILL.md"

# A2. SKILL.md に name: context7 が含まれる
assert_file_contains "SKILL.md に name: context7 が含まれる" \
  "${SCRIPT_DIR}/templates/claude/skills/context7/SKILL.md" \
  "name: context7"

# A3. SKILL.md に c7 コマンドの記述がある
assert_file_contains "SKILL.md に c7 コマンドの記述がある" \
  "${SCRIPT_DIR}/templates/claude/skills/context7/SKILL.md" \
  "c7"

# A4. SKILL.md に未インストール時のフォールバック案内がある
assert_file_contains "SKILL.md に未インストール時のフォールバック案内がある" \
  "${SCRIPT_DIR}/templates/claude/skills/context7/SKILL.md" \
  "インストール"

# ============================================
echo "=== B. プリセット別配置テスト ==="
# ============================================

# B1. minimal プリセットでは context7 が削除される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
assert_dir_not_exists "minimal: context7 スキルが削除される" \
  "$TMPDIR_ROOT/.claude/skills/context7"
cleanup

# B2. standard プリセットでは context7 が配置される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
assert_dir_exists "standard: context7 スキルが配置される" \
  "$TMPDIR_ROOT/.claude/skills/context7"
assert_file_exists "standard: context7 SKILL.md が配置される" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md"
cleanup

# B3. full プリセットでは context7 が配置される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
assert_dir_exists "full: context7 スキルが配置される" \
  "$TMPDIR_ROOT/.claude/skills/context7"
assert_file_exists "full: context7 SKILL.md が配置される" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md"
cleanup

# ============================================
echo "=== C. SKILL.md の内容検証 ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null

# C1. フロントマターに description がある
assert_file_contains "SKILL.md に description がある" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md" \
  "description:"

# C2. c7 resolve コマンドの記述がある
assert_file_contains "SKILL.md に c7 resolve の記述がある" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md" \
  "c7 resolve"

# C3. c7 get コマンドの記述がある
assert_file_contains "SKILL.md に c7 get の記述がある" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md" \
  "c7 get"

# C4. エラーハンドリングセクションがある
assert_file_contains "SKILL.md にエラーハンドリングの記述がある" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md" \
  "エラーハンドリング"

# C5. 未インストール時のインストール方法が記載されている
assert_file_contains "SKILL.md にインストール方法の記載がある" \
  "$TMPDIR_ROOT/.claude/skills/context7/SKILL.md" \
  "npm install"

cleanup

# ============================================
echo "=== D. yml による無効化テスト ==="
# ============================================

# D1. vibecorp.yml で context7 を無効化すると配置されない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
# context7 が配置されていることを確認
assert_dir_exists "無効化前: context7 が配置されている" \
  "$TMPDIR_ROOT/.claude/skills/context7"

# vibecorp.yml に skills セクションを追加して context7 を無効化
{
  echo "skills:"
  echo "  context7: false"
} >> "$TMPDIR_ROOT/.claude/vibecorp.yml"

# --update で再インストール
bash "$INSTALL_SH" --update 2>/dev/null
assert_dir_not_exists "yml 無効化後: context7 スキルが削除される" \
  "$TMPDIR_ROOT/.claude/skills/context7"
cleanup

# ============================================
echo ""
echo "=== 結果 ==="
echo "合計: $TOTAL  成功: $PASSED  失敗: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
