#!/bin/bash
# test_install_review_md.sh
# ─────────────────────────────────────────────
# install.sh の generate_review_md と generate_coderabbit_yaml の path_filters 注入を検証
# Issue #465: REVIEW.md 初期テンプレート配布 + skip_paths を 2 経路に反映
#
# 検証対象:
#   1. claude_action.enabled: true で REVIEW.md が生成される
#   2. REVIEW.md にレビュー言語が反映される（vibecorp.yml の language）
#   3. REVIEW.md に skip_paths が `- "<path>"` 形式で反映される
#   4. REVIEW.md に SoT への参照が含まれる（review-handling.md / review-observations.md）
#   5. claude_action.enabled: false で REVIEW.md が生成されない
#   6. .coderabbit.yaml の path_filters に skip_paths が `!` プレフィックス付きで反映される
#   7. skip_paths が空の場合の挙動（フォールバック）
#   8. claude_action.enabled: false で REVIEW.md が削除される（管理下のみ）
#   9. ai-review.yml に REVIEW.md 読込ステップが含まれる

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== generate_review_md / coderabbit path_filters 注入のテスト ==="

# ============================================
# 1. enabled: true で REVIEW.md が生成される
# ============================================
echo ""
echo "--- 1. enabled: true で REVIEW.md が生成される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "REVIEW.md が生成される" "$R/REVIEW.md"
assert_file_contains "ai-review.yml 言及（命令文プロンプト化により Issue #525 で参照を関連設定セクションに移動）"     "$R/REVIEW.md" ".github/workflows/ai-review.yml"
assert_file_contains "severity 定義参照（指示書型では補足セクションに移動、Issue #521）" "$R/REVIEW.md" "severity 定義"
assert_file_contains "review-handling.md 参照"    "$R/REVIEW.md" "review-handling.md"
assert_file_contains "review-observations.md 参照" "$R/REVIEW.md" "review-observations.md"
assert_file_contains "severity/claude-action.md 参照" "$R/REVIEW.md" "severity/claude-action.md"

# テスト中はワイルドカード等のメタ文字を含むパターンを照合するため、
# grep -F による固定文字列検索を行うアサート関数を使用する
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

# ============================================
# 2. レビュー言語が反映される（vibecorp.yml の language）
# ============================================
echo ""
echo "--- 2. レビュー言語が反映される ---"
assert_file_contains_fixed "ja デフォルトが反映される" "$R/REVIEW.md" "**ja**"
cleanup

# ============================================
# 2b. --language en で英語反映
# ============================================
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language en 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_contains_fixed "en が反映される" "$R/REVIEW.md" "**en**"
cleanup

# ============================================
# 3. skip_paths が REVIEW.md に反映される
# ============================================
echo ""
echo "--- 3. skip_paths が REVIEW.md に反映される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# デフォルトの 7 件が `- "<path>"` 形式で含まれる
assert_file_contains       "skip rules セクション"  "$R/REVIEW.md" "skip rules"
assert_file_contains_fixed 'skip: *.lock'           "$R/REVIEW.md" '- "*.lock"'
assert_file_contains_fixed 'skip: .git/**'          "$R/REVIEW.md" '- ".git/**"'
assert_file_contains_fixed 'skip: node_modules/**'  "$R/REVIEW.md" '- "node_modules/**"'
assert_file_contains_fixed 'skip: dist/**'          "$R/REVIEW.md" '- "dist/**"'
assert_file_contains_fixed 'skip: build/**'         "$R/REVIEW.md" '- "build/**"'
assert_file_contains_fixed 'skip: .cache/**'        "$R/REVIEW.md" '- ".cache/**"'
assert_file_contains_fixed 'skip: vendor/**'        "$R/REVIEW.md" '- "vendor/**"'
cleanup

# ============================================
# 4. .coderabbit.yaml の path_filters に skip_paths が反映される
# ============================================
echo ""
echo "--- 4. .coderabbit.yaml の path_filters に反映される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains       "path_filters セクション"     "$R/.coderabbit.yaml" "path_filters:"
assert_file_contains_fixed "coderabbit: !*.lock"        "$R/.coderabbit.yaml" '- "!*.lock"'
assert_file_contains_fixed "coderabbit: !.git/**"       "$R/.coderabbit.yaml" '- "!.git/**"'
assert_file_contains_fixed "coderabbit: !node_modules/**" "$R/.coderabbit.yaml" '- "!node_modules/**"'
assert_file_contains_fixed "coderabbit: !dist/**"       "$R/.coderabbit.yaml" '- "!dist/**"'
cleanup

# ============================================
# 4c. 既存ユーザー REVIEW.md は初回 install で上書きされない
# ============================================
echo ""
echo "--- 4c. 利用者が手動配置した REVIEW.md は初回 install で保護される ---"
create_test_repo
R="$TMPDIR_ROOT"

# vibecorp install 前に手動で REVIEW.md を配置
echo "# user-managed REVIEW (do not overwrite)" > "$R/REVIEW.md"

bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
assert_file_contains_fixed "ユーザー REVIEW.md が保持される" "$R/REVIEW.md" "user-managed REVIEW"
cleanup

# ============================================
# 5. claude_action.enabled: false で REVIEW.md が生成されない
# ============================================
echo ""
echo "--- 5. enabled: false で REVIEW.md が生成されない ---"
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
assert_file_not_exists "enabled: false なら REVIEW.md は無い" "$R/REVIEW.md"
cleanup

# ============================================
# 6. enabled: true → false で管理下 REVIEW.md が削除される
# ============================================
echo ""
echo "--- 6. enabled: true → false で管理下 REVIEW.md が削除される ---"
create_test_repo
R="$TMPDIR_ROOT"
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
assert_file_exists "初回 install で REVIEW.md 配置" "$R/REVIEW.md"

# enabled を false に
yml="$R/.claude/vibecorp.yml"
tmp="$(mktemp "$(dirname "$yml")/.${yml##*/}.XXXXXX")"
awk '
  /^claude_action:/ { in_block = 1; print; next }
  in_block && /^[[:space:]]+enabled:/ { print "  enabled: false"; next }
  in_block && /^[^[:space:]#]/ { in_block = 0 }
  { print }
' "$yml" > "$tmp" && mv "$tmp" "$yml"

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "--update で REVIEW.md が削除される" "$R/REVIEW.md"
assert_file_not_exists "base snapshot も削除される" "$R/.claude/vibecorp-base/REVIEW.md"
cleanup

# ============================================
# 7. 利用者が手動配置した REVIEW.md は enabled: false でも残置される
# ============================================
echo ""
echo "--- 7. 管理外 REVIEW.md は enabled: false でも残置される ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

# vibecorp 管理外で手動配置
echo "# user-defined REVIEW" > "$R/REVIEW.md"

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
assert_file_exists "管理外 REVIEW.md は残置される" "$R/REVIEW.md"
assert_file_contains "中身も保持される" "$R/REVIEW.md" "user-defined REVIEW"
cleanup

# ============================================
# 8. ai-review.yml に REVIEW.md 読込ステップが含まれる
# ============================================
echo ""
echo "--- 8. ai-review.yml に REVIEW.md 読込ステップ ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "ai-review.yml に REVIEW.md 読込ステップ" "$R/.github/workflows/ai-review.yml" "REVIEW.md をプロンプトに読み込む"
assert_file_contains "claude-code-action に prompt 引き渡し" "$R/.github/workflows/ai-review.yml" "prompt: \${{ steps.review_prompt.outputs.prompt }}"
# heredoc delimiter は固定でなくランダム化されている（REVIEW.md 本文との衝突回避）
assert_file_contains_fixed "heredoc delimiter のランダム化"  "$R/.github/workflows/ai-review.yml" 'EOF_REVIEW_MD_$(date +%s)_${RANDOM}'
cleanup

# ============================================
# 9. skip_paths が空（key だけ存在）の場合のフォールバック（CodeRabbit 側）
# ============================================
echo ""
echo "--- 9. skip_paths key だけ存在 → フォールバック発動 ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

# skip_paths key が存在するが要素ゼロ。ensure_claude_action_section は key が
# あるので追加せず、_read_skip_paths が空を返す。フォールバックが発動する。
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
  enabled: true
  skip_paths: []
EOF

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_contains_fixed "フォールバック !**/*.lock" "$R/.coderabbit.yaml" '!**/*.lock'
cleanup

# ============================================
# 10. skip_paths 内のコメント行・空行を読み飛ばす（途中終了しない）
# ============================================
echo ""
echo "--- 10. skip_paths 内のコメント行・空行が安全に読み飛ばされる ---"
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
  enabled: true
  skip_paths:
    # コメント行 (このコメントの後のパスも取り込めること)
    - "*.lock"

    - "node_modules/**"
    # 末尾コメント
    - "vendor/**"
EOF

bash "$INSTALL_SH" --update 2>/dev/null

# REVIEW.md にコメント行直後の skip_paths も含まれることを確認
assert_file_contains_fixed "コメント直後のパス *.lock" "$R/REVIEW.md" '- "*.lock"'
assert_file_contains_fixed "空行を挟んだ node_modules/**" "$R/REVIEW.md" '- "node_modules/**"'
assert_file_contains_fixed "途中コメント後の vendor/**" "$R/REVIEW.md" '- "vendor/**"'
cleanup

# ============================================
# 11. skip_paths が single quote で書かれていても正しくパースされる
# ============================================
echo ""
echo "--- 11. single-quoted skip_paths が正しく剥がされる ---"
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"

# YAML として妥当な single quote 形式の skip_paths
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
  enabled: true
  skip_paths:
    - '*.lock'
    - 'vendor/**'
EOF

bash "$INSTALL_SH" --update 2>/dev/null

# REVIEW.md には double-quote 形式で出力されることを確認（single quote が剥がされている）
assert_file_contains_fixed "REVIEW.md: single quote が剥がれて *.lock"   "$R/REVIEW.md" '- "*.lock"'
assert_file_contains_fixed "REVIEW.md: single quote が剥がれて vendor"   "$R/REVIEW.md" '- "vendor/**"'

# .coderabbit.yaml にも double-quote 形式で出力（! プレフィックス付き）
assert_file_contains_fixed "coderabbit: !*.lock 正規化"      "$R/.coderabbit.yaml" '- "!*.lock"'
assert_file_contains_fixed "coderabbit: !vendor/** 正規化"   "$R/.coderabbit.yaml" '- "!vendor/**"'

# single quote が混入していないことの確認
if grep -q -F -- "'*.lock'" "$R/.coderabbit.yaml"; then
  fail "coderabbit.yaml に single quote が残っている（剥がし忘れ）"
else
  pass "coderabbit.yaml に single quote が残っていない"
fi
cleanup

print_test_summary
