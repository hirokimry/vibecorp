#!/bin/bash
# test_state_no_placeholder.sh
# templates/claude/hooks と templates/claude/skills から
# {{PROJECT_NAME}} placeholder と /tmp/.${PROJECT_NAME} 参照が消滅していることを検証する回帰テスト
#
# Issue #255 で /tmp/ スタンプを $CLAUDE_PROJECT_DIR/.claude/state/ に移行した。
# 退化を防ぐため、CI で本テストが常に PASS する必要がある。
#
# 使い方: bash tests/test_state_no_placeholder.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
TOTAL=0

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

# check_pattern_absent — grep の終了コードを明示的に判定して exit 0/1/その他を分離する
# 引数: $1=ラベル, $2=パターン, $3..=検索対象パス
# 終了コード: 0 → fail（パターン検出）/ 1 → pass（パターン未検出）/ その他 → fail（grep エラー）
check_pattern_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  # local 宣言と $? キャプチャを混ぜると local builtin が $? を上書きするため分離する
  local match
  local code
  match=$(grep -rEn "$pattern" "$@" 2>&1)
  code=$?
  case "$code" in
    0)
      fail "$label が残存している"
      printf '    検出箇所:\n'
      printf '%s\n' "$match" | sed 's/^/      /'
      ;;
    1)
      pass "$label は存在しない"
      ;;
    *)
      fail "$label の検査で grep エラー（exit $code）: $match"
      ;;
  esac
}

# --- 1. {{PROJECT_NAME}} placeholder の不在 ---

echo "=== {{PROJECT_NAME}} placeholder 検出 ==="

check_pattern_absent \
  "{{PROJECT_NAME}} placeholder（hooks/skills）" \
  '\{\{PROJECT_NAME\}\}' \
  "${SCRIPT_DIR}/templates/claude/hooks" \
  "${SCRIPT_DIR}/templates/claude/skills"

# --- 2. /tmp/.${PROJECT_NAME} 参照の不在 ---

echo ""
echo "=== /tmp/ スタンプファイル参照検出 ==="

# /tmp/.${PROJECT_NAME}-* / /tmp/.{{PROJECT_NAME}}-* / /tmp/.{project}-* を一括検出
check_pattern_absent \
  "/tmp/.\${PROJECT_NAME} 参照（hooks/skills）" \
  '/tmp/\.(\$\{PROJECT_NAME\}|\{\{PROJECT_NAME\}\}|\{project\})' \
  "${SCRIPT_DIR}/templates/claude/hooks" \
  "${SCRIPT_DIR}/templates/claude/skills"

# --- 3. PROJECT_NAME 変数定義の不在（hooks 限定） ---
# hooks では get_project_name 呼び出しが消滅しているはず
# （SKILL.md は別の用途で PROJECT_NAME を扱う可能性があるため対象外）

echo ""
echo "=== hooks の PROJECT_NAME 変数定義検出 ==="

# PROJECT_NAME=$(get_project_name) と PROJECT_NAME="$(get_project_name)" 両方を検出
check_pattern_absent \
  'hooks の PROJECT_NAME=$(get_project_name)' \
  'PROJECT_NAME=("|'"'"')?\$\(get_project_name\)' \
  "${SCRIPT_DIR}/templates/claude/hooks"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
