#!/bin/bash
# test_check_workflow_scripts.sh
# ─────────────────────────────────────────────
# Issue #624: check 系 4 workflow から切り出した .github/scripts/ 配下スクリプトの
# サニティテスト（存在 / 実行権限 / shebang / set -euo pipefail / bash -n 構文検査）。
#
# 挙動テスト（実行結果に基づく分岐検証）は子 Issue #625 で別途追加する想定。
# 本テストは Issue #624 の挙動不変リファクタが最低限の品質基準を満たしていることを保証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

SCRIPTS=(
  ".github/scripts/check-plugin-version-bump-comment.sh"
  ".github/scripts/check-intent-label-issue.sh"
  ".github/scripts/check-pr-issue-link.sh"
  ".github/scripts/check-update-pr-branches.sh"
)

echo "=== Issue #624: check 系 workflow 切り出しスクリプトのサニティテスト ==="

for rel_path in "${SCRIPTS[@]}"; do
  abs_path="${SCRIPT_DIR}/${rel_path}"
  echo ""
  echo "--- ${rel_path} ---"

  # 1. ファイル存在
  assert_file_exists "ファイルが存在する: ${rel_path}" "$abs_path"

  # 2. 実行権限あり
  assert_file_executable "実行権限あり: ${rel_path}" "$abs_path"

  # 3. shebang が #!/usr/bin/env bash である
  first_line=$(head -n 1 "$abs_path")
  assert_eq "shebang は #!/usr/bin/env bash: ${rel_path}" "#!/usr/bin/env bash" "$first_line"

  # 4. set -euo pipefail が含まれる
  assert_file_contains "set -euo pipefail を含む: ${rel_path}" "$abs_path" "set -euo pipefail"

  # 5. bash -n で構文エラーがない（エラー詳細を fail メッセージに含めデバッグ容易化）
  if error_output=$(bash -n "$abs_path" 2>&1); then
    pass "bash -n で構文エラーなし: ${rel_path}"
  else
    fail "bash -n で構文エラーあり: ${rel_path}"$'\n'"${error_output}"
  fi
done

echo ""
echo "=== 各 workflow が切り出したスクリプトを呼び出している ==="

# workflow と呼び出しスクリプトの対応を検証（挙動不変リファクタの構造検証）
declare_workflows() {
  cat <<'EOF'
.github/workflows/plugin-version-bump-check.yml|.github/scripts/check-plugin-version-bump-comment.sh
.github/workflows/intent-label-issue-check.yml|.github/scripts/check-intent-label-issue.sh
.github/workflows/pr-issue-link-check.yml|.github/scripts/check-pr-issue-link.sh
.github/workflows/update-pr-branches.yml|.github/scripts/check-update-pr-branches.sh
EOF
}

while IFS='|' read -r workflow script; do
  abs_workflow="${SCRIPT_DIR}/${workflow}"
  assert_file_exists "workflow 存在: ${workflow}" "$abs_workflow"
  assert_file_contains "workflow が ${script} を呼び出す" "$abs_workflow" "$script"
done < <(declare_workflows)

# plugin-version-bump-check.yml step 1 が既存 scripts/ 配下スクリプトを呼び出している（既存挙動維持）
assert_file_contains \
  "plugin-version-bump-check.yml step 1 は既存 scripts/check-plugin-version-bump.sh を呼ぶ" \
  "${SCRIPT_DIR}/.github/workflows/plugin-version-bump-check.yml" \
  "scripts/check-plugin-version-bump.sh"

print_test_summary
