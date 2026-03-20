#!/bin/bash
# review-to-rules-gate.sh — gh pr merge 前に /review-to-rules の実行を強制するフック
# review-to-rules がOK判定を出したスタンプがあればmerge許可

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# コマンドの先頭3トークンを抽出（環境変数プレフィックスを除去）
# 引数値内の "gh pr merge" に誤反応しないようにする
CMD_HEAD=$(echo "$COMMAND" | sed 's/^[[:space:]]*//' | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//' | awk '{print $1, $2, $3}')

if [ "$CMD_HEAD" != "gh pr merge" ]; then
  exit 0
fi

# vibecorp.yml からプロジェクト名を取得
VIBECORP_YML="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
PROJECT_NAME="vibecorp-project"
if [ -f "$VIBECORP_YML" ]; then
  PROJECT_NAME=$(grep '^name:' "$VIBECORP_YML" | sed 's/^name: *//' | sed 's/ *$//')
fi

STAMP_FILE="/tmp/.${PROJECT_NAME}-review-to-rules-ok"

if [ -f "$STAMP_FILE" ]; then
  rm -f "$STAMP_FILE"
  exit 0
fi

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "マージ前に /review-to-rules を実行してください。レビュー指摘の規約・ナレッジ反映が必要です。"
  }
}'
exit 0
