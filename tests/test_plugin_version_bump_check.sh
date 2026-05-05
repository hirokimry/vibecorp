#!/bin/bash
# test_plugin_version_bump_check.sh
# ─────────────────────────────────────────────
# Issue #458「plugin.json bump 漏れ自動検知 CI」の単体テスト
#
# scripts/check-plugin-version-bump.sh を 5 ケースで検証:
#   1. skills 追加 + version bump → exit 0
#   2. skills 追加 + version 不変 → exit 1（警告）
#   3. skills 不変 → exit 0
#   4. marketplace.json が base に不在 → exit 0（graceful skip）
#   5. skills 削除 + version 不変 → exit 1（警告）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

CHECK_SCRIPT="${SCRIPT_DIR}/scripts/check-plugin-version-bump.sh"

if [[ ! -x "$CHECK_SCRIPT" ]]; then
  fail "scripts/check-plugin-version-bump.sh が存在しないか実行権限なし"
  exit 1
fi

TMPDIR_ROOT=""
cleanup() {
  if [[ -n "$TMPDIR_ROOT" && -d "$TMPDIR_ROOT" ]]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
}
trap cleanup EXIT

# 仮想 plugin リポを作る:
#   - .claude-plugin/plugin.json と .claude-plugin/marketplace.json を持つ
#   - main commit の後に PR ブランチで内容を編集する
setup_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q -b main
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  mkdir -p .claude-plugin scripts tests/lib
  # check スクリプト本体をコピー（仮想リポ内で同じパスから呼び出すため）
  cp "$CHECK_SCRIPT" scripts/check-plugin-version-bump.sh
  chmod +x scripts/check-plugin-version-bump.sh
}

write_plugin_json() {
  local version="$1"
  cat > .claude-plugin/plugin.json <<EOF
{
  "name": "vibecorp",
  "version": "${version}",
  "description": "test"
}
EOF
}

write_marketplace_json() {
  # 残りの引数が skills の配列要素
  local skills_json
  skills_json=$(printf '"%s",' "$@")
  skills_json="[${skills_json%,}]"
  cat > .claude-plugin/marketplace.json <<EOF
{
  "name": "vibecorp",
  "plugins": [
    {
      "name": "vibecorp",
      "skills": ${skills_json}
    }
  ]
}
EOF
}

run_check() {
  local rc=0
  bash scripts/check-plugin-version-bump.sh main HEAD >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# ============================================
# Case 1: skills 追加 + version bump → exit 0
# ============================================
echo ""
echo "--- Case 1: skills 追加 + version bump → exit 0 ---"
setup_repo
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b"
git add -A
git commit -q -m "initial"
git checkout -q -b pr
write_plugin_json "0.2.0"
write_marketplace_json "./skills/a" "./skills/b" "./skills/c"
git add -A
git commit -q -m "add skill c + bump"
rc=$(run_check)
assert_eq "Case 1: exit 0" "0" "$rc"
cd "$SCRIPT_DIR"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 2: skills 追加 + version 不変 → exit 1
# ============================================
echo ""
echo "--- Case 2: skills 追加 + version 不変 → exit 1 ---"
setup_repo
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b"
git add -A
git commit -q -m "initial"
git checkout -q -b pr
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b" "./skills/c"
git add -A
git commit -q -m "add skill c without bump"
rc=$(run_check)
assert_eq "Case 2: exit 1" "1" "$rc"
cd "$SCRIPT_DIR"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 3: skills 不変 → exit 0
# ============================================
echo ""
echo "--- Case 3: skills 不変 → exit 0 ---"
setup_repo
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b"
git add -A
git commit -q -m "initial"
git checkout -q -b pr
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b"
echo "// unrelated" > README.md
git add -A
git commit -q -m "unrelated change"
rc=$(run_check)
assert_eq "Case 3: exit 0" "0" "$rc"
cd "$SCRIPT_DIR"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 4: marketplace.json が base に不在 → graceful skip (exit 0)
# ============================================
echo ""
echo "--- Case 4: marketplace.json が base に不在 → exit 0 (graceful skip) ---"
setup_repo
# base には marketplace.json なし
mkdir -p docs
echo "test" > docs/README.md
git add -A
git commit -q -m "initial without marketplace"
git checkout -q -b pr
# head で marketplace.json + plugin.json を新規追加
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a"
git add -A
git commit -q -m "introduce plugin manifests"
rc=$(run_check)
assert_eq "Case 4: exit 0 (graceful skip)" "0" "$rc"
cd "$SCRIPT_DIR"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 5: skills 削除 + version 不変 → exit 1
# ============================================
echo ""
echo "--- Case 5: skills 削除 + version 不変 → exit 1 ---"
setup_repo
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b" "./skills/c"
git add -A
git commit -q -m "initial"
git checkout -q -b pr
write_plugin_json "0.1.0"
write_marketplace_json "./skills/a" "./skills/b"
git add -A
git commit -q -m "remove skill c without bump"
rc=$(run_check)
assert_eq "Case 5: exit 1" "1" "$rc"
cd "$SCRIPT_DIR"
cleanup
TMPDIR_ROOT=""

print_test_summary
