#!/bin/bash
# test_lib_common_vibecorp_yml.sh — lib/common.sh の vibecorp.yml 実行時読み取り API テスト
# 用途: Issue #702 で追加した vibecorp_yml_get / vibecorp_yml_get_preset /
#       hook_skip_if_disabled の動作と、preset 別 hook 有効リストが install.sh の
#       プリセット引き算定義と一致することを検証する。
# 使い方: bash tests/test_lib_common_vibecorp_yml.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$LIB" ]]; then
  fail "前提ファイル lib/common.sh が存在しない"
  exit 1
fi

# shellcheck disable=SC1090
source "$LIB"

# テスト中は CLAUDE_PROJECT_DIR を一時ディレクトリに向ける
TMPDIR_TEST="$(mktemp -d)"
mkdir -p "${TMPDIR_TEST}/.claude"

cleanup() {
  rm -rf "${TMPDIR_TEST}" || true
}
trap cleanup EXIT

export CLAUDE_PROJECT_DIR="${TMPDIR_TEST}"
YML="${TMPDIR_TEST}/.claude/vibecorp.yml"

# ============================================
echo "=== vibecorp_yml_get（yml 不在時） ==="
# ============================================

rm -f "$YML"
RESULT="$(vibecorp_yml_get hooks role-gate)"
assert_eq "yml 不在時は空文字を返す" "" "$RESULT"

RESULT="$(vibecorp_yml_get coderabbit enabled)"
assert_eq "yml 不在時は section 問わず空文字" "" "$RESULT"

# ============================================
echo ""
echo "=== vibecorp_yml_get（key 未定義時） ==="
# ============================================

cat > "$YML" <<'YAML'
name: test-project
preset: standard
language: ja
coderabbit:
  enabled: true
hooks:
  role-gate: false
  guide-gate: true
YAML

RESULT="$(vibecorp_yml_get hooks not-exist)"
assert_eq "未定義 key は空文字を返す" "" "$RESULT"

RESULT="$(vibecorp_yml_get not-exist-section foo)"
assert_eq "未定義 section も空文字を返す" "" "$RESULT"

# ============================================
echo ""
echo "=== vibecorp_yml_get（値取得） ==="
# ============================================

RESULT="$(vibecorp_yml_get coderabbit enabled)"
assert_eq "coderabbit.enabled の値を取得" "true" "$RESULT"

RESULT="$(vibecorp_yml_get hooks role-gate)"
assert_eq "hooks.role-gate の値を取得（false）" "false" "$RESULT"

RESULT="$(vibecorp_yml_get hooks guide-gate)"
assert_eq "hooks.guide-gate の値を取得（true）" "true" "$RESULT"

# ============================================
echo ""
echo "=== vibecorp_yml_get_preset ==="
# ============================================

# preset: standard の場合
RESULT="$(vibecorp_yml_get_preset)"
assert_eq "preset: standard を読み取る" "standard" "$RESULT"

# preset: full
cat > "$YML" <<'YAML'
name: test-project
preset: full
language: ja
YAML
RESULT="$(vibecorp_yml_get_preset)"
assert_eq "preset: full を読み取る" "full" "$RESULT"

# preset: minimal
cat > "$YML" <<'YAML'
name: test-project
preset: minimal
language: ja
YAML
RESULT="$(vibecorp_yml_get_preset)"
assert_eq "preset: minimal を読み取る" "minimal" "$RESULT"

# preset 未定義（フィールドなし）
cat > "$YML" <<'YAML'
name: test-project
language: ja
YAML
RESULT="$(vibecorp_yml_get_preset)"
assert_eq "preset 未定義時はデフォルト standard" "standard" "$RESULT"

# yml 不在時
rm -f "$YML"
RESULT="$(vibecorp_yml_get_preset)"
assert_eq "yml 不在時はデフォルト standard" "standard" "$RESULT"

# ============================================
echo ""
echo "=== hook_skip_if_disabled（yml 明示無効化） ==="
# ============================================

cat > "$YML" <<'YAML'
name: test-project
preset: full
language: ja
hooks:
  guide-gate: false
  role-gate: true
YAML

# yml で明示的に false → skip すべき (return 0)
if hook_skip_if_disabled guide-gate; then
  pass "hooks: guide-gate: false → hook_skip_if_disabled が 0 を返す（skip）"
else
  fail "hooks: guide-gate: false → hook_skip_if_disabled が 0 を返すべき"
fi

# yml で明示的に true（かつ preset 有効リスト内）→ continue (return 1)
if hook_skip_if_disabled role-gate; then
  fail "hooks: role-gate: true（full preset）→ continue すべき"
else
  pass "hooks: role-gate: true（full preset）→ hook_skip_if_disabled が 1 を返す（continue）"
fi

# ============================================
echo ""
echo "=== hook_skip_if_disabled（preset 別有効リスト） ==="
# ============================================

# minimal: 共通 6 hook のみ有効
cat > "$YML" <<'YAML'
name: test-project
preset: minimal
language: ja
YAML

# 共通 hook は continue
for common_hook in block-api-bypass command-log protect-branch protect-files protect-knowledge-bash-writes protect-knowledge-direct-writes; do
  if hook_skip_if_disabled "$common_hook"; then
    fail "minimal preset: ${common_hook} は continue すべき"
  else
    pass "minimal preset: ${common_hook} → continue"
  fi
done

# minimal 限定で skip すべき hook
for skipped_hook in sync-gate review-gate guide-gate role-gate diagnose-guard; do
  if hook_skip_if_disabled "$skipped_hook"; then
    pass "minimal preset: ${skipped_hook} → skip"
  else
    fail "minimal preset: ${skipped_hook} は skip すべき"
  fi
done

# standard: 共通 + sync-gate / review-gate / guide-gate 有効
cat > "$YML" <<'YAML'
name: test-project
preset: standard
language: ja
YAML

for std_hook in sync-gate session-harvest-gate review-gate guide-gate; do
  if hook_skip_if_disabled "$std_hook"; then
    fail "standard preset: ${std_hook} は continue すべき"
  else
    pass "standard preset: ${std_hook} → continue"
  fi
done

for std_skipped in role-gate diagnose-guard; do
  if hook_skip_if_disabled "$std_skipped"; then
    pass "standard preset: ${std_skipped} → skip"
  else
    fail "standard preset: ${std_skipped} は skip すべき"
  fi
done

# full: 全 hook 有効
cat > "$YML" <<'YAML'
name: test-project
preset: full
language: ja
YAML

for full_hook in sync-gate session-harvest-gate review-gate guide-gate role-gate diagnose-guard; do
  if hook_skip_if_disabled "$full_hook"; then
    fail "full preset: ${full_hook} は continue すべき"
  else
    pass "full preset: ${full_hook} → continue"
  fi
done

# ============================================
echo ""
echo "=== preset 別 hook 有効リストが install.sh と一致 ==="
# ============================================

INSTALL_SH="${SCRIPT_DIR}/install.sh"
HOOKS_DIR_TEMPLATE="${SCRIPT_DIR}/hooks"

if [[ ! -f "$INSTALL_SH" ]]; then
  fail "install.sh が存在しない（前提ファイル）"
  exit 1
fi
if [[ ! -d "$HOOKS_DIR_TEMPLATE" ]]; then
  fail "hooks/ が存在しない（前提ディレクトリ）"
  exit 1
fi

# install.sh のプリセット別 rm -f リストから、削除される hook 名を抽出する。
# minimal / standard ブロックそれぞれの hook 削除行のみ拾う（skills / agents 削除行は除外）。
# 実存する hook ファイルのみ照合対象とし、レガシー clean-up（実在しない hook の rm）は無視する。
extract_removed_hooks() {
  local preset="$1"
  awk -v preset="$preset" '
    $0 ~ "^    " preset ")" { in_block = 1; next }
    in_block && /^    ;;/ { in_block = 0 }
    in_block && /rm -f .*hooks_dir.*\.sh"/ {
      # rm -f "${hooks_dir}/role-gate.sh" から basename を抽出
      match($0, /\/[^\/]+\.sh"/)
      if (RSTART > 0) {
        hook = substr($0, RSTART + 1, RLENGTH - 2)
        sub(/\.sh$/, "", hook)
        print hook
      }
    }
  ' "$INSTALL_SH"
}

# 実存する hook 一覧（拡張子なし）
existing_hooks=()
while IFS= read -r f; do
  name="$(basename "$f")"
  existing_hooks+=("${name%.sh}")
done < <(find "$HOOKS_DIR_TEMPLATE" -maxdepth 1 -type f -name '*.sh' | sort)

# minimal preset での install.sh 削除リスト ∩ 実存 hook → lib の skip 判定で 0（skip）になるべき
echo "  minimal で install.sh が削除する hook を照合中..."
for removed in $(extract_removed_hooks "minimal"); do
  # 実存 hook かどうかチェック
  found=0
  for existing in "${existing_hooks[@]}"; do
    if [[ "$existing" == "$removed" ]]; then
      found=1
      break
    fi
  done
  [[ "$found" == "1" ]] || continue

  cat > "$YML" <<EOF
name: test-project
preset: minimal
language: ja
EOF

  if hook_skip_if_disabled "$removed"; then
    pass "install.sh minimal で削除される ${removed} は lib でも skip 判定"
  else
    fail "install.sh minimal で削除される ${removed} が lib で continue 判定（不整合）"
  fi
done

# standard preset での照合
echo "  standard で install.sh が削除する hook を照合中..."
for removed in $(extract_removed_hooks "standard"); do
  found=0
  for existing in "${existing_hooks[@]}"; do
    if [[ "$existing" == "$removed" ]]; then
      found=1
      break
    fi
  done
  [[ "$found" == "1" ]] || continue

  cat > "$YML" <<EOF
name: test-project
preset: standard
language: ja
EOF

  if hook_skip_if_disabled "$removed"; then
    pass "install.sh standard で削除される ${removed} は lib でも skip 判定"
  else
    fail "install.sh standard で削除される ${removed} が lib で continue 判定（不整合）"
  fi
done

# 逆方向: install.sh が削除しない（=有効として残す）hook が lib で continue 判定になるか
# minimal / standard 両方で「残存対象→continue」を照合する（順方向「削除対象→skip」と対称）。
echo "  install.sh が minimal で残す hook を逆方向照合..."
removed_minimal=$(extract_removed_hooks "minimal")
# plugin native (#720): install.sh が hook 削除行を持たなくなったため、逆方向照合は無意味
if [[ -z "$removed_minimal" ]]; then
  pass "minimal: install.sh が hooks を物理削除しなくなった (#720, plugin native 配布)"
fi
for existing in "${existing_hooks[@]}"; do
  [[ -n "$removed_minimal" ]] || continue
  is_removed=0
  for r in $removed_minimal; do
    if [[ "$r" == "$existing" ]]; then
      is_removed=1
      break
    fi
  done
  [[ "$is_removed" == "0" ]] || continue

  cat > "$YML" <<EOF
name: test-project
preset: minimal
language: ja
EOF

  if hook_skip_if_disabled "$existing"; then
    fail "install.sh minimal で残る ${existing} が lib で skip 判定（不整合）"
  else
    pass "install.sh minimal で残る ${existing} は lib でも continue 判定"
  fi
done

# standard preset の残存対象: 実存 hook − standard 削除 hook
echo "  install.sh が standard で残す hook を逆方向照合..."
removed_standard=$(extract_removed_hooks "standard")
# plugin native (#720): install.sh が hook 削除行を持たなくなったため、逆方向照合は無意味
if [[ -z "$removed_standard" ]]; then
  pass "standard: install.sh が hooks を物理削除しなくなった (#720, plugin native 配布)"
fi
for existing in "${existing_hooks[@]}"; do
  [[ -n "$removed_standard" ]] || continue
  is_removed=0
  for r in $removed_standard; do
    if [[ "$r" == "$existing" ]]; then
      is_removed=1
      break
    fi
  done
  [[ "$is_removed" == "0" ]] || continue

  cat > "$YML" <<EOF
name: test-project
preset: standard
language: ja
EOF

  if hook_skip_if_disabled "$existing"; then
    fail "install.sh standard で残る ${existing} が lib で skip 判定（不整合）"
  else
    pass "install.sh standard で残る ${existing} は lib でも continue 判定"
  fi
done

# ============================================
echo ""
print_test_summary
