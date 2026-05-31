#!/bin/bash
# test_settings_json_hooks_exist.sh — settings.json が参照する hook スクリプトの実在性検証
#
# 検証対象:
#   - .claude/settings.json: hooks ブロック再混入による dead な .claude/hooks/ 参照が無い
#     （#759 で symlink → templates/claude/settings.json 化、hooks は hooks/hooks.json へ一元化）
#   - templates/claude/settings.json: 単一 SSOT（#759 で settings.json.tpl を統合）
#   - 回帰防止: settings.json から削除済み team-auto-approve.sh への参照が復活していないこと
#
# 目的:
#   Issue #385 の再発防止。PR #381 で team-auto-approve.sh を削除した際に settings.json
#   から該当エントリを消し忘れた結果、teammate の Bash/Edit/Write で毎回 hook 実行失敗 →
#   permission prompt 格上げ → CEO に通知届かず、並列 ship が崩壊した。
#
# 検出ロジック:
#   settings.json は `hooks.<eventName>[].hooks[].command` の 3 階層構造。
#   全イベント（PreToolUse / PostToolUse / UserPromptSubmit / Stop 等）を走査する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# settings.json / settings.json.tpl から .claude/hooks/ 参照の basename を抽出
extract_hook_basenames() {
  local target="$1"
  (jq -r '.hooks | to_entries[].value[].hooks[].command' "$target" \
    | grep -oE '/\.claude/hooks/[A-Za-z0-9_-]+\.sh' || true) \
    | awk -F/ '{ print $NF }' \
    | sort -u
}

# 対象ファイルが参照する全 hook が指定ディレクトリに実在することを検証
# fallback_dir が指定された場合、hooks_dir に無ければ fallback_dir も探す
# （CI 環境では .claude/hooks/ に install.sh 配置前の hook が無いため
#   hooks/ をフォールバックとして参照する）
assert_all_hooks_exist() {
  local desc="$1"
  local settings_file="$2"
  local hooks_dir="$3"
  local fallback_dir="${4:-}"
  local missing=""
  local hooks
  hooks=$(extract_hook_basenames "$settings_file")

  if [ -z "$hooks" ]; then
    # plugin native (#720): settings.json.tpl は hooks ブロックを持たなくなった
    # （hooks 登録は ${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json 経由に一元化）
    # CR PR #731 Minor #9 対応: .hooks キー自体が存在しないことを明示検証して退行を捕捉する
    if jq -e '.hooks' "$settings_file" >/dev/null 2>&1; then
      fail "$desc (.hooks キー残存だが参照抽出 0 件 = 構造不一致による誤検出の可能性)"
    else
      pass "$desc (plugin native 配布で .hooks キー不在、#720 / #716)"
    fi
    return
  fi

  local hook
  while IFS= read -r hook; do
    if [ ! -f "${hooks_dir}/${hook}" ]; then
      if [ -z "$fallback_dir" ] || [ ! -f "${fallback_dir}/${hook}" ]; then
        missing="${missing} ${hook}"
      fi
    fi
  done <<< "$hooks"

  if [ -z "$missing" ]; then
    pass "$desc"
  else
    fail "$desc (実在しない hook:${missing} / 期待ディレクトリ: ${hooks_dir}${fallback_dir:+ / フォールバック: ${fallback_dir}})"
  fi
}

# JSON 構文妥当性を検証
assert_json_valid() {
  local desc="$1"
  local target="$2"
  if jq . "$target" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc (JSON 構文エラー: $target)"
  fi
}

# 対象ファイルに指定文字列が存在しないことを検証（回帰防止）
assert_no_reference() {
  local desc="$1"
  local target="$2"
  local pattern="$3"
  if grep -q -- "$pattern" "$target"; then
    fail "$desc (参照が残っている: $pattern in $target)"
  else
    pass "$desc"
  fi
}

# ============================================
echo "=== settings.json hook 実在性検証 ==="
# ============================================

SETTINGS_JSON="${SCRIPT_DIR}/.claude/settings.json"
SSOT_SETTINGS="${SCRIPT_DIR}/templates/claude/settings.json"
CLAUDE_HOOKS_DIR="${SCRIPT_DIR}/.claude/hooks"
TEMPLATE_HOOKS_DIR="${SCRIPT_DIR}/hooks"

# 前提ファイルの存在確認（不在なら後続テストが全て無意味なので即 exit 1）。
# .claude/settings.json は #759 で symlink 化されたため -e（symlink 解決）で確認する。
# .claude/hooks/ は plugin native 化（hooks/hooks.json 一元化）で廃止済みのため存在を要求しない。
if [ ! -e "$SETTINGS_JSON" ]; then
  fail ".claude/settings.json が存在しない（symlink 解決不可を含む）"
  exit 1
fi

if [ ! -f "$SSOT_SETTINGS" ]; then
  fail "単一 SSOT templates/claude/settings.json が存在しない"
  exit 1
fi

# --- .claude/settings.json（symlink → 単一 SSOT） ---

echo ""
echo "--- .claude/settings.json ---"

assert_json_valid ".claude/settings.json の JSON 構文が妥当" "$SETTINGS_JSON"
# hooks は plugin native 配布（hooks/hooks.json）へ一元化済み。settings.json に hooks ブロックが
# 再混入し dead な .claude/hooks/ 参照が生じていないことを検証する（#385 / #759）。
# .claude/hooks/ は廃止済みのため、万一参照が復活した場合 fallback の hooks/ でも実在確認する。
assert_all_hooks_exist \
  ".claude/settings.json に dead な .claude/hooks/ 参照が無い（plugin native）" \
  "$SETTINGS_JSON" \
  "$CLAUDE_HOOKS_DIR" \
  "$TEMPLATE_HOOKS_DIR"

# Issue #385 固有の回帰防止: team-auto-approve.sh は PR #381 で削除済み
assert_no_reference \
  "回帰防止: settings.json に team-auto-approve.sh 参照が残っていない" \
  "$SETTINGS_JSON" \
  "team-auto-approve.sh"

# --- templates/claude/settings.json（単一 SSOT、#759 で settings.json.tpl を統合） ---

echo ""
echo "--- templates/claude/settings.json ---"

assert_json_valid "templates/claude/settings.json の JSON 構文が妥当" "$SSOT_SETTINGS"
assert_all_hooks_exist \
  "templates/claude/settings.json に dead な .claude/hooks/ 参照が無い（plugin native）" \
  "$SSOT_SETTINGS" \
  "$TEMPLATE_HOOKS_DIR"

assert_no_reference \
  "回帰防止: SSOT settings.json に team-auto-approve.sh 参照が残っていない" \
  "$SSOT_SETTINGS" \
  "team-auto-approve.sh"

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
