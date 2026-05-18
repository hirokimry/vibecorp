#!/bin/bash
# test_release_publish.sh
# ─────────────────────────────────────────────
# Issue #625: .github/scripts/release-publish.sh の挙動テスト。
# Conventional Commits 解析・semver 計算・タグ衝突判定・early exit の各経路を
# サンドボックス git リポジトリで再現して検証する。
#
# 実装制約:
#   - GitHub への push / Release API 呼び出しは行わない（stub する）
#   - git push origin / gh release create は stub に置き換えて副作用を遮断する
#   - サンドボックス内でのタグ作成は本物の git tag が走る（temp repo 内のみ）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

TARGET="${SCRIPT_DIR}/.github/scripts/release-publish.sh"

if [ ! -x "$TARGET" ]; then
  fail "release-publish.sh が存在し実行可能である"
  exit 1
fi

TMP_ROOT=""

cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT" || true
  fi
}
trap cleanup EXIT

# サンドボックス git リポジトリと stub PATH をセットアップする。
# サンドボックスごとに別 temp ディレクトリを使い、テスト間で状態を汚さない。
setup_sandbox() {
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-publish-test.XXXXXX")"
  local repo_dir="${TMP_ROOT}/repo"
  local stub_bin="${TMP_ROOT}/bin"

  mkdir -p "$repo_dir" "$stub_bin"

  # stub: gh — release create / view を握りつぶす
  cat > "${stub_bin}/gh" <<'STUB'
#!/usr/bin/env bash
# テスト用 stub: gh release create / view は副作用なく成功させる
case "$1 $2" in
  "release view")
    # 既存 release は無い前提で 1 を返す
    exit 1
    ;;
  "release create")
    echo "[stub gh] release create $*"
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "${stub_bin}/gh"

  # stub: git push を握りつぶす（origin 未設定の temp repo で fail しないように）
  # 他の git サブコマンドは本物に委譲する
  cat > "${stub_bin}/git" <<'STUB'
#!/usr/bin/env bash
# テスト用 stub: git push のみ握りつぶし、他は本物の git に委譲
if [ "${1:-}" = "push" ]; then
  echo "[stub git] push $*"
  exit 0
fi
exec /usr/bin/env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" /usr/bin/git "$@"
STUB
  # 上記の env -i は環境を最小化しすぎるので、テスト時は単に本物 git を呼ぶだけで良い
  cat > "${stub_bin}/git" <<'STUB'
#!/usr/bin/env bash
# テスト用 stub: git push のみ握りつぶし、他は本物の git に委譲
if [ "${1:-}" = "push" ]; then
  echo "[stub git] push $*"
  exit 0
fi
# 自スクリプトを PATH から外して本物の git を呼ぶ
PATH_WITHOUT_STUB="$(echo ":$PATH:" | sed -e "s|:$(dirname "$0"):|:|g" -e 's|^:||' -e 's|:$||')"
PATH="$PATH_WITHOUT_STUB" command git "$@"
STUB
  chmod +x "${stub_bin}/git"

  # repo を初期化（本物 git で直接、stub を経由しない）
  command git -C "$repo_dir" init -q
  command git -C "$repo_dir" config user.email "test@example.com"
  command git -C "$repo_dir" config user.name "test"

  echo "$repo_dir"
  echo "$stub_bin"
}

# サンドボックスでスクリプトを実行する
# 引数: <repo_dir> <stub_bin>
run_script_in() {
  local repo_dir="$1"
  local stub_bin="$2"
  (
    cd "$repo_dir"
    PATH="${stub_bin}:${PATH}" bash "$TARGET" 2>&1
  )
}

# git コマンドを repo 内で実行（stub を経由しない）
commit_in() {
  local repo_dir="$1"
  shift
  local message="$1"
  shift
  echo "$message" > "${repo_dir}/file-$RANDOM.txt"
  command git -C "$repo_dir" add -A
  command git -C "$repo_dir" commit -q -m "$message"
}

tag_in() {
  local repo_dir="$1"
  local tag="$2"
  command git -C "$repo_dir" tag "$tag"
}

echo "=== Issue #625: release-publish.sh の挙動テスト ==="
echo ""

# --- ケース 1: タグなし + chore のみ → リリーススキップ ---
echo "--- ケース 1: タグなし + chore のみ → リリーススキップ ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "chore: initial"
commit_in "$repo" "chore: bump deps"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリース対象のコミットがないためスキップ"; then
  pass "chore のみのコミット群でリリースをスキップする"
else
  fail "chore のみでスキップしない: $output"
fi
cleanup

# --- ケース 2: タグなし + feat あり → version 0.1.0 ---
echo "--- ケース 2: タグなし + feat あり → 初回リリース 0.1.0 ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: first feature"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v0.1.0"; then
  pass "初回リリースは v0.1.0"
else
  fail "初回リリースが v0.1.0 にならない: $output"
fi
cleanup

# --- ケース 3: v1.0.0 タグあり + fix → v1.0.1 ---
echo "--- ケース 3: v1.0.0 タグあり + fix → v1.0.1 ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v1.0.0"
commit_in "$repo" "fix: bug fix"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v1.0.1"; then
  pass "fix で patch bump（v1.0.0 → v1.0.1）"
else
  fail "patch bump しない: $output"
fi
cleanup

# --- ケース 4: v1.0.0 タグあり + feat → v1.1.0 ---
echo "--- ケース 4: v1.0.0 タグあり + feat → v1.1.0 ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v1.0.0"
commit_in "$repo" "feat: new feature"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v1.1.0"; then
  pass "feat で minor bump（v1.0.0 → v1.1.0）"
else
  fail "minor bump しない: $output"
fi
cleanup

# --- ケース 5: v1.0.0 タグあり + feat! (breaking) → v2.0.0 ---
echo "--- ケース 5: v1.0.0 タグあり + feat! → v2.0.0 ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v1.0.0"
commit_in "$repo" "feat!: breaking change"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v2.0.0"; then
  pass "feat! で major bump（v1.0.0 → v2.0.0）"
else
  fail "major bump しない: $output"
fi
cleanup

# --- ケース 6: タグ部分一致の防止（v1.2.3 vs v1.2.30） ---
echo "--- ケース 6: タグ完全一致判定（v1.2.30 存在時に v1.2.3 を別物として扱う） ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v1.2.30"
commit_in "$repo" "fix: tiny fix"
# 直前タグ v1.2.30 から fix なら v1.2.31 が新タグとなる（部分一致で誤って既存扱いされないこと）
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v1.2.31"; then
  pass "v1.2.30 + fix で v1.2.31（v1.2.3 と誤マッチしない）"
else
  fail "v1.2.31 になっていない: $output"
fi
cleanup

# --- ケース 7: feat + fix 混在 → minor 優先 ---
echo "--- ケース 7: feat + fix 混在 → minor bump 優先 ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v2.5.7"
commit_in "$repo" "fix: bug"
commit_in "$repo" "feat: feature"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v2.6.0"; then
  pass "feat + fix で minor bump（v2.5.7 → v2.6.0）"
else
  fail "minor 優先になっていない: $output"
fi
cleanup

# --- ケース 8: コミットメッセージにパイプ (`|`) を含んでも parser が壊れない（CR Major 指摘対応の検証） ---
echo "--- ケース 8: メッセージにパイプを含んでも parser が壊れない ---"
read -r repo stub < <(setup_sandbox | xargs)
commit_in "$repo" "feat: initial"
tag_in "$repo" "v1.0.0"
commit_in "$repo" "feat: support A | B | C in parser"
output=$(run_script_in "$repo" "$stub")
if echo "$output" | grep -q "リリースバージョン: v1.1.0"; then
  pass "パイプ含むメッセージでも minor bump が動く"
else
  fail "パイプ含むメッセージで parser が壊れた: $output"
fi
cleanup

echo ""
print_test_summary
