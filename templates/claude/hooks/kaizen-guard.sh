#!/bin/bash
# kaizen-guard.sh — /kaizen 実行中に保護ファイルへの編集をブロックするフック
# kaizen-active スタンプ存在時に hooks/*.sh, vibecorp.yml, MVV.md, kaizen-guard.sh への変更を deny

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
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

STAMP_FILE="/tmp/.${PROJECT_NAME}-kaizen-active"

# kaizen-active スタンプが存在しない場合は何もしない
if [ ! -f "$STAMP_FILE" ]; then
  exit 0
fi

# vibecorp.yml の kaizen.forbidden_targets を読み取る（デフォルト値あり）
FORBIDDEN_PATTERNS=""
if [ -f "$VIBECORP_YML" ]; then
  FORBIDDEN_PATTERNS=$(awk '
    /^kaizen:/ { in_kaizen = 1; next }
    in_kaizen && /^[^ #]/ { exit }
    in_kaizen && /^  forbidden_targets:/ { in_targets = 1; next }
    in_kaizen && in_targets && /^  [^ -]/ { exit }
    in_kaizen && in_targets && /^    - / {
      sub(/^    - /, "")
      sub(/[[:space:]]*$/, "")
      # クォートを除去
      gsub(/"/, "")
      gsub(/'\''/, "")
      print
    }
  ' "$VIBECORP_YML")
fi

# forbidden_targets が空の場合はデフォルト値を使用
if [ -z "$FORBIDDEN_PATTERNS" ]; then
  FORBIDDEN_PATTERNS="hooks/*.sh
vibecorp.yml
MVV.md
SECURITY.md
POLICY.md"
fi

# kaizen-guard.sh 自体は常に保護（forbidden_targets に関係なく）
if echo "$FILE_PATH" | grep -q 'kaizen-guard\.sh$'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "/kaizen 実行中は kaizen-guard.sh を変更できません。自己制約の緩和は禁止されています。"
    }
  }'
  exit 0
fi

# forbidden_targets のパターンマッチ
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue

  # ワイルドカードパターン（例: hooks/*.sh）
  if echo "$pattern" | grep -q '\*'; then
    # glob パターンを正規表現に変換
    REGEX_PATTERN=$(printf '%s' "$pattern" | sed 's/\./\\./g' | sed 's/\*/[^\/]*/g')
    if echo "$FILE_PATH" | grep -qE "$REGEX_PATTERN"; then
      jq -n --arg pattern "$pattern" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": ("/kaizen 実行中は " + $pattern + " に一致するファイルを変更できません。暴走防止のため保護されています。")
        }
      }'
      exit 0
    fi
  else
    # 完全一致（パス末尾比較）
    if [[ "$FILE_PATH" == *"$pattern" ]]; then
      jq -n --arg pattern "$pattern" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": ("/kaizen 実行中は " + $pattern + " を変更できません。暴走防止のため保護されています。")
        }
      }'
      exit 0
    fi
  fi
done <<< "$FORBIDDEN_PATTERNS"

exit 0
