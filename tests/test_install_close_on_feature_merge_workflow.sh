#!/bin/bash
# test_install_close_on_feature_merge_workflow.sh
# ─────────────────────────────────────────────
# install.sh の copy_close_on_feature_merge_workflow() の動作検証
# Issue #347: feature ブランチマージ時に子 Issue を自動 close する GHA テンプレート配布
#
# 検証対象:
#   1. テンプレートファイルが存在する
#   2. ワークフロー定義の主要要素 (trigger, branches, permissions, parse pattern)
#   3. full プリセットでは .github/workflows/close-on-feature-merge.yml が配置される
#   4. minimal/standard プリセットでは配置されない
#   5. 既存ファイルは上書きされない (opt-in)
#   6. copy_workflows が close-on-feature-merge.yml を素通り (full-only 委譲が効く)
#   7. install.sh main() が copy_close_on_feature_merge_workflow を呼ぶ
#   8. docs/design-philosophy.md に「統合問題は配布先のデフォルト CI で担保する」セクションが存在
#   9. README.md に該当セクションへのリンクが存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"
TEMPLATE="${SCRIPT_DIR}/templates/.github/workflows/close-on-feature-merge.yml"
DESIGN_DOC="${SCRIPT_DIR}/docs/design-philosophy.md"
README="${SCRIPT_DIR}/README.md"

echo ""
echo "=== copy_close_on_feature_merge_workflow のテスト ==="

# ============================================
# 0. テンプレートファイル存在
# ============================================
echo ""
echo "--- 0. テンプレートファイル存在 ---"
if [[ -f "$TEMPLATE" ]]; then
  pass "templates/.github/workflows/close-on-feature-merge.yml が存在する"
else
  fail "templates/.github/workflows/close-on-feature-merge.yml が存在しない"
  # 前提ファイル不在 → 後続テストは無意味なので即終了
  exit 1
fi

# ============================================
# 1. ワークフロー定義の主要要素
# ============================================
echo ""
echo "--- 1. ワークフロー定義の主要要素 ---"

assert_file_contains "name: close-on-feature-merge"   "$TEMPLATE" "name: close-on-feature-merge"
assert_file_contains "on: pull_request トリガー"      "$TEMPLATE" "pull_request:"
assert_file_contains "types: \[closed\] トリガー"     "$TEMPLATE" "types: \[closed\]"
assert_file_contains "branches: feature/epic-*"       "$TEMPLATE" "feature/epic-"
assert_file_contains "permissions: issues: write"     "$TEMPLATE" "issues: write"
assert_file_contains "permissions: contents: read"    "$TEMPLATE" "contents: read"
assert_file_contains "permissions: pull-requests: read" "$TEMPLATE" "pull-requests: read"
assert_file_contains "merged == true ガード"          "$TEMPLATE" "merged == true"

# 厳密パース: Closes/Fixes/Resolves とそのバリエーション
assert_file_contains "close キーワードマッチ (close[sd]?)"     "$TEMPLATE" "close\[sd\]?"
assert_file_contains "fix キーワードマッチ (fix(es|ed)?)"      "$TEMPLATE" "fix(es|ed)?"
assert_file_contains "resolve キーワードマッチ (resolve[sd]?)" "$TEMPLATE" "resolve\[sd\]?"

# Refs / Related to が抽出パターンに含まれていないこと（暴発防止）
parse_line=$(grep -E "grep .*-oiE" "$TEMPLATE" || true)
if [[ -z "$parse_line" ]]; then
  fail "抽出パターン (grep -oiE) が見つからない"
elif echo "$parse_line" | grep -qiE 'refs|related'; then
  fail "抽出パターンに refs/related が含まれている (暴発リスク)"
else
  pass "抽出パターンに refs/related が含まれていない (暴発防止)"
fi

assert_file_contains "gh issue close 呼び出し" "$TEMPLATE" "gh issue close"

# 冪等性: 既に close 済みの Issue はスキップ
assert_file_contains "冪等性: CLOSED 状態の Issue をスキップ" "$TEMPLATE" "CLOSED"

# LLM 非介在: claude-code-action 等の参照がないこと
assert_file_not_contains "LLM 非介在: claude-code-action 参照なし" "$TEMPLATE" "claude-code-action"
assert_file_not_contains "LLM 非介在: anthropic 参照なし"          "$TEMPLATE" "anthropic"

# ============================================
# 2. full プリセットで配置される
# ============================================
echo ""
echo "--- 2. full プリセットで配置される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "full: .github/workflows/close-on-feature-merge.yml が配置される" \
  "$R/.github/workflows/close-on-feature-merge.yml"

# ============================================
# 3. minimal プリセットでは配置されない
# ============================================
echo ""
echo "--- 3. minimal プリセットでは配置されない ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_not_exists "minimal: close-on-feature-merge.yml が配置されない" \
  "$R/.github/workflows/close-on-feature-merge.yml"

# ============================================
# 4. standard プリセットでは配置されない
# ============================================
echo ""
echo "--- 4. standard プリセットでは配置されない ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_not_exists "standard: close-on-feature-merge.yml が配置されない" \
  "$R/.github/workflows/close-on-feature-merge.yml"

# ============================================
# 5. 既存ファイルは上書きされない (opt-in)
# ============================================
echo ""
echo "--- 5. 既存ファイルは上書きされない ---"
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github/workflows"
USER_MARKER="# user customized close-on-feature-merge"
printf '%s\n' "$USER_MARKER" > "$TMPDIR_ROOT/.github/workflows/close-on-feature-merge.yml"

bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"

if grep -qF "$USER_MARKER" "$R/.github/workflows/close-on-feature-merge.yml"; then
  pass "既存ファイルが上書きされない (ユーザーカスタマイズ保持)"
else
  fail "既存ファイルが上書きされた"
fi

# ============================================
# 6. copy_workflows が close-on-feature-merge.yml を素通りさせる (full-only 委譲)
# ============================================
echo ""
echo "--- 6. copy_workflows が close-on-feature-merge.yml を委譲する ---"
COPY_WORKFLOWS_BLOCK="$(awk '/^copy_workflows\(\)/,/^}/' "$INSTALL_SCRIPT")"
if echo "$COPY_WORKFLOWS_BLOCK" | grep -qE 'close-on-feature-merge\.yml'; then
  pass "copy_workflows() に close-on-feature-merge.yml の skip 分岐がある"
else
  fail "copy_workflows() で close-on-feature-merge.yml が skip されていない (full-only 委譲が破綻)"
fi

# ============================================
# 7. install.sh main() が copy_close_on_feature_merge_workflow を呼ぶ
# ============================================
echo ""
echo "--- 7. install.sh main() が新規関数を呼ぶ ---"
if grep -qE '^[[:space:]]+copy_close_on_feature_merge_workflow[[:space:]]*$' "$INSTALL_SCRIPT"; then
  pass "main() から copy_close_on_feature_merge_workflow が呼ばれている"
else
  fail "main() から copy_close_on_feature_merge_workflow が呼ばれていない"
fi

# ============================================
# 8. design-philosophy.md にセクション追記
# ============================================
echo ""
echo "--- 8. design-philosophy.md の追記セクション ---"
assert_file_contains "「統合問題は配布先のデフォルト CI で担保する」セクションが存在" \
  "$DESIGN_DOC" "## 統合問題は配布先のデフォルト CI で担保する"
assert_file_contains "「配布する例外」サブセクションが存在" \
  "$DESIGN_DOC" "### 配布する例外"
assert_file_contains "close-on-feature-merge.yml の例外配布根拠が記載" \
  "$DESIGN_DOC" "close-on-feature-merge.yml"

# ============================================
# 9. README.md に該当セクションへのリンク
# ============================================
echo ""
echo "--- 9. README.md の設計思想セクションリンク ---"
assert_file_contains "README.md が design-philosophy.md の該当節へリンクしている" \
  "$README" "design-philosophy.md#統合問題は配布先のデフォルト-ci-で担保する"

print_test_summary
