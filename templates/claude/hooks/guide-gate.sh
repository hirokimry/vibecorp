#!/bin/bash
# guide-gate.sh — claude-code-guide エージェント参照を強制するフック
# .claude/ 配下のテンプレート（hooks / skills / agents / rules / settings.json / *.mcp.json）を
# Edit/Write/MultiEdit する際、guide-ok スタンプの存在を確認する。
# スタンプがあれば消費して許可、なければ deny を返す。

set -euo pipefail

# 共通ユーティリティ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- デフォルト監視スコープ ---
# .claude/hooks/, .claude/skills/, .claude/agents/, .claude/rules/,
# .claude/settings.json, *.mcp.json
DEFAULT_PATTERNS=(
  "*/.claude/hooks/*"
  "*/.claude/skills/*"
  "*/.claude/agents/*"
  "*/.claude/rules/*"
  "*/.claude/settings.json"
  "*.mcp.json"
  ".claude/hooks/*"
  ".claude/skills/*"
  ".claude/agents/*"
  ".claude/rules/*"
  ".claude/settings.json"
)

# --- vibecorp.yml から guide_gate.extra_paths を読み取る ---
VIBECORP_YML="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
EXTRA_PATTERNS=()
EXTRA_PATTERNS_COUNT=0

if [ -f "$VIBECORP_YML" ]; then
  while IFS= read -r extra_path; do
    [ -z "$extra_path" ] && continue
    # パスの末尾に * がなければ /* を追加（ディレクトリ配下全体をカバー）
    if [[ "$extra_path" == */ ]]; then
      EXTRA_PATTERNS+=("${extra_path}*")
      EXTRA_PATTERNS+=("*/${extra_path}*")
    elif [[ "$extra_path" == *"*" ]]; then
      EXTRA_PATTERNS+=("$extra_path")
      EXTRA_PATTERNS+=("*/${extra_path}")
    else
      EXTRA_PATTERNS+=("${extra_path}*")
      EXTRA_PATTERNS+=("*/${extra_path}*")
      EXTRA_PATTERNS+=("$extra_path")
      EXTRA_PATTERNS+=("*/${extra_path}")
    fi
    EXTRA_PATTERNS_COUNT=$((EXTRA_PATTERNS_COUNT + 1))
  done < <(
    awk '
      /^guide_gate:[[:space:]]*$/ { in_gg = 1; next }
      in_gg && /^[^[:space:]#]/ { exit }
      in_gg && /^[[:space:]]+extra_paths:[[:space:]]*$/ { in_ep = 1; next }
      in_ep && /^[[:space:]]+[^[:space:]-]/ && !/^[[:space:]]+-/ { exit }
      in_ep && /^[^[:space:]]/ { exit }
      in_ep && /^[[:space:]]*-[[:space:]]*/ {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        sub(/[[:space:]]*$/, "", $0)
        print
      }
    ' "$VIBECORP_YML"
  )
fi

# --- スコープ判定 ---
in_scope=false

for pattern in "${DEFAULT_PATTERNS[@]}"; do
  # bash 3.2 互換: case 文でグロブマッチ
  case "$FILE_PATH" in
    $pattern) in_scope=true; break ;;
  esac
done

if [ "$in_scope" = false ] && [ "${EXTRA_PATTERNS_COUNT}" -gt 0 ]; then
  for pattern in "${EXTRA_PATTERNS[@]}"; do
    case "$FILE_PATH" in
      $pattern) in_scope=true; break ;;
    esac
  done
fi

if [ "$in_scope" = false ]; then
  exit 0
fi

# --- スタンプ確認 ---
# 対象パスの場合のみスタンプパスを解決（無関係ファイルで git rev-parse + shasum を走らせない）
STAMP_FILE="$(vibecorp_stamp_path guide)"

if [ -f "$STAMP_FILE" ]; then
  rm -f "$STAMP_FILE"
  exit 0
fi

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "編集前に claude-code-guide エージェントで Claude Code 仕様を確認してください。確認後にスタンプが発行されます。"
  }
}'
exit 0
