#!/bin/bash
# test_diagnose_limits_sync.sh — 起票上限デフォルト値の 5 ファイル間同期検証
#
# 検証目的:
#   docs/cost-analysis.md の MUST 制約「max_issues_per_run / max_issues_per_day /
#   max_files_per_issue の値を変更する場合、複数ファイルを同時更新し値の整合を保つ」
#   を自動チェックする。
#
# 検証対象ファイル（Source of Truth は .claude/vibecorp.yml）:
#   1. .claude/vibecorp.yml          (Source of Truth)
#   2. install.sh                     (YAML テンプレ初期値)
#   3. README.md                      (例示)
#   4. skills/diagnose/SKILL.md       (設定テーブル)
#   5. docs/cost-analysis.md          (上限値表)
#
# 設計思想:
#   テスト用 fixture（tests/test_diagnose_guard.sh 等）は production default と
#   独立して任意値を取るため対象外。本テストは production の同期のみを保証する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================
echo "=== 起票上限デフォルト値の同期検証 ==="
# ============================================

# --- Source of Truth から期待値を抽出 ---

VYML="${REPO_ROOT}/.claude/vibecorp.yml"

if [ ! -f "$VYML" ]; then
  fail ".claude/vibecorp.yml が存在しない"
  print_test_summary
  exit 1
fi

# .claude/vibecorp.yml の diagnose: ブロック配下から各キーの値を抽出
# awk でブロック単位（次のトップレベルキーで停止）に抽出（.claude/rules/shell.md 準拠）
extract_yaml_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    /^diagnose:/ { in_block = 1; next }
    in_block && /^[^[:space:]]/ { exit }
    in_block && $1 == key":" { print $2; exit }
  ' "$file"
}

EXPECTED_PER_RUN=$(extract_yaml_value "max_issues_per_run" "$VYML")
EXPECTED_PER_DAY=$(extract_yaml_value "max_issues_per_day" "$VYML")
EXPECTED_FILES_PER_ISSUE=$(extract_yaml_value "max_files_per_issue" "$VYML")

echo "--- Source of Truth (.claude/vibecorp.yml) ---"
echo "  max_issues_per_run = ${EXPECTED_PER_RUN}"
echo "  max_issues_per_day = ${EXPECTED_PER_DAY}"
echo "  max_files_per_issue = ${EXPECTED_FILES_PER_ISSUE}"

# 期待値が空でないことを保証
if [ -z "$EXPECTED_PER_RUN" ] || [ -z "$EXPECTED_PER_DAY" ] || [ -z "$EXPECTED_FILES_PER_ISSUE" ]; then
  fail ".claude/vibecorp.yml から期待値を抽出できなかった (per_run='${EXPECTED_PER_RUN}', per_day='${EXPECTED_PER_DAY}', files='${EXPECTED_FILES_PER_ISSUE}')"
  print_test_summary
  exit 1
fi

# ============================================
echo "=== install.sh のヒアドキュメント YAML テンプレ ==="
# ============================================

INSTALL_SH="${REPO_ROOT}/install.sh"
assert_file_exists "install.sh が存在する" "$INSTALL_SH"

# install.sh 内の YAML ヒアドキュメント（generate_vibecorp_yaml 内）
# パターン: 行頭 2 スペースインデント + キー名 + コロン + 値
ACTUAL=$(awk '/^  max_issues_per_run:/ { print $2; exit }' "$INSTALL_SH")
assert_eq "install.sh の max_issues_per_run が vibecorp.yml と一致" \
  "$EXPECTED_PER_RUN" "$ACTUAL"

ACTUAL=$(awk '/^  max_issues_per_day:/ { print $2; exit }' "$INSTALL_SH")
assert_eq "install.sh の max_issues_per_day が vibecorp.yml と一致" \
  "$EXPECTED_PER_DAY" "$ACTUAL"

ACTUAL=$(awk '/^  max_files_per_issue:/ { print $2; exit }' "$INSTALL_SH")
assert_eq "install.sh の max_files_per_issue が vibecorp.yml と一致" \
  "$EXPECTED_FILES_PER_ISSUE" "$ACTUAL"

# ============================================
echo "=== README.md の例示 YAML ==="
# ============================================

README="${REPO_ROOT}/README.md"
assert_file_exists "README.md が存在する" "$README"

# README.md の YAML 例示は `  max_issues_per_run: <値>    # コメント` 形式
ACTUAL=$(awk '/^  max_issues_per_run:/ { print $2; exit }' "$README")
assert_eq "README.md の max_issues_per_run が vibecorp.yml と一致" \
  "$EXPECTED_PER_RUN" "$ACTUAL"

ACTUAL=$(awk '/^  max_issues_per_day:/ { print $2; exit }' "$README")
assert_eq "README.md の max_issues_per_day が vibecorp.yml と一致" \
  "$EXPECTED_PER_DAY" "$ACTUAL"

ACTUAL=$(awk '/^  max_files_per_issue:/ { print $2; exit }' "$README")
assert_eq "README.md の max_files_per_issue が vibecorp.yml と一致" \
  "$EXPECTED_FILES_PER_ISSUE" "$ACTUAL"

# ============================================
echo "=== skills/diagnose/SKILL.md の設定テーブル ==="
# ============================================

SKILL_MD="${REPO_ROOT}/skills/diagnose/SKILL.md"
assert_file_exists "skills/diagnose/SKILL.md が存在する" "$SKILL_MD"

# Markdown テーブル行から値を抽出: | `<key>` | <値> | <説明> |
# 行頭が `|` で始まるテーブル行のみ対象とする（説明文中の `<key>` を除外）
extract_md_table_value() {
  local key="$1"
  local file="$2"
  awk -v key="\`${key}\`" -F'|' '
    /^\|/ && $0 ~ key {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      print $3
      exit
    }
  ' "$file"
}

ACTUAL=$(extract_md_table_value "max_issues_per_run" "$SKILL_MD")
assert_eq "skills/diagnose/SKILL.md の max_issues_per_run が vibecorp.yml と一致" \
  "$EXPECTED_PER_RUN" "$ACTUAL"

ACTUAL=$(extract_md_table_value "max_issues_per_day" "$SKILL_MD")
assert_eq "skills/diagnose/SKILL.md の max_issues_per_day が vibecorp.yml と一致" \
  "$EXPECTED_PER_DAY" "$ACTUAL"

ACTUAL=$(extract_md_table_value "max_files_per_issue" "$SKILL_MD")
assert_eq "skills/diagnose/SKILL.md の max_files_per_issue が vibecorp.yml と一致" \
  "$EXPECTED_FILES_PER_ISSUE" "$ACTUAL"

# ============================================
echo "=== docs/cost-analysis.md の上限値表 ==="
# ============================================

COST_MD="${REPO_ROOT}/docs/cost-analysis.md"
assert_file_exists "docs/cost-analysis.md が存在する" "$COST_MD"

ACTUAL=$(extract_md_table_value "max_issues_per_run" "$COST_MD")
assert_eq "docs/cost-analysis.md の max_issues_per_run が vibecorp.yml と一致" \
  "$EXPECTED_PER_RUN" "$ACTUAL"

ACTUAL=$(extract_md_table_value "max_issues_per_day" "$COST_MD")
assert_eq "docs/cost-analysis.md の max_issues_per_day が vibecorp.yml と一致" \
  "$EXPECTED_PER_DAY" "$ACTUAL"

ACTUAL=$(extract_md_table_value "max_files_per_issue" "$COST_MD")
assert_eq "docs/cost-analysis.md の max_files_per_issue が vibecorp.yml と一致" \
  "$EXPECTED_FILES_PER_ISSUE" "$ACTUAL"

# ============================================
print_test_summary
