#!/bin/bash
# test_common.sh — lib/common.sh のユニットテスト
# 使い方: bash tests/test_common.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMON_SH="${SCRIPT_DIR}/templates/claude/lib/common.sh"

# --- テスト用ディレクトリを準備 ---

TMPDIR_TEST=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

# ============================================
echo "=== lib/common.sh — get_project_name ==="
# ============================================

# 1. vibecorp.yml あり → プロジェクト名を返す
echo "--- 正常系 ---"

mkdir -p "${TMPDIR_TEST}/case1/.claude"
cat > "${TMPDIR_TEST}/case1/.claude/vibecorp.yml" <<'YAML'
name: my-cool-project
preset: standard
YAML

RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" get_project_name)
assert_eq "vibecorp.yml あり → プロジェクト名を返す" "my-cool-project" "$RESULT"

# 2. vibecorp.yml なし → デフォルト名を返す
mkdir -p "${TMPDIR_TEST}/case2/.claude"

RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case2" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case2" get_project_name)
assert_eq "vibecorp.yml なし → デフォルト名を返す" "vibecorp-project" "$RESULT"

# 3. name が空 → デフォルト名を返す
mkdir -p "${TMPDIR_TEST}/case3/.claude"
cat > "${TMPDIR_TEST}/case3/.claude/vibecorp.yml" <<'YAML'
name:
preset: standard
YAML

RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case3" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case3" get_project_name)
assert_eq "name が空 → デフォルト名を返す" "vibecorp-project" "$RESULT"

# 4. name に特殊文字 → サニタイズされる
echo "--- サニタイズ ---"

mkdir -p "${TMPDIR_TEST}/case4/.claude"
cat > "${TMPDIR_TEST}/case4/.claude/vibecorp.yml" <<'YAML'
name: hello world!@#
preset: standard
YAML

EXPECTED=$(printf '%s' "hello world!@#" | tr -cs 'A-Za-z0-9._-' '_')
RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case4" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case4" get_project_name)
assert_eq "name に特殊文字 → サニタイズされる" "$EXPECTED" "$RESULT"

# 5. name にクォート付きスペースのみ → awk がクォート込みで返し、tr でサニタイズされて "_" になる
mkdir -p "${TMPDIR_TEST}/case5/.claude"
cat > "${TMPDIR_TEST}/case5/.claude/vibecorp.yml" <<'YAML'
name: "   "
preset: standard
YAML

RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case5" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case5" get_project_name)
assert_eq "name にスペースのみ → サニタイズされて '_' を返す" "_" "$RESULT"

# 6. CLAUDE_PROJECT_DIR 未設定 → カレントディレクトリの .claude/vibecorp.yml を参照
echo "--- CLAUDE_PROJECT_DIR 未設定 ---"

mkdir -p "${TMPDIR_TEST}/case6/.claude"
cat > "${TMPDIR_TEST}/case6/.claude/vibecorp.yml" <<'YAML'
name: dir-fallback-project
preset: standard
YAML

RESULT=$(cd "${TMPDIR_TEST}/case6" && unset CLAUDE_PROJECT_DIR && source "$COMMON_SH" && get_project_name)
assert_eq "CLAUDE_PROJECT_DIR 未設定 → カレントディレクトリを参照" "dir-fallback-project" "$RESULT"

# 7. 複数回呼び出しても同じ結果を返す（冪等性）
echo "--- 冪等性 ---"

RESULT1=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" get_project_name)
RESULT2=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case1" get_project_name)
assert_eq "複数回呼び出しても同じ結果を返す" "$RESULT1" "$RESULT2"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
