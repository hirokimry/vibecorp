#!/bin/bash
# diagnose-guard.sh のユニットテスト
# 使い方: bash tests/test_diagnose_guard.sh
# CI: GitHub Actions で自動実行

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"
# Issue #703: hook が ${HOOK_DIR}/../lib/ で lib を解決するようになり、hooks/ から実行する経路では templates/claude/lib/ に lib が必要になる（plugin native 配布後の runtime 配置と同じ構造を再現する）
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/hook_fixtures.sh"
sync_lib_for_hook_tests

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/hooks/diagnose-guard.sh"
LIB_DIR="${SCRIPT_DIR}/lib"
TMPDIR_TEST=""
STAMP_FILE=""

assert_blocked() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    pass "$desc"
  else
    fail "$desc (期待: deny, 実際: allow)"
  fi
}

assert_allowed() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "deny"'; then
    fail "$desc (期待: allow, 実際: deny)"
  else
    pass "$desc"
  fi
}

# --- テスト用プロジェクトの準備 ---

setup_project_dir() {
  TMPDIR_TEST=$(mktemp -d)
  mkdir -p "${TMPDIR_TEST}/.claude/lib"
  cp "${LIB_DIR}/common.sh" "${TMPDIR_TEST}/.claude/lib/common.sh"
  # path_normalize.sh が必要（diagnose-guard.sh が symlink bypass 対策で source する）
  cp "${LIB_DIR}/path_normalize.sh" "${TMPDIR_TEST}/.claude/lib/path_normalize.sh"
  ( cd "$TMPDIR_TEST" && git init -q . && git config user.email t@example.com && git config user.name t )
  cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
diagnose:
  enabled: true
  max_issues_per_run: 5
  max_issues_per_day: 10
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
    - "skills/**"
YAML
  export CLAUDE_PROJECT_DIR="$TMPDIR_TEST"
  export HOME="${TMPDIR_TEST}/fakehome"
  export XDG_CACHE_HOME="${TMPDIR_TEST}/xdg-cache"
  mkdir -p "$HOME" "$XDG_CACHE_HOME"
  # スタンプパス計算
  STAMP_FILE=$( source "${TMPDIR_TEST}/.claude/lib/common.sh" && vibecorp_state_path diagnose-active )
  mkdir -p "$(dirname "$STAMP_FILE")"
  rm -f "$STAMP_FILE"
}

# --- クリーンアップ ---

cleanup() {
  if [ -n "$TMPDIR_TEST" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST" || true
  fi
}
trap cleanup EXIT

# ============================================
echo "=== diagnose-guard.sh ==="
# ============================================

setup_project_dir

# --- スタンプなし（通常時）---

echo "--- スタンプなし（通常動作）---"

# 1. スタンプなしで hooks/*.sh を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | bash "$HOOK")
assert_allowed "スタンプなしで hooks/*.sh 編集 → allow" "$OUTPUT"

# 2. スタンプなしで vibecorp.yml を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/vibecorp.yml"}}' | bash "$HOOK")
assert_allowed "スタンプなしで vibecorp.yml 編集 → allow" "$OUTPUT"

# 3. スタンプなしで MVV.md を編集 → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | bash "$HOOK")
assert_allowed "スタンプなしで MVV.md 編集 → allow" "$OUTPUT"

echo "--- スタンプあり（diagnose 実行中）---"
touch "$STAMP_FILE"

# 4. hooks/*.sh への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に hooks/*.sh 編集 → deny" "$OUTPUT"

# 5. vibecorp.yml への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/vibecorp.yml"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に vibecorp.yml 編集 → deny" "$OUTPUT"

# 6. MVV.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に MVV.md 編集 → deny" "$OUTPUT"

# 7. diagnose-guard.sh 自体への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/diagnose-guard.sh"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に diagnose-guard.sh 自体の編集 → deny" "$OUTPUT"

# 8. SECURITY.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/SECURITY.md"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に SECURITY.md 編集 → deny" "$OUTPUT"

# 9. POLICY.md への編集 → deny
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/POLICY.md"}}' | bash "$HOOK")
assert_blocked "diagnose 実行中に POLICY.md 編集 → deny" "$OUTPUT"

# 10. 通常のソースファイル → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/src/main.ts"}}' | bash "$HOOK")
assert_allowed "diagnose 実行中でも通常ファイル編集 → allow" "$OUTPUT"

# 11. docs/ 配下のファイル → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/docs/architecture.md"}}' | bash "$HOOK")
assert_allowed "diagnose 実行中でも docs/ 配下は → allow" "$OUTPUT"

OUTPUT=$(echo '{"tool_input":{}}' | bash "$HOOK")
assert_allowed "file_path が空 → allow" "$OUTPUT"

# --- glob → regex 変換の末尾アンカー回帰テスト（Issue #514） ---

echo "--- glob → regex 末尾アンカー回帰テスト ---"

# 12a. hooks/foo.sh.bak は hooks/*.sh の glob にマッチしない（.bak は .sh で終わらない）
# 末尾アンカーがないと regex `hooks/[^/]*\.sh` が `hooks/foo.sh.bak` にもマッチして
# 誤って deny してしまう。本テストは末尾 `$` の回帰を防ぐ。
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh.bak"}}' | bash "$HOOK")
assert_allowed "hooks/*.sh パターンは hooks/foo.sh.bak をマッチしない（末尾 \$ アンカー） → allow" "$OUTPUT"

# 12b. hooks/foo.sh.tmp も同様にマッチしない
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh.tmp"}}' | bash "$HOOK")
assert_allowed "hooks/*.sh パターンは hooks/foo.sh.tmp をマッチしない（末尾 \$ アンカー） → allow" "$OUTPUT"

# 12c. hooks/foo.sh はちゃんと deny される（既存挙動の維持確認）
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/foo.sh"}}' | bash "$HOOK")
assert_blocked "hooks/*.sh パターンは hooks/foo.sh をマッチする（既存挙動維持） → deny" "$OUTPUT"

# --- skills/** 再帰マッチテスト（Issue #460） ---

echo "--- skills/** 再帰マッチテスト ---"

# 12d. skills/** はトップレベル .claude/skills/SKILL.md を deny する（Issue #460 完了条件）
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills/SKILL.md"}}' | bash "$HOOK")
assert_blocked "skills/** パターンは .claude/skills/SKILL.md を deny する（Issue #460） → deny" "$OUTPUT"

# 12e. skills/** はネストした .claude/skills/ship/SKILL.md も deny する（** の再帰マッチ）
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills/ship/SKILL.md"}}' | bash "$HOOK")
assert_blocked "skills/** パターンは .claude/skills/ship/SKILL.md を deny する（再帰マッチ） → deny" "$OUTPUT"

# 12f. skills/** は深くネストした .claude/skills/ship-parallel/lib/util.sh も deny する
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills/ship-parallel/lib/util.sh"}}' | bash "$HOOK")
assert_blocked "skills/** パターンは .claude/skills/ship-parallel/lib/util.sh を deny する（深い再帰） → deny" "$OUTPUT"

# 12g. skills/** は `.claude/skills.json` のように skills 直後に / がないパスはマッチしない（境界）
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills.json"}}' | bash "$HOOK")
assert_allowed "skills/** パターンは .claude/skills.json をマッチしない（境界 / 必須） → allow" "$OUTPUT"

# --- シンボリックリンク bypass 回帰テスト（Issue #460 security-analyst H1） ---

echo "--- シンボリックリンク bypass 回帰テスト ---"

# 12h. skillz -> skills シンボリックリンク経由の書き込みは realpath 正規化で実体パスに解決され deny される
# 設計: 自律ループ内で攻撃者が .claude/skillz -> .claude/skills を作っても、
# diagnose-guard.sh が CANONICAL_PATH を生成して `skills/**` パターンで deny する。
SYMLINK_TEST_DIR="${TMPDIR_TEST}/symlink_test"
mkdir -p "${SYMLINK_TEST_DIR}/.claude/skills/diagnose"
ln -sf skills "${SYMLINK_TEST_DIR}/.claude/skillz"
# symlink 経由のパスで Write を試みる（CANONICAL_PATH 解決後に skills/diagnose/SKILL.md となる）
OUTPUT=$(echo '{"tool_input":{"file_path":"'"${SYMLINK_TEST_DIR}/.claude/skillz/diagnose/SKILL.md"'"}}' | bash "$HOOK")
# realpath / python3 が使える環境では deny される（symlink を解決して .claude/skills/ にマッチ）
# どちらも使えない環境では原文パスを使うため `skillz/` が `skills/.*$` にマッチせず allow される
# このテストは realpath / python3 のいずれかが存在する前提（CI / 開発機の通常前提）
if command -v realpath >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  assert_blocked "シンボリックリンク .claude/skillz -> .claude/skills 経由の書込みは realpath 正規化で deny される（H1 回帰）" "$OUTPUT"
else
  echo "  SKIP: realpath / python3 が不在の環境では symlink bypass テストはスキップ"
fi
# クリーンアップ
rm -rf "${SYMLINK_TEST_DIR}" || true

# --- 別プロジェクトの state ディレクトリ分離テスト ---

echo "--- worktree 分離テスト ---"

# スタンプを削除して別プロジェクトとして試す
rm -f "$STAMP_FILE"

# 13. 別の CLAUDE_PROJECT_DIR にスタンプがあっても影響しない（worktree 分離）
ALT_DIR=$(mktemp -d)
mkdir -p "${ALT_DIR}/.claude/lib"
cp "${LIB_DIR}/common.sh" "${ALT_DIR}/.claude/lib/common.sh"
( cd "$ALT_DIR" && git init -q . && git config user.email t@example.com && git config user.name t )
# ALT_DIR 用のスタンプパスを計算して作成
ALT_STAMP_FILE=$( CLAUDE_PROJECT_DIR="$ALT_DIR" bash -c 'source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh && vibecorp_state_path diagnose-active' )
mkdir -p "$(dirname "$ALT_STAMP_FILE")"
touch "$ALT_STAMP_FILE"
# 元の CLAUDE_PROJECT_DIR (TMPDIR_TEST) ではスタンプなし → allow
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/protect-files.sh"}}' | bash "$HOOK")
assert_allowed "別の CLAUDE_PROJECT_DIR の state は影響しない → allow" "$OUTPUT"
rm -rf "$ALT_DIR"
rm -rf "$(dirname "$ALT_STAMP_FILE")" || true

echo "--- デフォルト forbidden_targets テスト ---"

# diagnose セクションなしの vibecorp.yml を作成
cat > "${TMPDIR_TEST}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
YAML

touch "$STAMP_FILE"

# 14. diagnose セクションなしでもデフォルトの保護が有効
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/hooks/sync-gate.sh"}}' | bash "$HOOK")
assert_blocked "diagnose セクションなしでもデフォルトの hooks/*.sh 保護 → deny" "$OUTPUT"

# 15. デフォルトで MVV.md も保護
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/MVV.md"}}' | bash "$HOOK")
assert_blocked "diagnose セクションなしでもデフォルトの MVV.md 保護 → deny" "$OUTPUT"

# 16. デフォルトで通常ファイルは通す
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/src/app.ts"}}' | bash "$HOOK")
assert_allowed "diagnose セクションなしでも通常ファイルは → allow" "$OUTPUT"

# 16a. デフォルトで skills/** も保護される（Issue #460 — vibecorp.yml が壊れていても defense-in-depth）
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills/SKILL.md"}}' | bash "$HOOK")
assert_blocked "diagnose セクションなしでもデフォルトの skills/** 保護 → deny" "$OUTPUT"

# 16b. デフォルト skills/** はネストもブロック
OUTPUT=$(echo '{"tool_input":{"file_path":"/path/to/.claude/skills/diagnose/SKILL.md"}}' | bash "$HOOK")
assert_blocked "diagnose セクションなしでもデフォルトの skills/** 再帰保護 → deny" "$OUTPUT"

# 17. 旧パス .claude/state/diagnose-active には書き込まれない（退行検知）
if [ ! -e "${TMPDIR_TEST}/.claude/state/diagnose-active" ]; then
  pass "旧パス .claude/state/diagnose-active は存在しない"
else
  fail "旧パス .claude/state/diagnose-active が存在する（退行）"
fi

# --- クリーンアップ ---
rm -f "$STAMP_FILE"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
