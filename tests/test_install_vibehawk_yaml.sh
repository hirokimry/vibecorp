#!/bin/bash
# test_install_vibehawk_yaml.sh
# ─────────────────────────────────────────────
# install.sh の vibehawk / coderabbit 独立トグル配布の動作検証（Issue #531）
#
# 検証対象:
#   1. デフォルト install: vibecorp.yml に vibehawk(enabled: true)+skip_paths 7 件 /
#      coderabbit(enabled: false) / claude_action 不在
#   2. デフォルト install: .vibehawk.yaml 生成 + path_instructions 注入 + path_filters
#   3. 4 通り組み合わせの期待値マトリクス（.vibehawk.yaml / .coderabbit.yaml の有無）
#   4. claude_action: を持つ既存 yml → vibehawk: にリネーム（enabled 値保持）
#   5. vibehawk.enabled: false へ切替 → 管理下 .vibehawk.yaml が削除される
#   6. review-impl cleanup: REVIEW.md / ai-review.yml が新規生成されない
#   7. verify_vibehawk_prereq 単体: enabled: true で WARN + exit 0 / false で WARN なし + exit 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# vibecorp.yml の vibehawk / coderabbit ブロックの enabled 値を書き換えるヘルパー。
# shell.md「sed -i 禁止」に従い awk + mktemp + mv で置換する。
# $1: yml パス, $2: vibehawk enabled 値, $3: coderabbit enabled 値
set_reviewer_toggles() {
  local yml="$1"
  local vh="$2"
  local cr="$3"
  local tmp
  tmp="$(mktemp "$(dirname "$yml")/.$(basename "$yml").XXXXXX")"
  awk -v vh="$vh" -v cr="$cr" '
    /^vibehawk:/   { in_v = 1; in_c = 0; print; next }
    /^coderabbit:/ { in_v = 0; in_c = 1; print; next }
    /^[^[:space:]#]/ { in_v = 0; in_c = 0 }
    in_v && /^[[:space:]]+enabled:/ { print "  enabled: " vh; next }
    in_c && /^[[:space:]]+enabled:/ { print "  enabled: " cr; next }
    { print }
  ' "$yml" > "$tmp" && mv "$tmp" "$yml"
}

echo ""
echo "=== vibehawk / coderabbit トグル配布のテスト（Issue #531） ==="

# ============================================
# 1. デフォルト install: vibecorp.yml の reviewer セクション
# ============================================
echo ""
echo "--- 1. デフォルト install で vibehawk セクション + coderabbit(disabled) ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "vibehawk: セクション存在" "$R/.claude/vibecorp.yml" "^vibehawk:"
assert_file_contains "coderabbit: セクション存在" "$R/.claude/vibecorp.yml" "^coderabbit:"
assert_file_not_contains "claude_action: セクション不在" "$R/.claude/vibecorp.yml" "^claude_action:"

# vibehawk ブロックの enabled が true
vh_enabled=$(awk '
  /^vibehawk:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
' "$R/.claude/vibecorp.yml")
assert_eq "vibehawk.enabled は true（デフォルト vibehawk-only）" "true" "$vh_enabled"

# coderabbit ブロックの enabled が false
cr_enabled=$(awk '
  /^coderabbit:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
' "$R/.claude/vibecorp.yml")
assert_eq "coderabbit.enabled は false（デフォルト）" "false" "$cr_enabled"

# skip_paths の業界標準 7 件
for pattern in '- "*.lock"' '- ".git/**"' '- "node_modules/**"' '- "dist/**"' '- "build/**"' '- ".cache/**"' '- "vendor/**"'; do
  if grep -q -F -- "$pattern" "$R/.claude/vibecorp.yml"; then
    pass "vibehawk.skip_paths に '$pattern' が含まれる"
  else
    fail "vibehawk.skip_paths に '$pattern' が含まれない"
  fi
done
cleanup

# ============================================
# 2. デフォルト install: .vibehawk.yaml 生成内容
# ============================================
echo ""
echo "--- 2. デフォルト install で .vibehawk.yaml 生成（path_instructions + path_filters） ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists ".vibehawk.yaml 生成" "$R/.vibehawk.yaml"
assert_file_not_exists ".coderabbit.yaml 不在（coderabbit disabled）" "$R/.coderabbit.yaml"
assert_file_contains ".vibehawk.yaml に language: ja" "$R/.vibehawk.yaml" "language: ja"
assert_file_contains ".vibehawk.yaml に path_filters" "$R/.vibehawk.yaml" "path_filters:"
assert_file_contains ".vibehawk.yaml に path_instructions" "$R/.vibehawk.yaml" "path_instructions:"
assert_file_contains ".vibehawk.yaml に Issue 全要件チェック注入" "$R/.vibehawk.yaml" "must meet all requirements of the Issue"
assert_file_not_contains ".vibehawk.yaml にプレースホルダーなし" "$R/.vibehawk.yaml" '{{.*}}'
# path_filters に skip_paths が反映される（`!` 接頭辞なしの glob、Issue #531）
assert_file_contains ".vibehawk.yaml の path_filters に node_modules" "$R/.vibehawk.yaml" 'node_modules/'
cleanup

# ============================================
# 3. 4 通り組み合わせマトリクス
#    （create_test_repo → install → yml 編集 → update で配布物を assert）
# ============================================
echo ""
echo "--- 3. vibehawk × coderabbit 4 通りマトリクス ---"

# 3-1. vibehawk=on / coderabbit=off（デフォルト）→ .vibehawk.yaml 存在 / .coderabbit.yaml 不在
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_exists "[on/off] .vibehawk.yaml 存在" "$R/.vibehawk.yaml"
assert_file_not_exists "[on/off] .coderabbit.yaml 不在" "$R/.coderabbit.yaml"
cleanup

# 3-2. vibehawk=off / coderabbit=on → .vibehawk.yaml 不在 / .coderabbit.yaml 存在
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
set_reviewer_toggles "$R/.claude/vibecorp.yml" "false" "true"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "[off/on] .vibehawk.yaml 不在" "$R/.vibehawk.yaml"
assert_file_exists "[off/on] .coderabbit.yaml 存在" "$R/.coderabbit.yaml"
cleanup

# 3-3. vibehawk=on / coderabbit=on → 両方存在
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
set_reviewer_toggles "$R/.claude/vibecorp.yml" "true" "true"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "[on/on] .vibehawk.yaml 存在" "$R/.vibehawk.yaml"
assert_file_exists "[on/on] .coderabbit.yaml 存在" "$R/.coderabbit.yaml"
cleanup

# 3-4. vibehawk=off / coderabbit=off → 両方不在
# 注: generate_coderabbit_yaml は disabled 時に既存ファイルを削除しないため、
# デフォルトで .coderabbit.yaml が生成されない（coderabbit off）状態から両 off にし、
# vibehawk 管理下 .vibehawk.yaml が update で削除されることを確認する。
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
set_reviewer_toggles "$R/.claude/vibecorp.yml" "false" "false"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "[off/off] .vibehawk.yaml 不在" "$R/.vibehawk.yaml"
assert_file_not_exists "[off/off] .coderabbit.yaml 不在" "$R/.coderabbit.yaml"
cleanup

# ============================================
# 4. claude_action: → vibehawk: リネーム（enabled 値保持）
# ============================================
echo ""
echo "--- 4. 既存 claude_action: が vibehawk: にリネームされ enabled(false) が保持される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
# vibehawk: セクションを legacy claude_action:（enabled: false）に書き換える
yml_path="$R/.claude/vibecorp.yml"
tmp="$(mktemp "$(dirname "$yml_path")/.$(basename "$yml_path").XXXXXX")"
awk '
  /^vibehawk:[[:space:]]*$/ { print "claude_action:"; in_v = 1; next }
  in_v && /^[[:space:]]+enabled:/ { print "  enabled: false"; in_v = 0; next }
  { print }
' "$yml_path" > "$tmp" && mv "$tmp" "$yml_path"
assert_file_contains "前提: claude_action: が書き込まれた" "$yml_path" "^claude_action:"

bash "$INSTALL_SH" --update 2>/dev/null
assert_file_contains "リネーム後: vibehawk: が存在する" "$yml_path" "^vibehawk:"
assert_file_not_contains "リネーム後: claude_action: が消えた" "$yml_path" "^claude_action:"
# enabled: false が保持される
vh_enabled=$(awk '
  /^vibehawk:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
' "$yml_path")
assert_eq "リネーム後: enabled(false) が保持される" "false" "$vh_enabled"
cleanup

# ============================================
# 5. vibehawk.enabled: false 切替で管理下 .vibehawk.yaml が削除される
# ============================================
echo ""
echo "--- 5. vibehawk.enabled: false 切替で管理下 .vibehawk.yaml が削除される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_exists "前提: .vibehawk.yaml が生成済み" "$R/.vibehawk.yaml"
set_reviewer_toggles "$R/.claude/vibecorp.yml" "false" "false"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "切替後: 管理下 .vibehawk.yaml が削除された" "$R/.vibehawk.yaml"
cleanup

# ============================================
# 6. review-impl cleanup: REVIEW.md / ai-review.yml が新規生成されない
# ============================================
echo ""
echo "--- 6. REVIEW.md / ai-review*.yml が install で新規生成されない（vibehawk 移譲） ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_not_exists "REVIEW.md が生成されない" "$R/REVIEW.md"
assert_file_not_exists "ai-review.yml が生成されない" "$R/.github/workflows/ai-review.yml"
assert_file_not_exists "ai-review-golden-test.yml が生成されない" "$R/.github/workflows/ai-review-golden-test.yml"

# 管理外（利用者配置）の REVIEW.md は残置される（誤削除しない）
echo "# user-placed review prompt" > "$R/REVIEW.md"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "管理外 REVIEW.md は残置される" "$R/REVIEW.md"
assert_file_contains "管理外 REVIEW.md の内容が保持される" "$R/REVIEW.md" "user-placed review prompt"
cleanup

# ============================================
# 7. verify_vibehawk_prereq 単体（source して関数を直接呼ぶ）
# ============================================
echo ""
echo "--- 7. verify_vibehawk_prereq 単体（WARN + exit 0） ---"
# install.sh は末尾の if [[ ${BASH_SOURCE[0]} == "$0" ]] ガードで main 自動起動を抑止する
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install.sh"

# 単体テスト用ヘルパー: 一時 vibecorp.yml を作り verify_vibehawk_prereq を呼ぶ
# 戻り値 "<exit_code>|<stderr>" を返す
run_verify_prereq() {
  local enabled_val="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  mkdir -p "${tmp_root}/.claude"
  cat > "${tmp_root}/.claude/vibecorp.yml" <<YML
name: test
vibehawk:
  enabled: ${enabled_val}
YML
  local err ec=0
  err=$(REPO_ROOT="$tmp_root" LANGUAGE=ja verify_vibehawk_prereq 2>&1 >/dev/null) || ec=$?
  rm -rf "$tmp_root"
  printf '%s|%s' "$ec" "$err"
}

# 7-1. enabled: true → stderr に "npx vibehawk setup" を含む WARN + exit 0
result=$(run_verify_prereq "true")
ec="${result%%|*}"
err="${result#*|}"
assert_eq "enabled: true で exit 0" "0" "$ec"
if echo "$err" | grep -q "npx vibehawk setup"; then
  pass "enabled: true で stderr に 'npx vibehawk setup' 案内が出る"
else
  fail "enabled: true で 'npx vibehawk setup' 案内が出ない"
fi

# 7-2. enabled: false → WARN なし + exit 0
result=$(run_verify_prereq "false")
ec="${result%%|*}"
err="${result#*|}"
assert_eq "enabled: false で exit 0" "0" "$ec"
if echo "$err" | grep -q "npx vibehawk setup"; then
  fail "enabled: false で WARN が出てしまう（出るべきでない）"
else
  pass "enabled: false で WARN が出ない"
fi

print_test_summary
