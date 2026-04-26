#!/bin/bash
# test_issue.sh — /vibecorp:issue スキルの統合テスト
# 使い方: bash tests/test_issue.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/issue/SKILL.md"

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: $path)"
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
  fi
}

# ============================================
echo "=== /vibecorp:issue スキル テスト ==="
# ============================================

# --- SKILL.md の存在確認 ---

echo "--- SKILL.md の存在確認 ---"

# 1. SKILL.md が存在する
assert_file_exists "SKILL.md が存在する" "$SKILL_MD"

# --- SKILL.md の frontmatter ---

echo "--- frontmatter ---"

# 2. name が定義されている
assert_file_contains "frontmatter に name: issue がある" "$SKILL_MD" "^name: issue"

# 3. description が定義されている
assert_file_contains "frontmatter に description がある" "$SKILL_MD" "^description:"

# --- ワークフローの必須ステップ ---

echo "--- ワークフローの必須ステップ ---"

# 4. リポジトリ情報の取得ステップがある
assert_file_contains "リポジトリ情報の取得ステップがある" "$SKILL_MD" "リポジトリ情報の取得"

# 5. ユーザーヒアリングステップがある
assert_file_contains "ユーザーヒアリングステップがある" "$SKILL_MD" "ユーザーから Issue 内容を取得"

# 6. タイプ判定ステップがある
assert_file_contains "タイプ判定ステップがある" "$SKILL_MD" "タイプ判定"

# 7. Assignees 決定ステップがある
assert_file_contains "Assignees 決定ステップがある" "$SKILL_MD" "Assignees 決定"

# 8. 3者承認ゲートステップがある
assert_file_contains "3者承認ゲートステップがある" "$SKILL_MD" "3者承認ゲート"

# 9. Issue 起票ステップがある
assert_file_contains "Issue 起票ステップがある" "$SKILL_MD" "Issue 起票"

# 10. 結果報告ステップがある
assert_file_contains "結果報告ステップがある" "$SKILL_MD" "結果報告"

# --- 3者承認ゲート（CISO + CPO + SM） ---

echo "--- 3者承認ゲート（CISO + CPO + SM） ---"

# 11. preset 確認のコマンドがある
assert_file_contains "preset 確認のコマンドがある" "$SKILL_MD" "preset"

# 12. standard 以上の条件がある
assert_file_contains "standard 以上の条件がある" "$SKILL_MD" "standard"

# 13. minimal スキップの記述がある
assert_file_contains "minimal スキップの記述がある" "$SKILL_MD" "minimal"

# 14. preset キー未定義時のスキップ記述がある
assert_file_contains "preset キー未定義時のスキップ記述がある" "$SKILL_MD" "preset キーが未定義"

# 15. CISO エージェントの参照がある
assert_file_contains "CISO エージェントの参照がある" "$SKILL_MD" "ciso.md"

# 16. CPO エージェントの参照がある
assert_file_contains "CPO エージェントの参照がある" "$SKILL_MD" "cpo.md"

# 17. SM エージェントの参照がある
assert_file_contains "SM エージェントの参照がある" "$SKILL_MD" "sm.md"

# 18. autonomous-restrictions.md への参照がある
assert_file_contains "autonomous-restrictions.md への参照がある" "$SKILL_MD" "autonomous-restrictions.md"

# 19. 不可領域 認証 が記載されている
assert_file_contains "不可領域「認証」が記載されている" "$SKILL_MD" "認証"

# 20. 不可領域 暗号 が記載されている
assert_file_contains "不可領域「暗号」が記載されている" "$SKILL_MD" "暗号"

# 21. 不可領域 課金構造 が記載されている
assert_file_contains "不可領域「課金構造」が記載されている" "$SKILL_MD" "課金構造"

# 22. 不可領域 ガードレール が記載されている
assert_file_contains "不可領域「ガードレール」が記載されている" "$SKILL_MD" "ガードレール"

# 23. 不可領域 MVV が記載されている
assert_file_contains "不可領域「MVV」が記載されている" "$SKILL_MD" "MVV"

# 24. MVV チェック観点がある（CPO フィルタ）
assert_file_contains "MVV チェック観点がある" "$SKILL_MD" "MVV.md"

# 25. 却下時の返却フォーマットがある
assert_file_contains "却下時の返却フォーマットがある" "$SKILL_MD" "起票を見送りました"

# 26. 却下時に CISO/CPO/SM の判定結果を表示する
assert_file_contains "却下時に CISO/CPO/SM の判定結果を表示する" "$SKILL_MD" "CISO:"

# 27. minimal プリセットでの安全性根拠が明記されている
assert_file_contains "minimal プリセットの安全性根拠が記載されている" "$SKILL_MD" "minimal プリセットの安全性"

# --- 制約 ---

echo "--- 制約 ---"

# 18. jq の string interpolation 禁止がある
assert_file_contains "jq の string interpolation 禁止がある" "$SKILL_MD" "string interpolation"

# 19. コマンドそのまま実行の制約がある
assert_file_contains "コマンドそのまま実行の制約がある" "$SKILL_MD" "コマンドをそのまま実行する"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
