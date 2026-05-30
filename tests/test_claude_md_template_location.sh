#!/bin/bash
# test_claude_md_template_location.sh — Issue #763: CLAUDE.md テンプレが .claude/ 階層ミラーに配置される
#
# 検証対象:
#   - templates/claude/CLAUDE.md.tpl が存在する（配布先 .claude/CLAUDE.md の階層ミラー）
#   - 旧 templates/CLAUDE.md.tpl が廃止されている（移動の強制）
#   - placeholder（{{PROJECT_NAME}} / {{LANGUAGE}}）を保持する（symlink せず .tpl render 維持）
#   - install.sh の generate_claude_md() が新パスを参照する
#   - install 実行で .claude/CLAUDE.md が placeholder 置換済みで生成される（render 不変）
#
# 使い方: bash tests/test_claude_md_template_location.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
NEW_TPL="${SCRIPT_DIR}/templates/claude/CLAUDE.md.tpl"
OLD_TPL="${SCRIPT_DIR}/templates/CLAUDE.md.tpl"
TMPDIR_ROOT=""

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

echo "=== CLAUDE.md テンプレ配置の .claude/ 階層ミラー検証 (#763) ==="

# --- 1. 新パス存在 / 旧パス廃止 ---

assert_file_exists "templates/claude/CLAUDE.md.tpl が存在する（階層ミラー）" "$NEW_TPL"

if [[ -e "$OLD_TPL" ]]; then
  fail "旧 templates/CLAUDE.md.tpl が残存している（#763 で templates/claude/ へ移動済みのはず）"
else
  pass "旧 templates/CLAUDE.md.tpl が廃止されている（templates/claude/ へ移動）"
fi

# --- 2. placeholder を保持（.tpl render 維持の根拠） ---

if [[ -f "$NEW_TPL" ]]; then
  for ph in '{{PROJECT_NAME}}' '{{LANGUAGE}}'; do
    if grep -qF -- "$ph" "$NEW_TPL"; then
      pass "templates/claude/CLAUDE.md.tpl が placeholder ${ph} を保持する"
    else
      fail "templates/claude/CLAUDE.md.tpl に placeholder ${ph} が無い（.tpl render の前提が崩れる）"
    fi
  done
fi

# --- 3. install.sh の generate_claude_md が新パスを参照する ---

assert_file_contains "install.sh の generate_claude_md が新パスを参照する" \
  "$INSTALL_SH" 'templates/claude/CLAUDE.md.tpl'

# 旧パス参照が残っていない（generate_claude_md の src_template）
if grep -q 'templates/CLAUDE.md.tpl"' "$INSTALL_SH"; then
  fail "install.sh に旧パス templates/CLAUDE.md.tpl への参照が残っている"
else
  pass "install.sh に旧パス templates/CLAUDE.md.tpl への参照が残っていない"
fi

# --- 4. render 不変: install で .claude/CLAUDE.md が placeholder 置換済みで生成される ---

TMPDIR_ROOT=$(mktemp -d)
cd "$TMPDIR_ROOT"
git init -q
git config user.name "vibecorp-test"
git config user.email "vibecorp-test@example.com"
git commit --allow-empty -m "initial" -q
bash "$INSTALL_SH" --name render-test-proj --preset minimal --language ja >/dev/null 2>&1
R="$TMPDIR_ROOT"

assert_file_exists "install 後 .claude/CLAUDE.md が生成される" "$R/.claude/CLAUDE.md"
# placeholder が置換されている（render 不変）
if grep -q '{{PROJECT_NAME}}\|{{LANGUAGE}}' "$R/.claude/CLAUDE.md"; then
  fail "生成された .claude/CLAUDE.md に未置換 placeholder が残っている（render 不変が崩れた）"
else
  pass "生成された .claude/CLAUDE.md は placeholder 置換済み（render 不変）"
fi
assert_file_contains "生成された CLAUDE.md に PROJECT_NAME が反映されている" \
  "$R/.claude/CLAUDE.md" "render-test-proj"

cleanup
TMPDIR_ROOT=""

print_test_summary
