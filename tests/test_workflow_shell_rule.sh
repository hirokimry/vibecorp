#!/bin/bash
# test_workflow_shell_rule.sh — workflow-shell ルールが本体と配布元 templates の両方に配置され
# 完全一致していること、および関連既存ルールからの参照が追加されたことを検証する（Issue #622）
# 使い方: bash tests/test_workflow_shell_rule.sh
# CI: GitHub Actions の test.yml 'other' シャードで自動実行される

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 配置先（本体 + 配布元 templates）
SRC_DIR="${SCRIPT_DIR}/.claude/rules"
BASE_DIR="${SCRIPT_DIR}/.claude/vibecorp-base/rules"
TEMPLATE_DIR="${SCRIPT_DIR}/templates/claude/rules"

RULE_FILE="workflow-shell.md"

# ============================================
echo "=== 本体 .claude/rules/${RULE_FILE} が存在する ==="
# ============================================

assert_file_exists "本体 .claude/rules/${RULE_FILE} が存在する" "${SRC_DIR}/${RULE_FILE}"

# 本体が無いと後続テストが無意味になるので早期終了
if [[ ! -f "${SRC_DIR}/${RULE_FILE}" ]]; then
  echo ""
  echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
  echo "本体 ${RULE_FILE} が存在しないため後続テストを中止します"
  exit 1
fi

# ============================================
echo "=== 配布元 templates/claude/rules/${RULE_FILE} が存在する ==="
# ============================================

assert_file_exists "配布元 templates/claude/rules/${RULE_FILE} が存在する" "${TEMPLATE_DIR}/${RULE_FILE}"

# ============================================
echo "=== 本体 ↔ 配布元 templates が完全一致する ==="
# ============================================

if cmp -s "${SRC_DIR}/${RULE_FILE}" "${TEMPLATE_DIR}/${RULE_FILE}"; then
  pass "本体 ↔ 配布元 templates の ${RULE_FILE} が完全一致"
else
  fail "本体 ↔ 配布元 templates の ${RULE_FILE} が一致しない（同期されていない）"
fi

# ============================================
echo "=== 必須キーワードを含む（本体 + 配布元 templates） ==="
# ============================================

# Issue #622 完了条件: ルール本文に必須要素が含まれていること
REQUIRED_KEYWORDS=(
  "3 行"
  ".github/scripts/"
  "tests/"
  "shell.md"
  "testing.md"
  "インライン"
)

for dir_pair in "本体:${SRC_DIR}" "配布元 templates:${TEMPLATE_DIR}"; do
  label="${dir_pair%%:*}"
  dir="${dir_pair#*:}"
  for kw in "${REQUIRED_KEYWORDS[@]}"; do
    assert_file_contains "${label} ${RULE_FILE} に必須キーワード「${kw}」が含まれる" \
      "${dir}/${RULE_FILE}" "${kw}"
  done
done

# ============================================
echo "=== 関連既存ルール（shell.md / testing.md）から workflow-shell.md への参照が追加された ==="
# ============================================

# 本体側
assert_file_contains "本体 shell.md に workflow-shell.md への参照" \
  "${SRC_DIR}/shell.md" "workflow-shell.md"
assert_file_contains "本体 testing.md に workflow-shell.md への参照" \
  "${SRC_DIR}/testing.md" "workflow-shell.md"

# 配布元 templates 側
assert_file_contains "配布元 templates shell.md に workflow-shell.md への参照" \
  "${TEMPLATE_DIR}/shell.md" "workflow-shell.md"
assert_file_contains "配布元 templates testing.md に workflow-shell.md への参照" \
  "${TEMPLATE_DIR}/testing.md" "workflow-shell.md"

# ============================================
echo "=== install.sh の copy_rules() が ${RULE_FILE} を列挙する ==="
# ============================================

# copy_rules() は find -maxdepth 2 -type f -name "*.md" で自動列挙する
FOUND_RULES=$(find "${TEMPLATE_DIR}" -maxdepth 2 -type f -name "*.md")
if echo "$FOUND_RULES" | grep -q -e "${TEMPLATE_DIR}/${RULE_FILE}"; then
  pass "install.sh の copy_rules() が ${RULE_FILE} を列挙する"
else
  fail "install.sh の copy_rules() が ${RULE_FILE} を列挙しない"
fi

# ============================================
echo "=== 配布版1 .claude/vibecorp-base/rules/ の検証（self-install 済みのローカルのみ） ==="
# ============================================

# .claude/vibecorp-base/ は .claude/.gitignore で除外されたベーススナップショット。
# self-install 済みのローカル環境では検証、CI/fresh clone ではスキップ。
if [[ -d "${BASE_DIR}" && -f "${BASE_DIR}/${RULE_FILE}" ]]; then
  if cmp -s "${SRC_DIR}/${RULE_FILE}" "${BASE_DIR}/${RULE_FILE}"; then
    pass "本体 ↔ 配布版1 の ${RULE_FILE} が完全一致"
  else
    fail "本体 ↔ 配布版1 の ${RULE_FILE} が一致しない（install.sh 再実行で再生成可能）"
  fi
else
  echo "  SKIP: .claude/vibecorp-base/rules/${RULE_FILE} が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
