#!/bin/bash
# review-to-rules-gate.sh — gh pr merge 前に /review-to-rules の実行を強制するフック
# review-to-rules がOK判定を出したスタンプがあればmerge許可

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

# 対象コマンドの場合のみスタンプパスを解決（早期 exit 後に評価することで
# 無関係コマンドで git rev-parse + shasum を走らせない）
STAMP_FILE="$(vibecorp_stamp_path review-to-rules)"

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
