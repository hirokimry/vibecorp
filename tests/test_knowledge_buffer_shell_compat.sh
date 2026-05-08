#!/bin/bash
# test_knowledge_buffer_shell_compat.sh — knowledge_buffer.sh が bash / zsh 両方で source できることを検証
# 使い方: bash tests/test_knowledge_buffer_shell_compat.sh
#
# 背景: Issue #537 — `${BASH_SOURCE[0]}` が zsh で空文字列になり、source が呼出元 cwd 起点で
#       common.sh を探してしまうバグの回帰防止テスト。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/templates/claude/lib/knowledge_buffer.sh"

# 前提ファイル存在確認
if [[ -f "$LIB" ]]; then
  pass "knowledge_buffer.sh が存在する: $LIB"
else
  fail "knowledge_buffer.sh が存在しない: $LIB"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

echo ""
echo "=== bash で source できる ==="

if bash -c ". \"$LIB\" && type knowledge_buffer_repo_id" >/dev/null 2>&1; then
  pass "bash で knowledge_buffer.sh を source して関数が定義される"
else
  fail "bash で source 後に knowledge_buffer_repo_id が定義されていない"
fi

# 呼出元 cwd を変えて source しても common.sh を解決できる（パス解決の堅牢性）
TMPDIR_RUN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_RUN" || true' EXIT
if (cd "$TMPDIR_RUN" && bash -c ". \"$LIB\" && type knowledge_buffer_repo_id") >/dev/null 2>&1; then
  pass "bash: 呼出元 cwd が異なっても source 成功 (絶対パス解決)"
else
  fail "bash: 呼出元 cwd を変えると source に失敗する"
fi

echo ""
echo "=== zsh で source できる ==="

if command -v zsh >/dev/null 2>&1; then
  if zsh -c ". \"$LIB\" && type knowledge_buffer_repo_id" >/dev/null 2>&1; then
    pass "zsh で knowledge_buffer.sh を source して関数が定義される"
  else
    fail "zsh で source 後に knowledge_buffer_repo_id が定義されていない (Issue #537 回帰)"
  fi

  # 呼出元 cwd を変えて source しても common.sh を解決できる（Issue #537 の症状と同じ条件）
  if (cd "$TMPDIR_RUN" && zsh -c ". \"$LIB\" && type knowledge_buffer_repo_id") >/dev/null 2>&1; then
    pass "zsh: 呼出元 cwd が異なっても source 成功 (Issue #537 修正の核)"
  else
    fail "zsh: 呼出元 cwd を変えると source に失敗する (Issue #537 回帰)"
  fi
else
  echo "  SKIP: zsh が未インストールのため zsh テストをスキップ"
fi

echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
