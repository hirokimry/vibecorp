#!/bin/bash
# protect-knowledge-direct-writes.sh — knowledge/{role}/decisions/ 等の作業ブランチ直書きを deny する
# Issue #439: knowledge への書込みは knowledge/buffer worktree 経由に統一する
# Issue #442: 監査ログを {role}/audit-log/YYYY-QN.md の四半期集約構造に統一
#
# 設計:
#   順序: realpath 正規化 → deny パターン判定 → buffer 配下判定 → スタンプは fail-secure で対象外
#   decisions/ や {role}/audit-log/ は C*O 判断記録 / 監査の責務領域であり、harvest-all のスコープ外。
#   harvest-all-active スタンプは「decisions/audit-log 以外への直書き」専用例外で、
#   decisions/audit-log パターンに合致した時点でスタンプによる救済は受け付けない。

set -euo pipefail

# 共通ユーティリティ読み込み
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"
# shellcheck source=../lib/knowledge_buffer.sh
source "${HOOK_DIR}/../lib/knowledge_buffer.sh"
# shellcheck source=../lib/path_normalize.sh
# パス正規化ヘルパー _pkw_normalize_path を共通 lib から取得（Issue #448）
source "${HOOK_DIR}/../lib/path_normalize.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# パス正規化（パストラバーサル / シンボリックリンク対策）
abs_file_path="$(_pkw_normalize_path "$FILE_PATH" 2>/dev/null || echo "")"

# 正規化不能（realpath / python3 両方不在）の場合の fail-closed 判定
# 原文 FILE_PATH に対して deny パターンを適用し、合致時のみ deny する。
# 合致しない場合は関与せず通す（無関係ファイルへの誤 deny を避ける）。
if [ -z "$abs_file_path" ]; then
  case "$FILE_PATH" in
    *.claude/knowledge/*/decisions/*.md|\
    *.claude/knowledge/*/decisions-index.md|\
    *.claude/knowledge/*/audit-log/*.md)
      # fail-closed: 正規化できないがパターン合致なので deny
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": "パス正規化に失敗（realpath / python3 が不在）。安全のため deny します。realpath（GNU coreutils）または python3 をインストールしてください。"
        }
      }'
      exit 0
      ;;
    *)
      exit 0  # 関与せず通す
      ;;
  esac
fi

# deny 対象パターン判定
is_deny_target=0
case "$abs_file_path" in
  *.claude/knowledge/*/decisions/*.md|\
  *.claude/knowledge/*/decisions-index.md|\
  *.claude/knowledge/*/audit-log/*.md)
    is_deny_target=1
    ;;
esac

# 非対象なら関与せず通す
if [ "$is_deny_target" -eq 0 ]; then
  exit 0
fi

# buffer worktree 配下なら許可（deny 対象でも buffer 経由は許可）
# expected_prefix は vibecorp_cache_root を経由して XDG_CACHE_HOME を尊重する
# （${HOME}/.cache 直書きだと XDG_CACHE_HOME 設定環境で誤 deny する）
buffer_dir="$(knowledge_buffer_worktree_dir 2>/dev/null || true)"
if [ -n "$buffer_dir" ]; then
  abs_buffer_dir="$(_pkw_normalize_path "$buffer_dir" 2>/dev/null || echo "")"
  expected_prefix="$(vibecorp_cache_root)/vibecorp/buffer-worktree/"
  if [ -n "$abs_buffer_dir" ] && [[ "$abs_buffer_dir" == "$expected_prefix"* ]] && [[ "$abs_file_path" == "${abs_buffer_dir}/"* ]]; then
    exit 0
  fi
fi

# harvest-all-active スタンプ判定（decisions/audit-log パターンに合致したものは対象外・fail-secure）
# 仕様: スタンプは knowledge/{role}/{topic}.md のような decisions/audit-log 以外への直書き許可専用。
# decisions/ や {role}/audit-log/ は C*O 判断記録 / 監査の責務領域であり、スタンプ通過対象から除外する。

# deny を返却
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ".claude/knowledge/{role}/decisions/ や {role}/audit-log/ は knowledge/buffer worktree 経由で更新してください。\n\n復旧手順:\n1. . .claude/lib/knowledge_buffer.sh\n2. knowledge_buffer_ensure\n3. BUFFER_DIR=$(knowledge_buffer_worktree_dir)\n4. ファイルパスを ${BUFFER_DIR}/.claude/knowledge/... に置き換えて再実行\n\nスキル経由の場合: /vibecorp:session-harvest, /vibecorp:sync-edit, /vibecorp:audit-cost, /vibecorp:audit-security のいずれかを使用\n詳細: docs/specification.md の「自動反映フロー」節"
  }
}'
exit 0
