#!/bin/bash
# test_install_claude_action_yml.sh
# ─────────────────────────────────────────────
# install.sh の generate_vibecorp_yml と ensure_claude_action_section の動作検証
# Issue #468: vibecorp.yml に claude_action セクション独立フラグを追加
#
# 検証対象:
#   1. 新規 install で claude_action セクションが含まれる
#   2. 新規 install で enabled: true がデフォルト
#   3. 新規 install で skip_paths に 7 件の業界標準パターンが含まれる
#   4. 既存 vibecorp.yml で claude_action セクション全体不在 → セクション追加
#   5. 既存 vibecorp.yml で enabled: false → 値が維持される
#   6. 既存 vibecorp.yml で skip_paths カスタマイズ値 → そのまま維持
#   7. 既存 vibecorp.yml で部分定義（enabled だけ）→ skip_paths のみ追加
#   8. 既存 vibecorp.yml で部分定義（skip_paths だけ）→ enabled のみ追加
#   9. 全プリセット（minimal/standard/full）で enabled: true がデフォルト
#  10. ensure_claude_action_section 単体: vibecorp.yml 不在時は no-op

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== claude_action セクション schema 拡張のテスト ==="

# ============================================
# 1. 新規 install: claude_action セクションが含まれる
# ============================================
echo ""
echo "--- 1. 新規 install で claude_action セクションが追加される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "claude_action: セクション" "$R/.claude/vibecorp.yml" "^claude_action:"
assert_file_contains "enabled: true デフォルト"   "$R/.claude/vibecorp.yml" "enabled: true"
assert_file_contains "skip_paths: 含まれる"        "$R/.claude/vibecorp.yml" "skip_paths:"

# skip_paths の業界標準 7 件が含まれることを検証（YAML リスト要素として完全一致）
for pattern in '- "*.lock"' '- ".git/**"' '- "node_modules/**"' '- "dist/**"' '- "build/**"' '- ".cache/**"' '- "vendor/**"'; do
  if grep -q -F -- "$pattern" "$R/.claude/vibecorp.yml"; then
    pass "skip_paths に '$pattern' が含まれる"
  else
    fail "skip_paths に '$pattern' が含まれない"
  fi
done
cleanup

# ============================================
# 2. 各プリセットで enabled: true がデフォルト
# ============================================
echo ""
echo "--- 2. 各プリセットで enabled: true がデフォルト ---"
for preset in minimal standard full; do
  create_test_repo
  bash "$INSTALL_SH" --name test-proj --preset "$preset" 2>/dev/null

  yml="$TMPDIR_ROOT/.claude/vibecorp.yml"
  # claude_action ブロック内の enabled の値を抽出
  enabled=$(awk '
    /^claude_action:/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+enabled:/ {
      sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$yml")
  assert_eq "preset=${preset}: enabled は true" "true" "$enabled"
  cleanup
done

# ============================================
# 3. ensure_claude_action_section 単体テスト準備
# ============================================
echo ""
echo "--- 3. ensure_claude_action_section の単体動作 ---"

# install.sh を source して関数を呼べるようにする
# install.sh は末尾の if [[ ${BASH_SOURCE[0]} == "$0" ]] ガードで main 自動起動を抑止している
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install.sh"

# 単体テスト用のヘルパー: 一時的な vibecorp.yml を作って関数を呼ぶ
run_ensure_with_yml() {
  local yml_content="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  mkdir -p "${tmp_root}/.claude"
  printf '%s' "$yml_content" > "${tmp_root}/.claude/vibecorp.yml"

  REPO_ROOT="$tmp_root" ensure_claude_action_section >/dev/null 2>&1

  cat "${tmp_root}/.claude/vibecorp.yml"
  rm -rf "$tmp_root"
}

# 3-1. claude_action セクション全体不在 → 末尾に追加
result=$(run_ensure_with_yml "$(cat <<'EOF'
name: test
preset: minimal
language: ja
coderabbit:
  enabled: true
EOF
)")
if echo "$result" | grep -q -e "^claude_action:"; then
  pass "セクション不在時に claude_action: が追加される"
else
  fail "セクション不在時に claude_action: が追加されない"
fi
if echo "$result" | grep -q "node_modules/"; then
  pass "セクション不在時に skip_paths も追加される"
else
  fail "セクション不在時に skip_paths が追加されない"
fi

# 3-2. enabled: false の維持（既存値の上書き禁止）
result=$(run_ensure_with_yml "$(cat <<'EOF'
name: test
preset: minimal
claude_action:
  enabled: false
  skip_paths:
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"
EOF
)")
enabled=$(echo "$result" | awk '
  /^claude_action:/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
')
assert_eq "enabled: false が維持される" "false" "$enabled"

# 3-3. skip_paths カスタマイズ値の維持
result=$(run_ensure_with_yml "$(cat <<'EOF'
name: test
preset: minimal
claude_action:
  enabled: true
  skip_paths:
    - "custom/*"
EOF
)")
if echo "$result" | grep -q "custom/"; then
  pass "カスタマイズ skip_paths が維持される"
else
  fail "カスタマイズ skip_paths が消失した"
fi
# 業界標準デフォルト（node_modules）が**追加されない**ことも確認
if echo "$result" | grep -q "node_modules/"; then
  fail "ensure が既存 skip_paths を上書きしている"
else
  pass "既存 skip_paths が上書きされない"
fi

# 3-4. 部分定義（enabled だけ）→ skip_paths のみ追加
result=$(run_ensure_with_yml "$(cat <<'EOF'
name: test
preset: minimal
claude_action:
  enabled: false
EOF
)")
if echo "$result" | grep -q "skip_paths:"; then
  pass "enabled のみの状態で skip_paths が追加される"
else
  fail "enabled のみの状態で skip_paths が追加されない"
fi
enabled=$(echo "$result" | awk '
  /^claude_action:/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
')
assert_eq "enabled: false は維持される（追加時に上書きされない）" "false" "$enabled"

# 3-5. 部分定義（skip_paths だけ）→ enabled のみ追加
result=$(run_ensure_with_yml "$(cat <<'EOF'
name: test
preset: minimal
claude_action:
  skip_paths:
    - "custom/*"
EOF
)")
if echo "$result" | awk '/^claude_action:/{found=1; next} found && /^[^[:space:]#]/{exit} found && /^[[:space:]]+enabled:[[:space:]]*true/{print "yes"; exit}' | grep -q "yes"; then
  pass "skip_paths のみの状態で enabled: true が追加される"
else
  fail "skip_paths のみの状態で enabled が追加されない"
fi
if echo "$result" | grep -q "custom/"; then
  pass "既存 skip_paths（custom/*）が維持される"
else
  fail "既存 skip_paths が消失した"
fi

# 3-6. 両方ある → 何も追加しない
yml_content=$(cat <<'EOF'
name: test
preset: minimal
claude_action:
  enabled: true
  skip_paths:
    - "*.lock"
    - "node_modules/**"
EOF
)
result=$(run_ensure_with_yml "$yml_content")
# 比較のため改行整形（POSIX 互換）
expected="$yml_content"
if [[ "$result" == "$expected" ]]; then
  pass "両方ある場合は変更されない（idempotent）"
else
  fail "両方ある場合に変更が発生した"
fi

# 3-7. vibecorp.yml 不在時は no-op
tmp_root="$(mktemp -d)"
mkdir -p "${tmp_root}/.claude"
REPO_ROOT="$tmp_root" ensure_claude_action_section >/dev/null 2>&1
if [[ ! -f "${tmp_root}/.claude/vibecorp.yml" ]]; then
  pass "vibecorp.yml 不在時は no-op（ファイル作成しない）"
else
  fail "vibecorp.yml 不在時にファイルが作成された"
fi
rm -rf "$tmp_root"

# ============================================
# 4. --update モードでの動作
# ============================================
echo ""
echo "--- 4. --update モードで claude_action が追加される ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# 既存 yml から claude_action セクションを削除（旧バージョンからのアップデート相当）
yml_path="$R/.claude/vibecorp.yml"
tmp="$(mktemp "$(dirname "$yml_path")/.${yml_path##*/}.XXXXXX")"
awk '
  /^claude_action:/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { in_block = 0 }
  !in_block { print }
' "$yml_path" > "$tmp" && mv "$tmp" "$yml_path"

assert_file_not_contains "削除確認: claude_action セクションが消えた" "$yml_path" "^claude_action:"

# --update を走らせると claude_action セクションが復活
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_contains "--update で claude_action 復活" "$yml_path" "^claude_action:"
assert_file_contains "--update で skip_paths 復活"   "$yml_path" "skip_paths:"
cleanup

# ============================================
# 5. verify_claude_action_secrets が新セクションで正しく動作する（パース整合）
# ============================================
echo ""
echo "--- 5. verify_claude_action_secrets パース整合 ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# 新セクションから enabled の値を verify_claude_action_secrets と同じ awk で抽出
enabled=$(awk '
  /^claude_action:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[^[:space:]#]/ { exit }
  in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
    sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
    sub(/[[:space:]]*$/, "", $0)
    print
    exit
  }
' "$R/.claude/vibecorp.yml")
assert_eq "verify_claude_action_secrets と同じ awk で true が抽出できる" "true" "$enabled"
cleanup

print_test_summary
