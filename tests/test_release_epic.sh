#!/bin/bash
# test_release_epic.sh — /vibecorp:release-epic スキルの構造テスト
# 使い方: bash tests/test_release_epic.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/release-epic/SKILL.md"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
MARKETPLACE_JSON="${SCRIPT_DIR}/.claude-plugin/marketplace.json"

# ============================================
echo "=== /vibecorp:release-epic スキル テスト ==="
# ============================================

# --- A. SKILL.md の存在と frontmatter ---

echo "--- A. SKILL.md の存在と frontmatter ---"

assert_file_exists "SKILL.md が存在する" "$SKILL_MD"

if [[ ! -f "$SKILL_MD" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

assert_file_contains "frontmatter に name: release-epic がある" "$SKILL_MD" "^name: release-epic"
assert_file_contains "frontmatter に description がある" "$SKILL_MD" "^description:"

# --- B. ワークフローの必須ステップ ---

echo "--- B. ワークフローの必須ステップ ---"

assert_file_contains "プリセット確認ステップがある" "$SKILL_MD" "プリセット確認"
assert_file_contains "full プリセット専用の記述がある" "$SKILL_MD" "full プリセット専用"
assert_file_contains "親エピック Issue 取得ステップがある" "$SKILL_MD" "親エピック Issue の取得"
assert_file_contains "エピック判定ステップがある" "$SKILL_MD" "エピック判定"
assert_file_contains "sub-issue 一覧取得ステップがある" "$SKILL_MD" "sub-issue 一覧"
assert_file_contains "未 close 子 Issue 検証ステップがある" "$SKILL_MD" "未 close 子 Issue"
assert_file_contains "feature ブランチ確認ステップがある" "$SKILL_MD" "feature ブランチ"
assert_file_contains "リリースノート生成ステップがある" "$SKILL_MD" "リリースノート"
assert_file_contains "リリース PR 作成ステップがある" "$SKILL_MD" "リリース PR の作成"
assert_file_contains "親 Issue 更新ステップがある" "$SKILL_MD" "親エピック Issue の更新"

# --- C. GitHub API 呼び出しの記述 ---

echo "--- C. GitHub API 呼び出しの記述 ---"

assert_file_contains "gh issue view の使用がある" "$SKILL_MD" "gh issue view"
assert_file_contains "sub_issues API 呼び出しがある" "$SKILL_MD" "sub_issues"
assert_file_contains "gh api の使用がある" "$SKILL_MD" "gh api"
assert_file_contains "gh pr create の使用がある" "$SKILL_MD" "gh pr create"
assert_file_contains "git ls-remote によるブランチ確認がある" "$SKILL_MD" "git ls-remote"
assert_file_contains "GitHub 公式ドキュメント URL がある" "$SKILL_MD" "docs.github.com/en/rest/issues/sub-issues"

# --- D. スコープ外の明記 ---

echo "--- D. スコープ外の明記 ---"

assert_file_contains "auto-merge 設定スコープ外の記述がある" "$SKILL_MD" "auto-merge 設定はスコープ外"
assert_file_contains "gh pr merge --auto を呼ばない明記がある" "$SKILL_MD" "gh pr merge --auto"
assert_file_contains "タグ打ちスコープ外の記述がある" "$SKILL_MD" "タグ打ち"

# --- E. 制約・介入ポイント ---

echo "--- E. 制約・介入ポイント ---"

assert_file_contains "コード変更禁止の制約がある" "$SKILL_MD" "コード変更は一切行わない"
assert_file_contains "jq 文字列補間禁止の制約がある" "$SKILL_MD" "string interpolation"
assert_file_contains "コマンド素直実行の制約がある" "$SKILL_MD" "コマンドをそのまま実行"
assert_file_contains "1 コマンド 1 呼び出し制約がある" "$SKILL_MD" "1 コマンド 1 呼び出し"
assert_file_contains "介入ポイントの記述がある" "$SKILL_MD" "介入ポイント"

# --- F. install.sh のプリセット分岐 ---

echo "--- F. install.sh のプリセット分岐 ---"

assert_file_exists "install.sh が存在する" "$INSTALL_SH"

# minimal / standard プリセットで release-epic を削除する分岐がある
RELEASE_EPIC_DELETIONS=$(grep -c 'rm -rf "\${skills_dir}/release-epic"' "$INSTALL_SH" || true)
if [[ "$RELEASE_EPIC_DELETIONS" -ge 2 ]]; then
  pass "install.sh に release-epic 削除分岐が 2 箇所以上ある（minimal + standard）"
else
  fail "install.sh の release-epic 削除分岐が不足（${RELEASE_EPIC_DELETIONS} 件、期待: 2 件以上）"
fi

# minimal / standard 両方のブロックに release-epic 削除がある
if awk '
  /minimal\)/ { in_minimal=1 }
  /standard\)/ { in_minimal=0; in_standard=1 }
  /esac/ { in_minimal=0; in_standard=0 }
  in_minimal && /skills_dir\}\/release-epic/ { found_minimal=1 }
  in_standard && /skills_dir\}\/release-epic/ { found_standard=1 }
  END { exit !(found_minimal && found_standard) }
' "$INSTALL_SH"; then
  pass "minimal / standard 両方のブロックに release-epic 削除がある"
else
  fail "minimal / standard 両方のブロックに release-epic 削除がない"
fi

# --- G. marketplace.json への登録 ---

echo "--- G. marketplace.json への登録 ---"

assert_file_exists "marketplace.json が存在する" "$MARKETPLACE_JSON"
assert_file_contains "marketplace.json に release-epic が登録されている" "$MARKETPLACE_JSON" "./skills/release-epic"

# --- H. 返却フォーマット ---

echo "--- H. 返却フォーマット ---"

assert_file_contains "結果報告フォーマットがある" "$SKILL_MD" "結果報告\|完了"
assert_file_contains "リリース PR URL が報告に含まれる" "$SKILL_MD" "リリース PR\|PR URL"

# ============================================
print_test_summary
# ============================================
