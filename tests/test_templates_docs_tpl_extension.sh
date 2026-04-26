#!/bin/bash
# test_templates_docs_tpl_extension.sh — templates/docs/ 配下の拡張子整合 (#245)
#
# 検証対象:
#   templates/docs/ 配下に置かれた配布用テンプレートが全て .tpl 拡張子を持つこと。
#
# 目的:
#   `install.sh` の copy_docs() は `templates/docs/*.tpl` パターンでファイルを
#   列挙する。.tpl 拡張子を持たないテンプレートは copy_docs に拾われず、
#   インストール先の docs/ に配置されない（#245）。
#   このテストはテンプレート追加時に拡張子付け忘れを早期検出する。
#
# 使い方: bash tests/test_templates_docs_tpl_extension.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_TPL_DIR="${REPO_ROOT}/templates/docs"

if [[ ! -d "$DOCS_TPL_DIR" ]]; then
  fail "templates/docs/ ディレクトリが存在しない"
  exit 1
fi

echo "=== templates/docs/ 拡張子整合検証 (#245) ==="

# .tpl 拡張子を持たないファイルを検出
non_tpl_files=()
while IFS= read -r f; do
  non_tpl_files+=("$f")
done < <(find "$DOCS_TPL_DIR" -maxdepth 1 -type f ! -name '*.tpl')

if [[ ${#non_tpl_files[@]} -eq 0 ]]; then
  pass "templates/docs/ 配下の全ファイルが .tpl 拡張子を持つ"
else
  fail "templates/docs/ 配下に .tpl 拡張子のないファイルが存在する（copy_docs に拾われない）"
  for f in "${non_tpl_files[@]}"; do
    echo "    - $(basename "$f")"
  done
fi

# .tpl ファイルが1つ以上存在する
tpl_count=$(find "$DOCS_TPL_DIR" -maxdepth 1 -type f -name '*.tpl' | wc -l | tr -d ' ')
if [[ "$tpl_count" -gt 0 ]]; then
  pass "templates/docs/ 配下に .tpl ファイルが ${tpl_count} 個存在する"
else
  fail "templates/docs/ 配下に .tpl ファイルが存在しない"
fi

echo ""
echo "=== 結果 ==="
echo "Total : $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
