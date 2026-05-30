#!/bin/bash
# test_bin_ssot_symlink.sh — Issue #760: templates/claude/bin/ SSOT + .claude/bin/ ファイル単位 symlink を検証する
#
# 対象（self-install / dogfooding 状態）:
#   - templates/claude/bin/ が SSOT 実体（symlink でない）
#   - vibecorp 自身の .claude/bin/{activate.sh,claude,vibecorp-sandbox} が symlink で
#     ../../templates/claude/bin/<name> を指し、dangling でなく内容が SSOT と一致する
#   - claude-real（マシン固有 symlink）は本検証の対象外（gitignore 済み）
#   - install.sh の copy_isolation_templates() が self/user 分岐を持つ
#
# user-install（配布先）の copy 配置検証は tests/test_install_isolation.sh が担う。
#
# 使い方: bash tests/test_bin_ssot_symlink.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SSOT_DIR="${ROOT}/templates/claude/bin"
DOGFOOD_DIR="${ROOT}/.claude/bin"

# symlink SSOT 対象（claude-real はマシン固有 symlink のため対象外）
BIN_FILES="activate.sh claude vibecorp-sandbox"

# ============================================
echo "=== 1. SSOT templates/claude/bin/ が実体ファイルを保持する ==="
# ============================================

assert_dir_exists "SSOT templates/claude/bin/ が存在する" "$SSOT_DIR"

if [[ ! -d "$SSOT_DIR" ]]; then
  fail "SSOT templates/claude/bin/ が存在しないため後続テストを中止します"
  exit 1
fi

for name in $BIN_FILES; do
  assert_file_exists "SSOT templates/claude/bin/${name} が存在する" "${SSOT_DIR}/${name}"
  if [[ -L "${SSOT_DIR}/${name}" ]]; then
    fail "SSOT ファイルが symlink になっている（実体であるべき）: templates/claude/bin/${name}"
  else
    pass "SSOT templates/claude/bin/${name} は実体ファイル（symlink でない）"
  fi
done

# ============================================
echo ""
echo "=== 2. vibecorp 自身の .claude/bin/{activate.sh,claude,vibecorp-sandbox} が symlink ==="
# ============================================

assert_dir_exists ".claude/bin/ ディレクトリが存在する" "$DOGFOOD_DIR"

for name in $BIN_FILES; do
  if [[ -L "${DOGFOOD_DIR}/${name}" ]]; then
    pass ".claude/bin/${name} は symlink"
  else
    fail ".claude/bin/${name} が symlink でない（self-install では symlink であるべき）"
  fi
done

# ============================================
echo ""
echo "=== 3. 各 symlink が正しい相対ターゲットを指す ==="
# ============================================

for name in $BIN_FILES; do
  target="$(readlink "${DOGFOOD_DIR}/${name}")"
  expected="../../templates/claude/bin/${name}"
  if [[ "$target" == "$expected" ]]; then
    pass ".claude/bin/${name} → ${expected}"
  else
    fail ".claude/bin/${name} の symlink ターゲットが ${target}（期待 ${expected}）"
  fi
done

# ============================================
echo ""
echo "=== 4. symlink が dangling でなく内容が SSOT と一致する ==="
# ============================================

for name in $BIN_FILES; do
  if [[ ! -e "${DOGFOOD_DIR}/${name}" ]]; then
    fail "dangling symlink（解決先不在）: .claude/bin/${name}"
  elif cmp -s "${DOGFOOD_DIR}/${name}" "${SSOT_DIR}/${name}"; then
    pass ".claude/bin/${name} が SSOT に解決され内容一致"
  else
    fail ".claude/bin/${name} が SSOT に解決されない（内容不一致）"
  fi
done

# ============================================
echo ""
echo "=== 5. claude-real は symlink SSOT 検証の対象外（マシン固有） ==="
# ============================================

# claude-real が存在する場合でも、SSOT（templates/claude/bin/）には含まれないことを確認する。
if [[ -e "${SSOT_DIR}/claude-real" || -L "${SSOT_DIR}/claude-real" ]]; then
  fail "claude-real が SSOT に混入している（マシン固有のため配布対象外であるべき）"
else
  pass "claude-real は SSOT（templates/claude/bin/）に含まれない"
fi

# ============================================
echo ""
echo "=== 6. install.sh の copy_isolation_templates() が self/user 分岐を持つ ==="
# ============================================

assert_file_contains "copy_isolation_templates() が bin の self-install symlink を貼る" \
  "${ROOT}/install.sh" 'ln -sfn "../../templates/claude/bin/'

assert_file_contains "copy_isolation_templates() が self/user 判定を持つ" \
  "${ROOT}/install.sh" 'bin_self_install=true'

# ============================================
print_test_summary
