#!/bin/bash
# test_diagnose_speed_ux.sh — /vibecorp:diagnose のスピード/UX 観点（Issue #355）
# 使い方: bash tests/test_diagnose_speed_ux.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/diagnose/SKILL.md"
PASSED=0
FAILED=0
TOTAL=0

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -- "$pattern" "$path"; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
  fi
}

# ============================================
echo "=== /vibecorp:diagnose スピード/UX 観点 テスト（Issue #355） ==="
# ============================================

# 前提ファイル不在は後続テストを無意味にするため早期終了する（rules/testing.md 準拠）
if [[ ! -f "$SKILL_MD" ]]; then
  fail "SKILL.md が存在しない: $SKILL_MD"
  exit 1
fi
pass "SKILL.md が存在する"

# --- 受入基準: SKILL.md 上部に「モデル指定・コスト最適化に踏み込まない」旨の明記 ---

echo "--- 上部明記（受入基準3） ---"

assert_file_contains "上部に「モデル指定・コスト最適化には一切踏み込まない」旨が記載されている" \
  "$SKILL_MD" "モデル指定・コスト最適化には一切踏み込まない"

# --- 受入基準: ステップ4a/4b（CTO 分析）にスピード/UX 観点のチェックリスト ---

echo "--- CTO 分析プロンプトのスピード/UX チェックリスト（受入基準1） ---"

assert_file_contains "CTO 分析プロンプトに「スピード/UX」見出しがある" \
  "$SKILL_MD" "スピード/UX"

assert_file_contains "観点: 並列化可能な逐次処理" \
  "$SKILL_MD" "並列化可能な逐次処理"

assert_file_contains "観点: 同期待ちが長いフェーズ" \
  "$SKILL_MD" "同期待ちが長いフェーズ"

assert_file_contains "観点: フック実行時間の肥大化" \
  "$SKILL_MD" "フック実行時間の肥大化"

assert_file_contains "観点: スキル間の冗長な再実行" \
  "$SKILL_MD" "スキル間の冗長な再実行"

# --- CTO 分析プロンプトの禁止事項（CFO 管轄に閉じ込める） ---

echo "--- CTO 分析プロンプトの禁止事項 ---"

assert_file_contains "禁止: モデル指定の変更提案" \
  "$SKILL_MD" "モデル指定の変更提案（Opus → Sonnet 等）は出さない"

assert_file_contains "禁止: エージェント削減・合議制回数削減" \
  "$SKILL_MD" "エージェント削減・合議制回数削減は出さない"

assert_file_contains "禁止: 並列度自体の削減" \
  "$SKILL_MD" "並列度自体の削減は出さない"

assert_file_contains "禁止: max_issues_per_run コスト上限値の変更" \
  "$SKILL_MD" "max_issues_per_run"

# --- 受入基準: SM フィルタ（ステップ6b）でモデル指定変更・エージェント削減が除外される ---

echo "--- SM フィルタプロンプトの追加除外項目（受入基準2） ---"

# §3 課金構造に「モデル指定の変更」が明示されていることを確認
assert_file_contains "SM フィルタ §3 課金構造に「モデル指定の変更」が明示されている" \
  "$SKILL_MD" "モデル指定の変更（Opus → Sonnet 等）"

# §4 ガードレールに「エージェント削減・合議制回数削減・並列度自体の削減」が明示されていることを確認
assert_file_contains "SM フィルタ §4 ガードレールに「エージェント削減・合議制回数削減・並列度自体の削減」が明示されている" \
  "$SKILL_MD" "エージェント削減・合議制回数削減・並列度自体の削減"

# モデル指定変更の候補が SM フィルタの不可領域記述に到達するための前提（ステップ6bプロンプトが課金構造を列挙していること）
assert_file_contains "SM フィルタプロンプトに不可領域 3. 課金構造の記述がある" \
  "$SKILL_MD" "3. 課金構造"

assert_file_contains "SM フィルタプロンプトに不可領域 4. ガードレールの記述がある" \
  "$SKILL_MD" "4. ガードレール"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
