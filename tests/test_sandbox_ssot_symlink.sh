#!/bin/bash
# test_sandbox_ssot_symlink.sh — Issue #761: templates/claude/sandbox/ SSOT + .claude/sandbox/ symlink を検証する
#
# 対象（self-install / dogfooding 状態）:
#   - templates/claude/sandbox/{claude.sb,bwrap-args.sh} が SSOT 実体（symlink でない）
#   - vibecorp 自身の .claude/sandbox/claude.sb（dev マシン macOS の OS 該当ファイル）が symlink で
#     ../../templates/claude/sandbox/claude.sb を指し、dangling でなく内容が SSOT と一致する
#   - install.sh の copy_isolation_templates() が OS 別選択を self/user 分岐内に持つ
#
# user-install（配布先）の OS 別 copy 配置検証は tests/test_install_isolation.sh が担う。
#
# 使い方: bash tests/test_sandbox_ssot_symlink.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SSOT_DIR="${ROOT}/templates/claude/sandbox"
DOGFOOD_DIR="${ROOT}/.claude/sandbox"

# ============================================
echo "=== 1. SSOT templates/claude/sandbox/ が OS 別実体ファイルを保持する ==="
# ============================================

assert_dir_exists "SSOT templates/claude/sandbox/ が存在する" "$SSOT_DIR"

if [[ ! -d "$SSOT_DIR" ]]; then
  fail "SSOT templates/claude/sandbox/ が存在しないため後続テストを中止します"
  exit 1
fi

for name in claude.sb bwrap-args.sh; do
  assert_file_exists "SSOT templates/claude/sandbox/${name} が存在する" "${SSOT_DIR}/${name}"
  if [[ -L "${SSOT_DIR}/${name}" ]]; then
    fail "SSOT ファイルが symlink になっている（実体であるべき）: templates/claude/sandbox/${name}"
  else
    pass "SSOT templates/claude/sandbox/${name} は実体ファイル（symlink でない）"
  fi
done

# ============================================
echo ""
echo "=== 2. vibecorp 自身の .claude/sandbox/claude.sb が symlink ==="
# ============================================

assert_dir_exists ".claude/sandbox/ ディレクトリが存在する" "$DOGFOOD_DIR"

# dev マシンは macOS のため claude.sb が OS 該当ファイル（symlink SSOT 化対象）
if [[ -L "${DOGFOOD_DIR}/claude.sb" ]]; then
  pass ".claude/sandbox/claude.sb は symlink"
else
  fail ".claude/sandbox/claude.sb が symlink でない（self-install では symlink であるべき）"
fi

# ============================================
echo ""
echo "=== 3. symlink が正しい相対ターゲットを指し dangling でなく内容一致 ==="
# ============================================

target="$(readlink "${DOGFOOD_DIR}/claude.sb")"
expected="../../templates/claude/sandbox/claude.sb"
if [[ "$target" == "$expected" ]]; then
  pass ".claude/sandbox/claude.sb → ${expected}"
else
  fail ".claude/sandbox/claude.sb の symlink ターゲットが ${target}（期待 ${expected}）"
fi

if [[ ! -e "${DOGFOOD_DIR}/claude.sb" ]]; then
  fail "dangling symlink（解決先不在）: .claude/sandbox/claude.sb"
elif cmp -s "${DOGFOOD_DIR}/claude.sb" "${SSOT_DIR}/claude.sb"; then
  pass ".claude/sandbox/claude.sb が SSOT に解決され内容一致"
else
  fail ".claude/sandbox/claude.sb が SSOT に解決されない（内容不一致）"
fi

# ============================================
echo ""
echo "=== 4. install.sh の sandbox 配置が OS 別選択 + self/user 分岐を持つ ==="
# ============================================

assert_file_contains "sandbox 配置が darwin→claude.sb を選択する" \
  "${ROOT}/install.sh" 'darwin) sandbox_file="claude.sb"'
assert_file_contains "sandbox 配置が linux→bwrap-args.sh を選択する" \
  "${ROOT}/install.sh" 'linux)  sandbox_file="bwrap-args.sh"'
assert_file_contains "sandbox の self-install symlink を貼る" \
  "${ROOT}/install.sh" 'ln -sfn "../../templates/claude/sandbox/'
assert_file_contains "bin/sandbox 共有の self/user 判定を持つ" \
  "${ROOT}/install.sh" 'isolation_self_install=true'

# ============================================
print_test_summary
