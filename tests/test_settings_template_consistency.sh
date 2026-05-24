#!/bin/bash
# test_settings_template_consistency.sh — settings.json テンプレートの二重存在ドリフト検出 (#241)
#
# 検証対象:
#   - templates/settings.json.tpl: install.sh が参照する正本テンプレート
#   - templates/claude/settings.json: 配布リファレンス（テスト・ドキュメント参照）
#
# 目的:
#   Issue #241 の再発防止。両ファイルが乖離したまま放置されると、install.sh の
#   出力（実際にユーザーに届く .claude/settings.json）と、テスト・ドキュメントが
#   参照する templates/claude/settings.json で挙動・期待値が一致しなくなる。
#   両ファイルを full preset 想定で構造同一に保つことで、テンプレートの正本／
#   リファレンスの役割分離を維持する。
#
# 検証ロジック:
#   - jq -S（キーソート）で両ファイルを正規化し、構造比較
#   - permissions.allow が両ファイルで完全一致することを検証
#   - hooks.PreToolUse の matcher / hook 集合が両ファイルで一致することを検証
#
# 使い方: bash tests/test_settings_template_consistency.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="${REPO_ROOT}/templates/settings.json.tpl"
CLAUDE_SETTINGS="${REPO_ROOT}/templates/claude/settings.json"

# 前提ファイル存在確認
if [[ ! -f "$TPL" ]]; then
  fail "templates/settings.json.tpl が存在しない"
  exit 1
fi
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  fail "templates/claude/settings.json が存在しない"
  exit 1
fi

echo "=== settings.json テンプレート整合性検証 (#241) ==="

# JSON 構文妥当性
if jq . "$TPL" >/dev/null 2>&1; then
  pass "templates/settings.json.tpl の JSON 構文が妥当"
else
  fail "templates/settings.json.tpl の JSON 構文エラー"
  exit 1
fi

if jq . "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
  pass "templates/claude/settings.json の JSON 構文が妥当"
else
  fail "templates/claude/settings.json の JSON 構文エラー"
  exit 1
fi

# 構造完全一致検証（jq -S でキーソート後に diff）
TPL_SORTED=$(jq -S . "$TPL")
CLAUDE_SORTED=$(jq -S . "$CLAUDE_SETTINGS")

if [[ "$TPL_SORTED" == "$CLAUDE_SORTED" ]]; then
  pass "templates/settings.json.tpl と templates/claude/settings.json が full preset 想定で構造同一"
else
  fail "両 settings.json の構造が乖離している（jq -S diff で差分を確認）"
  echo ""
  echo "--- 差分 ---"
  diff <(echo "$TPL_SORTED") <(echo "$CLAUDE_SORTED") || true
  echo "--- 差分終わり ---"
fi

# permissions.allow の完全一致検証
TPL_ALLOW=$(jq -S '.permissions.allow // []' "$TPL")
CLAUDE_ALLOW=$(jq -S '.permissions.allow // []' "$CLAUDE_SETTINGS")

if [[ "$TPL_ALLOW" == "$CLAUDE_ALLOW" ]]; then
  pass "permissions.allow が両ファイルで一致"
else
  fail "permissions.allow が両ファイルで乖離している"
fi

# hooks.PreToolUse の matcher / hook 集合一致検証
# plugin native 配布 (#716/#720) 以降、settings.json は hooks を持たない (hooks.json に一元化)。
# 両ファイルとも hooks がなければ skip、両方あれば比較、片方だけにあれば fail。
# CR PR #731 Major #1 v2 対応: plugin native 方針では hooks ブロック残存自体を NG とする
# (両ファイル一致でも hooks 再混入は禁止、両ファイル共に hooks 不在のみ pass)
TPL_HAS_HOOKS=$(jq -e '.hooks' "$TPL" >/dev/null 2>&1 && echo yes || echo no)
CLAUDE_HAS_HOOKS=$(jq -e '.hooks' "$CLAUDE_SETTINGS" >/dev/null 2>&1 && echo yes || echo no)
if [ "$TPL_HAS_HOOKS" = "no" ] && [ "$CLAUDE_HAS_HOOKS" = "no" ]; then
  pass "hooks ブロック不在で一致 (plugin native 配布、#720)"
else
  fail "plugin native 方針に反して hooks ブロックが残存: tpl=$TPL_HAS_HOOKS / claude=$CLAUDE_HAS_HOOKS"
fi

# CR PR #731 Major #7 v3 対応: plugin native 配布の必須構造を退行検知する
# Issue #700 系の中核要件: .claude-plugin/plugin.json の hooks 参照固定 + hooks/hooks.json の構造固定
PLUGIN_JSON="${REPO_ROOT}/.claude-plugin/plugin.json"
HOOKS_MANIFEST="${REPO_ROOT}/hooks/hooks.json"

if [ -f "$PLUGIN_JSON" ]; then
  if jq -e '.hooks == "./hooks/hooks.json"' "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass ".claude-plugin/plugin.json の hooks フィールドが \"./hooks/hooks.json\" を指す"
  else
    fail ".claude-plugin/plugin.json の hooks 参照が plugin native の標準パスから乖離"
  fi
else
  fail ".claude-plugin/plugin.json が存在しない"
fi

if [ -f "$HOOKS_MANIFEST" ]; then
  if jq -e '.hooks.PreToolUse | type == "array" and length > 0' "$HOOKS_MANIFEST" >/dev/null 2>&1; then
    pass "hooks/hooks.json の PreToolUse が non-empty array (plugin native 構造)"
  else
    fail "hooks/hooks.json の PreToolUse が非配列または空 (plugin native 構造違反)"
  fi

  # 全 hook command が \${CLAUDE_PLUGIN_ROOT}/hooks/ で始まることを確認 (経路固定)
  NON_PLUGIN_PATH_COUNT=$(jq -r '
    [.hooks | to_entries[].value[] | .hooks[] | .command]
    | map(select(startswith("${CLAUDE_PLUGIN_ROOT}/hooks/") | not))
    | length
  ' "$HOOKS_MANIFEST")
  if [ "$NON_PLUGIN_PATH_COUNT" = "0" ]; then
    pass "hooks/hooks.json の全 command が \${CLAUDE_PLUGIN_ROOT}/hooks/ 経路 (plugin native 規約)"
  else
    fail "hooks/hooks.json に \${CLAUDE_PLUGIN_ROOT}/hooks/ 以外の command が ${NON_PLUGIN_PATH_COUNT} 件 (規約違反)"
  fi
else
  fail "hooks/hooks.json が存在しない"
fi

echo ""
echo "=== 結果 ==="
echo "Total : $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
