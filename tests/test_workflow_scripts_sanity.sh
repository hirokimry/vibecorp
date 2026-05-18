#!/bin/bash
# test_workflow_scripts_sanity.sh
# ─────────────────────────────────────────────
# Issue #625: .github/scripts/ 配下の全シェルスクリプトに対するサニティテスト。
# 存在 / 実行権限 / shebang / set -euo pipefail / bash -n 構文検査 を機械的に確認する。
#
# 本テストは shellcheck の補完として機能する: shellcheck では検出できない
# 「shebang が #!/usr/bin/env bash で揃っている」「実行ビットが立っている」等の
# プロジェクト規約を検証する。
#
# 切り出した check-*.sh は test_check_workflow_scripts.sh が個別に詳細サニティを
# カバーするが、本テストでは全 .github/scripts/*.sh を網羅的に走査することで、
# 新規スクリプト追加時の規約準拠を一括検証できる。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

SCRIPTS_BASE="${SCRIPT_DIR}/.github/scripts"

echo "=== Issue #625: .github/scripts/ 配下の全スクリプトのサニティテスト ==="
echo ""

if [ ! -d "$SCRIPTS_BASE" ]; then
  fail ".github/scripts/ ディレクトリが存在する"
  exit 1
fi

# .github/scripts/ 配下の *.sh を全列挙（サブディレクトリも再帰）
# mapfile は bash 4+ 専用のため、macOS bash 3.2 互換の read ループで構築する
scripts=()
while IFS= read -r line; do
  scripts+=("$line")
done < <(find "$SCRIPTS_BASE" -type f -name '*.sh' | sort)

if [ "${#scripts[@]}" -eq 0 ]; then
  fail ".github/scripts/ にスクリプトが 1 つ以上存在する"
  exit 1
fi

echo "検出されたスクリプト: ${#scripts[@]} 件"
for f in "${scripts[@]}"; do
  echo "  - ${f#"${SCRIPT_DIR}/"}"
done
echo ""

for abs_path in "${scripts[@]}"; do
  rel_path="${abs_path#"${SCRIPT_DIR}/"}"
  echo "--- ${rel_path} ---"

  # 1. ファイル存在
  assert_file_exists "ファイルが存在する: ${rel_path}" "$abs_path"

  # 2. 実行権限あり
  assert_file_executable "実行権限あり: ${rel_path}" "$abs_path"

  # 3. shebang が workflow-shell.md 規約の許容値（#!/usr/bin/env bash または #!/bin/bash）である
  first_line=$(head -n 1 "$abs_path")
  if [ "$first_line" = "#!/usr/bin/env bash" ] || [ "$first_line" = "#!/bin/bash" ]; then
    pass "shebang は許容値（#!/usr/bin/env bash or #!/bin/bash）: ${rel_path}"
  else
    fail "shebang が許容値外: ${rel_path} (実際: ${first_line})"
  fi

  # 4. set -euo pipefail が含まれる
  assert_file_contains "set -euo pipefail を含む: ${rel_path}" "$abs_path" "set -euo pipefail"

  # 5. bash -n で構文エラーなし
  if error_output=$(bash -n "$abs_path" 2>&1); then
    pass "bash -n で構文エラーなし: ${rel_path}"
  else
    fail "bash -n で構文エラーあり: ${rel_path}"$'\n'"${error_output}"
  fi
done

echo ""
print_test_summary
