#!/bin/bash
# sync-gate.sh — git push 前に /sync-check の実行を強制するフック
# sync-check がOK判定を出したスタンプがあればpush許可

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# コマンド正規化
# 1. 先頭空白除去
# 2. 環境変数プレフィックス (KEY=VALUE ...) を除去
# 3. ラッパーコマンド (env, command) を除去
# 4. 絶対パス/相対パスを basename に正規化
# 5. 先頭2トークン抽出 → "git push" と比較
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
CMD_HEAD=$(echo "$CMD_NORMALIZED" | awk '{print $1, $2}')

if [ "$CMD_HEAD" != "git push" ]; then
  exit 0
fi

# ブランチ削除（--delete / -d）はチェック不要
REST=$(echo "$CMD_NORMALIZED" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')
if echo "$REST" | grep -qE '(^| )(--delete|-d)( |$)'; then
  exit 0
fi

# 共通ライブラリ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${HOOK_DIR}/lib/common.sh"
PROJECT_NAME=$(get_project_name)

STAMP_FILE="/tmp/.${PROJECT_NAME}-sync-ok"

if [ -f "$STAMP_FILE" ]; then
  rm -f "$STAMP_FILE"
  exit 0
fi

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "push前に /sync-check を実行してください。docs/ と knowledge/ の整合性確認が必要です。"
  }
}'
exit 0
