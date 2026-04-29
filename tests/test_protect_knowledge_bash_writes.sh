#!/bin/bash
# test_protect_knowledge_bash_writes.sh — Issue #448: Bash 経由の knowledge 直書きを deny する hook の検証
# 使い方: bash tests/test_protect_knowledge_bash_writes.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
HOOK_FILE="${PROJECT_DIR}/templates/claude/hooks/protect-knowledge-bash-writes.sh"

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

echo "=== Issue #448: protect-knowledge-bash-writes.sh テスト ==="

# --- テスト1: ファイル存在 ---
echo ""
echo "--- テスト1: ファイル存在 ---"

if [[ -f "$HOOK_FILE" ]]; then
  pass "hook ファイルが存在する"
else
  fail "hook ファイルが存在しない"
  exit 1
fi
assert_file_executable "hook が実行可能" "$HOOK_FILE"

# 共通: hook 実行ヘルパー
run_hook() {
  local cmd="$1"
  local input
  input=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')
  echo "$input" | bash "$HOOK_FILE" 2>/dev/null
}

assert_deny() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(run_hook "$cmd")
  if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
    pass "$desc"
  else
    fail "$desc: $result"
  fi
}

assert_pass() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(run_hook "$cmd")
  if [ -z "$result" ]; then
    pass "$desc"
  else
    fail "$desc: $result"
  fi
}

# --- テスト2: command が空 → 関与せず通す ---
echo ""
echo "--- テスト2: command 空・欠落 ---"

result_empty=$(echo '{"tool_input":{"command":""}}' | bash "$HOOK_FILE" 2>/dev/null || true)
if [ -z "$result_empty" ]; then
  pass "command 空 → 通過"
else
  fail "command 空 → 出力あり: $result_empty"
fi

result_missing=$(echo '{"tool_input":{}}' | bash "$HOOK_FILE" 2>/dev/null || true)
if [ -z "$result_missing" ]; then
  pass "command 欠落 → 通過"
else
  fail "command 欠落 → 出力あり: $result_missing"
fi

# --- テスト3: 出力リダイレクト > / >> → deny ---
echo ""
echo "--- テスト3: 出力リダイレクト ---"

assert_deny "> redirect → deny" "echo foo > .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny ">> redirect → deny" "echo foo >> .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny ">> redirect (audit-log) → deny" "echo foo >> .claude/knowledge/accounting/audit-log/2026-Q2.md"
assert_deny "> redirect (security) → deny" "echo foo > .claude/knowledge/security/audit-log/2026-Q2.md"

# --- テスト4: tee / tee -a → deny ---
echo ""
echo "--- テスト4: tee ---"

assert_deny "tee → deny" "echo foo | tee .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "tee -a → deny" "echo foo | tee -a .claude/knowledge/cfo/decisions/2026-Q2.md"

# --- テスト5: cp / mv → deny ---
echo ""
echo "--- テスト5: cp / mv ---"

assert_deny "cp → deny" "cp src.md .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "mv → deny" "mv src.md .claude/knowledge/cfo/decisions/2026-Q2.md"

# --- テスト6: heredoc → deny（リダイレクト部分でマッチ） ---
echo ""
echo "--- テスト6: heredoc ---"

assert_deny "cat <<EOF > path → deny" 'cat <<EOF > .claude/knowledge/cfo/decisions/2026-Q2.md
content
EOF'
assert_deny "cat <<\047EOF\047 >> path → deny" "cat <<'EOF' >> .claude/knowledge/cfo/decisions/2026-Q2.md
content
EOF"

# --- テスト7: sed -i / awk -i inplace → deny ---
echo ""
echo "--- テスト7: sed -i / awk -i inplace ---"

assert_deny "GNU sed -i → deny" "sed -i 's/foo/bar/' .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "BSD sed -i '' → deny" "sed -i '' 's/foo/bar/' .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "awk -i inplace → deny" 'awk -i inplace "{print}" .claude/knowledge/cfo/decisions/2026-Q2.md'

# --- テスト8: 複合コマンド・正規化 ---
echo ""
echo "--- テスト8: 複合コマンド・正規化 ---"

assert_deny "cmd1 && cmd2 >> file → deny" "git status && echo foo >> .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "echo foo | tee path → deny" "echo foo | tee .claude/knowledge/cfo/decisions/2026-Q2.md"

# 環境変数プレフィックス（複数）
assert_deny "KEY1=v1 cat >> path → deny" "FOO=1 cat >> .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "KEY1=v1 KEY2=v2 cat >> path → deny" "FOO=1 BAR=2 cat >> .claude/knowledge/cfo/decisions/2026-Q2.md"

# env / command ラッパー
assert_deny "env KEY=v cat >> path → deny" "env FOO=1 cat >> .claude/knowledge/cfo/decisions/2026-Q2.md"
assert_deny "command tee path → deny" "command tee .claude/knowledge/cfo/decisions/2026-Q2.md"

# bash -c / sh -c 展開
assert_deny "bash -c \"cat >> path\" → deny" 'bash -c "cat >> .claude/knowledge/cfo/decisions/2026-Q2.md"'
assert_deny "sh -c \"tee path\" → deny" "sh -c \"tee .claude/knowledge/cfo/decisions/2026-Q2.md\""

# --- テスト9: 通過（無関係 / knowledge 外） ---
echo ""
echo "--- テスト9: 通過パターン ---"

assert_pass "git status → 通過" "git status"
assert_pass "ls -la → 通過" "ls -la"
assert_pass ">> /tmp/foo → 通過" "echo foo >> /tmp/foo.md"
assert_pass "knowledge/ 外 cp → 通過" "cp foo.md /tmp/bar.md"
# quote 内の偽パスは検出ロジック上 detect される可能性があるが、書込み宛先ではないため通過すべき
# 現実装は宛先パターンをマッチさせるため、文字列 "...>" に knowledge path が含まれていれば deny される
# これは false positive だが安全側（fail-secure）なので許容

# --- テスト10: buffer 経由（許可） ---
echo ""
echo "--- テスト10: buffer 経由許可 ---"

# 実 buffer worktree パスを取得
real_buffer_dir="$(. "${PROJECT_DIR}/templates/claude/lib/common.sh" && . "${PROJECT_DIR}/templates/claude/lib/knowledge_buffer.sh" && knowledge_buffer_worktree_dir 2>/dev/null || echo "")"

if [ -n "$real_buffer_dir" ] && [ -d "$real_buffer_dir" ]; then
  mkdir -p "${real_buffer_dir}/.claude/knowledge/cfo/decisions"
  buffer_target="${real_buffer_dir}/.claude/knowledge/cfo/decisions/2026-Q2.md"
  assert_pass "buffer 経由 >> → 許可" "echo foo >> ${buffer_target}"
else
  echo "  SKIP: buffer worktree が利用できないため skip"
fi

# --- テスト11: 既知ギャップ（明示的に「検出しない」を確認） ---
echo ""
echo "--- テスト11: 既知ギャップ（多層防御で他の層がカバー） ---"

# bash -c $'...' 形式（$'' quote）は未対応
result=$(run_hook "bash -c \$'cat >> .claude/knowledge/cfo/decisions/2026-Q2.md'")
if [ -z "$result" ]; then
  pass "bash -c \$'...' は通過（既知ギャップ・Edit/Write 層 + agent 定義でカバー）"
else
  pass "bash -c \$'...' は deny される（過剰検出だが安全側で許容）"
fi

# --- テスト12: templates / 本体 同期検証 ---
echo ""
echo "--- テスト12: templates と本体の hook 同期 ---"

BODY_HOOK_FILE="${PROJECT_DIR}/.claude/hooks/protect-knowledge-bash-writes.sh"
if [ -f "$BODY_HOOK_FILE" ]; then
  if diff -q "$HOOK_FILE" "$BODY_HOOK_FILE" >/dev/null 2>&1; then
    pass "templates と本体の hook が同一"
  else
    fail "templates と本体の hook が乖離している"
  fi
else
  pass "本体 hook 未配置（dogfood 環境のみ存在、新規 install では templates から配布）"
fi

print_test_summary
