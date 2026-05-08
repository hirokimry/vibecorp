#!/bin/bash
# test_install_ai_review_golden_test_workflow.sh
# ─────────────────────────────────────────────
# install.sh の generate_ai_review_golden_test_workflow() の動作検証
# Issue #532: vibecorp が claude-code-action を一時的に無効化して
#             CodeRabbit 単独運用に切り替わるようになる
#
# 検証対象:
#   1. claude_action.enabled: true で .github/workflows/ai-review-golden-test.yml が生成される
#   2. テンプレートの主要要素（name / on / paths / permissions / concurrency / job）が反映される
#   3. claude_action セクション不在時はデフォルト true として生成される
#   4. claude_action.enabled: false で生成されない
#   5. enabled: true → false で管理下 ai-review-golden-test.yml が削除される
#   6. snapshot だけ残っているパターンでも snapshot が掃除される
#   7. 利用者が手動配置した ai-review-golden-test.yml は残置される
#   8. copy_workflows() で ai-review-golden-test.yml がスキップされる
#   9. run_install() から generate_ai_review_golden_test_workflow が呼ばれる

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== generate_ai_review_golden_test_workflow のテスト ==="

# ============================================
# 1. claude_action.enabled: true で生成される
# ============================================
echo ""
echo "--- 1. enabled: true で ai-review-golden-test.yml が生成される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "ai-review-golden-test.yml が存在する" "$R/.github/workflows/ai-review-golden-test.yml"

# ============================================
# 2. テンプレートの主要要素が反映される
# ============================================
echo ""
echo "--- 2. テンプレート主要要素 ---"
yml="$R/.github/workflows/ai-review-golden-test.yml"

assert_file_contains "name: AI Review Golden Test"             "$yml" "name: AI Review Golden Test"
assert_file_contains "on: pull_request トリガー"                "$yml" "pull_request:"
assert_file_contains "opened トリガー"                          "$yml" "opened"
assert_file_contains "synchronize トリガー"                     "$yml" "synchronize"
assert_file_contains "ready_for_review トリガー"                "$yml" "ready_for_review"
assert_file_contains "paths: REVIEW.md"                         "$yml" "REVIEW.md"
assert_file_contains "paths: templates/REVIEW.md.tpl"           "$yml" "templates/REVIEW.md.tpl"
assert_file_contains "paths: .claude/rules/severity/**"         "$yml" ".claude/rules/severity/\\*\\*"
assert_file_contains "paths: tests/golden/**"                   "$yml" "tests/golden/\\*\\*"
assert_file_contains "permissions: contents: read"              "$yml" "contents: read"
assert_file_contains "permissions: pull-requests: read"         "$yml" "pull-requests: read"
assert_file_contains "concurrency 設定"                         "$yml" "concurrency:"
assert_file_contains "concurrency.group 値"                     "$yml" 'group: ai-review-golden-test-${{ github.event.pull_request.number }}'
assert_file_contains "concurrency.cancel-in-progress"           "$yml" "cancel-in-progress: true"
assert_file_contains "golden-test ジョブ"                       "$yml" "golden-test:"
assert_file_contains "Fork PR 除外条件"                          "$yml" 'github.event.pull_request.head.repo.full_name == github.repository'
assert_file_contains "draft PR 除外ガード"                       "$yml" '!github.event.pull_request.draft'

cleanup

# ============================================
# 3. claude_action セクション不在 → デフォルト true で生成される
# ============================================
echo ""
echo "--- 3. claude_action セクション不在 → デフォルト true で生成される ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

cat > "$R/.claude/vibecorp.yml" <<'EOF'
name: test-proj
preset: minimal
language: ja
base_branch: main
protected_files:
  - MVV.md
coderabbit:
  enabled: true
EOF

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "セクション不在 → ai-review-golden-test.yml が生成される" "$R/.github/workflows/ai-review-golden-test.yml"
cleanup

# ============================================
# 4. claude_action.enabled: false で生成されない
# ============================================
echo ""
echo "--- 4. enabled: false で ai-review-golden-test.yml が生成されない ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

cat > "$R/.claude/vibecorp.yml" <<'EOF'
name: test-proj
preset: minimal
language: ja
base_branch: main
protected_files:
  - MVV.md
coderabbit:
  enabled: true
claude_action:
  enabled: false
  skip_paths:
    - "*.lock"
EOF

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "enabled: false なら ai-review-golden-test.yml は無い" "$R/.github/workflows/ai-review-golden-test.yml"
cleanup

# ============================================
# 5. enabled: true → false で管理下ファイルが削除される
# ============================================
echo ""
echo "--- 5. enabled: true → false で管理下 ai-review-golden-test.yml が削除される ---"
create_test_repo
R="$TMPDIR_ROOT"

# まず enabled: true で初回 install
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
assert_file_exists "初回 install で ai-review-golden-test.yml 配置" "$R/.github/workflows/ai-review-golden-test.yml"

# vibecorp.yml の claude_action.enabled を false に切替
yml="$R/.claude/vibecorp.yml"
tmp="$(mktemp "$(dirname "$yml")/.${yml##*/}.XXXXXX")"
awk '
  /^claude_action:/ { in_block = 1; print; next }
  in_block && /^[[:space:]]+enabled:/ {
    print "  enabled: false"
    next
  }
  in_block && /^[^[:space:]#]/ { in_block = 0 }
  { print }
' "$yml" > "$tmp" && mv "$tmp" "$yml"

# --update で削除されることを確認
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "--update 後に管理下 ai-review-golden-test.yml が削除される" "$R/.github/workflows/ai-review-golden-test.yml"
# base snapshot も削除されないと、後から手動配置されたファイルが「管理下」と誤認される
assert_file_not_exists "base snapshot も削除される" "$R/.claude/vibecorp-base/.github/workflows/ai-review-golden-test.yml"
cleanup

# ============================================
# 6. target 削除済み + snapshot 残存 → snapshot も掃除される
# （stale snapshot による次回誤削除を防ぐ回帰テスト）
# ============================================
echo ""
echo "--- 6. target 削除済み + snapshot 残存 → snapshot も掃除される ---"
create_test_repo
R="$TMPDIR_ROOT"

# enabled: true で初回 install
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null

# target を手動削除（利用者が ai-review-golden-test.yml を直接 rm したケース）
rm -f "$R/.github/workflows/ai-review-golden-test.yml"
assert_file_exists "snapshot は残っている" "$R/.claude/vibecorp-base/.github/workflows/ai-review-golden-test.yml"

# enabled を false に切替
yml="$R/.claude/vibecorp.yml"
tmp="$(mktemp "$(dirname "$yml")/.${yml##*/}.XXXXXX")"
awk '
  /^claude_action:/ { in_block = 1; print; next }
  in_block && /^[[:space:]]+enabled:/ {
    print "  enabled: false"
    next
  }
  in_block && /^[^[:space:]#]/ { in_block = 0 }
  { print }
' "$yml" > "$tmp" && mv "$tmp" "$yml"

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "snapshot が掃除される（target 不在でも）" "$R/.claude/vibecorp-base/.github/workflows/ai-review-golden-test.yml"
cleanup

# ============================================
# 7. 利用者が手動配置した ai-review-golden-test.yml は残置される
# ============================================
echo ""
echo "--- 7. 管理外（base_hash 無し）の ai-review-golden-test.yml は残置される ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude" "$R/.github/workflows"

# vibecorp 管理外で手動配置（vibecorp.lock 不在 → base_hash 無し）
echo "name: user-defined-golden-test" > "$R/.github/workflows/ai-review-golden-test.yml"

# vibecorp.yml だけ配置して --update（claude_action.enabled: false）
cat > "$R/.claude/vibecorp.yml" <<'EOF'
name: test-proj
preset: minimal
language: ja
base_branch: main
protected_files:
  - MVV.md
claude_action:
  enabled: false
EOF

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "管理外の ai-review-golden-test.yml は残置される" "$R/.github/workflows/ai-review-golden-test.yml"
assert_file_contains "中身も保持される" "$R/.github/workflows/ai-review-golden-test.yml" "user-defined-golden-test"
cleanup

# ============================================
# 8. copy_workflows() で ai-review-golden-test.yml がスキップされる
# ============================================
echo ""
echo "--- 8. copy_workflows() で ai-review-golden-test.yml がスキップされる ---"
# install.sh 内で ai-review-golden-test.yml を扱う条件があることを検証
if grep -q -e 'ai-review-golden-test.yml' "$INSTALL_SH"; then
  pass "install.sh に ai-review-golden-test.yml への明示的な扱いがある"
else
  fail "install.sh に ai-review-golden-test.yml の明示的な扱いがない"
fi

# copy_workflows() 関数内で ai-review-golden-test.yml 専用分岐の continue が
# あることを確認（test_install_ai_review_workflow.sh と同パターン）
copy_workflows_block=$(awk '/^copy_workflows\(\) \{/,/^\}$/' "$INSTALL_SH")
if echo "$copy_workflows_block" | awk '
  /\[\[ "\$name" == "ai-review-golden-test\.yml" \]\]/ { in_branch = 1; next }
  in_branch && /continue/ { found = 1; exit }
  in_branch && /^[[:space:]]*fi/ { in_branch = 0 }
  END { exit !found }
'; then
  pass "copy_workflows() の ai-review-golden-test.yml 分岐内で continue が使われている"
else
  fail "copy_workflows() の ai-review-golden-test.yml 分岐に continue がない（重複生成のリスク）"
fi

# ============================================
# 9. run_install() から generate_ai_review_golden_test_workflow が呼ばれる
# ============================================
echo ""
echo "--- 9. run_install() から新関数が呼ばれる ---"
if grep -q -e 'generate_ai_review_golden_test_workflow' "$INSTALL_SH"; then
  pass "install.sh で generate_ai_review_golden_test_workflow が呼ばれている"
else
  fail "install.sh で generate_ai_review_golden_test_workflow が呼ばれていない"
fi

# 関数定義自体の存在確認
if grep -q -e '^generate_ai_review_golden_test_workflow()' "$INSTALL_SH"; then
  pass "generate_ai_review_golden_test_workflow 関数定義が存在する"
else
  fail "generate_ai_review_golden_test_workflow 関数定義が無い"
fi

print_test_summary
