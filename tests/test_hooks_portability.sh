#!/bin/bash
# test_hooks_portability.sh — hooks の移植性（環境非依存性）テスト
# 使い方: bash tests/test_hooks_portability.sh
#
# hooks は実行環境（ユーザーの HOME、ワークツリー、将来的なコンテナ/隔離環境）に
# 依存せず、$CLAUDE_PROJECT_DIR を基準として動作する必要がある。
# 本テストは hooks がその前提条件を満たすことを構造検査する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_DIR/templates/claude/hooks"

echo "=== hooks 移植性テスト ==="

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

# --- テスト4: 環境非依存な anchor（$CLAUDE_PROJECT_DIR または $HOOK_DIR）を使用していること ---

# hook は実行環境に依存しない anchor で参照を解決する必要がある。
# 1. $CLAUDE_PROJECT_DIR: 利用者リポジトリのルートを指す（install.sh 配置時の前提）。
# 2. $HOOK_DIR: hook 自身の位置を起点にした相対解決（plugin native 配布化後の前提、Issue #703）。
# どちらも HOME / 絶対パス非依存で hook を移植可能にするため等価に扱う。
echo ""
echo "--- テスト4: 環境非依存な anchor（\$CLAUDE_PROJECT_DIR または \$HOOK_DIR）を使用していること ---"

for hook in "${HOOK_FILES[@]}"; do
  HOOK_PATH="$HOOKS_DIR/$hook"
  if [[ ! -f "$HOOK_PATH" ]]; then
    fail "$hook が存在しないためスキップ"
    continue
  fi

  if grep -qE 'CLAUDE_PROJECT_DIR|HOOK_DIR' "$HOOK_PATH"; then
    pass "$hook は \$CLAUDE_PROJECT_DIR / \$HOOK_DIR で anchor を解決している"
  else
    # ファイルシステムにアクセスせず stdin のみ読み取るフックは anchor 不要
    FILE_ACCESS=$(grep -cE '(open|source|readfile|\$\{?CLAUDE_PROJECT_DIR|\$\{?HOOK_DIR)' "$HOOK_PATH" || true)
    if [[ "$FILE_ACCESS" -eq 0 ]]; then
      pass "$hook は stdin のみ読み取るため anchor 不要"
    else
      fail "$hook は \$CLAUDE_PROJECT_DIR / \$HOOK_DIR のいずれも使用していない"
    fi
  fi
done

# --- 結果 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
