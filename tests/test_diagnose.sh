#!/bin/bash
# test_diagnose.sh — /vibecorp:diagnose スキルの統合テスト
# 使い方: bash tests/test_diagnose.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/diagnose/SKILL.md"

assert_file_not_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    fail "$desc (パターン '$pattern' がファイルに含まれる: $path)"
  else
    pass "$desc"
  fi
}

# ============================================
echo "=== /vibecorp:diagnose スキル テスト ==="
# ============================================

# --- SKILL.md の存在確認 ---

echo "--- SKILL.md の存在確認 ---"

# 1. SKILL.md が存在する
assert_file_exists "SKILL.md が存在する" "$SKILL_MD"

# --- SKILL.md の frontmatter ---

echo "--- frontmatter ---"

# 2. name が定義されている
assert_file_contains "frontmatter に name: diagnose がある" "$SKILL_MD" "^name: diagnose"

# 3. description が定義されている
assert_file_contains "frontmatter に description がある" "$SKILL_MD" "^description:"

# --- ワークフローの必須ステップ ---

echo "--- ワークフローの必須ステップ ---"

# 4. プリセット確認ステップがある
assert_file_contains "プリセット確認ステップがある" "$SKILL_MD" "プリセット確認"

# 5. full プリセット専用の記述がある
assert_file_contains "full プリセット専用の記述がある" "$SKILL_MD" "full プリセット専用"

# 6. diagnose-active スタンプ作成がある
assert_file_contains "diagnose-active スタンプ作成がある" "$SKILL_MD" "diagnose-active"

# 7. /vibecorp:harvest-all --dry-run の呼び出しがある
assert_file_contains "/vibecorp:harvest-all --dry-run の呼び出しがある" "$SKILL_MD" "harvest-all --dry-run"

# 8. CISO フィルタリングがある
assert_file_contains "CISO フィルタリングがある" "$SKILL_MD" "CISO"

# 9. CPO フィルタリングがある
assert_file_contains "CPO フィルタリングがある" "$SKILL_MD" "CPO"

# 9.1 CPO によるプロダクト整合分析（4c）がある
assert_file_contains "CPO プロダクト整合分析がある" "$SKILL_MD" "プロダクト整合分析"

# 9.2 3つの並行実行の記述がある
assert_file_contains "3つの並行実行がある" "$SKILL_MD" "3つを並行して実行する"

# 10. 起票上限チェックがある
assert_file_contains "起票上限チェックがある" "$SKILL_MD" "max_issues_per_run"

# 11. max_issues_per_day がある
assert_file_contains "max_issues_per_day がある" "$SKILL_MD" "max_issues_per_day"

# --- 暴走防止の記述 ---

echo "--- 暴走防止の記述 ---"

# 12. コード変更禁止の制約がある
assert_file_contains "コード変更禁止の制約がある" "$SKILL_MD" "コード変更は一切行わない"

# 13. forbidden_targets の記述がある
assert_file_contains "forbidden_targets の記述がある" "$SKILL_MD" "forbidden_targets"

# 14. スタンプ削除の記述がある
assert_file_contains "スタンプ削除の記述がある" "$SKILL_MD" "diagnose-active.*削除"

# --- --dry-run サポート ---

echo "--- --dry-run サポート ---"

# 15. --dry-run の使用方法がある
assert_file_contains "--dry-run の使用方法がある" "$SKILL_MD" "\-\-dry-run"

# 16. --scope の使用方法がある
assert_file_contains "--scope の使用方法がある" "$SKILL_MD" "\-\-scope"

# --- Issue 起票関連 ---

echo "--- Issue 起票関連 ---"

# 17. /vibecorp:issue スキルの呼び出しがある
assert_file_contains "/vibecorp:issue スキルの呼び出しがある" "$SKILL_MD" "/vibecorp:issue"

# 18. diagnose ラベルの付与がある
assert_file_contains "diagnose ラベルの付与がある" "$SKILL_MD" "diagnose"

# --- 制約 ---

echo "--- 制約 ---"

# 19. jq の string interpolation 禁止がある
assert_file_contains "jq の string interpolation 禁止がある" "$SKILL_MD" 'string interpolation'

# 20. コマンドそのまま実行の制約がある
assert_file_contains "コマンドそのまま実行の制約がある" "$SKILL_MD" "コマンドをそのまま実行する"

# --- state ファイル参照（XDG: ~/.cache/vibecorp/state/<repo-id>/diagnose-active） ---

echo "--- state ファイル参照 ---"

# 21. diagnose-active state ファイルを stamp_dir 経由で touch する
assert_file_contains "vibecorp_state_mkdir で state ディレクトリを作成する" "$SKILL_MD" "vibecorp_state_mkdir"
assert_file_contains "stamp_dir/diagnose-active を touch する" "$SKILL_MD" 'touch "\${stamp_dir}/diagnose-active"'

# 22. diagnose-active state ファイルを rm -f する
assert_file_contains "vibecorp_state_path diagnose-active を rm -f する" "$SKILL_MD" 'rm -f "\$(vibecorp_state_path diagnose-active)"'

# 23. 旧 .claude/state/diagnose-active パスが SKILL 内に残っていない（退行検知）
if ! grep -q '\.claude/state/diagnose-active' "$SKILL_MD"; then
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: 旧パス .claude/state/diagnose-active が SKILL に残っていない"
else
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: 旧パス .claude/state/diagnose-active が SKILL に残っている（退行）"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
