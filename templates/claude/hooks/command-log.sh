#!/bin/bash
# command-log.sh — 全 Bash コマンドをログファイルに記録する PreToolUse フック
# ログは ~/.cache/vibecorp/state/<repo-id>/command-log に追記される（Issue #334）
# 判定は返さない（ログ記録のみ）

set -euo pipefail

# HOOK_DIR 経由で lib を解決することで、plugin native 配布化後（hook が plugin cache 配下に置かれるケース）でも参照が壊れないようにする（Issue #703）
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Bash 以外は記録しない
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
  exit 0
fi

vibecorp_state_mkdir >/dev/null
LOG_FILE="$(vibecorp_state_path command-log)"

printf '%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$COMMAND" >> "$LOG_FILE"

exit 0
