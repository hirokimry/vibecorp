#!/bin/bash
# test_install_ai_review_workflow.sh
# ─────────────────────────────────────────────
# install.sh の generate_ai_review_workflow() の動作検証
# Issue #461: AI レビュー用 GitHub Actions ワークフロー骨格を配布できるようになる
#
# 検証対象:
#   1. claude_action.enabled: true で .github/workflows/ai-review.yml が生成される
#   2. claude_action.enabled: false で生成されない
#   3. claude_action セクション不在時はデフォルト true として生成される
#   4. CISO 要件: on/permissions/concurrency/Fork PR 除外条件が含まれる
#   5. claude-code-action@v1 と claude_code_oauth_token への参照が含まれる
#   6. intent ラベル数チェックジョブが含まれる（1 PR 1 intent）
#   7. 既存ファイル（カスタマイズ無し）→ テンプレート反映
#   8. 既存ファイル（カスタマイズあり、テンプレート未変更）→ カスタム保持
#   9. copy_workflows が ai-review.yml を上書き処理しない（generate_ai_review_workflow に委譲）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== generate_ai_review_workflow のテスト ==="

# ============================================
# 1. claude_action.enabled: true で生成される
# ============================================
echo ""
echo "--- 1. enabled: true で ai-review.yml が生成される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "ai-review.yml が存在する" "$R/.github/workflows/ai-review.yml"

# ============================================
# 2. CISO 要件の主要要素が含まれる
# ============================================
echo ""
echo "--- 2. CISO 要件の主要要素 ---"
yml="$R/.github/workflows/ai-review.yml"

assert_file_contains "on: pull_request" "$yml" "pull_request:"
assert_file_contains "ready_for_review トリガー" "$yml" "ready_for_review"
assert_file_contains "draft PR 除外ガード"     "$yml" '!github.event.pull_request.draft'
assert_file_contains "permissions: contents: read" "$yml" "contents: read"
assert_file_contains "permissions: pull-requests: write" "$yml" "pull-requests: write"
assert_file_contains "permissions: issues: write" "$yml" "issues: write"
assert_file_contains "concurrency 設定" "$yml" "concurrency:"
assert_file_contains "Fork PR 除外条件" "$yml" 'github.event.pull_request.head.repo.full_name == github.repository'

# ============================================
# 3. claude-code-action 呼び出し
# ============================================
echo ""
echo "--- 3. claude-code-action 呼び出し ---"
assert_file_contains "anthropics/claude-code-action@v1" "$yml" "anthropics/claude-code-action@v1"
assert_file_contains "claude_code_oauth_token 渡し" "$yml" "claude_code_oauth_token: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}"

# ============================================
# 4. intent ラベル数チェックジョブ
# ============================================
echo ""
echo "--- 4. intent ラベル数チェック ---"
assert_file_contains "intent-label-check ジョブ" "$yml" "intent-label-check:"
assert_file_contains "1 PR 1 intent ルール記述" "$yml" "1 PR 1 intent"
assert_file_contains "intent/ プレフィックス検査" "$yml" "intent/"
cleanup

# ============================================
# 5. claude_action.enabled: false で生成されない
# ============================================
echo ""
echo "--- 5. enabled: false で ai-review.yml が生成されない ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

# 先に vibecorp.yml を配置（claude_action.enabled: false）
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
assert_file_not_exists "enabled: false なら ai-review.yml は無い" "$R/.github/workflows/ai-review.yml"
cleanup

# ============================================
# 5b. enabled: true → false で既存 ai-review.yml が削除される
# ============================================
echo ""
echo "--- 5b. enabled: true → false で管理下 ai-review.yml が削除される ---"
create_test_repo
R="$TMPDIR_ROOT"

# まず enabled: true で初回 install
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
assert_file_exists "初回 install で ai-review.yml 配置" "$R/.github/workflows/ai-review.yml"

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
assert_file_not_exists "--update 後に管理下 ai-review.yml が削除される" "$R/.github/workflows/ai-review.yml"
cleanup

# ============================================
# 5c. 利用者が手動配置した ai-review.yml は claude_action.enabled: false でも残置される
# ============================================
echo ""
echo "--- 5c. 管理外（base_hash 無し）の ai-review.yml は残置される ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude" "$R/.github/workflows"

# vibecorp 管理外で手動配置（vibecorp.lock 不在 → base_hash 無し）
echo "name: user-defined" > "$R/.github/workflows/ai-review.yml"

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
assert_file_exists "管理外の ai-review.yml は残置される" "$R/.github/workflows/ai-review.yml"
assert_file_contains "中身も保持される" "$R/.github/workflows/ai-review.yml" "user-defined"
cleanup

# ============================================
# 6. 既存ファイル（カスタマイズ無し）→ 上書き
# ============================================
echo ""
echo "--- 6. カスタマイズ無し既存ファイル → テンプレート反映 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# install 直後のファイルは「カスタマイズ無し」状態（base_hash と一致）
yml_path="$R/.github/workflows/ai-review.yml"
assert_file_exists "初回 install で配置済み" "$yml_path"

# 再度 --update を実行 → 上書きされる（変化なし）
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "再 install 後も存在する" "$yml_path"
assert_file_contains "再 install 後も CISO 要件保持" "$yml_path" "ready_for_review"
cleanup

# ============================================
# 7. 既存ファイル（カスタマイズあり、テンプレート未変更）→ 保持
# ============================================
echo ""
echo "--- 7. カスタマイズあり + テンプレート未変更 → カスタム保持 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

yml_path="$R/.github/workflows/ai-review.yml"

# ユーザーがカスタムジョブを追加
echo "" >> "$yml_path"
echo "  custom-job:" >> "$yml_path"
echo "    runs-on: ubuntu-latest" >> "$yml_path"
echo "    steps: [{ run: 'echo custom' }]" >> "$yml_path"

# 再 --update（テンプレートは変わっていないのでカスタム保持）
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_contains "カスタムジョブが保持される" "$yml_path" "custom-job:"
cleanup

# ============================================
# 8. copy_workflows が ai-review.yml を扱わない
# ============================================
echo ""
echo "--- 8. copy_workflows での重複処理がない ---"
# install.sh の copy_workflows 内で ai-review.yml をスキップする条件があることを検証
if grep -q -e 'ai-review.yml' "$INSTALL_SH"; then
  pass "install.sh に ai-review.yml への明示的な扱いがある"
else
  fail "install.sh に ai-review.yml の明示的な扱いがない"
fi

# copy_workflows() 関数内で `if [[ "$name" == "ai-review.yml" ]]` 直後に continue があることを確認
# 単純な grep "continue" だと `[[ -f "$f" ]] || continue` でも一致するため、
# ai-review.yml 専用分岐の continue だけを抽出して厳密に検証する
copy_workflows_block=$(awk '/^copy_workflows\(\) \{/,/^\}$/' "$INSTALL_SH")
if echo "$copy_workflows_block" | awk '
  /\[\[ "\$name" == "ai-review\.yml" \]\]/ { in_branch = 1; next }
  in_branch && /continue/ { found = 1; exit }
  in_branch && /^[[:space:]]*fi/ { in_branch = 0 }
  END { exit !found }
'; then
  pass "copy_workflows() の ai-review.yml 専用分岐内で continue が使われている"
else
  fail "copy_workflows() の ai-review.yml 分岐に continue がない（重複生成のリスク）"
fi

print_test_summary
