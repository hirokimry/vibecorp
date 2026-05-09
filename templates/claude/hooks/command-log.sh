#!/bin/bash
# command-log.sh — 全 Bash コマンドをログファイルに記録する PreToolUse フック
# ログは ~/.cache/vibecorp/state/<repo-id>/command-log に追記される（Issue #334）
# 判定は返さない（ログ記録のみ）
#
# 機密情報（API キー / トークン / パスワード等）は mask_secrets() でマスキング
# してから記録する（Issue #513）。マスクパターンは SECRET_PATTERNS 配列に
# 集約しているので、新パターン追加時はそこを編集するだけでよい。

set -euo pipefail

# shellcheck source=../lib/common.sh
source "${CLAUDE_PROJECT_DIR:-.}/.claude/lib/common.sh"

# 機密情報マスクパターン（sed -E 互換、順に適用される）
SECRET_PATTERNS=(
  's/(--token[= ])[^[:space:]]+/\1***MASKED***/g'
  's/(--auth-token[= ])[^[:space:]]+/\1***MASKED***/g'
  's/(--password[= ])[^[:space:]]+/\1***MASKED***/g'
  's/(--secret[= ])[^[:space:]]+/\1***MASKED***/g'
  's/(ANTHROPIC_API_KEY=)[^[:space:]]+/\1***MASKED***/g'
  's/(GH_TOKEN=)[^[:space:]]+/\1***MASKED***/g'
  's/(GITHUB_TOKEN=)[^[:space:]]+/\1***MASKED***/g'
  's/(OPENAI_API_KEY=)[^[:space:]]+/\1***MASKED***/g'
  's/([A-Z][A-Z0-9_]*_KEY=)[^[:space:]]+/\1***MASKED***/g'
  's/[A-Z][A-Z0-9_]*_SECRET=[^[:space:]]+/***MASKED***/g'
  's/[A-Z][A-Z0-9_]*_PASSWORD=[^[:space:]]+/***MASKED***/g'
  's/sk-ant-[A-Za-z0-9_-]+/***MASKED***/g'
  's/ghp_[A-Za-z0-9_]+/***MASKED***/g'
  's/ghs_[A-Za-z0-9_]+/***MASKED***/g'
  's/gho_[A-Za-z0-9_]+/***MASKED***/g'
  's/ghu_[A-Za-z0-9_]+/***MASKED***/g'
  's/ghr_[A-Za-z0-9_]+/***MASKED***/g'
)

mask_secrets() {
  local input="$1"
  local pattern
  for pattern in "${SECRET_PATTERNS[@]}"; do
    input="$(printf '%s' "$input" | sed -E "$pattern")"
  done
  printf '%s' "$input"
}

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

# 機密情報をマスクしてからログ記録（平文の API キー等が残らないように）
MASKED_COMMAND="$(mask_secrets "$COMMAND")"

# state ディレクトリを作成してログファイルに追記
vibecorp_state_mkdir >/dev/null
LOG_FILE="$(vibecorp_state_path command-log)"

# タイムスタンプ + マスク済みコマンドをログに追記
printf '%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$MASKED_COMMAND" >> "$LOG_FILE"

exit 0
