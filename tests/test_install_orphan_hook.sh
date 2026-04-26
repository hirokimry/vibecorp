#!/bin/bash
# test_install_orphan_hook.sh — install.sh --update の orphan hook 削除ロジックの統合テスト
#
# 検証対象:
#   - get_orphan_hooks()   : lock 記載 + templates 不在の hook 名を列挙する
#   - remove_orphan_hooks(): 上記の hook を .claude/hooks/ から物理削除する
#   - generate_settings_json(): --update 時に orphan hook のエントリが .claude/settings.json から消える
#
# シナリオ:
#   1) vibecorp 本体ツリーを一時ディレクトリへコピー（本体 templates を汚さない）
#   2) コピー側 templates/claude/hooks/ に stub-hook-for-test.sh を追加
#   3) ダミープロジェクトに --preset minimal で install（stub が配置される）
#   4) コピー側 templates から stub を削除してから --update 実行
#   5) .claude/hooks/stub-hook-for-test.sh が物理削除されていることを確認
#   6) .claude/vibecorp.lock の files.hooks から stub が消えていることを確認
#   7) .claude/settings.json に stub の PreToolUse エントリが残っていないことを確認
#   8) 非 regression: 他の hook（例: command-log.sh）は残っていること

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_ROOT=""
VIBECORP_COPY=""
TEST_REPO=""

assert_lock_has() {
  local desc="$1"
  local lock="$2"
  local name="$3"
  if grep -qxF "    - ${name}" "$lock"; then
    pass "$desc"
  else
    fail "$desc (lock に ${name} が含まれない)"
  fi
}

assert_lock_not_has() {
  local desc="$1"
  local lock="$2"
  local name="$3"
  if grep -qxF "    - ${name}" "$lock"; then
    fail "$desc (lock に ${name} が残っている)"
  else
    pass "$desc"
  fi
}

assert_settings_has_hook() {
  local desc="$1"
  local settings="$2"
  local name="$3"
  if jq -r '.. | objects | .command? // empty' "$settings" 2>/dev/null \
      | grep -qxF "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/${name}"; then
    pass "$desc"
  else
    fail "$desc (settings.json に ${name} エントリがない)"
  fi
}

assert_settings_not_has_hook() {
  local desc="$1"
  local settings="$2"
  local name="$3"
  if jq -r '.. | objects | .command? // empty' "$settings" 2>/dev/null \
      | grep -qxF "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/${name}"; then
    fail "$desc (settings.json に ${name} エントリが残っている)"
  else
    pass "$desc"
  fi
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# ============================================
echo "=== orphan hook 削除ロジックの統合テスト ==="
# ============================================

# 1) テスト環境構築（vibecorp 本体を一時コピー）
TMPDIR_ROOT=$(mktemp -d)
VIBECORP_COPY="${TMPDIR_ROOT}/vibecorp"
TEST_REPO="${TMPDIR_ROOT}/test-repo"

# vibecorp 本体を一時コピー（git 管理ファイルのみで十分だが、tree ごとコピーして簡潔に）
if ! cp -R "$SCRIPT_DIR" "$VIBECORP_COPY"; then
  fail "vibecorp 本体のコピーに失敗"
  exit 1
fi

INSTALL_SH="${VIBECORP_COPY}/install.sh"
STUB_TEMPLATE="${VIBECORP_COPY}/templates/claude/hooks/stub-hook-for-test.sh"

if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh がコピー先に存在しない: $INSTALL_SH"
  exit 1
fi

# 2) stub hook をテンプレートに追加（何もせず exit 0 する最小 hook）
cat > "$STUB_TEMPLATE" <<'EOF'
#!/bin/bash
# stub-hook-for-test.sh — orphan hook テスト用のダミー hook
cat >/dev/null
exit 0
EOF
chmod +x "$STUB_TEMPLATE"

# 3) ダミープロジェクトに初回 install
mkdir -p "$TEST_REPO"
cd "$TEST_REPO"
git init -q
git config user.name "vibecorp-test"
git config user.email "vibecorp-test@example.com"
git commit --allow-empty -m "initial" -q

if ! bash "$INSTALL_SH" --name test-proj --preset minimal >/dev/null 2>&1; then
  fail "初回 install に失敗"
  exit 1
fi

STUB_DEST="${TEST_REPO}/.claude/hooks/stub-hook-for-test.sh"
LOCK_FILE="${TEST_REPO}/.claude/vibecorp.lock"
SETTINGS_FILE="${TEST_REPO}/.claude/settings.json"

assert_file_exists "初回 install で stub hook が配置される" "$STUB_DEST"
assert_lock_has "初回 install で lock に stub が記載される" "$LOCK_FILE" "stub-hook-for-test.sh"

# settings.json.tpl には stub エントリが含まれないため、
# orphan 削除時に settings.json から除去される動作を検証するには、
# install 後のユーザー side settings.json に stub エントリを手動注入しておく。
# （stub template を settings.json.tpl に入れる方法もあるが、テンプレート本体を触るのは避ける）
INJECT_TMP="${SETTINGS_FILE}.inject.tmp"
jq '.hooks.PreToolUse += [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stub-hook-for-test.sh"
      }]
    }]' "$SETTINGS_FILE" > "$INJECT_TMP" && mv "$INJECT_TMP" "$SETTINGS_FILE"
assert_settings_has_hook "stub エントリを settings.json に注入" "$SETTINGS_FILE" "stub-hook-for-test.sh"

# 4) templates から stub を削除してから --update 実行
rm -f "$STUB_TEMPLATE"

if ! bash "$INSTALL_SH" --update >/dev/null 2>&1; then
  fail "--update 実行に失敗"
  exit 1
fi

# 5-7) orphan 削除の結果検証
assert_file_not_exists "--update で orphan hook が削除される" "$STUB_DEST"
assert_lock_not_has "--update で lock から orphan hook が消える" "$LOCK_FILE" "stub-hook-for-test.sh"
assert_settings_not_has_hook "--update で settings.json から orphan hook エントリが消える" "$SETTINGS_FILE" "stub-hook-for-test.sh"

# 8) 非 regression: テンプレートに存在する他の hook は残っている
assert_file_exists "非 regression: command-log.sh は残存" "${TEST_REPO}/.claude/hooks/command-log.sh"
assert_file_exists "非 regression: protect-files.sh は残存" "${TEST_REPO}/.claude/hooks/protect-files.sh"

# 9) セキュリティ回帰: lock 改ざんで name に / を含めても hooks 外が削除されない
#    remove_orphan_hooks() の `[[ "$name" == */* ]] && continue` 防御の回帰確認
SENTINEL="${TEST_REPO}/.claude/keep-me.txt"
echo "do-not-delete" > "$SENTINEL"
awk '
  { print }
  $0 == "  hooks:" { print "    - ../keep-me.txt" }
' "$LOCK_FILE" > "${LOCK_FILE}.tmp" && mv "${LOCK_FILE}.tmp" "$LOCK_FILE"

if ! bash "$INSTALL_SH" --update >/dev/null 2>&1; then
  fail "セキュリティ回帰確認の --update 実行に失敗"
  exit 1
fi
assert_file_exists "path traversal 対策: hooks 外ファイルは削除されない" "$SENTINEL"

# ============================================
echo ""
echo "=== 結果 ==="
echo "Total : $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
