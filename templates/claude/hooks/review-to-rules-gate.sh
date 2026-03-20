#!/bin/bash
# review-to-rules-gate.sh — gh pr merge 前に /review-to-rules の実行を強制するフック
# review-to-rules がOK判定を出したスタンプがあればmerge許可

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# コマンドの先頭3トークンを抽出
# 1. 先頭空白除去
# 2. 環境変数プレフィックス (KEY=VALUE ...) を除去
# 3. ラッパーコマンド (env, command) を除去
# 4. 絶対パス/相対パスを basename に正規化
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

if [ "$CMD_HEAD" != "gh pr merge" ]; then
  exit 0
fi

# vibecorp.yml からプロジェクト名を取得
VIBECORP_YML="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
PROJECT_NAME="vibecorp-project"
if [ -f "$VIBECORP_YML" ]; then
  RAW_NAME=$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$VIBECORP_YML")
  if [ -n "${RAW_NAME:-}" ]; then
    PROJECT_NAME=$(printf '%s' "$RAW_NAME" | tr -cs 'A-Za-z0-9._-' '_')
  fi
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
