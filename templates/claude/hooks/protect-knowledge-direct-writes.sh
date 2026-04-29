#!/bin/bash
# protect-knowledge-direct-writes.sh — knowledge/{role}/decisions/ 等の作業ブランチ直書きを deny する
# Issue #439: knowledge への書込みは knowledge/buffer worktree 経由に統一する
#
# 設計:
#   順序: realpath 正規化 → deny パターン判定 → buffer 配下判定 → スタンプは fail-secure で対象外
#   decisions/ や audit-*.md は C*O 判断記録 / 監査の責務領域であり、harvest-all のスコープ外。
#   harvest-all-active スタンプは「decisions/audit 以外への直書き」専用例外で、
#   decisions/audit パターンに合致した時点でスタンプによる救済は受け付けない。

set -euo pipefail

# 共通ユーティリティ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"
# shellcheck source=../lib/knowledge_buffer.sh
source "${HOOK_DIR}/../lib/knowledge_buffer.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# realpath -m が macOS BSD で利用不能な場合の Python フォールバック
# Python コード内に変数展開を埋め込まず、引数渡しでインジェクション回避
_pkw_normalize_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    realpath -m -- "$p"
  elif command -v python3 >/dev/null 2>&1; then
    # 引数渡しでインジェクション回避（変数展開を Python コードに埋め込まない）
    # `--` は使わない（python3 -c は -c の値で「コード」を受け、それ以降の引数は sys.argv[1:] に入る）
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p"
  else
    return 1
  fi
}

# パス正規化（パストラバーサル / シンボリックリンク対策）
abs_file_path="$(_pkw_normalize_path "$FILE_PATH" 2>/dev/null || echo "")"
if [ -z "$abs_file_path" ]; then
  exit 0  # 正規化不能なら関与せず通す（他の hook に委ねる）
fi

# deny 対象パターン判定
is_deny_target=0
case "$abs_file_path" in
  *.claude/knowledge/*/decisions/*.md|\
  *.claude/knowledge/*/decisions-index.md|\
  *.claude/knowledge/accounting/audit-*.md|\
  *.claude/knowledge/security/audit-*.md)
    is_deny_target=1
    ;;
esac

# 非対象なら関与せず通す
if [ "$is_deny_target" -eq 0 ]; then
  exit 0
fi

# buffer worktree 配下なら許可（deny 対象でも buffer 経由は許可）
buffer_dir="$(knowledge_buffer_worktree_dir 2>/dev/null || true)"
if [ -n "$buffer_dir" ]; then
  abs_buffer_dir="$(_pkw_normalize_path "$buffer_dir" 2>/dev/null || echo "")"
  expected_prefix="${HOME}/.cache/vibecorp/buffer-worktree/"
  if [ -n "$abs_buffer_dir" ] && [[ "$abs_buffer_dir" == "$expected_prefix"* ]] && [[ "$abs_file_path" == "${abs_buffer_dir}/"* ]]; then
    exit 0
  fi
fi

# harvest-all-active スタンプ判定（decisions/audit パターンに合致したものは対象外・fail-secure）
# 仕様: スタンプは knowledge/{role}/{topic}.md のような decisions/audit 以外への直書き許可専用。
# decisions/ や audit-*.md は C*O 判断記録 / 監査の責務領域であり、スタンプ通過対象から除外する。

# deny を返却
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ".claude/knowledge/{role}/decisions/ や audit-*.md は knowledge/buffer worktree 経由で更新してください。\n\n復旧手順:\n1. . .claude/lib/knowledge_buffer.sh\n2. knowledge_buffer_ensure\n3. BUFFER_DIR=$(knowledge_buffer_worktree_dir)\n4. ファイルパスを ${BUFFER_DIR}/.claude/knowledge/... に置き換えて再実行\n\nスキル経由の場合: /vibecorp:session-harvest, /vibecorp:sync-edit, /vibecorp:audit-cost, /vibecorp:audit-security のいずれかを使用\n詳細: docs/specification.md の「自動反映フロー」節"
  }
}'
exit 0
