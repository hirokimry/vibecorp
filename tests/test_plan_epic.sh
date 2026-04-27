#!/bin/bash
# test_plan_epic.sh — /vibecorp:plan-epic スキルの構造テスト
# 使い方: bash tests/test_plan_epic.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="${SCRIPT_DIR}/skills/plan-epic/SKILL.md"
INSTALL_SH="${SCRIPT_DIR}/install.sh"

# ============================================
echo "=== /vibecorp:plan-epic スキル テスト ==="
# ============================================

# --- A. SKILL.md の存在と frontmatter ---

echo "--- A. SKILL.md の存在と frontmatter ---"

assert_file_exists "SKILL.md が存在する" "$SKILL_MD"

if [[ ! -f "$SKILL_MD" ]]; then
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

assert_file_contains "frontmatter に name: plan-epic がある" "$SKILL_MD" "^name: plan-epic"
assert_file_contains "frontmatter に description がある" "$SKILL_MD" "^description:"

# --- B. ワークフローの必須ステップ ---

echo "--- B. ワークフローの必須ステップ ---"

assert_file_contains "プリセット確認ステップがある" "$SKILL_MD" "プリセット確認"
assert_file_contains "full プリセット専用の記述がある" "$SKILL_MD" "full プリセット専用"
assert_file_contains "plan mode の記述がある" "$SKILL_MD" "plan mode"
assert_file_contains "EnterPlanMode の使用がある" "$SKILL_MD" "EnterPlanMode"
assert_file_contains "ExitPlanMode の使用がある" "$SKILL_MD" "ExitPlanMode"

# --- C. 親 Issue / 子 Issue / sub-issue API ---

echo "--- C. 親 Issue / 子 Issue / sub-issue API ---"

assert_file_contains "親 Issue 起票ステップがある" "$SKILL_MD" "親 Issue（エピック）の起票"
assert_file_contains "epic ラベル付与の記述がある" "$SKILL_MD" "epic.*ラベル\|--label \"epic\""
assert_file_contains "子 Issue 起票ステップがある" "$SKILL_MD" "子 Issue の起票"
assert_file_contains "/vibecorp:issue の呼び出しがある" "$SKILL_MD" "/vibecorp:issue"
assert_file_contains "sub-issue API 呼び出しがある" "$SKILL_MD" "sub_issues"
assert_file_contains "gh api の使用がある" "$SKILL_MD" "gh api"
assert_file_contains "GitHub 公式ドキュメント URL がある" "$SKILL_MD" "docs.github.com/en/rest/issues/sub-issues"

# --- D. 親 feature ブランチの作成 ---

echo "--- D. 親 feature ブランチの作成 ---"

assert_file_contains "feature ブランチ作成ステップがある" "$SKILL_MD" "親 feature ブランチの作成"
assert_file_contains "feature/epic- 命名規約の記述がある" "$SKILL_MD" "feature/epic-"
assert_file_contains "git push で origin に push する記述がある" "$SKILL_MD" "git push.*origin.*feature/epic-"
assert_file_contains "git ls-remote で検出可能にする記述がある" "$SKILL_MD" "git ls-remote"

# --- E. --dry-run サポート ---

echo "--- E. --dry-run サポート ---"

assert_file_contains "--dry-run の使用方法がある" "$SKILL_MD" "\-\-dry-run"
assert_file_contains "--dry-run モードの説明がある" "$SKILL_MD" "起票.*ブランチ作成.*API 呼び出しは行わない\|起票しない"

# --- F. 制約・介入ポイント ---

echo "--- F. 制約・介入ポイント ---"

assert_file_contains "コード変更禁止の制約がある" "$SKILL_MD" "コード変更は一切行わない"
assert_file_contains "jq 文字列補間禁止の制約がある" "$SKILL_MD" "string interpolation"
assert_file_contains "コマンド素直実行の制約がある" "$SKILL_MD" "コマンドをそのまま実行"
assert_file_contains "介入ポイントの記述がある" "$SKILL_MD" "介入ポイント"

# --- G. install.sh のプリセット分岐 ---

echo "--- G. install.sh のプリセット分岐 ---"

assert_file_exists "install.sh が存在する" "$INSTALL_SH"

# minimal / standard プリセットで plan-epic を削除する分岐がある
PLAN_EPIC_DELETIONS=$(grep -c 'rm -rf "\${skills_dir}/plan-epic"' "$INSTALL_SH" || true)
if [[ "$PLAN_EPIC_DELETIONS" -ge 2 ]]; then
  pass "install.sh に plan-epic 削除分岐が 2 箇所以上ある（minimal + standard）"
else
  fail "install.sh の plan-epic 削除分岐が不足（${PLAN_EPIC_DELETIONS} 件、期待: 2 件以上）"
fi

# minimal ブロック内に plan-epic 削除がある（diagnose と同じ場所）
if awk '
  /minimal\)/ { in_minimal=1 }
  /standard\)/ { in_minimal=0; in_standard=1 }
  /esac/ { in_minimal=0; in_standard=0 }
  in_minimal && /skills_dir\}\/plan-epic/ { found_minimal=1 }
  in_standard && /skills_dir\}\/plan-epic/ { found_standard=1 }
  END { exit !(found_minimal && found_standard) }
' "$INSTALL_SH"; then
  pass "minimal / standard 両方のブロックに plan-epic 削除がある"
else
  fail "minimal / standard 両方のブロックに plan-epic 削除がない"
fi

# --- H. 返却フォーマット ---

echo "--- H. 返却フォーマット ---"

assert_file_contains "結果報告フォーマットがある" "$SKILL_MD" "結果報告\|完了"
assert_file_contains "親 Issue URL が報告に含まれる" "$SKILL_MD" "親 Issue\|親 URL"
assert_file_contains "子 Issue 一覧が報告に含まれる" "$SKILL_MD" "子 Issue"

# ============================================
print_test_summary
# ============================================
