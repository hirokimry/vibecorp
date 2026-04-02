#!/bin/bash
# command-log.sh — 全 Bash コマンドをログファイルに記録する PreToolUse フック
# ログは /tmp/.{project}-command-log に追記される
# 判定は返さない（ログ記録のみ）

set -euo pipefail

# 共通ユーティリティ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# プロジェクト名からログファイルパスを決定
PROJECT_NAME=$(get_project_name)
LOG_FILE="/tmp/.${PROJECT_NAME}-command-log"

# タイムスタンプ + コマンドをログに追記
printf '%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$COMMAND" >> "$LOG_FILE"

exit 0
