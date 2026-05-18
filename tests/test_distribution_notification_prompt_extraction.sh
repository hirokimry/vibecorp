#!/bin/bash
# test_distribution_notification_prompt_extraction.sh — 切り出しルール (notification-prompt-extraction.md) が利用先プロジェクトへ配布される構造を検証する (Issue #638)
# 使い方: bash tests/test_distribution_notification_prompt_extraction.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 配布対象 1 ファイル
RULE="notification-prompt-extraction.md"

# 配置先 3 か所
SRC_DIR="${SCRIPT_DIR}/.claude/rules"
BASE_DIR="${SCRIPT_DIR}/.claude/vibecorp-base/rules"
TEMPLATE_DIR="${SCRIPT_DIR}/templates/claude/rules"

# ============================================
echo "=== 本体 .claude/rules/ にファイルが存在する ==="
# ============================================

assert_file_exists "本体 .claude/rules/${RULE} が存在する" "${SRC_DIR}/${RULE}"

# 本体が存在しないと後続テストが無意味になるので早期終了 (testing.md 規約)
if [[ ! -f "${SRC_DIR}/${RULE}" ]]; then
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "本体 ${RULE} が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 配布元 templates/claude/rules/ にファイルが存在する（git 管理対象） ==="
# ============================================

assert_file_exists "配布元 templates/claude/rules/${RULE} が存在する" "${TEMPLATE_DIR}/${RULE}"

# ============================================
echo "=== 本体 ↔ 配布元（templates）が完全一致する ==="
# ============================================

if cmp -s "${SRC_DIR}/${RULE}" "${TEMPLATE_DIR}/${RULE}"; then
  pass "本体 ↔ 配布元 templates の ${RULE} が完全一致"
else
  fail "本体 ↔ 配布元 templates の ${RULE} が一致しない（同期されていない）"
fi

# ============================================
echo "=== 配布版1 .claude/vibecorp-base/rules/ の検証（install.sh 自動生成、ローカルのみ） ==="
# ============================================

# .claude/vibecorp-base/ は .claude/.gitignore で除外されたベーススナップショット。
# install.sh の copy_rules() → save_base_snapshot() で自動生成される。
# 本体リポジトリで self-install 済みのローカル環境では検証、CI/fresh clone ではスキップ。
if [[ -d "${BASE_DIR}" ]]; then
  assert_file_exists "配布版1 .claude/vibecorp-base/rules/${RULE} が存在する" "${BASE_DIR}/${RULE}"
  if [[ -f "${BASE_DIR}/${RULE}" ]]; then
    if cmp -s "${SRC_DIR}/${RULE}" "${BASE_DIR}/${RULE}"; then
      pass "本体 ↔ 配布版1 の ${RULE} が完全一致"
    else
      fail "本体 ↔ 配布版1 の ${RULE} が一致しない（install.sh 再実行で再生成可能）"
    fi
  fi
else
  echo "  SKIP: .claude/vibecorp-base/rules/ が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
echo "=== install.sh の copy_rules() が新規ファイルを配布対象として列挙する ==="
# ============================================

# copy_rules() は find -maxdepth 2 -type f -name "*.md" で自動列挙する
FOUND_RULES=$(find "${TEMPLATE_DIR}" -maxdepth 2 -type f -name "*.md")
if echo "$FOUND_RULES" | grep -q -e "${TEMPLATE_DIR}/${RULE}"; then
  pass "install.sh の copy_rules() が ${RULE} を列挙する"
else
  fail "install.sh の copy_rules() が ${RULE} を列挙しない"
fi

# ============================================
echo "=== 配布版 templates が本体と同じ frontmatter (paths) を保持する ==="
# ============================================

# 切り出しルールは workflow / hook / SKILL.md を対象に作動する。配布版でも paths が同期しないと利用先で発動しない。
assert_file_contains "配布元 templates に paths キー" "${TEMPLATE_DIR}/${RULE}" "^paths:"
assert_file_contains "配布元 templates に .github/workflows/**/*.yml" "${TEMPLATE_DIR}/${RULE}" '"\.github/workflows/\*\*/\*\.yml"'
assert_file_contains "配布元 templates に .github/workflows/**/*.yaml" "${TEMPLATE_DIR}/${RULE}" '"\.github/workflows/\*\*/\*\.yaml"'
assert_file_contains "配布元 templates に hooks/**/*.sh" "${TEMPLATE_DIR}/${RULE}" '"hooks/\*\*/\*\.sh"'
assert_file_contains "配布元 templates に skills/**/SKILL.md" "${TEMPLATE_DIR}/${RULE}" '"skills/\*\*/SKILL\.md"'

# ============================================
echo ""
echo "=== 結果サマリ ==="
# ============================================

print_test_summary
