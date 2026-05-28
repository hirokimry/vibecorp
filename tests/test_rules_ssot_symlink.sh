#!/bin/bash
# test_rules_ssot_symlink.sh — Issue #747: トップ rules/ SSOT + .claude/rules/ ファイル単位 symlink + templates/claude/rules/ 廃止 を検証する
# 使い方: bash tests/test_rules_ssot_symlink.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SSOT_DIR="${ROOT}/rules"
DOGFOOD_DIR="${ROOT}/.claude/rules"
TEMPLATE_DIR="${ROOT}/templates/claude/rules"

# 期待ファイル数（トップレベル 21 + severity サブ 2 = 23）
EXPECTED_TOTAL=23

# ============================================
echo "=== 1. SSOT rules/ が存在し 23 ファイル（severity サブ含む）を保持する ==="
# ============================================

assert_dir_exists "SSOT rules/ ディレクトリが存在する" "$SSOT_DIR"

# SSOT は実体ファイル（symlink でない通常ファイル）であること。
if [[ ! -d "$SSOT_DIR" ]]; then
  fail "SSOT rules/ が存在しないため後続テストを中止します"
  exit 1
fi

ssot_count=$(find "$SSOT_DIR" -type f -name "*.md" | wc -l | tr -d ' ')
if [[ "$ssot_count" -eq "$EXPECTED_TOTAL" ]]; then
  pass "SSOT rules/ に ${EXPECTED_TOTAL} ファイル存在する"
else
  fail "SSOT rules/ のファイル数が ${ssot_count}（期待 ${EXPECTED_TOTAL}）"
fi

# severity サブディレクトリ維持（.coderabbit.yaml / REVIEW.md 参照経路との整合）
assert_file_exists "SSOT rules/severity/claude-action.md" "${SSOT_DIR}/severity/claude-action.md"
assert_file_exists "SSOT rules/severity/coderabbit.md" "${SSOT_DIR}/severity/coderabbit.md"

# SSOT 配下のファイルは実体（symlink でない）であること
while IFS= read -r f; do
  if [[ -L "$f" ]]; then
    fail "SSOT ファイルが symlink になっている（実体であるべき）: ${f}"
  fi
done < <(find "$SSOT_DIR" -type f -name "*.md")
pass "SSOT rules/ 配下は全て実体ファイル（symlink でない）"

# ============================================
echo "=== 2. templates/claude/rules/ が物理削除されている ==="
# ============================================

if [[ ! -e "$TEMPLATE_DIR" ]]; then
  pass "templates/claude/rules/ が存在しない（物理削除済）"
else
  fail "templates/claude/rules/ がまだ残っている"
fi

# ============================================
echo "=== 3. .claude/rules/ 配下が全て symlink（実体ファイル 0 個） ==="
# ============================================

assert_dir_exists ".claude/rules/ ディレクトリが存在する" "$DOGFOOD_DIR"

# -type f は symlink を辿った先が通常ファイルだと真になるため、-type l（symlink そのもの）と
# 「symlink でない通常ファイル」を分けて数える。実体ファイル（! -L かつ -f）が 0 個であることを確認する。
real_file_count=0
while IFS= read -r f; do
  if [[ ! -L "$f" ]]; then
    real_file_count=$((real_file_count + 1))
    fail ".claude/rules/ に実体ファイルが残っている: ${f}"
  fi
done < <(find "$DOGFOOD_DIR" \( -type f -o -type l \) -name "*.md")

if [[ "$real_file_count" -eq 0 ]]; then
  pass ".claude/rules/ 配下に実体ファイルが 0 個（全て symlink）"
fi

# symlink 総数が 23 個であること
symlink_count=$(find "$DOGFOOD_DIR" -type l -name "*.md" | wc -l | tr -d ' ')
if [[ "$symlink_count" -eq "$EXPECTED_TOTAL" ]]; then
  pass ".claude/rules/ 配下の symlink が ${EXPECTED_TOTAL} 個"
else
  fail ".claude/rules/ 配下の symlink 数が ${symlink_count}（期待 ${EXPECTED_TOTAL}）"
fi

# ============================================
echo "=== 4. 各 symlink が正しい相対ターゲットを指す ==="
# ============================================

# トップレベル: .claude/rules/<file> → ../../rules/<file>
while IFS= read -r link; do
  base="$(basename "$link")"
  target="$(readlink "$link")"
  expected="../../rules/${base}"
  if [[ "$target" == "$expected" ]]; then
    pass ".claude/rules/${base} → ${expected}"
  else
    fail ".claude/rules/${base} の symlink ターゲットが ${target}（期待 ${expected}）"
  fi
done < <(find "$DOGFOOD_DIR" -maxdepth 1 -type l -name "*.md")

# severity サブ: .claude/rules/severity/<file> → ../../../rules/severity/<file>
while IFS= read -r link; do
  base="$(basename "$link")"
  target="$(readlink "$link")"
  expected="../../../rules/severity/${base}"
  if [[ "$target" == "$expected" ]]; then
    pass ".claude/rules/severity/${base} → ${expected}"
  else
    fail ".claude/rules/severity/${base} の symlink ターゲットが ${target}（期待 ${expected}）"
  fi
done < <(find "${DOGFOOD_DIR}/severity" -maxdepth 1 -type l -name "*.md")

# ============================================
echo "=== 5. symlink 経由で内容が読める（context loading 維持の代理検証） ==="
# ============================================

# 代表として markdown.md / severity/coderabbit.md が symlink 経由で SSOT 実体と一致することを確認する。
if cmp -s "${DOGFOOD_DIR}/markdown.md" "${SSOT_DIR}/markdown.md"; then
  pass ".claude/rules/markdown.md が SSOT に解決され内容一致"
else
  fail ".claude/rules/markdown.md が SSOT に解決されない"
fi
if cmp -s "${DOGFOOD_DIR}/severity/coderabbit.md" "${SSOT_DIR}/severity/coderabbit.md"; then
  pass ".claude/rules/severity/coderabbit.md が SSOT に解決され内容一致"
else
  fail ".claude/rules/severity/coderabbit.md が SSOT に解決されない"
fi

# 全 symlink が dangling（解決先不在）でないことを確認する
dangling=0
while IFS= read -r link; do
  if [[ ! -e "$link" ]]; then
    dangling=$((dangling + 1))
    fail "dangling symlink（解決先不在）: ${link}"
  fi
done < <(find "$DOGFOOD_DIR" -type l -name "*.md")
if [[ "$dangling" -eq 0 ]]; then
  pass ".claude/rules/ 配下に dangling symlink が無い"
fi

# ============================================
echo "=== 6. install.sh の copy_rules() が SSOT rules/ を配布元にしている ==="
# ============================================

assert_file_contains "copy_rules() が rules/ を配布元にしている" \
  "${ROOT}/install.sh" 'src="\${SCRIPT_DIR}/rules"'

# 旧配布元 templates/claude/rules を copy_rules が参照していないこと
if grep -q -e 'src="\${SCRIPT_DIR}/templates/claude/rules"' "${ROOT}/install.sh"; then
  fail "copy_rules() が旧配布元 templates/claude/rules を参照している"
else
  pass "copy_rules() が旧配布元 templates/claude/rules を参照していない"
fi

# ============================================
echo "=== 7. 内容乖離 3 ファイル（markdown / mvv / use-skills）が構造化版で SSOT に存在 ==="
# ============================================

# 構造化版は冒頭に [!IMPORTANT] コールアウトを持つ（古い箇条書き版は持たない）。
for f in markdown.md mvv.md use-skills.md; do
  assert_file_contains "SSOT rules/${f} が構造化版（IMPORTANT コールアウト）である" \
    "${SSOT_DIR}/${f}" "> \[!IMPORTANT\]"
done

# ============================================
print_test_summary
