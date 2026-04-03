#!/bin/bash
# team-auto-approve.sh — チームモードでの安全なツールコールを自動承認するフック
# チームメイトが settings.local.json の allow リストを継承しない問題の回避策
# 参照: anthropics/claude-code#26479

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# --- Write / Edit: 保護対象ファイル以外を自動承認 ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  if [ -z "$FILE_PATH" ]; then
    exit 0
  fi

  # 保護対象ファイルは承認しない（通常フローに委ねる）
  case "$FILE_PATH" in
    *.env|*secrets*|*credentials*|*id_rsa*|*id_ed25519*)
      exit 0
      ;;
    */MVV.md)
      exit 0
      ;;
  esac

  # それ以外は自動承認
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow"
    }
  }'
  exit 0
fi

# --- Read: 機密ファイル以外を自動承認 ---
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  if [ -z "$FILE_PATH" ]; then
    exit 0
  fi

  case "$FILE_PATH" in
    *.env|*secrets*|*credentials*|*key*|*token*|*id_rsa*|*id_ed25519*)
      exit 0
      ;;
  esac

  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow"
    }
  }'
  exit 0
fi

# --- Glob / Grep: 常に自動承認 ---
if [ "$TOOL_NAME" = "Glob" ] || [ "$TOOL_NAME" = "Grep" ]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow"
    }
  }'
  exit 0
fi

# --- Bash: 安全なコマンドのみ自動承認 ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  if [ -z "$COMMAND" ]; then
    exit 0
  fi

  # 環境変数プレフィックス・ラッパーコマンドを除去して正規化
  normalized="$COMMAND"
  while [[ "$normalized" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]](.+)$ ]]; do
    normalized="${BASH_REMATCH[1]}"
  done
  normalized="${normalized#env }"
  normalized="${normalized#command }"

  # ベースコマンドを抽出
  base_cmd=$(echo "$normalized" | awk '{print $1}')
  base_cmd=$(basename "$base_cmd")

  # 危険なコマンドは承認しない
  case "$base_cmd" in
    rm|sudo|kill|killall|pkill|reboot|shutdown|dd|mkfs|fdisk)
      exit 0
      ;;
  esac

  # 危険なフラグを検出
  if echo "$normalized" | grep -qE '(--force|--hard|-rf|-fr|--no-verify|--delete)'; then
    exit 0
  fi

  # bash はファイル実行（bash *.sh）のみ許可。-c による任意コード実行はブロック
  if [ "$base_cmd" = "bash" ]; then
    # 複合オプション（-xc, -vc 等）も検出するため -[a-zA-Z]*[cs] にマッチ
    if echo "$normalized" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[cs]'; then
      exit 0
    fi
    jq -n '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow"
      }
    }'
    exit 0
  fi

  # 安全なコマンドリスト（任意実行・外部通信不可のコマンドのみ）
  case "$base_cmd" in
    cd|ls|pwd|cat|head|tail|echo|printf|test|true|false|\
    grep|find|awk|sed|sort|uniq|wc|cut|tr|tee|diff|comm|rev|paste|jq|\
    git|gh|cr|coderabbit|shellcheck|\
    basename|dirname|realpath|readlink|stat|file|which|type|id|whoami|hostname|\
    mkdir|cp|mv|touch|chmod|mktemp|rmdir|\
    source|export|set|shopt|for|while|do|done|xargs|\
    npm|npx|\
    rsync|tar|zip|unzip|tree|\
    date|sleep)
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "allow"
        }
      }'
      exit 0
      ;;
  esac

  # リストにないコマンドは通常フローに委ねる
  exit 0
fi

# その他のツールは通常フローに委ねる
exit 0
