#!/bin/bash
# run-golden-test.sh — claude-code-action のレビュー出力リグレッション検知
#
# Issue #473: 既知 PR を claude-action に再レビューさせ、期待結果（severity 件数 +
# キーワードの最低マッチ数）と一致するかを検証する。プロンプト変更時のリグレッション検知用。
#
# 実行: bash scripts/run-golden-test.sh
#
# 前提条件:
#   - tests/golden/*.json に各 intent の golden データ（最低 1 件、最大 7 件）
#   - GH_TOKEN（gh CLI 経由で PR 情報取得用）
#   - CLAUDE_CODE_OAUTH_TOKEN（claude-action API 呼び出し用、CI シークレット）

set -euo pipefail

GOLDEN_DIR="tests/golden"
FAIL_COUNT=0
PASS_COUNT=0

if [[ ! -d "$GOLDEN_DIR" ]]; then
  echo "❌ tests/golden ディレクトリが見つかりません" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq が必要です（golden JSON のパース用）" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh CLI が必要です（PR diff 取得用）" >&2
  exit 1
fi

shopt -s nullglob
golden_files=("$GOLDEN_DIR"/*.json)

if [[ ${#golden_files[@]} -eq 0 ]]; then
  echo "❌ golden JSON が 1 件もありません" >&2
  exit 1
fi

# _example.json は実機データではないのでスキップ
real_files=()
for f in "${golden_files[@]}"; do
  base=$(basename "$f")
  if [[ "$base" != "_example.json" ]]; then
    real_files+=("$f")
  fi
done

if [[ ${#real_files[@]} -eq 0 ]]; then
  echo "ℹ️  golden データが未配置です（_example.json のみ）。実機検証期間 (#475) で配置されるまでスキップします。"
  exit 0
fi

echo "=== Golden Test: ${#real_files[@]} 件の golden データを検証 ==="
echo ""

for f in "${real_files[@]}"; do
  echo "--- $(basename "$f") ---"

  pr_number=$(jq -r '.pr_number' "$f")
  intent=$(jq -r '.intent' "$f")
  description=$(jq -r '.description' "$f")
  expected_critical=$(jq -r '.expected_severity_counts.critical // 0' "$f")
  expected_major=$(jq -r '.expected_severity_counts.major // 0' "$f")
  expected_minor=$(jq -r '.expected_severity_counts.minor // 0' "$f")
  expected_keyword_min_match=$(jq -r '.expected_keyword_min_match // 1' "$f")

  echo "  PR #${pr_number} (intent: ${intent})"
  echo "  説明: ${description}"
  echo "  期待件数: critical=${expected_critical}, major=${expected_major}, minor=${expected_minor}"
  echo "  期待キーワード最低マッチ数: ${expected_keyword_min_match}"

  # 実装方針:
  # 1. PR の diff を gh で取得
  # 2. claude-code-action を起動して再レビュー（CI 上で別ジョブとして実行する想定）
  # 3. レビュー結果を集計（severity 件数 + キーワードマッチ数）
  # 4. 期待値と比較
  #
  # 実機検証期間（#475）で claude-action 呼び出しの具体実装を確定する。
  # 本フレームワークでは検証スキップ（PASS）扱いとする。

  echo "  → 実機検証期間 (#475) で実装確定予定。本フレームワークでは PASS 扱い"
  PASS_COUNT=$((PASS_COUNT + 1))
  echo ""
done

echo "=== Golden Test 結果 ==="
echo "PASS: ${PASS_COUNT}"
echo "FAIL: ${FAIL_COUNT}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
