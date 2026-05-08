#!/bin/bash
# test_install_claude_action_disable_cleanup.sh
# ─────────────────────────────────────────────
# 導入先での claude_action.enabled: true → false 切替時の一括クリーンアップ検証
# Issue #532: vibecorp が claude-code-action を一時的に無効化して
#             CodeRabbit 単独運用に切り替わるようになる
#
# CEO 要求: 「導入先でも true→false したときにちゃんと綺麗に掃除されるようにする必要あり」
#
# 検証対象:
#   1. enabled: true で初回 install すると claude-action 関連 3 ファイル全てが配置される
#      （REVIEW.md, ai-review.yml, ai-review-golden-test.yml）
#   2. 上記 3 ファイル全ての base snapshot が生成される
#   3. 上記 3 ファイル全ての base_hash が vibecorp.lock に記録される
#   4. enabled: false に切替 + --update で 3 ファイル全てが削除される
#   5. 上記 3 ファイル全ての base snapshot が削除される
#   6. 上記 3 ファイル全ての base_hash エントリが vibecorp.lock から消える
#   7. .coderabbit.yaml は影響を受けない（CodeRabbit 単独運用継続）
#   8. テンプレートファイル（templates/ 配下）は削除されない（再有効化のため保持）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

echo ""
echo "=== claude_action.enabled: true → false 一括クリーンアップ検証 ==="

# ============================================
# Step A: enabled: true で初回 install
# ============================================
echo ""
echo "--- Step A: enabled: true で初回 install ---"
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# A-1. 3 ファイル全てが配置される
assert_file_exists "REVIEW.md が配置される"                             "$R/REVIEW.md"
assert_file_exists "ai-review.yml が配置される"                         "$R/.github/workflows/ai-review.yml"
assert_file_exists "ai-review-golden-test.yml が配置される"             "$R/.github/workflows/ai-review-golden-test.yml"

# A-2. 3 ファイル全ての base snapshot が生成される
assert_file_exists "REVIEW.md の base snapshot が生成される"            "$R/.claude/vibecorp-base/REVIEW.md"
assert_file_exists "ai-review.yml の base snapshot が生成される"        "$R/.claude/vibecorp-base/.github/workflows/ai-review.yml"
assert_file_exists "ai-review-golden-test.yml の base snapshot が生成される" "$R/.claude/vibecorp-base/.github/workflows/ai-review-golden-test.yml"

# A-3. 3 ファイル全ての base_hash が vibecorp.lock に記録される
assert_file_contains "lock に REVIEW.md エントリ"                        "$R/.claude/vibecorp.lock" "REVIEW.md:"
assert_file_contains "lock に ai-review.yml エントリ"                    "$R/.claude/vibecorp.lock" ".github/workflows/ai-review.yml:"
assert_file_contains "lock に ai-review-golden-test.yml エントリ"        "$R/.claude/vibecorp.lock" ".github/workflows/ai-review-golden-test.yml:"

# ============================================
# Step B: enabled: false に切替 + --update
# ============================================
echo ""
echo "--- Step B: enabled: false に切替 + --update ---"
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

# .coderabbit.yaml の内容を切替前に記録（不変性検証用）
coderabbit_before=""
if [[ -f "$R/.coderabbit.yaml" ]]; then
  coderabbit_before="$(shasum -a 256 "$R/.coderabbit.yaml" | awk '{print $1}')"
fi

bash "$INSTALL_SH" --update 2>/dev/null

# B-1. 3 ファイル全てが削除される
assert_file_not_exists "REVIEW.md が削除される"                          "$R/REVIEW.md"
assert_file_not_exists "ai-review.yml が削除される"                      "$R/.github/workflows/ai-review.yml"
assert_file_not_exists "ai-review-golden-test.yml が削除される"          "$R/.github/workflows/ai-review-golden-test.yml"

# B-2. 3 ファイル全ての base snapshot が削除される
assert_file_not_exists "REVIEW.md の base snapshot が削除される"         "$R/.claude/vibecorp-base/REVIEW.md"
assert_file_not_exists "ai-review.yml の base snapshot が削除される"     "$R/.claude/vibecorp-base/.github/workflows/ai-review.yml"
assert_file_not_exists "ai-review-golden-test.yml の base snapshot が削除される" "$R/.claude/vibecorp-base/.github/workflows/ai-review-golden-test.yml"

# B-3. 3 ファイル全ての base_hash エントリが vibecorp.lock から消える
if grep -q -e "^    REVIEW.md:" "$R/.claude/vibecorp.lock"; then
  fail "lock から REVIEW.md エントリが消えていない"
else
  pass "lock から REVIEW.md エントリが消える"
fi

if grep -q -e "^    .github/workflows/ai-review.yml:" "$R/.claude/vibecorp.lock"; then
  fail "lock から ai-review.yml エントリが消えていない"
else
  pass "lock から ai-review.yml エントリが消える"
fi

if grep -q -e "^    .github/workflows/ai-review-golden-test.yml:" "$R/.claude/vibecorp.lock"; then
  fail "lock から ai-review-golden-test.yml エントリが消えていない"
else
  pass "lock から ai-review-golden-test.yml エントリが消える"
fi

# B-4. .coderabbit.yaml は影響を受けない（CodeRabbit 単独運用継続）
if [[ -n "$coderabbit_before" && -f "$R/.coderabbit.yaml" ]]; then
  coderabbit_after="$(shasum -a 256 "$R/.coderabbit.yaml" | awk '{print $1}')"
  if [[ "$coderabbit_before" == "$coderabbit_after" ]]; then
    pass ".coderabbit.yaml は変更されない"
  else
    fail ".coderabbit.yaml が変更されている（CodeRabbit 単独運用継続のため不変であるべき）"
  fi
else
  fail ".coderabbit.yaml が存在しない（CodeRabbit 単独運用継続のため必須）"
fi

# B-5. テンプレートファイルは削除されない（再有効化のため保持）
# ※テンプレートは ${SCRIPT_DIR}/templates/ にあり、テストリポジトリ ($R) ではなく
# vibecorp 本体側のファイルなので、本体側の存在を確認する
assert_file_exists "templates/REVIEW.md.tpl は削除されない"              "${SCRIPT_DIR}/templates/REVIEW.md.tpl"
assert_file_exists "templates/ai-review.yml は削除されない"              "${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
assert_file_exists "templates/ai-review-golden-test.yml は削除されない"  "${SCRIPT_DIR}/templates/.github/workflows/ai-review-golden-test.yml"

cleanup

print_test_summary
