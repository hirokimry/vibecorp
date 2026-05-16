#!/bin/bash
# test_install_migrate_forbidden_targets.sh
# ─────────────────────────────────────────────
# install.sh の migrate_forbidden_targets_skills の動作検証
# Issue #460 / CodeRabbit 指摘: 既存 vibecorp.yml に skills/** を --update 時に自動補完する
#
# 検証対象:
#   1. skills/** が無い既存 yml で skills/** が追加される
#   2. skills/** が既にある yml は変更されない（冪等性）
#   3. forbidden_targets セクション自体が無い yml は触らない（利用者の意図的削除を尊重）
#   4. diagnose セクション自体が無い yml は触らない
#   5. vibecorp.yml 不在時は no-op

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# install.sh を source して関数を呼べるようにする
# install.sh は末尾の if [[ ${BASH_SOURCE[0]} == "$0" ]] ガードで main 自動起動を抑止している
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install.sh"

echo ""
echo "=== migrate_forbidden_targets_skills のテスト ==="

# 単体テスト用ヘルパー: 一時的な vibecorp.yml を作って関数を呼ぶ
run_migrate_with_yml() {
  local yml_content="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  mkdir -p "${tmp_root}/.claude"
  if [[ -n "$yml_content" ]]; then
    printf '%s' "$yml_content" > "${tmp_root}/.claude/vibecorp.yml"
  fi

  REPO_ROOT="$tmp_root" migrate_forbidden_targets_skills >/dev/null 2>&1

  if [[ -f "${tmp_root}/.claude/vibecorp.yml" ]]; then
    cat "${tmp_root}/.claude/vibecorp.yml"
  fi
  rm -rf "$tmp_root"
}

# 1. skills/** が無い既存 yml で skills/** が追加される（典型的な既存ユーザーシナリオ）
echo ""
echo "--- 1. skills/** 不在時に追加 ---"
result=$(run_migrate_with_yml "$(cat <<'EOF'
name: test
preset: full
language: ja
diagnose:
  enabled: true
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
coderabbit:
  enabled: true
EOF
)")
if echo "$result" | grep -q -F '"skills/**"'; then
  pass "skills/** が無い既存 yml に skills/** が追加される"
else
  fail "skills/** が無い既存 yml に skills/** が追加されない"
fi
# 既存エントリが保持されているか
for existing in '"hooks/*.sh"' '"vibecorp.yml"' '"MVV.md"' '"SECURITY.md"' '"POLICY.md"'; do
  if echo "$result" | grep -q -F "$existing"; then
    pass "既存エントリ $existing が保持される"
  else
    fail "既存エントリ $existing が消えた"
  fi
done
# 後段の coderabbit セクションが保持されているか（YAML 構造保護の回帰）
if echo "$result" | grep -q '^coderabbit:'; then
  pass "後段の coderabbit セクションが保持される"
else
  fail "後段の coderabbit セクションが壊れた"
fi

# 2. skills/** が既にある yml は変更されない（冪等性）
echo ""
echo "--- 2. skills/** 既存時は冪等 ---"
result=$(run_migrate_with_yml "$(cat <<'EOF'
name: test
preset: full
language: ja
diagnose:
  enabled: true
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
    - "skills/**"
EOF
)")
# skills/** の出現回数が 1 回のみ（冪等）
count=$(echo "$result" | grep -c -F '"skills/**"' || true)
if [[ "$count" -eq 1 ]]; then
  pass "skills/** が既に 1 件のとき重複追加されない（冪等）"
else
  fail "skills/** が ${count} 件になった（冪等性違反）"
fi

# 3. forbidden_targets セクション自体が無い yml は触らない
echo ""
echo "--- 3. forbidden_targets 不在時は触らない ---"
result=$(run_migrate_with_yml "$(cat <<'EOF'
name: test
preset: full
language: ja
diagnose:
  enabled: true
EOF
)")
if echo "$result" | grep -q -F 'skills/**'; then
  fail "forbidden_targets 不在時に skills/** が追加された（利用者の削除意図を破壊）"
else
  pass "forbidden_targets 不在時は触らない（利用者の削除意図を尊重）"
fi

# 4. diagnose セクション自体が無い yml は触らない
echo ""
echo "--- 4. diagnose セクション不在時は触らない ---"
result=$(run_migrate_with_yml "$(cat <<'EOF'
name: test
preset: minimal
language: ja
coderabbit:
  enabled: true
EOF
)")
if echo "$result" | grep -q -F 'skills/**'; then
  fail "diagnose セクション不在時に skills/** が追加された（minimal preset 等で誤反映）"
else
  pass "diagnose セクション不在時は触らない（minimal preset 等で誤反映しない）"
fi

# 5. vibecorp.yml 不在時は no-op
echo ""
echo "--- 5. vibecorp.yml 不在時は no-op ---"
result=$(run_migrate_with_yml "")
if [[ -z "$result" ]]; then
  pass "vibecorp.yml 不在時は no-op（クラッシュしない）"
else
  fail "vibecorp.yml 不在時に予期しない出力: $result"
fi

# 6. inline 空配列形式（forbidden_targets: []）でも YAML が壊れず block 形式に正規化される
#    CodeRabbit Minor 指摘（PR #586）への対応 — inline `[]` 後ろに block エントリを継ぎ足すと YAML が壊れる
echo ""
echo "--- 6. inline 空配列形式は block 形式に正規化される ---"
result=$(run_migrate_with_yml "$(cat <<'EOF'
name: test
preset: full
language: ja
diagnose:
  enabled: true
  forbidden_targets: []
coderabbit:
  enabled: true
EOF
)")
# 期待: forbidden_targets が block 形式になり、skills/** が 1 件目として入る
if echo "$result" | grep -q -E '^  forbidden_targets:[[:space:]]*$'; then
  pass "inline 空配列が block 形式（forbidden_targets:）に正規化される"
else
  fail "inline 空配列が block 形式に正規化されない"
fi
if echo "$result" | grep -q -F '    - "skills/**"'; then
  pass "block 化した forbidden_targets に skills/** が 1 件目として挿入される"
else
  fail "skills/** が挿入されない"
fi
# 旧 inline 空配列リテラル `[]` が消えていること（残ると YAML が壊れる）
if echo "$result" | grep -q -F 'forbidden_targets: []'; then
  fail "inline 空配列リテラル '[]' が残っている（YAML 構造破壊）"
else
  pass "inline 空配列リテラル '[]' は消えている"
fi
# 後段の coderabbit セクションが保持されていること（YAML 構造保護回帰）
if echo "$result" | grep -q '^coderabbit:'; then
  pass "inline 空配列 → block 化後も後段 coderabbit セクションが保持される"
else
  fail "inline 空配列 → block 化で後段 coderabbit セクションが壊れた"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
