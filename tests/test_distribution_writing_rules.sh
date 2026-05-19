#!/bin/bash
# test_distribution_writing_rules.sh — 書き方ルール 6 ファイルが配布対象に追加されたことを検証する（Issue #599 / #632）
# 使い方: bash tests/test_distribution_writing_rules.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 配布対象 6 ファイル（#599 で 4 本、#632 でコメント基準 2 本を追加）
RULES=(
  "communication.md"
  "documentation.md"
  "document-writing.md"
  "prompt-writing.md"
  "comment-writing.md"
  "code-comments.md"
)

# 配置先 3 か所
SRC_DIR="${SCRIPT_DIR}/.claude/rules"
BASE_DIR="${SCRIPT_DIR}/.claude/vibecorp-base/rules"
TEMPLATE_DIR="${SCRIPT_DIR}/templates/claude/rules"

# ============================================
echo "=== 本体 .claude/rules/ に 6 ファイルが存在する ==="
# ============================================

for f in "${RULES[@]}"; do
  assert_file_exists "本体 .claude/rules/${f} が存在する" "${SRC_DIR}/${f}"
done

# 本体が存在しないと後続テストが無意味になるので早期終了
for f in "${RULES[@]}"; do
  if [[ ! -f "${SRC_DIR}/${f}" ]]; then
    echo ""
    echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
    echo "本体 ${f} が存在しないため後続テストを中止します"
    exit 1
  fi
done

# ============================================
echo "=== 配布元 templates/claude/rules/ に 6 ファイルが存在する（git 管理対象） ==="
# ============================================

for f in "${RULES[@]}"; do
  assert_file_exists "配布元 templates/claude/rules/${f} が存在する" "${TEMPLATE_DIR}/${f}"
done

# ============================================
echo "=== 本体 ↔ 配布元（templates） が完全一致する ==="
# ============================================

for f in "${RULES[@]}"; do
  if cmp -s "${SRC_DIR}/${f}" "${TEMPLATE_DIR}/${f}"; then
    pass "本体 ↔ 配布元 templates の ${f} が完全一致"
  else
    fail "本体 ↔ 配布元 templates の ${f} が一致しない（同期されていない）"
  fi
done

# ============================================
echo "=== 配布版1 .claude/vibecorp-base/rules/ の検証（install.sh 自動生成、ローカルのみ） ==="
# ============================================

# .claude/vibecorp-base/ は .claude/.gitignore で除外されたベーススナップショット。
# install.sh の copy_rules() → save_base_snapshot() で自動生成される。
# 本体リポジトリで self-install 済みのローカル環境では検証、CI/fresh clone ではスキップ。
if [[ -d "${BASE_DIR}" ]]; then
  for f in "${RULES[@]}"; do
    assert_file_exists "配布版1 .claude/vibecorp-base/rules/${f} が存在する" "${BASE_DIR}/${f}"
    if [[ -f "${BASE_DIR}/${f}" ]]; then
      if cmp -s "${SRC_DIR}/${f}" "${BASE_DIR}/${f}"; then
        pass "本体 ↔ 配布版1 の ${f} が完全一致"
      else
        fail "本体 ↔ 配布版1 の ${f} が一致しない（install.sh 再実行で再生成可能）"
      fi
    fi
  done
else
  echo "  SKIP: .claude/vibecorp-base/rules/ が未生成（self-install されていないため検証スキップ）"
fi

# ============================================
echo "=== prompt-writing.md に「利用先プロジェクトでのフォールバック」節が同期されている ==="
# ============================================

FALLBACK_HEADING="### 利用先プロジェクトでのフォールバック"

assert_file_contains "本体 prompt-writing.md に「利用先プロジェクトでのフォールバック」節" \
  "${SRC_DIR}/prompt-writing.md" "${FALLBACK_HEADING}"
assert_file_contains "配布元 templates prompt-writing.md に「利用先プロジェクトでのフォールバック」節" \
  "${TEMPLATE_DIR}/prompt-writing.md" "${FALLBACK_HEADING}"
if [[ -f "${BASE_DIR}/prompt-writing.md" ]]; then
  assert_file_contains "配布版1 vibecorp-base prompt-writing.md に「利用先プロジェクトでのフォールバック」節" \
    "${BASE_DIR}/prompt-writing.md" "${FALLBACK_HEADING}"
fi

# フォールバック節の中核キーワード（本体 + 配布元 templates は必須、配布版1 は存在時のみ）
for path_label in "本体:${SRC_DIR}" "配布元 templates:${TEMPLATE_DIR}"; do
  label="${path_label%%:*}"
  dir="${path_label#*:}"
  assert_file_contains "${label} prompt-writing.md フォールバック節に minimal/standard 言及" \
    "${dir}/prompt-writing.md" "minimal/standard preset"
  assert_file_contains "${label} prompt-writing.md フォールバック節に docs.claude.com 直参照" \
    "${dir}/prompt-writing.md" "https://docs.claude.com"
  assert_file_contains "${label} prompt-writing.md に「完全に省略はしない」" \
    "${dir}/prompt-writing.md" "完全に省略はしない"
done

if [[ -f "${BASE_DIR}/prompt-writing.md" ]]; then
  assert_file_contains "配布版1 vibecorp-base prompt-writing.md フォールバック節に minimal/standard 言及" \
    "${BASE_DIR}/prompt-writing.md" "minimal/standard preset"
  assert_file_contains "配布版1 vibecorp-base prompt-writing.md フォールバック節に docs.claude.com 直参照" \
    "${BASE_DIR}/prompt-writing.md" "https://docs.claude.com"
  assert_file_contains "配布版1 vibecorp-base prompt-writing.md に「完全に省略はしない」" \
    "${BASE_DIR}/prompt-writing.md" "完全に省略はしない"
fi

# ============================================
echo "=== install.sh が 6 ファイルを配布対象として列挙する ==="
# ============================================

# copy_rules() は find -maxdepth 2 -type f -name "*.md" で自動列挙する
FOUND_RULES=$(find "${TEMPLATE_DIR}" -maxdepth 2 -type f -name "*.md")
for f in "${RULES[@]}"; do
  if echo "$FOUND_RULES" | grep -q -e "${TEMPLATE_DIR}/${f}"; then
    pass "install.sh の copy_rules() が ${f} を列挙する"
  else
    fail "install.sh の copy_rules() が ${f} を列挙しない"
  fi
done

# ============================================
echo ""
echo "=== 結果: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
