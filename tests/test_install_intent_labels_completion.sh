#!/bin/bash
# test_install_intent_labels_completion.sh
# ─────────────────────────────────────────────
# Issue #469 リオープン後の追加実装を検証
# - revert を intent/bugfix に統一（両 docs 整合）
# - CC 11 種厳格定義の細部追加
# - 主従関係（絶対条件）の追加項目
# - intent-labels.md の挙動不変性確認・3 者ゲート連携・役割分離
# - 残 #3 Issue 側 intent ラベル必須化 hook
# - 残 #5 PR Issue 番号必須化 hook
# - 残 #4 backfill スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

assert_file_contains_fixed() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q -F -- "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '${pattern}' がファイルに含まれない: ${path})"
  fi
}

echo ""
echo "=== Issue #469 完成度検証 ==="

# ============================================
# 1. revert を intent/bugfix に統一
# ============================================
echo ""
echo "--- 1. revert の intent/bugfix 統一 ---"

assert_file_contains_fixed "docs: revert に intent/bugfix 明記" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "intent/bugfix"

if grep -q -F -- "対象外（intent ラベル付与なし）" "${SCRIPT_DIR}/docs/conventional-commits.md"; then
  fail "docs: 旧「対象外」表記が残っている"
else
  pass "docs: 旧「対象外」表記が削除された"
fi

assert_file_contains_fixed "rules: revert PR にも intent/bugfix" \
  "${SCRIPT_DIR}/.claude/rules/intent-labels.md" \
  "intent/bugfix"

# ============================================
# 2. CC 11 種厳格定義の細部追加
# ============================================
echo ""
echo "--- 2. CC 11 種厳格定義の細部 ---"

assert_file_contains_fixed "fix: セキュリティ脆弱性も含む" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "セキュリティ脆弱性の修正もここに含める"

assert_file_contains_fixed "perf: 観測不可能な内部最適化のみは refactor" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "観測不可能な内部最適化のみで挙動完全不変なら"

assert_file_contains_fixed "refactor: 公開 API リネーム不可" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "公開 API のリネーム"

assert_file_contains_fixed "refactor: 内部関数のリネーム OK" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "内部関数のリネーム"

assert_file_contains_fixed "style: intent/refactor に統合" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "intent/refactor\` ラベルに統合される"

assert_file_contains_fixed "docs: サンプルコード本体影響時の扱い" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "docs 内のサンプルコード"

assert_file_contains_fixed "test: 本番コード修正は別 commit" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "テスト追加時に本番コードのバグも修正する場合は別 commit に分ける"

assert_file_contains_fixed "chore: 依存メジャー更新で API 変わる場合は不可" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "依存パッケージのメジャー更新で API が変わる"

# ============================================
# 3. 主従関係の追加項目
# ============================================
echo ""
echo "--- 3. 主従関係（絶対条件）追加項目 ---"

assert_file_contains_fixed "「prefix が複数 intent を持つ」見方禁止" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "prefix が複数 intent を持つ"

assert_file_contains_fixed "議論・設計の順序も主従に従う" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "議論・設計の順序も主従に従う"

assert_file_contains_fixed "違反時の影響例（security: 単独 prefix）" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "security:\` 単独 prefix を採用しない"

assert_file_contains_fixed "検証時に除外したエッジケース" \
  "${SCRIPT_DIR}/docs/conventional-commits.md" \
  "検証時にあえて除外したエッジケース"

# ============================================
# 4. intent-labels.md の追加項目
# ============================================
echo ""
echo "--- 4. intent-labels.md の追加項目 ---"

assert_file_contains_fixed "挙動不変性の確認 観点" \
  "${SCRIPT_DIR}/.claude/rules/intent-labels.md" \
  "挙動不変性の確認"

assert_file_contains_fixed "3 者承認ゲート（CISO/CPO/SM）連携" \
  "${SCRIPT_DIR}/.claude/rules/intent-labels.md" \
  "既存 3 者承認ゲート"

assert_file_contains_fixed "役割分離テーブル" \
  "${SCRIPT_DIR}/.claude/rules/intent-labels.md" \
  "intent 判定への関与"

# ============================================
# 5. 残 #3: Issue 側 intent ラベル必須化 hook
# ============================================
echo ""
echo "--- 5. 残 #3: Issue 側ラベル必須化ワークフロー ---"

assert_file_exists "templates 側に intent-label-issue-check.yml" \
  "${SCRIPT_DIR}/templates/.github/workflows/intent-label-issue-check.yml"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "配布側に intent-label-issue-check.yml" \
  "$R/.github/workflows/intent-label-issue-check.yml"
assert_file_contains "issues トリガー" \
  "$R/.github/workflows/intent-label-issue-check.yml" \
  "on:"
assert_file_contains "issues.opened トリガー対象" \
  "$R/.github/workflows/intent-label-issue-check.yml" \
  "opened"
assert_file_contains "0 件 fail 検知" \
  "$R/.github/workflows/intent-label-issue-check.yml" \
  'allowed_intent.*-eq 0'
assert_file_contains "2 件以上 fail 検知" \
  "$R/.github/workflows/intent-label-issue-check.yml" \
  'allowed_intent.*-gt 1'
assert_file_contains "未知 intent/* ラベル混入 fail 検知" \
  "$R/.github/workflows/intent-label-issue-check.yml" \
  'unknown_intent.*-gt 0'
cleanup

# ============================================
# 6. 残 #5: PR Issue 番号必須化 hook
# ============================================
echo ""
echo "--- 6. 残 #5: PR Issue 番号必須化ワークフロー ---"

assert_file_exists "templates 側に pr-issue-link-check.yml" \
  "${SCRIPT_DIR}/templates/.github/workflows/pr-issue-link-check.yml"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "配布側に pr-issue-link-check.yml" \
  "$R/.github/workflows/pr-issue-link-check.yml"
assert_file_contains "pull_request トリガー" \
  "$R/.github/workflows/pr-issue-link-check.yml" \
  "pull_request:"
assert_file_contains "Issue 参照キーワード grep" \
  "$R/.github/workflows/pr-issue-link-check.yml" \
  "close\\|fix\\|resolve\\|refs"
assert_file_contains "Fork PR 除外" \
  "$R/.github/workflows/pr-issue-link-check.yml" \
  "head.repo.full_name == github.repository"
cleanup

# ============================================
# 7. 残 #4: backfill スクリプト
# ============================================
echo ""
echo "--- 7. 残 #4: backfill スクリプト ---"

assert_file_exists "scripts/backfill-intent-labels.sh" "${SCRIPT_DIR}/scripts/backfill-intent-labels.sh"
assert_file_executable "実行権限あり" "${SCRIPT_DIR}/scripts/backfill-intent-labels.sh"
assert_file_contains "open Issue のみ対象（closed は触らない）" \
  "${SCRIPT_DIR}/scripts/backfill-intent-labels.sh" \
  "open"
assert_file_contains "intent ラベル 7 種を全て扱う" \
  "${SCRIPT_DIR}/scripts/backfill-intent-labels.sh" \
  "intent/feature"
assert_file_contains "--dry-run サポート" \
  "${SCRIPT_DIR}/scripts/backfill-intent-labels.sh" \
  "dry-run"

print_test_summary
