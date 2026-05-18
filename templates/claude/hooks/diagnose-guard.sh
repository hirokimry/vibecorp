#!/bin/bash
# diagnose-guard.sh — /vibecorp:diagnose 実行中に保護ファイルへの編集をブロックするフック
# diagnose-active スタンプ存在時に hooks/*.sh, vibecorp.yml, MVV.md, SECURITY.md, POLICY.md,
# skills/** (再帰的に skills 配下の全パス), diagnose-guard.sh への変更を deny

set -euo pipefail

# shellcheck source=../lib/common.sh
source "${CLAUDE_PROJECT_DIR:-.}/.claude/lib/common.sh"
# shellcheck source=../lib/path_normalize.sh
# realpath 正規化を使い、シンボリックリンク経由の bypass（例: skillz -> skills）を塞ぐ
source "${CLAUDE_PROJECT_DIR:-.}/.claude/lib/path_normalize.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# シンボリックリンク bypass 対策: realpath 正規化を試みる
# - 成功: 正規化後のパスでパターンマッチ（symlink 先の実体パスを判定）
# - 失敗（realpath / python3 不在）: 原文パスで判定（degraded だが既存挙動は維持）
# CANONICAL_PATH が空のとき、後段のマッチ判定で FILE_PATH のみを使う設計
CANONICAL_PATH="$(_pkw_normalize_path "$FILE_PATH" 2>/dev/null || true)"

STAMP_FILE="$(vibecorp_state_path diagnose-active)"

# diagnose-active スタンプが存在しない場合は何もしない
if [ ! -f "$STAMP_FILE" ]; then
  exit 0
fi

# vibecorp.yml の diagnose.forbidden_targets を読み取る（デフォルト値あり）
VIBECORP_YML="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
FORBIDDEN_PATTERNS=""
if [ -f "$VIBECORP_YML" ]; then
  FORBIDDEN_PATTERNS=$(awk '
    /^diagnose:/ { in_diagnose = 1; next }
    in_diagnose && /^[^ #]/ { exit }
    in_diagnose && /^  forbidden_targets:/ { in_targets = 1; next }
    in_diagnose && in_targets && /^  [^ -]/ { exit }
    in_diagnose && in_targets && /^    - / {
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
# skills/** は再帰マッチ（** が `.*` に変換され、skills 配下の全パスを deny する）
if [ -z "$FORBIDDEN_PATTERNS" ]; then
  FORBIDDEN_PATTERNS="hooks/*.sh
vibecorp.yml
MVV.md
SECURITY.md
POLICY.md
skills/**"
fi

# diagnose-guard.sh 自体は常に保護（forbidden_targets に関係なく）
# 原文・正規化後の両方を判定し、シンボリックリンク経由の bypass を塞ぐ
if echo "$FILE_PATH" | grep -q 'diagnose-guard\.sh$' \
  || { [ -n "$CANONICAL_PATH" ] && echo "$CANONICAL_PATH" | grep -q 'diagnose-guard\.sh$'; }; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "/vibecorp:diagnose 実行中は diagnose-guard.sh を変更できません。自己制約の緩和は禁止されています。"
    }
  }'
  exit 0
fi

# forbidden_targets のパターンマッチ
# シンボリックリンク bypass 対策として、原文 FILE_PATH と正規化後 CANONICAL_PATH の
# 両方を判定する（どちらか片方でもマッチしたら deny）。
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue

  # ワイルドカードパターン（例: hooks/*.sh, skills/**）
  if echo "$pattern" | grep -q '\*'; then
    # glob パターンを正規表現に変換
    # - `**` は cross-directory マッチ（`.*`）— skills/** → skills/.*$ で配下全体を保護
    # - `*` は同一ディレクトリ内マッチ（`[^/]*`）— hooks/*.sh → hooks/[^/]*\.sh$
    # 末尾アンカー `$` を必ず付与する（付与しないと `hooks/*.sh` が `hooks/foo.sh.bak`
    # にも誤マッチして deny してしまう）。
    # 変換順序:
    #   1. `**` を sentinel `__GLOBSTAR__` に退避（次の単一 `*` 変換で食われないよう保護）
    #   2. リテラル `.` を `\.` にエスケープ
    #   3. 単一 `*` を `[^/]*` に変換
    #   4. sentinel を `.*` に復元
    REGEX_PATTERN=$(printf '%s' "$pattern" \
      | sed 's/\*\*/__GLOBSTAR__/g' \
      | sed 's/\./\\./g' \
      | sed 's/\*/[^\/]*/g' \
      | sed 's/__GLOBSTAR__/.*/g')'$'
    if echo "$FILE_PATH" | grep -qE "$REGEX_PATTERN" \
      || { [ -n "$CANONICAL_PATH" ] && echo "$CANONICAL_PATH" | grep -qE "$REGEX_PATTERN"; }; then
      jq -n --arg pattern "$pattern" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": ("/vibecorp:diagnose 実行中は " + $pattern + " に一致するファイルを変更できません。暴走防止のため保護されています。")
        }
      }'
      exit 0
    fi
  else
    # 完全一致（パス末尾比較）
    if [[ "$FILE_PATH" == *"$pattern" ]] \
      || { [ -n "$CANONICAL_PATH" ] && [[ "$CANONICAL_PATH" == *"$pattern" ]]; }; then
      jq -n --arg pattern "$pattern" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": ("/vibecorp:diagnose 実行中は " + $pattern + " を変更できません。暴走防止のため保護されています。")
        }
      }'
      exit 0
    fi
  fi
done <<< "$FORBIDDEN_PATTERNS"

exit 0
