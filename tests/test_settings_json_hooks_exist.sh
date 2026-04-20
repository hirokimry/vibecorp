#!/bin/bash
# test_settings_json_hooks_exist.sh — settings.json が参照する hook スクリプトの実在性検証
#
# 検証対象:
#   - .claude/settings.json: 参照する全 hook が .claude/hooks/ に実在する
#   - templates/settings.json.tpl: 参照する全 hook が templates/claude/hooks/ に実在する
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

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
TOTAL=0

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

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
#   templates/claude/hooks/ をフォールバックとして参照する）
assert_all_hooks_exist() {
  local desc="$1"
  local settings_file="$2"
  local hooks_dir="$3"
  local fallback_dir="${4:-}"
  local missing=""
  local hooks
  hooks=$(extract_hook_basenames "$settings_file")

  if [ -z "$hooks" ]; then
    fail "$desc (hook 参照が1件も抽出できない: $settings_file)"
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
SETTINGS_TPL="${SCRIPT_DIR}/templates/settings.json.tpl"
HOOKS_DIR="${SCRIPT_DIR}/.claude/hooks"
TEMPLATE_HOOKS_DIR="${SCRIPT_DIR}/templates/claude/hooks"

# 前提ファイルの存在確認（不在なら後続テストが全て無意味なので即 exit 1）
if [ ! -f "$SETTINGS_JSON" ]; then
  fail ".claude/settings.json が存在しない"
  exit 1
fi

if [ ! -d "$HOOKS_DIR" ]; then
  fail ".claude/hooks/ ディレクトリが存在しない"
  exit 1
fi

# --- .claude/settings.json ---

echo ""
echo "--- .claude/settings.json ---"

assert_json_valid ".claude/settings.json の JSON 構文が妥当" "$SETTINGS_JSON"
assert_all_hooks_exist \
  ".claude/settings.json が参照する全 hook が .claude/hooks/ に実在する" \
  "$SETTINGS_JSON" \
  "$HOOKS_DIR" \
  "$TEMPLATE_HOOKS_DIR"

# Issue #385 固有の回帰防止: team-auto-approve.sh は PR #381 で削除済み
assert_no_reference \
  "回帰防止: settings.json に team-auto-approve.sh 参照が残っていない" \
  "$SETTINGS_JSON" \
  "team-auto-approve.sh"

# --- templates/settings.json.tpl ---

if [ -f "$SETTINGS_TPL" ]; then
  echo ""
  echo "--- templates/settings.json.tpl ---"

  assert_json_valid "templates/settings.json.tpl の JSON 構文が妥当" "$SETTINGS_TPL"

  if [ -d "$TEMPLATE_HOOKS_DIR" ]; then
    assert_all_hooks_exist \
      "templates/settings.json.tpl が参照する全 hook が templates/claude/hooks/ に実在する" \
      "$SETTINGS_TPL" \
      "$TEMPLATE_HOOKS_DIR"
  else
    fail "templates/claude/hooks/ ディレクトリが存在しない"
    exit 1
  fi

  assert_no_reference \
    "回帰防止: settings.json.tpl に team-auto-approve.sh 参照が残っていない" \
    "$SETTINGS_TPL" \
    "team-auto-approve.sh"
fi

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
