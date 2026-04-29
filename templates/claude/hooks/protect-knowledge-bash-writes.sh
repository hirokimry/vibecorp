#!/bin/bash
# protect-knowledge-bash-writes.sh — Bash 経由の knowledge 直書きを deny する
# Issue #448: Edit/Write hook で deny する protect-knowledge-direct-writes.sh と対をなす多層防御の Bash 層
#
# 設計:
#   順序: コマンド正規化（環境変数除去、ラッパー除去、bash -c 展開）
#         → 検出パターン照合 + パス抽出
#         → buffer 経由判定（既存 hook の 3 段ガード踏襲）
#         → deny 出力
#
# 既知ギャップ（明示的に Edit/Write 層 + agent 定義の Edit/Write 強制でカバー）:
#   - bash -c $'...' 形式（$''quote）
#   - shell function 経由
#   - eval "..." 経由

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"
# shellcheck source=../lib/knowledge_buffer.sh
source "${HOOK_DIR}/../lib/knowledge_buffer.sh"
# shellcheck source=../lib/path_normalize.sh
source "${HOOK_DIR}/../lib/path_normalize.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# === 1. コマンド正規化 ===

cmd_normalized="$COMMAND"

# 1a) 複数の環境変数プレフィックス除去（while ループで全て剥がす）
while [[ "$cmd_normalized" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
  cmd_normalized="${cmd_normalized#*[[:space:]]}"
done

# 1b) ラッパーコマンド（env / command）の除去
# `env -i` / `env --ignore-environment` 等のフラグも一緒に剥がす
while true; do
  case "$cmd_normalized" in
    "env "*)
      rest="${cmd_normalized#env }"
      # env のフラグを剥がす（次の非フラグ引数まで）
      while [[ "$rest" =~ ^-[^[:space:]]*[[:space:]] ]]; do
        rest="${rest#*[[:space:]]}"
      done
      cmd_normalized="$rest"
      ;;
    "command "*)
      cmd_normalized="${cmd_normalized#command }"
      ;;
    *)
      break
      ;;
  esac
done

# 1c) `bash -c "..."` / `sh -c "..."` 内のコマンドを展開
case "$cmd_normalized" in
  "bash -c \""*"\""|"bash -c '"*"'"|"sh -c \""*"\""|"sh -c '"*"'")
    inner=$(printf '%s' "$cmd_normalized" | sed -E "s/^(bash|sh) -c [\"'](.*)[\"']\$/\\2/")
    if [ -n "$inner" ] && [ "$inner" != "$cmd_normalized" ]; then
      cmd_normalized="$inner"
    fi
    ;;
esac

# === 2. 検出パターン照合 + パス抽出 ===

is_deny_target=0
detected_path=""

for forbidden in 'decisions/' 'audit-log/'; do
  # 2a) 出力リダイレクト（> / >>）
  # 複合コマンド `cmd1 && cmd2 > file` も対象
  if [[ "$cmd_normalized" =~ (\>{1,2})[[:space:]]*[\'\"]?([^[:space:]\'\"\;]*\.claude/knowledge/[^/]+/${forbidden}[^[:space:]\'\"\;]*) ]]; then
    detected_path="${BASH_REMATCH[2]}"
    is_deny_target=1
    break
  fi
  # 2b) tee / tee -a
  if [[ "$cmd_normalized" =~ tee[[:space:]]+(-a[[:space:]]+)?[\'\"]?([^[:space:]\'\"\;]*\.claude/knowledge/[^/]+/${forbidden}[^[:space:]\'\"\;]*) ]]; then
    detected_path="${BASH_REMATCH[2]}"
    is_deny_target=1
    break
  fi
  # 2c) cp / mv の宛先
  if [[ "$cmd_normalized" =~ (cp|mv)[[:space:]]+[^\|\;\&]+[[:space:]]+[\'\"]?([^[:space:]\'\"\;]*\.claude/knowledge/[^/]+/${forbidden}[^[:space:]\'\"\;]*) ]]; then
    detected_path="${BASH_REMATCH[2]}"
    is_deny_target=1
    break
  fi
  # 2d) GNU sed -i / BSD sed -i '' / awk -i inplace
  if [[ "$cmd_normalized" =~ (sed[[:space:]]+-i([[:space:]]+\'\')?|awk[[:space:]]+-i[[:space:]]+inplace)[[:space:]]+[^\|\;\&]*[\'\"]?([^[:space:]\'\"\;]*\.claude/knowledge/[^/]+/${forbidden}[^[:space:]\'\"\;]*) ]]; then
    detected_path="${BASH_REMATCH[3]}"
    is_deny_target=1
    break
  fi
done

if [ "$is_deny_target" -eq 0 ]; then
  exit 0
fi

# === 3. buffer 経由判定（既存 hook の 3 段ガード踏襲） ===

buffer_dir="$(knowledge_buffer_worktree_dir 2>/dev/null || true)"
abs_detected_path="$(_pkw_normalize_path "$detected_path" 2>/dev/null || echo "")"

if [ -n "$buffer_dir" ] && [ -n "$abs_detected_path" ]; then
  abs_buffer_dir="$(_pkw_normalize_path "$buffer_dir" 2>/dev/null || echo "")"
  expected_prefix="$(vibecorp_cache_root)/vibecorp/buffer-worktree/"
  if [ -n "$abs_buffer_dir" ] && [[ "$abs_buffer_dir" == "$expected_prefix"* ]] && [[ "$abs_detected_path" == "${abs_buffer_dir}/"* ]]; then
    exit 0
  fi
fi

# === 4. deny 出力 ===

buffer_label="${buffer_dir:-（未取得・knowledge_buffer_ensure を実行してください）}"

jq -n \
  --arg detected "$detected_path" \
  --arg buffer "$buffer_label" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("検出パス: " + $detected + "\n\n.claude/knowledge/{role}/decisions/ や {role}/audit-log/ への Bash 経由直書きは禁止です（>, >>, tee, cp, mv, sed -i, awk -i inplace を含む）。\n\n復旧手順:\n1. . .claude/lib/knowledge_buffer.sh\n2. knowledge_buffer_ensure\n3. BUFFER_DIR=" + $buffer + "\n4. コマンドの宛先を ${BUFFER_DIR}/.claude/knowledge/... に置き換えて再実行\n\n書込みは Bash redirect ではなく Edit/Write/MultiEdit ツールを使うことを推奨します（hook が deny を確実に検出できます）。")
    }
  }'
exit 0
