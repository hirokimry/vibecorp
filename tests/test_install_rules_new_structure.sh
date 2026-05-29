#!/bin/bash
# test_install_rules_new_structure.sh — Issue #749: 実 SSOT 全量を配布元にした copy_rules() の両モード配置を検証する
# 使い方: bash tests/test_install_rules_new_structure.sh
# CI: GitHub Actions（other シャード）で自動実行
#
# #748 の test_install_rules_copy.sh は 2 ファイルの作為的モック SSOT で copy_rules() を検証する。
# 本テストは「実 SSOT を temp に複製したもの」を配布元にして copy_rules() を通し、
# Issue 表の「install → symlink × 23 再生成 / 物理コピー配置 / user 固有 rule 保持」を全量で充足する。
#
# 検証対象:
#   1. self-install（SCRIPT_DIR == REPO_ROOT）: .claude/rules/ が実 SSOT 全件分の symlink で再生成される
#   2. user-install（SCRIPT_DIR != REPO_ROOT）: .claude/rules/ が実 SSOT 全件分の物理コピーで配置される
#   3. severity/ サブが両モードで正しく配置される
#   4. user 固有 rule（配布対象外）が両モードで保持される

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# install.sh を source して copy_rules を直接呼べるようにする。
# install.sh 末尾の if [[ ${BASH_SOURCE[0]} == "$0" ]] ガードで main 自動起動は抑止される。
# shellcheck disable=SC1091
source "${ROOT}/install.sh"

# 実 SSOT のファイル数を動的取得する。ハードコード（23）に依存せず、SSOT 増減で陳腐化しない。
SSOT_SRC="${ROOT}/rules"
EXPECTED_TOTAL=$(find "$SSOT_SRC" -type f -name "*.md" | wc -l | tr -d ' ')

# 実 SSOT が存在しないと後続テストは全て無意味なので即終了する（testing.md）。
if [[ "$EXPECTED_TOTAL" -ge 1 ]]; then
  pass "実 SSOT rules/ に ${EXPECTED_TOTAL} ファイル存在する（配布元として有効）"
else
  fail "実 SSOT rules/ が空または不在のため後続テストを中止します"
  exit 1
fi

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

# 機能: 実 SSOT 全量を temp 配下に実体複製する（SSOT は symlink を含まない実体のため cp -R で安全）。
clone_ssot() {
  local dest_root="$1"
  mkdir -p "$dest_root"
  cp -R "$SSOT_SRC" "${dest_root}/rules"
}

# ============================================
echo "=== 1. self-install: .claude/rules/ が実 SSOT 全件分の symlink で再生成される ==="
# ============================================

self_root="${TMPDIR_ROOT}/self"
clone_ssot "$self_root"

# self-install は SCRIPT_DIR == REPO_ROOT。_canonical_dir の絶対パス比較が一致するよう同一文字列を渡す。
SCRIPT_DIR="$self_root" REPO_ROOT="$self_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

self_dest="${self_root}/.claude/rules"

# symlink 総数が実 SSOT 件数と一致する（= 全件 symlink で再生成された）
self_symlink_count=$(find "$self_dest" -type l -name "*.md" | wc -l | tr -d ' ')
if [[ "$self_symlink_count" -eq "$EXPECTED_TOTAL" ]]; then
  pass "self-install: symlink が ${EXPECTED_TOTAL} 個（実 SSOT 全件分）"
else
  fail "self-install: symlink 数が ${self_symlink_count}（期待 ${EXPECTED_TOTAL}）"
fi

# 実体ファイル（! -L かつ -f）が 0 個（全て symlink）
self_real_count=0
while IFS= read -r f; do
  if [[ ! -L "$f" ]]; then
    self_real_count=$((self_real_count + 1))
    fail "self-install: 実体ファイルが残っている: ${f}"
  fi
done < <(find "$self_dest" \( -type f -o -type l \) -name "*.md")
if [[ "$self_real_count" -eq 0 ]]; then
  pass "self-install: 実体ファイルが 0 個（全て symlink）"
fi

# severity サブが symlink で配置され正しい相対ターゲットを指す
if [[ -L "${self_dest}/severity/coderabbit.md" ]]; then
  pass "self-install: severity/coderabbit.md が symlink"
else
  fail "self-install: severity/coderabbit.md が symlink でない"
fi
self_sev_target=$(readlink "${self_dest}/severity/coderabbit.md")
assert_eq "self-install: severity/coderabbit.md の相対ターゲット" \
  "../../../rules/severity/coderabbit.md" "$self_sev_target"

# 機能: rel_path から .claude/rules 起点の期待相対ターゲットを独立計算する。
# install.sh の _relpath_to_rules をそのまま使うと検証が同義反復になるため、
# 同じ仕様（.claude/rules の 2 段 + サブディレクトリ深さ分だけ遡り rules/<rel>）をテスト側で再実装する。
expected_rel_target() {
  local rel="$1"
  local slash_count
  slash_count=$(printf '%s' "$rel" | tr -cd '/' | wc -c | tr -d ' ')
  local up_levels=$((2 + slash_count))
  local prefix=""
  local i
  for ((i = 0; i < up_levels; i++)); do
    prefix="${prefix}../"
  done
  printf '%s' "${prefix}rules/${rel}"
}

# 全件: 各 rule が symlink であり、相対ターゲットが期待値と一致し、解決先が実 SSOT と内容一致することを検証する。
# 代表ファイルのみの検証だと「件数は合うが個別のリンク先が誤り」を取りこぼすため（Issue #749 全量保証）。
while IFS= read -r src_file; do
  rel="${src_file#"${self_root}/rules/"}"
  dst="${self_dest}/${rel}"
  if [[ ! -L "$dst" ]]; then
    fail "self-install: ${rel} が symlink でない"
    continue
  fi
  expected_target="$(expected_rel_target "$rel")"
  actual_target=$(readlink "$dst")
  assert_eq "self-install: ${rel} の相対ターゲット" "$expected_target" "$actual_target"
  if cmp -s "$dst" "$src_file"; then
    pass "self-install: ${rel} が実 SSOT に解決され内容一致"
  else
    fail "self-install: ${rel} の解決先内容が実 SSOT と一致しない"
  fi
done < <(find "${self_root}/rules" -maxdepth 2 -type f -name "*.md")

# dangling symlink が 0 個（symlink 経由で実 SSOT に解決される）
self_dangling=0
while IFS= read -r link; do
  if [[ ! -e "$link" ]]; then
    self_dangling=$((self_dangling + 1))
    fail "self-install: dangling symlink: ${link}"
  fi
done < <(find "$self_dest" -type l -name "*.md")
if [[ "$self_dangling" -eq 0 ]]; then
  pass "self-install: dangling symlink が 0 個（実 SSOT に解決される）"
fi

# ============================================
echo "=== 2. user-install: .claude/rules/ が実 SSOT 全件分の物理コピーで配置される ==="
# ============================================

plugin_root="${TMPDIR_ROOT}/plugin"
clone_ssot "$plugin_root"
user_root="${TMPDIR_ROOT}/user"
mkdir -p "$user_root"

# 既存配布対象ファイルを stale 内容で先置きし、「上書き（3-way マージなし）」を検証する（Issue #748 / #749）。
# install 後に SSOT と完全一致すれば、旧内容を温存せず最新で上書きしたことが保証される。
mkdir -p "${user_root}/.claude/rules/severity"
printf 'stale-content\n' > "${user_root}/.claude/rules/markdown.md"
printf 'stale-content\n' > "${user_root}/.claude/rules/severity/coderabbit.md"

# user-install は SCRIPT_DIR != REPO_ROOT
SCRIPT_DIR="$plugin_root" REPO_ROOT="$user_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

user_dest="${user_root}/.claude/rules"

# 実体ファイル（! -L かつ -f）の総数が実 SSOT 件数と一致する
user_real_count=0
while IFS= read -r f; do
  if [[ ! -L "$f" ]]; then
    user_real_count=$((user_real_count + 1))
  fi
done < <(find "$user_dest" -type f -name "*.md")
if [[ "$user_real_count" -eq "$EXPECTED_TOTAL" ]]; then
  pass "user-install: 実体ファイルが ${EXPECTED_TOTAL} 個（実 SSOT 全件分）"
else
  fail "user-install: 実体ファイル数が ${user_real_count}（期待 ${EXPECTED_TOTAL}）"
fi

# symlink が 0 個（user-install では symlink を配布しない）
user_symlink_count=$(find "$user_dest" -type l -name "*.md" | wc -l | tr -d ' ')
if [[ "$user_symlink_count" -eq 0 ]]; then
  pass "user-install: symlink が 0 個（物理コピーのみ）"
else
  fail "user-install: symlink が ${user_symlink_count} 個残っている（0 個であるべき）"
fi

# severity サブも物理コピー（実体）で配置される
if [[ -f "${user_dest}/severity/coderabbit.md" && ! -L "${user_dest}/severity/coderabbit.md" ]]; then
  pass "user-install: severity/coderabbit.md が実体ファイル（非 symlink）"
else
  fail "user-install: severity/coderabbit.md が実体ファイルでない"
fi

# 代表ファイル内容が実 SSOT と一致する
if cmp -s "${user_dest}/markdown.md" "${plugin_root}/rules/markdown.md"; then
  pass "user-install: markdown.md の内容が実 SSOT と一致"
else
  fail "user-install: markdown.md の内容が実 SSOT と一致しない"
fi
if cmp -s "${user_dest}/severity/coderabbit.md" "${plugin_root}/rules/severity/coderabbit.md"; then
  pass "user-install: severity/coderabbit.md の内容が実 SSOT と一致"
else
  fail "user-install: severity/coderabbit.md の内容が実 SSOT と一致しない"
fi

# 全件: 各 rule が実体ファイル（非 symlink）かつ実 SSOT と内容一致することを検証する。
# 先置きした stale ファイル（markdown.md / severity/coderabbit.md）も含めて完全一致なら、
# 「上書き（3-way マージなし）」が全量で担保される（Issue #748 / #749）。
while IFS= read -r src_file; do
  rel="${src_file#"${plugin_root}/rules/"}"
  dst="${user_dest}/${rel}"
  if [[ ! -f "$dst" || -L "$dst" ]]; then
    fail "user-install: ${rel} が実体ファイルでない"
    continue
  fi
  if cmp -s "$dst" "$src_file"; then
    pass "user-install: ${rel} の内容が実 SSOT と一致（stale 上書き済み）"
  else
    fail "user-install: ${rel} の内容が実 SSOT と一致しない"
  fi
done < <(find "${plugin_root}/rules" -maxdepth 2 -type f -name "*.md")

# ============================================
echo "=== 3. user 固有 rule（配布対象外）が両モードで保持される ==="
# ============================================

# user-install: 配布物にない名前のファイルを先置きし、全件 install 後も保持される
keep_user_root="${TMPDIR_ROOT}/keep_user"
clone_ssot "$keep_user_root"
mkdir -p "${keep_user_root}/.claude/rules"
printf 'user-own-rule\n' > "${keep_user_root}/.claude/rules/my-custom.md"
keep_plugin_root="${TMPDIR_ROOT}/keep_plugin"
clone_ssot "$keep_plugin_root"

SCRIPT_DIR="$keep_plugin_root" REPO_ROOT="$keep_user_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

assert_file_exists "user-install: 配布対象外 my-custom.md が保持される" \
  "${keep_user_root}/.claude/rules/my-custom.md"

# self-install: 配布物にない名前のファイルを先置きし、symlink 再生成後も保持される
keep_self_root="${TMPDIR_ROOT}/keep_self"
clone_ssot "$keep_self_root"
mkdir -p "${keep_self_root}/.claude/rules"
printf 'user-own-rule\n' > "${keep_self_root}/.claude/rules/my-custom.md"

SCRIPT_DIR="$keep_self_root" REPO_ROOT="$keep_self_root" UPDATE_MODE=false COPIED_RULES="" copy_rules >/dev/null 2>&1

assert_file_exists "self-install: 配布対象外 my-custom.md が保持される" \
  "${keep_self_root}/.claude/rules/my-custom.md"

# ============================================
print_test_summary
