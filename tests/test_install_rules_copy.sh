#!/bin/bash
# test_install_rules_copy.sh — Issue #748: copy_rules() の self-install / user-install 2 モード分岐を検証する
# 使い方: bash tests/test_install_rules_copy.sh
# CI: GitHub Actions で自動実行
#
# 検証対象:
#   1. _relpath_to_rules がサブディレクトリ深さに応じた相対 symlink ターゲットを返す
#   2. self-install（SCRIPT_DIR == REPO_ROOT）: .claude/rules/ が SSOT への symlink で再生成される
#   3. user-install（SCRIPT_DIR != REPO_ROOT）: .claude/rules/ が物理コピー（実体ファイル）で配置される
#   4. user-install: 既存のカスタム編集ファイルが 3-way マージされず常に上書きされる
#   5. user 固有 rule（配布対象外）が両モードで保持される

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# install.sh を source して copy_rules / _relpath_to_rules を直接呼べるようにする。
# install.sh は末尾の if [[ ${BASH_SOURCE[0]} == "$0" ]] ガードで main 自動起動を抑止している。
# shellcheck disable=SC1091
source "${ROOT}/install.sh"

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

# テスト用の最小 SSOT rules/ を一時ディレクトリ配下に作る
make_ssot() {
  local plugin_root="$1"
  mkdir -p "${plugin_root}/rules/severity"
  printf 'top-rule-body\n' > "${plugin_root}/rules/markdown.md"
  printf 'sub-rule-body\n' > "${plugin_root}/rules/severity/coderabbit.md"
}

# ============================================
echo "=== 1. _relpath_to_rules が階層深さに応じた相対ターゲットを返す ==="
# ============================================

result=$(_relpath_to_rules "markdown.md")
assert_eq "トップ直下 markdown.md → ../../rules/markdown.md" "../../rules/markdown.md" "$result"

result=$(_relpath_to_rules "severity/coderabbit.md")
assert_eq "severity サブ → ../../../rules/severity/coderabbit.md" "../../../rules/severity/coderabbit.md" "$result"

# ============================================
echo "=== 2. self-install: .claude/rules/ が symlink で再生成される ==="
# ============================================

self_root="${TMPDIR_ROOT}/self"
mkdir -p "$self_root"
make_ssot "$self_root"

# self-install は SCRIPT_DIR == REPO_ROOT
SCRIPT_DIR="$self_root" REPO_ROOT="$self_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

self_dest="${self_root}/.claude/rules"

if [[ -L "${self_dest}/markdown.md" ]]; then
  pass "self-install: markdown.md が symlink"
else
  fail "self-install: markdown.md が symlink でない"
fi

if [[ -L "${self_dest}/severity/coderabbit.md" ]]; then
  pass "self-install: severity/coderabbit.md が symlink"
else
  fail "self-install: severity/coderabbit.md が symlink でない"
fi

target=$(readlink "${self_dest}/markdown.md")
assert_eq "self-install: markdown.md ターゲット" "../../rules/markdown.md" "$target"

target=$(readlink "${self_dest}/severity/coderabbit.md")
assert_eq "self-install: severity/coderabbit.md ターゲット" "../../../rules/severity/coderabbit.md" "$target"

# symlink 経由で SSOT 実体と内容一致（dangling でない）
if cmp -s "${self_dest}/markdown.md" "${self_root}/rules/markdown.md"; then
  pass "self-install: symlink 経由で SSOT 内容に解決される"
else
  fail "self-install: symlink が SSOT に解決されない（dangling）"
fi

# ============================================
echo "=== 3. user-install: .claude/rules/ が物理コピー（実体ファイル）で配置される ==="
# ============================================

plugin_root="${TMPDIR_ROOT}/plugin"
user_root="${TMPDIR_ROOT}/user"
mkdir -p "$plugin_root" "$user_root"
make_ssot "$plugin_root"

# user-install は SCRIPT_DIR != REPO_ROOT
SCRIPT_DIR="$plugin_root" REPO_ROOT="$user_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

user_dest="${user_root}/.claude/rules"

if [[ -f "${user_dest}/markdown.md" && ! -L "${user_dest}/markdown.md" ]]; then
  pass "user-install: markdown.md が実体ファイル（非 symlink）"
else
  fail "user-install: markdown.md が実体ファイルでない"
fi

if [[ -f "${user_dest}/severity/coderabbit.md" && ! -L "${user_dest}/severity/coderabbit.md" ]]; then
  pass "user-install: severity/coderabbit.md が実体ファイル（非 symlink）"
else
  fail "user-install: severity/coderabbit.md が実体ファイルでない"
fi

if cmp -s "${user_dest}/markdown.md" "${plugin_root}/rules/markdown.md"; then
  pass "user-install: 物理コピー内容が SSOT と一致"
else
  fail "user-install: 物理コピー内容が SSOT と一致しない"
fi

# ============================================
echo "=== 4. user-install: カスタム編集ファイルが 3-way マージされず上書きされる ==="
# ============================================

overwrite_root="${TMPDIR_ROOT}/overwrite"
mkdir -p "${overwrite_root}/.claude/rules"
make_ssot "$plugin_root"
# 配置先に SSOT と異なるカスタム内容を先に置く
printf 'CUSTOM-EDITED-CONTENT\n' > "${overwrite_root}/.claude/rules/markdown.md"

SCRIPT_DIR="$plugin_root" REPO_ROOT="$overwrite_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

# 上書きされ SSOT 内容になる（カスタム内容は保持されない）
if cmp -s "${overwrite_root}/.claude/rules/markdown.md" "${plugin_root}/rules/markdown.md"; then
  pass "user-install: カスタム編集が SSOT で上書きされる"
else
  fail "user-install: カスタム編集が上書きされていない"
fi

# コンフリクトマーカーが生成されていない（3-way マージしていない証跡）
if grep -q -e '<<<<<<<' "${overwrite_root}/.claude/rules/markdown.md"; then
  fail "user-install: コンフリクトマーカーが混入（3-way マージが残っている）"
else
  pass "user-install: コンフリクトマーカーなし（3-way マージしていない）"
fi

# ============================================
echo "=== 5. user 固有 rule（配布対象外）が両モードで保持される ==="
# ============================================

# user-install: 配布対象外ファイルを置いてから copy_rules を呼んでも残る
keep_user_root="${TMPDIR_ROOT}/keep_user"
mkdir -p "${keep_user_root}/.claude/rules"
make_ssot "$plugin_root"
printf 'user-own-rule\n' > "${keep_user_root}/.claude/rules/custom-user-rule.md"

SCRIPT_DIR="$plugin_root" REPO_ROOT="$keep_user_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

assert_file_exists "user-install: 配布対象外 custom-user-rule.md が保持される" \
  "${keep_user_root}/.claude/rules/custom-user-rule.md"

# self-install: 配布対象外ファイルを置いてから copy_rules を呼んでも残る
keep_self_root="${TMPDIR_ROOT}/keep_self"
mkdir -p "${keep_self_root}/.claude/rules"
make_ssot "$keep_self_root"
printf 'user-own-rule\n' > "${keep_self_root}/.claude/rules/custom-user-rule.md"

SCRIPT_DIR="$keep_self_root" REPO_ROOT="$keep_self_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

assert_file_exists "self-install: 配布対象外 custom-user-rule.md が保持される" \
  "${keep_self_root}/.claude/rules/custom-user-rule.md"

# ============================================
print_test_summary
