#!/bin/bash
# test_common_lib.sh — lib/common.sh のユニットテスト
# 使い方: bash tests/test_common_lib.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/common.sh"
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
    fail "$desc (期待: '$expected', 実際: '$actual')"
  fi
}

# 共通ライブラリ読み込み
source "$LIB"

# ============================================
echo "=== normalize_command ==="
# ============================================

# 1. 通常のコマンド（変更なし）
RESULT=$(normalize_command "git push origin main")
assert_eq "通常のコマンド → そのまま" "git push origin main" "$RESULT"

# 2. 先頭空白除去
RESULT=$(normalize_command "  git push origin main")
assert_eq "先頭空白除去" "git push origin main" "$RESULT"

# 3. 環境変数プレフィックス除去（単一）
RESULT=$(normalize_command "GIT_SSH_COMMAND=ssh git push origin main")
assert_eq "環境変数プレフィックス除去（単一）" "git push origin main" "$RESULT"

# 4. 環境変数プレフィックス除去（複数）
RESULT=$(normalize_command "FOO=bar BAZ=qux git push origin main")
assert_eq "環境変数プレフィックス除去（複数）" "git push origin main" "$RESULT"

# 5. env ラッパー除去
RESULT=$(normalize_command "env git push origin main")
assert_eq "env ラッパー除去" "git push origin main" "$RESULT"

# 6. command ラッパー除去
RESULT=$(normalize_command "command gh pr merge")
assert_eq "command ラッパー除去" "gh pr merge" "$RESULT"

# 7. 絶対パスの basename 正規化
RESULT=$(normalize_command "/usr/bin/git push origin main")
assert_eq "絶対パスの basename 正規化" "git push origin main" "$RESULT"

# 8. 相対パスの basename 正規化
RESULT=$(normalize_command "./bin/gh pr merge")
assert_eq "相対パスの basename 正規化" "gh pr merge" "$RESULT"

# 9. 環境変数 + env ラッパー + 絶対パスの複合
RESULT=$(normalize_command "FOO=bar env /usr/local/bin/gh pr merge --squash")
assert_eq "複合（環境変数+env+絶対パス）" "gh pr merge --squash" "$RESULT"

# 10. 先頭空白 + 環境変数 + command ラッパー
RESULT=$(normalize_command "  GH_TOKEN=xxx command gh pr merge")
assert_eq "複合（空白+環境変数+command）" "gh pr merge" "$RESULT"

# 11. 引数のないコマンド
RESULT=$(normalize_command "git")
assert_eq "引数のないコマンド" "git" "$RESULT"

# 12. 空文字列
RESULT=$(normalize_command "")
assert_eq "空文字列" "" "$RESULT"

# ============================================
echo ""
echo "=== get_project_name ==="
# ============================================

# --- テスト用の vibecorp.yml を準備 ---
TMPDIR_TEST=$(mktemp -d)

cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

# 13. vibecorp.yml がある場合
mkdir -p "${TMPDIR_TEST}/.claude"
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
YAML
CLAUDE_PROJECT_DIR="$TMPDIR_TEST" RESULT=$(get_project_name)
assert_eq "vibecorp.yml からプロジェクト名取得" "test-project" "$RESULT"

# 14. vibecorp.yml がない場合 → フォールバック
TMPDIR_EMPTY=$(mktemp -d)
CLAUDE_PROJECT_DIR="$TMPDIR_EMPTY" RESULT=$(get_project_name)
assert_eq "vibecorp.yml なし → フォールバック" "vibecorp-project" "$RESULT"
rm -rf "$TMPDIR_EMPTY"

# 15. プロジェクト名に不正文字が含まれる場合 → サニタイズ
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: my project/test@2024
preset: standard
YAML
CLAUDE_PROJECT_DIR="$TMPDIR_TEST" RESULT=$(get_project_name)
assert_eq "不正文字のサニタイズ" "my_project_test_2024" "$RESULT"

# 16. name が空の場合 → フォールバック
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name:
preset: standard
YAML
CLAUDE_PROJECT_DIR="$TMPDIR_TEST" RESULT=$(get_project_name)
assert_eq "name が空 → フォールバック" "vibecorp-project" "$RESULT"

# 17. CLAUDE_PROJECT_DIR 未設定で vibecorp.yml もない場合 → フォールバック
TMPDIR_NO_YML=$(mktemp -d)
RESULT=$(cd "$TMPDIR_NO_YML" && unset CLAUDE_PROJECT_DIR && get_project_name)
assert_eq "CLAUDE_PROJECT_DIR 未設定 + vibecorp.yml なし → フォールバック" "vibecorp-project" "$RESULT"
rm -rf "$TMPDIR_NO_YML"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
