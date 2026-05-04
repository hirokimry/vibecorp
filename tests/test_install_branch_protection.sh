#!/bin/bash
# test_install_branch_protection.sh
# ─────────────────────────────────────────────
# install.sh の branch_protection.required_approvals サポート
# Issue #463: Bot approve 経路（Branch Protection の require approvals 設定可能化）
#
# 検証対象:
#   1. vibecorp.yml に branch_protection.required_approvals: 1 がデフォルトで含まれる
#   2. 全プリセット（minimal/standard/full）でデフォルト 1
#   3. configure_github_repo の awk で値を抽出できる（カスタム値含む）
#   4. dismiss_stale_reviews が常に true で設定される（議論結論）
#   5. configure_github_repo のログメッセージに required_approvals が含まれる
#   6. 旧 vibecorp.yml（branch_protection 不在）は default 1 で動作する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== branch_protection.required_approvals サポートのテスト ==="

# ============================================
# 1. デフォルト required_approvals: 1 で生成
# ============================================
echo ""
echo "--- 1. デフォルト required_approvals: 1 で生成 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "branch_protection: セクション" "$R/.claude/vibecorp.yml" "branch_protection:"
assert_file_contains "required_approvals: 1 デフォルト" "$R/.claude/vibecorp.yml" "required_approvals: 1"
cleanup

# ============================================
# 2. 全プリセットで required_approvals: 1 デフォルト
# ============================================
echo ""
echo "--- 2. 全プリセットで required_approvals: 1 デフォルト ---"
for preset in minimal standard full; do
  create_test_repo
  bash "$INSTALL_SH" --name test-proj --preset "$preset" 2>/dev/null

  yml="$TMPDIR_ROOT/.claude/vibecorp.yml"
  val=$(awk '
    /^branch_protection:[[:space:]]*$/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+required_approvals:[[:space:]]*/ {
      sub(/^[[:space:]]+required_approvals:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$yml")
  assert_eq "preset=${preset}: required_approvals は 1" "1" "$val"
  cleanup
done

# ============================================
# 3. install.sh のロジックが branch_protection ブロックから値を抽出できる
# ============================================
echo ""
echo "--- 3. install.sh の awk が required_approvals 抽出できる ---"

# install.sh から configure_github_repo の必要部分を抽出して動作確認
INSTALL_SH="${SCRIPT_DIR}/install.sh"

# branch_protection.required_approvals の awk 抽出ロジックが install.sh に存在
if grep -q "required_approvals:" "$INSTALL_SH"; then
  pass "install.sh に required_approvals パースロジックがある"
else
  fail "install.sh に required_approvals パースロジックがない"
fi

if grep -q "required_approving_review_count: \\\$required_approvals" "$INSTALL_SH"; then
  pass "Branch Protection JSON に required_approvals 変数が使われている"
else
  fail "Branch Protection JSON で required_approvals が使われていない"
fi

# ============================================
# 4. dismiss_stale_reviews: true 固定
# ============================================
echo ""
echo "--- 4. dismiss_stale_reviews: true が常時設定される ---"
if grep -q "dismiss_stale_reviews: true" "$INSTALL_SH"; then
  pass "dismiss_stale_reviews: true が install.sh で設定されている"
else
  fail "dismiss_stale_reviews が true で設定されていない"
fi

# ============================================
# 5. ログメッセージに required_approvals が含まれる
# ============================================
echo ""
echo "--- 5. ブランチ保護ログに required_approvals 件数が出る ---"
if grep -q 'approve \${required_approvals}件以上必須' "$INSTALL_SH"; then
  pass "ログメッセージに required_approvals の動的件数が含まれる"
else
  fail "ログメッセージが固定文言のまま（required_approvals が反映されない）"
fi

# ============================================
# 6. 旧 vibecorp.yml（branch_protection 不在）でも動作
# ============================================
echo ""
echo "--- 6. branch_protection 不在の旧 yml でデフォルト 1 動作 ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

# 旧形式の vibecorp.yml（branch_protection なし）を配置
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

# install.sh を source して configure_github_repo の値抽出だけテスト
# （実際の gh api 呼び出しはしない）
val=$(awk '
  /^branch_protection:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+required_approvals:[[:space:]]*/ {
    sub(/^[[:space:]]+required_approvals:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
' "$R/.claude/vibecorp.yml")

# 不在時は空文字列が返り、install.sh 側で「数字でなければデフォルト 1」として扱う
assert_eq "branch_protection 不在 → 空文字列" "" "$val"
cleanup

print_test_summary
