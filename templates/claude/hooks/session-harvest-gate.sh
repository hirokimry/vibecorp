#!/bin/bash
# session-harvest-gate.sh — gh pr merge 前に /session-harvest の実行を強制するフック
# セッション中の知見が rules/knowledge/docs に反映されているか確認するゲート

set -euo pipefail

# 共通ユーティリティ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# コマンド正規化（共通関数を使用）
CMD_NORMALIZED=$(normalize_command "$COMMAND")
CMD_HEAD=$(echo "$CMD_NORMALIZED" | awk '{print $1, $2, $3}')

if [ "$CMD_HEAD" != "gh pr merge" ]; then
  exit 0
fi

STAMP_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/state/session-harvest-ok"

if [ -f "$STAMP_FILE" ]; then
  rm -f "$STAMP_FILE"
  exit 0
fi

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "マージ前に /session-harvest を実行してください。セッション中の知見を rules/knowledge/docs に反映する必要があります。"
  }
}'
exit 0
