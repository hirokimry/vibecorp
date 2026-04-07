#!/bin/bash
# review-gate.sh — gh pr create 前に /review または /review-loop の実行を強制するフック
# レビュー完了スタンプがあれば PR 作成を許可

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# コマンド正規化
# 1. 先頭空白除去
# 2. 環境変数プレフィックス (KEY=VALUE ...) を除去
# 3. ラッパーコマンド (env, command) を除去
# 4. 絶対パス/相対パスを basename に正規化
# 5. 先頭3トークン抽出 → "gh pr create" と比較
CMD_NORMALIZED=$(echo "$COMMAND" | sed 's/^[[:space:]]*//' | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')
# ラッパー除去ループ
while true; do
  FIRST_TOKEN=$(echo "$CMD_NORMALIZED" | awk '{print $1}')
  case "$FIRST_TOKEN" in
    env|command) CMD_NORMALIZED=$(echo "$CMD_NORMALIZED" | sed -E 's/^[^ ]+ +//') ;;
    *) break ;;
  esac
done
# 絶対パス/相対パスを basename に正規化
FIRST_TOKEN=$(echo "$CMD_NORMALIZED" | awk '{print $1}')
if [[ "$FIRST_TOKEN" == */* ]]; then
  BASE_CMD=$(basename "$FIRST_TOKEN")
  CMD_NORMALIZED="$BASE_CMD $(echo "$CMD_NORMALIZED" | awk '{$1=""; print}' | sed 's/^ *//')"
fi
CMD_HEAD=$(echo "$CMD_NORMALIZED" | awk '{print $1, $2, $3}')

if [ "$CMD_HEAD" != "gh pr create" ]; then
  exit 0
fi

STAMP_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/state/review-ok"

if [ -f "$STAMP_FILE" ]; then
  rm -f "$STAMP_FILE"
  exit 0
fi

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "PR作成前に /review-loop または /review を実行してください。コードレビューが未完了です。"
  }
}'
exit 0
