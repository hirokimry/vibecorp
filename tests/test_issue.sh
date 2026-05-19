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

# ============================================
echo "=== /vibecorp:issue スキル テスト ==="
# ============================================

echo "--- SKILL.md の存在確認 ---"

assert_file_exists "SKILL.md が存在する" "$SKILL_MD"

# --- SKILL.md の frontmatter ---

echo "--- frontmatter ---"

# 2. name が定義されている
assert_file_contains "frontmatter に name: issue がある" "$SKILL_MD" "^name: issue"

# 3. description が定義されている
assert_file_contains "frontmatter に description がある" "$SKILL_MD" "^description:"

echo "--- ワークフローの必須ステップ ---"

assert_file_contains "リポジトリ情報の取得ステップがある" "$SKILL_MD" "リポジトリ情報の取得"

assert_file_contains "ユーザーヒアリングステップがある" "$SKILL_MD" "ユーザーから Issue 内容を取得"

assert_file_contains "タイプ判定ステップがある" "$SKILL_MD" "タイプ判定"

assert_file_contains "Assignees 決定ステップがある" "$SKILL_MD" "Assignees 決定"

assert_file_contains "3者承認ゲートステップがある" "$SKILL_MD" "3者承認ゲート"

assert_file_contains "Issue 起票ステップがある" "$SKILL_MD" "Issue 起票"

assert_file_contains "結果報告ステップがある" "$SKILL_MD" "結果報告"

echo "--- 3者承認ゲート（CISO + CPO + SM） ---"

assert_file_contains "preset 確認のコマンドがある" "$SKILL_MD" "preset"

assert_file_contains "standard 以上の条件がある" "$SKILL_MD" "standard"

assert_file_contains "minimal スキップの記述がある" "$SKILL_MD" "minimal"

assert_file_contains "preset キー未定義時のスキップ記述がある" "$SKILL_MD" "preset キーが未定義"

assert_file_contains "CISO エージェントの参照がある" "$SKILL_MD" "ciso.md"

assert_file_contains "CPO エージェントの参照がある" "$SKILL_MD" "cpo.md"

assert_file_contains "SM エージェントの参照がある" "$SKILL_MD" "sm.md"

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

assert_file_contains "却下時の返却フォーマットがある" "$SKILL_MD" "起票を見送りました"

assert_file_contains "却下時に CISO/CPO/SM の判定結果を表示する" "$SKILL_MD" "CISO:"

# 27. minimal プリセットでの安全性根拠が明記されている
assert_file_contains "minimal プリセットの安全性根拠が記載されている" "$SKILL_MD" "minimal プリセットの安全性"

echo "--- SM 自動判定（エピック/単発ルーティング） ---"

assert_file_contains "SM 自動判定ステップが存在する" "$SKILL_MD" "SM 自動判定"

# 29. エピック/単発ルーティング の語が存在する
assert_file_contains "エピック/単発ルーティングの記述がある" "$SKILL_MD" "エピック/単発ルーティング"

# 30. 単発判定キーワード
assert_file_contains "単発判定キーワードがある" "$SKILL_MD" "単発判定"

# 31. エピック化判定キーワード
assert_file_contains "エピック化判定キーワードがある" "$SKILL_MD" "エピック化判定"

assert_file_contains "/plan-epic への参照がある" "$SKILL_MD" "plan-epic"

# 33. 判定基準: 複数要件の列挙
assert_file_contains "判定基準: 複数要件の列挙が記載されている" "$SKILL_MD" "複数要件の列挙"

# 34. 判定基準: ファイル領域の複数跨ぎ
assert_file_contains "判定基準: ファイル領域の複数跨ぎが記載されている" "$SKILL_MD" "ファイル領域の複数跨ぎ"

# 35. 判定基準: 並列実行可否
assert_file_contains "判定基準: 並列実行可否が記載されている" "$SKILL_MD" "並列実行可否"

assert_file_contains "CEO override セクションがある" "$SKILL_MD" "CEO override"

# 37. CEO override: 単発上書きの記述
assert_file_contains "CEO override: 単発上書きの記述がある" "$SKILL_MD" "単発でいい"

# 38. CEO override: エピック上書きの記述
assert_file_contains "CEO override: エピック上書きの記述がある" "$SKILL_MD" "エピックにして"

# 39. full プリセット限定が明記されている
assert_file_contains "full プリセット限定の記述がある" "$SKILL_MD" "\`full\` プリセット"

# 40. minimal / standard でスキップする旨
assert_file_contains "minimal / standard スキップの記述がある" "$SKILL_MD" "\`minimal\` / \`standard\`"

# 41. SM は 1 回のみ呼ぶ（合議なし）が明記されている
assert_file_contains "SM 1回のみ呼ぶ記述がある" "$SKILL_MD" "\*\*1 回だけ\*\*"

assert_file_contains "合議なしが明記されている" "$SKILL_MD" "合議は行わず"

assert_file_contains "/plan-epic 未配置時のフォールバックが明記されている" "$SKILL_MD" "plan-epic\` スキルが配置されていない場合"

# 44. 返却フォーマット（単発時）に判定結果セクションがある
assert_file_contains "返却フォーマット（単発時）に判定結果がある" "$SKILL_MD" "SM 判定: 単発"

# 45. 返却フォーマット（エピック時）に判定結果セクションがある
assert_file_contains "返却フォーマット（エピック時）に判定結果がある" "$SKILL_MD" "SM 判定: エピック化"

assert_file_contains "エピック化ルーティング時の返却フォーマットがある" "$SKILL_MD" "エピック化して起票しました"

# 47. 透明性確保の記述
assert_file_contains "透明性確保の記述がある" "$SKILL_MD" "透明性確保"

echo "--- 制約 ---"

assert_file_contains "jq の string interpolation 禁止がある" "$SKILL_MD" "string interpolation"

assert_file_contains "コマンドそのまま実行の制約がある" "$SKILL_MD" "コマンドをそのまま実行する"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
