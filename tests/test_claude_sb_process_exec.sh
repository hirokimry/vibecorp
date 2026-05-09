#!/bin/bash
# test_claude_sb_process_exec.sh
# ─────────────────────────────────────────────
# Issue #513: claude.sb の process-exec ホワイトリスト制限を静的検証する。
#
# vibecorp 自身（.claude/sandbox/claude.sb）と配布版（templates/claude/sandbox/claude.sb）の
# 両方に対して以下を確認する:
#
#   1. 無制限の `(allow process-exec)` 単独行が存在しない
#   2. ホワイトリスト方式の `(allow process-exec ... (subpath ...))` ブロックが存在する
#   3. システムバイナリパス（/usr, /bin, /sbin, /opt/homebrew, /usr/local 等）が許可される
#   4. WORKTREE パラメータが subpath に含まれない（任意バイナリ実行不可）
#   5. 自リポ版と配布版が完全一致する（同期 drift 検知）
#
# sandbox-exec 経由の実機テストは tests/test_isolation_macos.sh が担当する。本テストは
# プロファイル定義そのものの整合性を OS 非依存で検証する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF_SB="${SCRIPT_DIR}/.claude/sandbox/claude.sb"
TEMPLATE_SB="${SCRIPT_DIR}/templates/claude/sandbox/claude.sb"

assert_file_exists "vibecorp 自リポ claude.sb が存在する" "$SELF_SB"
assert_file_exists "templates 配布版 claude.sb が存在する" "$TEMPLATE_SB"

# ============================================
# Case 1: 無制限の (allow process-exec) 単独行が存在しない
# ============================================
echo ""
echo "--- Case 1: 無制限 (allow process-exec) 単独行が存在しない ---"

check_no_unrestricted_exec() {
  local label="$1"
  local file="$2"
  # 単独行 `(allow process-exec)` （閉じ括弧の直後に改行）にマッチする行を探す
  if grep -qE '^\(allow process-exec\)[[:space:]]*$' "$file"; then
    fail "${label}: 無制限の (allow process-exec) 単独行が存在する"
  else
    pass "${label}: 無制限の (allow process-exec) 単独行は存在しない"
  fi
}

check_no_unrestricted_exec "自リポ版" "$SELF_SB"
check_no_unrestricted_exec "配布版" "$TEMPLATE_SB"

# ============================================
# Case 2: ホワイトリスト方式の process-exec ブロックが存在する
# ============================================
echo ""
echo "--- Case 2: ホワイトリスト方式の process-exec ブロックが存在する ---"

check_whitelist_block() {
  local label="$1"
  local file="$2"
  # `(allow process-exec` で始まり、複数行に subpath が続くブロックを検出
  if grep -qE '^\(allow process-exec[[:space:]]*$' "$file"; then
    pass "${label}: ホワイトリストブロック開始行が存在"
  else
    fail "${label}: (allow process-exec の複数行ブロックが見つからない"
  fi
}

check_whitelist_block "自リポ版" "$SELF_SB"
check_whitelist_block "配布版" "$TEMPLATE_SB"

# ============================================
# Case 3: 必須システムバイナリパスが許可される
# ============================================
echo ""
echo "--- Case 3: 必須システムバイナリパスが許可される ---"

# claude.sb 内で process-exec ブロックの subpath にこれらが含まれるはず
REQUIRED_PATHS=(
  '/usr'
  '/bin'
  '/sbin'
  '/System'
  '/Library'
  '/opt/homebrew'
  '/usr/local'
  '/Applications'
)

extract_process_exec_block() {
  local file="$1"
  # `(allow process-exec` で始まる行から、次の `(allow ...` 直前までを抽出する。
  # ブロック内の最後の閉じ括弧はインデント行末にあるため `^\)` で終端できない。
  # 同階層の次の `(allow` キーワードが現れたら停止する。
  awk '
    /^\(allow process-exec[[:space:]]*$/ { in_block = 1; print; next }
    in_block && /^\(allow/ { exit }
    in_block { print }
  ' "$file"
}

check_required_path() {
  local label="$1"
  local file="$2"
  local block
  block="$(extract_process_exec_block "$file")"
  for path in "${REQUIRED_PATHS[@]}"; do
    if printf '%s' "$block" | grep -qF "(subpath \"${path}\")"; then
      pass "${label}: ${path} が process-exec で許可されている"
    else
      fail "${label}: ${path} が process-exec で許可されていない"
    fi
  done

  # claude バイナリ実体が置かれる HOME 配下も process-exec で許可されている必要がある
  if printf '%s' "$block" | grep -qF '(subpath (string-append (param "HOME") "/.local/share/claude"))'; then
    pass "${label}: HOME/.local/share/claude が process-exec で許可されている"
  else
    fail "${label}: HOME/.local/share/claude が process-exec で許可されていない"
  fi
}

check_required_path "自リポ版" "$SELF_SB"
check_required_path "配布版" "$TEMPLATE_SB"

# ============================================
# Case 4: WORKTREE パラメータが subpath に含まれない（任意バイナリ実行不可）
# ============================================
echo ""
echo "--- Case 4: WORKTREE パラメータが process-exec subpath に含まれない ---"

check_worktree_excluded() {
  local label="$1"
  local file="$2"
  local block
  block="$(extract_process_exec_block "$file")"
  if printf '%s' "$block" | grep -qE '\(subpath \(param "WORKTREE"\)\)'; then
    fail "${label}: WORKTREE が process-exec subpath に含まれる（任意バイナリ実行可能になるため危険）"
  else
    pass "${label}: WORKTREE が process-exec subpath に含まれない（任意バイナリ実行不可）"
  fi
}

check_worktree_excluded "自リポ版" "$SELF_SB"
check_worktree_excluded "配布版" "$TEMPLATE_SB"

# ============================================
# Case 5: 自リポ版と配布版が完全一致する
# ============================================
echo ""
echo "--- Case 5: 自リポ版と配布版が完全一致する（同期 drift 検知） ---"

if diff -q "$SELF_SB" "$TEMPLATE_SB" >/dev/null; then
  pass "自リポ版と配布版の claude.sb が完全一致"
else
  fail "自リポ版と配布版の claude.sb が乖離している"
fi

print_test_summary
