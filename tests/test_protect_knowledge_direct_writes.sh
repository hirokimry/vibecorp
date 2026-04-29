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
# テスト中に作成されるスタンプファイルのトラッキング
HARVEST_STAMP_FILE=""
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
  # テスト失敗時にスタンプファイルが残らないよう削除
  if [ -n "$HARVEST_STAMP_FILE" ]; then
    rm -f "$HARVEST_STAMP_FILE" || true
  fi
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
  # exit status を握り潰さないために || true は使わない。
  # 呼出元側で stdout の有無 + パターンマッチで判定する。
  echo "$input" | bash "$HOOK_FILE" 2>/dev/null
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

# --- テスト3b: 正規 buffer worktree 配下の decisions/ → 許可（ポジティブケース） ---
echo ""
echo "--- テスト3b: 正規 buffer 配下の decisions/ 許可 ---"

# 実 buffer worktree パスを取得（vibecorp_cache_root ベース）
. "${PROJECT_DIR}/templates/claude/lib/common.sh"
buffer_root="$(vibecorp_cache_root)/vibecorp/buffer-worktree"
mkdir -p "${buffer_root}/test-allow-positive/.claude/knowledge/cfo/decisions"
positive_path="${buffer_root}/test-allow-positive/.claude/knowledge/cfo/decisions/2026-Q2.md"

# hook は knowledge_buffer_worktree_dir で「現在のリポジトリの buffer」を判定する
# テストでは別の repo-id で擬似的に作るため、hook が「許可」するのは実際の buffer のみ。
# よってこのケースは fake_buffer 的に「期待 prefix と一致する別パス」を許可するわけではない。
# 代わりに、現在のリポジトリの buffer worktree ディレクトリパスを使う。
real_buffer_dir="$(. "${PROJECT_DIR}/templates/claude/lib/knowledge_buffer.sh" && knowledge_buffer_worktree_dir)"
mkdir -p "${real_buffer_dir}/.claude/knowledge/cfo/decisions"
positive_in_real="${real_buffer_dir}/.claude/knowledge/cfo/decisions/2026-Q2.md"

result=$(run_hook "$positive_in_real")
if [ -z "$result" ]; then
  pass "正規 buffer worktree 配下の decisions/ → 許可（ポジティブテスト）"
else
  fail "正規 buffer worktree 配下の decisions/ が deny された: $result"
fi

rm -rf "${buffer_root}/test-allow-positive"

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

# --- テスト6: audit-log/ → deny（Issue #442 で audit-*.md → audit-log/* に移行） ---
echo ""
echo "--- テスト6: {role}/audit-log/ deny ---"

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/accounting/audit-log/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "accounting/audit-log/2026-Q2.md → deny"
else
  fail "accounting/audit-log/2026-Q2.md deny されない: $result"
fi

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/accounting/audit-log/audit-log-index.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "accounting/audit-log/audit-log-index.md → deny"
else
  fail "accounting/audit-log/audit-log-index.md deny されない: $result"
fi

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/security/audit-log/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "security/audit-log/2026-Q2.md → deny"
else
  fail "security/audit-log/2026-Q2.md deny されない: $result"
fi

result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/legal/audit-log/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "legal/audit-log/2026-Q2.md → deny"
else
  fail "legal/audit-log/2026-Q2.md deny されない: $result"
fi

# 旧パターン（audit-*.md フラット）は新構造で存在しないため deny テスト対象外

# --- テスト7: パストラバーサル（../） → realpath 正規化後の判定で deny ---
echo ""
echo "--- テスト7: パストラバーサル ---"

# 仮想 buffer 配下から ../ で workdir 直書きを試みる
# TMPDIR_ROOT 内に作成すれば cleanup trap で自動削除される
fake_buffer="${TMPDIR_ROOT}/fake-buffer-worktree"
mkdir -p "$fake_buffer"
evil_path="${fake_buffer}/../../../../tmp/.claude/knowledge/cfo/decisions/2026-Q2.md"
result=$(run_hook "$evil_path")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "パストラバーサル経路 → realpath 正規化後 deny"
else
  fail "パストラバーサル経路 deny されない: $result"
fi

# --- テスト8a: harvest-all-active スタンプあり + 非 deny 対象 → 許可 ---
echo ""
echo "--- テスト8a: スタンプあり + 非 deny 対象 ---"

# スタンプ作成（HARVEST_STAMP_FILE に記録して cleanup trap で削除）
. "${PROJECT_DIR}/templates/claude/lib/common.sh"
stamp_dir="$(vibecorp_state_mkdir)"
HARVEST_STAMP_FILE="${stamp_dir}/harvest-all-active"
touch "$HARVEST_STAMP_FILE"

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

# --- テスト8c: スタンプあり + audit-log/ → fail-secure deny（Issue #442） ---
result=$(run_hook "${TMPDIR_ROOT}/.claude/knowledge/accounting/audit-log/2026-Q2.md")
if [[ "$result" == *'"permissionDecision":'*'"deny"'* ]]; then
  pass "スタンプあり + audit-log/ → fail-secure deny"
else
  fail "スタンプあり + audit-log/ deny されない（fail-secure 違反）: $result"
fi

rm -f "$HARVEST_STAMP_FILE"
HARVEST_STAMP_FILE=""

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

# --- テスト10: realpath フォールバック（Python 代替）— 常に検証 ---
# Issue #448 で _pkw_normalize_path は lib/path_normalize.sh に共通化された
echo ""
echo "--- テスト10: Python フォールバック常時検証 ---"

LIB_FILE="${PROJECT_DIR}/templates/claude/lib/path_normalize.sh"

# realpath を PATH から外して Python フォールバック経路を強制実行
# 「native が使える環境では未検証」という穴を塞ぐ
empty_path="${TMPDIR_ROOT}/empty-bin"
mkdir -p "$empty_path"
# 必要最小限のコマンドだけ symlink（realpath は除外）
for cmd in bash python3 command; do
  cmd_path="$(command -v "$cmd" 2>/dev/null)"
  if [ -n "$cmd_path" ]; then
    ln -sf "$cmd_path" "${empty_path}/${cmd}" 2>/dev/null || true
  fi
done

fallback_result=$(PATH="$empty_path" bash -c "source '${LIB_FILE}'; _pkw_normalize_path '/foo/../bar/./baz'" 2>/dev/null || echo "FAIL")
if [ "${fallback_result}" = "/bar/baz" ]; then
  pass "Python フォールバック（realpath 不在強制）で /foo/../bar/./baz → /bar/baz"
else
  fail "Python フォールバック結果が期待外: ${fallback_result}（期待: /bar/baz）"
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

# C*O フォールバック失敗時の strict header 自体は deny メッセージには含めない（C*O 出力側の責務）。
# ただし呼出元スキルが grep する厳格ヘッダ「### 判断記録（記録先取得失敗）」が
# 関連 SKILL.md に正しく書かれていることを確認する。
SPEC_FILE_FOR_HEADER="${PROJECT_DIR}/skills/audit-cost/SKILL.md"
if grep -F '### 判断記録（記録先取得失敗）' "$SPEC_FILE_FOR_HEADER" >/dev/null 2>&1; then
  pass "audit-cost SKILL.md に厳格ヘッダ「### 判断記録（記録先取得失敗）」が存在する"
else
  fail "audit-cost SKILL.md に厳格ヘッダがない"
fi

# --- テスト12: templates / 本体 同期検証（Issue #442） ---
echo ""
echo "--- テスト12: templates と本体の hook 同期 ---"

BODY_HOOK_FILE="${PROJECT_DIR}/.claude/hooks/protect-knowledge-direct-writes.sh"
if [ -f "$BODY_HOOK_FILE" ]; then
  if diff -q "$HOOK_FILE" "$BODY_HOOK_FILE" >/dev/null 2>&1; then
    pass "templates と本体の hook が同一"
  else
    fail "templates と本体の hook が乖離している（diff があります）"
  fi
else
  pass "本体 hook 未配置（dogfood 環境のみ存在、新規 install では templates から配布）"
fi

print_test_summary
