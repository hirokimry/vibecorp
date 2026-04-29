#!/bin/bash
# test_cycle_metrics.sh — Issue #353: /cycle-metrics スキルのテスト
# 使い方: bash tests/test_cycle_metrics.sh
#
# 検証内容:
#   1. ファイル存在: SKILL.md / 3 スクリプト / テンプレート / フィクスチャ
#   2. SKILL.md に full プリセット限定の記述
#   3. 全スクリプトが LLM 呼び出し（claude -p / npx / bunx）を含まない（MUST 強制）
#   4. スクリプトの --help が動作する
#   5. フィクスチャでレポート生成が成功し、必須セクションを含む

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SKILL_DIR="${PROJECT_DIR}/skills/cycle-metrics"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
FETCH_PR="${SKILL_DIR}/fetch-pr-metrics.sh"
FETCH_AGENT="${SKILL_DIR}/fetch-agent-metrics.sh"
GEN_REPORT="${SKILL_DIR}/generate-report.sh"
TEMPLATE="${PROJECT_DIR}/templates/claude/knowledge/accounting/cycle-metrics-template.md"
FIXTURE_PR="${PROJECT_DIR}/tests/fixtures/cycle_metrics/pr_list.json"
FIXTURE_JSONL="${PROJECT_DIR}/tests/fixtures/cycle_metrics/sample-session.jsonl"

TMPDIR_ROOT=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

echo "=== Issue #353: /cycle-metrics テスト ==="

# --- テスト1: ファイル存在 ---
echo ""
echo "--- テスト1: ファイル存在 ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

assert_file_exists "fetch-pr-metrics.sh が存在する" "$FETCH_PR"
assert_file_exists "fetch-agent-metrics.sh が存在する" "$FETCH_AGENT"
assert_file_exists "generate-report.sh が存在する" "$GEN_REPORT"
assert_file_exists "cycle-metrics-template.md が存在する" "$TEMPLATE"
assert_file_exists "pr_list.json フィクスチャが存在する" "$FIXTURE_PR"
assert_file_exists "sample-session.jsonl フィクスチャが存在する" "$FIXTURE_JSONL"

# --- テスト2: 実行権限 ---
echo ""
echo "--- テスト2: 実行権限 ---"

assert_file_executable "fetch-pr-metrics.sh が実行可能" "$FETCH_PR"
assert_file_executable "fetch-agent-metrics.sh が実行可能" "$FETCH_AGENT"
assert_file_executable "generate-report.sh が実行可能" "$GEN_REPORT"

# --- テスト3: full プリセット限定 ---
echo ""
echo "--- テスト3: full プリセット限定 ---"

assert_file_contains "SKILL.md に full プリセット専用記述がある" "$SKILL_FILE" "full プリセット専用"
assert_file_contains "SKILL.md に preset 検出 awk がある" "$SKILL_FILE" "awk '/\^preset:"

# --- テスト4: ヘッドレス Claude 起動禁止（MUST） ---
echo ""
echo "--- テスト4: LLM 呼び出し非含有（MUST 受入基準） ---"

# 全スクリプトに対して claude -p / npx <cmd> / bunx <cmd> が含まれないことを検証する。
# 検査範囲は「実コード行のみ」とし、コメント行（行頭が任意の空白の後 #）は除外する。
# MUST 注記をスクリプト先頭のコメントに書く運用を許容するための除外。
check_no_llm_call() {
  local script="$1"
  local pattern="$2"
  local label="$3"
  local name
  name=$(basename "$script")

  # コメント行を除く実コードに pattern が含まれるか
  if grep -nvE '^[[:space:]]*#' "$script" | grep -qE -e "$pattern"; then
    fail "${name} に '${label}' 呼び出しが含まれている（MUST 違反）"
  else
    pass "${name} に '${label}' 呼び出しが含まれない"
  fi
}

for script in "$FETCH_PR" "$FETCH_AGENT" "$GEN_REPORT"; do
  check_no_llm_call "$script" 'claude[[:space:]]+-p( |$)' 'claude -p'
  check_no_llm_call "$script" 'npx[[:space:]]+@?[A-Za-z]' 'npx <pkg>'
  check_no_llm_call "$script" 'bunx[[:space:]]+@?[A-Za-z]' 'bunx <pkg>'
done

# --- テスト5: --help 動作 ---
echo ""
echo "--- テスト5: --help 動作 ---"

for script in "$FETCH_PR" "$FETCH_AGENT" "$GEN_REPORT"; do
  name=$(basename "$script")
  # --help は引数不足とは別経路で 0 終了する想定（generate-report.sh は引数必須なので usage で exit 2）
  set +e
  if [[ "$script" == "$GEN_REPORT" ]]; then
    bash "$script" >/dev/null 2>&1
    actual=$?
    set -e
    assert_exit_code "${name} は引数不足で usage を返す（exit 2）" 2 "$actual"
  else
    bash "$script" --help >/dev/null 2>&1
    actual=$?
    set -e
    assert_exit_code "${name} --help が exit 0" 0 "$actual"
  fi
done

# --- テスト6: PR メトリクス変換 ---
echo ""
echo "--- テスト6: PR メトリクス変換（fixture） ---"

PR_OUT="${TMPDIR_ROOT}/pr.json"
if bash "$FETCH_PR" --from-fixture "$FIXTURE_PR" > "$PR_OUT" 2>"${TMPDIR_ROOT}/pr.err"; then
  pass "fetch-pr-metrics.sh がフィクスチャを変換できる"
else
  fail "fetch-pr-metrics.sh がフィクスチャ変換に失敗（stderr: $(cat "${TMPDIR_ROOT}/pr.err"))"
fi

PR_COUNT=$(jq 'length' "$PR_OUT" 2>/dev/null || echo "0")
assert_eq "PR メトリクスが3件出力される" "3" "$PR_COUNT"

ISSUE_NUM=$(jq -r '.[0].issue_number' "$PR_OUT" 2>/dev/null || echo "")
assert_eq "PR #421 から Issue 番号 350 が抽出される" "350" "$ISSUE_NUM"

TOTAL_SEC=$(jq -r '.[0].total_seconds' "$PR_OUT" 2>/dev/null || echo "")
# 2026-04-20T05:30:00Z - 2026-04-20T01:00:00Z = 4.5 時間 = 16200 秒
assert_eq "PR #421 の総所要時間が 16200 秒" "16200" "$TOTAL_SEC"

NULL_ISSUE=$(jq -r '.[2].issue_number' "$PR_OUT" 2>/dev/null || echo "")
assert_eq "Issue 番号なしブランチは null" "null" "$NULL_ISSUE"

# --- テスト7: Agent メトリクス集計 ---
echo ""
echo "--- テスト7: Agent メトリクス集計（fixture） ---"

AGENT_OUT="${TMPDIR_ROOT}/agent.json"
if bash "$FETCH_AGENT" --from-fixture "$FIXTURE_JSONL" > "$AGENT_OUT" 2>"${TMPDIR_ROOT}/agent.err"; then
  pass "fetch-agent-metrics.sh がフィクスチャを集計できる"
else
  fail "fetch-agent-metrics.sh がフィクスチャ集計に失敗（stderr: $(cat "${TMPDIR_ROOT}/agent.err"))"
fi

BRANCH_COUNT=$(jq '.branches | length' "$AGENT_OUT" 2>/dev/null || echo "0")
# main ブランチは除外され dev/350 と dev/351 の2ブランチのみ
assert_eq "dev/ プレフィックス付きブランチ2件のみ集計" "2" "$BRANCH_COUNT"

SIDECHAIN_350=$(jq -r '.branches[] | select(.issue_number == 350) | .sidechain_count' "$AGENT_OUT" 2>/dev/null || echo "")
assert_eq "dev/350 の sidechain_count が 2" "2" "$SIDECHAIN_350"

SUBAGENT_EXPLORE=$(jq -r '.branches[] | select(.issue_number == 350) | .subagent_types["Explore"]' "$AGENT_OUT" 2>/dev/null || echo "")
assert_eq "dev/350 で Explore サブエージェント呼び出しが 1 回" "1" "$SUBAGENT_EXPLORE"

# --- テスト8: レポート生成 ---
echo ""
echo "--- テスト8: レポート生成 ---"

REPORT_OUT="${TMPDIR_ROOT}/cycle-metrics-test.md"
if bash "$GEN_REPORT" "$PR_OUT" "$AGENT_OUT" "$REPORT_OUT" >/dev/null 2>"${TMPDIR_ROOT}/report.err"; then
  pass "generate-report.sh がレポート生成に成功"
else
  fail "generate-report.sh がレポート生成に失敗（stderr: $(cat "${TMPDIR_ROOT}/report.err"))"
fi

assert_file_exists "レポートファイルが作成される" "$REPORT_OUT"
assert_file_contains "レポートに PR サマリ節がある" "$REPORT_OUT" "## PR サマリ"
assert_file_contains "レポートに PR 別詳細節がある" "$REPORT_OUT" "## PR 別詳細"
assert_file_contains "レポートにエージェント節がある" "$REPORT_OUT" "## エージェント・トークン消費"
assert_file_contains "レポートにモデル別集計節がある" "$REPORT_OUT" "## モデル別集計"
assert_file_contains "レポートにボトルネック節がある" "$REPORT_OUT" "## ボトルネック"
assert_file_contains "レポートにサブエージェント別節がある" "$REPORT_OUT" "## サブエージェント別呼び出し回数"

# --- テスト9: 出力ファイル名規約（Issue #442 で揮発データ ~/.cache/ 移行） ---
echo ""
echo "--- テスト9: 出力ファイル名規約 ---"

assert_file_contains "SKILL.md に YYYY-MM-DD.md の保存先記述がある" "$SKILL_FILE" "YYYY-MM-DD.md"
assert_file_contains "SKILL.md に ~/.cache/vibecorp/state/ パス記述がある" "$SKILL_FILE" "~/.cache/vibecorp/state/"
assert_file_contains "SKILL.md に cycle-metrics ディレクトリ参照がある" "$SKILL_FILE" "/cycle-metrics/"
assert_file_contains "SKILL.md に vibecorp_state_dir ヘルパー利用がある" "$SKILL_FILE" "vibecorp_state_dir"

# --- テスト10: テンプレートに必須セクション ---
echo ""
echo "--- テスト10: テンプレート構造 ---"

assert_file_contains "テンプレートに PR サマリ節がある" "$TEMPLATE" "## PR サマリ"
assert_file_contains "テンプレートにエージェント節がある" "$TEMPLATE" "## エージェント・トークン消費"
assert_file_contains "テンプレートにボトルネック節がある" "$TEMPLATE" "## ボトルネック"

# --- テスト11: buffer worktree / .claude/knowledge/ 非対象明文化（Issue #442） ---
echo ""
echo "--- テスト11: buffer worktree / .claude/knowledge/ 非対象の明文化 ---"

assert_file_contains "SKILL.md に「buffer worktree / .claude/knowledge/ への保存はしない」セクションがある" "$SKILL_FILE" "buffer worktree / .claude/knowledge/ への保存はしない"
assert_file_contains "SKILL.md に揮発データの説明がある" "$SKILL_FILE" "揮発データ"
assert_file_contains "SKILL.md にフックの deny パターン外であることの記載がある" "$SKILL_FILE" "protect-knowledge-direct-writes.sh"

print_test_summary
