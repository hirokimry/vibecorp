#!/bin/bash
# test_hooks_container_compat.sh — hooks がコンテナ内で動作する前提条件の構造テスト
# 使い方: bash tests/test_hooks_container_compat.sh

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_DIR/templates/claude/hooks"

echo "=== hooks コンテナ互換性テスト ==="

# --- テスト1: hooks ディレクトリの存在 ---

echo ""
echo "--- テスト1: hooks ディレクトリの存在 ---"

if [[ -d "$HOOKS_DIR" ]]; then
  pass "hooks ディレクトリが存在する"
else
  fail "hooks ディレクトリが存在しない: $HOOKS_DIR"
  echo ""
  echo "==========================="
  echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
  echo "==========================="
  # 前提ディレクトリ不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

# --- テスト2: 各 hook ファイルの存在確認 ---

echo ""
echo "--- テスト2: 各 hook ファイルの存在確認 ---"

HOOK_FILES=("command-log.sh" "protect-branch.sh" "block-api-bypass.sh")

for hook in "${HOOK_FILES[@]}"; do
  if [[ -f "$HOOKS_DIR/$hook" ]]; then
    pass "$hook が存在する"
  else
    fail "$hook が存在しない"
  fi
done

# --- テスト3: $HOME への直接依存がないこと ---

echo ""
echo "--- テスト3: \$HOME への直接依存がないこと ---"

for hook in "${HOOK_FILES[@]}"; do
  HOOK_PATH="$HOOKS_DIR/$hook"
  if [[ ! -f "$HOOK_PATH" ]]; then
    fail "$hook が存在しないためスキップ"
    continue
  fi

  # $HOME を直接使用している行を検出（コメント行は除外）
  HOME_REFS=$(grep -n '\$HOME\|${HOME}' "$HOOK_PATH" | grep -v '^\s*#' || true)
  if [[ -z "$HOME_REFS" ]]; then
    pass "$hook は \$HOME に直接依存していない"
  else
    fail "$hook が \$HOME に直接依存している: $HOME_REFS"
  fi
done

# --- テスト4: $CLAUDE_PROJECT_DIR を使用していること ---

echo ""
echo "--- テスト4: \$CLAUDE_PROJECT_DIR を使用していること ---"

for hook in "${HOOK_FILES[@]}"; do
  HOOK_PATH="$HOOKS_DIR/$hook"
  if [[ ! -f "$HOOK_PATH" ]]; then
    fail "$hook が存在しないためスキップ"
    continue
  fi

  if grep -q 'CLAUDE_PROJECT_DIR' "$HOOK_PATH"; then
    pass "$hook は \$CLAUDE_PROJECT_DIR を使用している"
  else
    # ファイルシステムにアクセスせず stdin のみ読み取るフックは CLAUDE_PROJECT_DIR 不要
    FILE_ACCESS=$(grep -cE '(open|source|readfile|\$\{?CLAUDE_PROJECT_DIR)' "$HOOK_PATH" || true)
    if [[ "$FILE_ACCESS" -eq 0 ]]; then
      pass "$hook は stdin のみ読み取るため \$CLAUDE_PROJECT_DIR 不要"
    else
      fail "$hook は \$CLAUDE_PROJECT_DIR を使用していない"
    fi
  fi
done

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
