#!/bin/bash
# test_readme_docs_consistency.sh — README 掲載 docs ファイルとテンプレートの整合 (#242)
#
# 検証対象:
#   README のインストール構造ツリーに掲載された docs/ 配下のファイル名が、
#   templates/docs/ 配下に対応する .tpl ファイルとして実在すること。
#
# 目的:
#   `install.sh` の copy_docs() は templates/docs/*.tpl のみコピーする。
#   README に書かれているのにテンプレートに無いファイルは、利用者の
#   インストール先 docs/ に配置されず約束が守られない（#242）。
#
# 使い方: bash tests/test_readme_docs_consistency.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="${REPO_ROOT}/README.md"
TPL_DIR="${REPO_ROOT}/templates/docs"

if [[ ! -f "$README" ]]; then
  fail "README.md が存在しない"
  exit 1
fi
if [[ ! -d "$TPL_DIR" ]]; then
  fail "templates/docs/ が存在しない"
  exit 1
fi

echo "=== README docs ツリーとテンプレート整合検証 (#242) ==="

# README の `├── docs/` から始まるブロックを抽出し、`├── name.md` または `└── name.md` を取り出す
# ツリーブロックは次のトップレベルディレクトリ行（例: `├── .github/`）または閉じ ``` で終わる
docs_block=$(awk '
  /^├── docs\// { in_block = 1; next }
  in_block && /^├── [^│]/ { in_block = 0 }
  in_block && /^└── [^│]/ { in_block = 0 }
  in_block && /^```/ { in_block = 0 }
  in_block { print }
' "$README")

# `│   ├── name.md` または `│   └── name.md` パターンから .md ファイル名のみ抽出
# BSD/GNU 互換のため sed の基本機能のみ使う
listed_files=$(echo "$docs_block" \
  | grep -E '[├└]── [A-Za-z0-9._-]+\.md$' \
  | sed -E 's/.*[├└]── ([A-Za-z0-9._-]+\.md)$/\1/')

if [[ -z "$listed_files" ]]; then
  fail "README の docs ツリーから .md エントリを抽出できなかった"
  exit 1
fi

echo "  README に掲載されている docs/:"
while IFS= read -r f; do
  echo "    - $f"
done <<< "$listed_files"

# 各ファイルが templates/docs/ に <name>.tpl として実在するか検証
missing=()
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ -f "${TPL_DIR}/${name}.tpl" ]]; then
    pass "templates/docs/${name}.tpl が存在する（README 掲載）"
  else
    missing+=("$name")
    fail "templates/docs/${name}.tpl が存在しない（README 掲載だが copy_docs に拾われない）"
  fi
done <<< "$listed_files"

# テンプレートだけにあって README に載っていないファイルは失敗扱い（1:1 対応）
declare -a tpl_orphans=()
while IFS= read -r tpl; do
  base=$(basename "$tpl")
  name="${base%.tpl}"
  if ! grep -qxF "${name}" <<< "$listed_files"; then
    tpl_orphans+=("$name")
  fi
done < <(find "$TPL_DIR" -maxdepth 1 -type f -name '*.md.tpl')

if [[ ${#tpl_orphans[@]} -gt 0 ]]; then
  echo ""
  for o in "${tpl_orphans[@]}"; do
    fail "README 未掲載テンプレート: ${o}"
  done
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
