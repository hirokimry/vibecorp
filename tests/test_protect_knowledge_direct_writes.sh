#!/bin/bash
# test_protect_knowledge_direct_writes.sh — Issue #439: ガードレール hook の検証
# 使い方: bash tests/test_protect_knowledge_direct_writes.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
HOOK_FILE="${PROJECT_DIR}/templates/claude/hooks/protect-knowledge-direct-writes.sh"

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

echo "=== Issue #439: protect-knowledge-direct-writes.sh テスト ==="

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
  local file_path="$1"
  local input
  input=$(printf '{"tool_input":{"file_path":"%s"}}' "$file_path")
  echo "$input" | bash "$HOOK_FILE" 2>/dev/null || true
}

# --- テスト2: file_path が空 → 関与せず通す ---
echo ""
echo "--- テスト2: file_path 空・欠落 ---"

result_empty=$(echo '{"tool_input":{"file_path":""}}' | bash "$HOOK_FILE" 2>/dev/null || true)
if [ -z "$result_empty" ]; then
  pass "file_path 空 → 関与せず通す"
else
  fail "file_path 空 → 出力あり: $result_empty"
fi

result_missing=$(echo '{"tool_input":{}}' | bash "$HOOK_FILE" 2>/dev/null || true)
if [ -z "$result_missing" ]; then
  pass "file_path 欠落 → 関与せず通す"
else
  fail "file_path 欠落 → 出力あり: $result_missing"
fi

# --- テスト3: knowledge/ 外 → 通過 ---
echo ""
echo "--- テスト3: knowledge/ 外のファイル ---"

result=$(run_hook "/tmp/some/random/path/file.md")
if [ -z "$result" ]; then
  pass "knowledge/ 外 → 通過"
else
  fail "knowledge/ 外 → 出力あり: $result"
fi

# --- テスト4: decisions/ への作業ブランチ直書き → deny ---
echo ""
echo "--- テスト4: decisions/ deny ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cfo/decisions/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "作業ブランチ decisions/ → deny"
else
  fail "作業ブランチ decisions/ deny されない: $result"
fi

# --- テスト5: decisions-index.md → deny ---
echo ""
echo "--- テスト5: decisions-index.md deny ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/sm/decisions-index.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "作業ブランチ decisions-index.md → deny"
else
  fail "作業ブランチ decisions-index.md deny されない: $result"
fi

# --- テスト6: audit-cost / audit-security → deny ---
echo ""
echo "--- テスト6: audit-*.md deny ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/accounting/audit-2026-04-29.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "accounting/audit-*.md → deny"
else
  fail "accounting/audit-*.md deny されない: $result"
fi

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/security/audit-2026-04-29.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "security/audit-*.md → deny"
else
  fail "security/audit-*.md deny されない: $result"
fi

# --- テスト7: パストラバーサル（../） → realpath 正規化後の判定で deny ---
echo ""
echo "--- テスト7: パストラバーサル ---"

# 仮想 buffer 配下から ../ で workdir 直書きを試みる
fake_buffer="${HOME}/.cache/vibecorp/buffer-worktree/test-repo-traversal"
mkdir -p "$fake_buffer"
evil_path="${fake_buffer}/../../../../tmp/.claude/knowledge/cfo/decisions/2026-Q2.md"
result=$(run_hook "$evil_path")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "パストラバーサル経路 → realpath 正規化後 deny"
else
  fail "パストラバーサル経路 deny されない: $result"
fi
rm -rf "$fake_buffer"

# --- テスト8a: harvest-all-active スタンプあり + 非 deny 対象 → 許可 ---
echo ""
echo "--- テスト8a: スタンプあり + 非 deny 対象 ---"

# スタンプ作成
. "${PROJECT_DIR}/templates/claude/lib/common.sh"
stamp_dir="$(vibecorp_state_mkdir)"
touch "${stamp_dir}/harvest-all-active"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cfo/index.md")
if [ -z "$result" ]; then
  pass "スタンプあり + 非 deny 対象 → 通過"
else
  fail "スタンプあり + 非 deny 対象 通過しない: $result"
fi

# --- テスト8b: スタンプあり + decisions/ → fail-secure deny ---
result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cfo/decisions/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "スタンプあり + decisions/ → fail-secure deny"
else
  fail "スタンプあり + decisions/ deny されない（fail-secure 違反）: $result"
fi

rm -f "${stamp_dir}/harvest-all-active"

# --- テスト9: knowledge/ の decisions/audit 以外 → 通過 ---
echo ""
echo "--- テスト9: knowledge/ の decisions/audit 以外 ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cfo/index.md")
if [ -z "$result" ]; then
  pass "knowledge/cfo/index.md → 通過"
else
  fail "knowledge/cfo/index.md 通過しない: $result"
fi

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cto/topic.md")
if [ -z "$result" ]; then
  pass "knowledge/cto/topic.md → 通過"
else
  fail "knowledge/cto/topic.md 通過しない: $result"
fi

# --- テスト10: realpath フォールバック（Python 代替） ---
echo ""
echo "--- テスト10: Python フォールバック同等性 ---"

# 関数定義のみを抽出した一時ファイルを作る
fn_file="${TMPDIR_ROOT}/_pkw_fn.sh"
awk '/^_pkw_normalize_path\(\)/,/^}$/' "$HOOK_FILE" > "$fn_file"

# native realpath -m が利用可能か判定
if realpath -m / >/dev/null 2>&1; then
  # native の場合は native の出力と Python の出力が一致するか確認
  python_result=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' '/foo/../bar/./baz' 2>/dev/null || echo "FAIL")
  native_result=$(realpath -m -- '/foo/../bar/./baz' 2>/dev/null || echo "FAIL")
  if [ "$python_result" = "$native_result" ] && [ "$python_result" = "/bar/baz" ]; then
    pass "Python と native realpath が同等の結果を返す（${python_result}）"
  else
    fail "Python と native の結果が異なる（python=${python_result}, native=${native_result}, 期待=/bar/baz）"
  fi
else
  # native が無い場合は関数自体を実行して Python フォールバックの動作を確認
  result=$(bash -c "source '${fn_file}'; _pkw_normalize_path '/foo/../bar/./baz'" 2>/dev/null || echo "FAIL")
  if [ "$result" = "/bar/baz" ]; then
    pass "Python フォールバック単独で /foo/../bar/./baz → /bar/baz"
  else
    fail "Python フォールバック結果が期待外: $result（期待: /bar/baz）"
  fi
fi

# --- テスト11: deny メッセージの可読性 ---
echo ""
echo "--- テスト11: deny メッセージ可読性 ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/cfo/decisions/2026-Q2.md")

if [[ "$result" == *"復旧手順:"* ]]; then
  pass "deny メッセージに「復旧手順:」を含む"
else
  fail "deny メッセージに「復旧手順:」がない"
fi

if [[ "$result" == *"knowledge_buffer_ensure"* ]]; then
  pass "deny メッセージに「knowledge_buffer_ensure」を含む"
else
  fail "deny メッセージに「knowledge_buffer_ensure」がない"
fi

if [[ "$result" == *"/vibecorp:"* ]]; then
  pass "deny メッセージにスキル名「/vibecorp:」を含む"
else
  fail "deny メッセージにスキル名がない"
fi

print_test_summary
