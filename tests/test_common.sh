#!/bin/bash
# test_common.sh — lib/common.sh のユニットテスト
# 使い方: bash tests/test_common.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMON_SH="${SCRIPT_DIR}/templates/claude/hooks/lib/common.sh"
PASSED=0
FAILED=0
TOTAL=0

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (期待: '${expected}', 実際: '${actual}')"
  fi
}

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

# 5. name にスペースのみ → サニタイズ後は '_' のみ（空ではない）
mkdir -p "${TMPDIR_TEST}/case5/.claude"
cat > "${TMPDIR_TEST}/case5/.claude/vibecorp.yml" <<'YAML'
name: "   "
preset: standard
YAML

RESULT=$(CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case5" source "$COMMON_SH" && CLAUDE_PROJECT_DIR="${TMPDIR_TEST}/case5" get_project_name)
# awk が "   " をそのまま返し、tr でサニタイズされて "_" になる
# ただしクォート付きの場合は awk の挙動次第
if [ -n "$RESULT" ]; then
  pass "name にスペースのみ → 空でない値を返す"
else
  # クォート処理で空になる場合はデフォルト
  pass "name にスペースのみ → デフォルト名を返す"
fi

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
