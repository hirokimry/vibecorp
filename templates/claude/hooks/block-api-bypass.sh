#!/bin/bash
# block-api-bypass.sh — gh api による安全チェック迂回をブロックするフック
# gh pr merge を使わずに gh api で直接マージする等のバイパス行為を防止する

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Bash ツールのみ対象
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# 環境変数プレフィックス・ラッパーコマンドを除去して正規化
normalized="$COMMAND"
while [[ "$normalized" =~ ^[A-Za-z_][A-Za-z0-9_]*=\S+\ (.+)$ ]]; do
  normalized="${BASH_REMATCH[1]}"
done
normalized="${normalized#env }"
normalized="${normalized#command }"

# gh api によるマージ API 直接呼び出しをブロック
# pulls/{number}/merge エンドポイントへの呼び出しを検出
if echo "$normalized" | grep -qE 'gh\s+api\s+.*pulls/[0-9]+/merge'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "gh api による直接マージは禁止です。gh pr merge を使用してください。安全チェック（CI・レビュー）を迂回するリスクがあります。"
    }
  }'
  exit 0
fi

exit 0
