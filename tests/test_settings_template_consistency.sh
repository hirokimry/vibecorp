#!/bin/bash
# test_settings_template_consistency.sh — settings.json 単一 SSOT 検証 + plugin native hooks 登録ゲート (#759)
#
# 検証対象:
#   - templates/claude/settings.json: 単一 SSOT（install.sh が参照する正本テンプレート）
#   - templates/settings.json.tpl: 廃止済み（#759 で削除、二重管理の解消）
#   - plugin native 配布構造: .claude-plugin/plugin.json の hooks 参照 + hooks/hooks.json の構造
#
# 目的:
#   Issue #759 で settings.json を単一 SSOT 化し、死んだ hooks ブロックと二重テンプレートを
#   解消した。本テストはその不変条件を退行検知する:
#     1. SSOT が単一（settings.json.tpl が復活しない）
#     2. SSOT に hooks ブロックが再混入しない（plugin native 統一）
#     3. 【CISO 必須ゲート】hooks/hooks.json が hooks/ 配下の全フックを登録維持し、
#        protect-branch 等の branch 保護フックが plugin 経由で発火する状態を保つ
#
# 使い方: bash tests/test_settings_template_consistency.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSOT="${REPO_ROOT}/templates/claude/settings.json"
OLD_TPL="${REPO_ROOT}/templates/settings.json.tpl"
PLUGIN_JSON="${REPO_ROOT}/.claude-plugin/plugin.json"
HOOKS_MANIFEST="${REPO_ROOT}/hooks/hooks.json"
HOOKS_DIR="${REPO_ROOT}/hooks"

echo "=== settings.json 単一 SSOT 検証 (#759) ==="

# --- 1. 単一 SSOT の存在と妥当性、旧 tpl の廃止 ---

if [[ ! -f "$SSOT" ]]; then
  fail "単一 SSOT templates/claude/settings.json が存在しない"
  exit 1
fi

if jq . "$SSOT" >/dev/null 2>&1; then
  pass "templates/claude/settings.json の JSON 構文が妥当"
else
  fail "templates/claude/settings.json の JSON 構文エラー"
  exit 1
fi

# 旧二重テンプレート settings.json.tpl が廃止されている（復活検知）
if [[ -e "$OLD_TPL" ]]; then
  fail "廃止済みの templates/settings.json.tpl が復活している（単一 SSOT 違反、#759）"
else
  pass "templates/settings.json.tpl が廃止されている（単一 SSOT）"
fi

# SSOT に必須の plugin 自動ロード設定が含まれる
if jq -e '.extraKnownMarketplaces.vibecorp and .enabledPlugins["vibecorp@vibecorp"]' "$SSOT" >/dev/null 2>&1; then
  pass "SSOT に extraKnownMarketplaces / enabledPlugins が登録されている"
else
  fail "SSOT に extraKnownMarketplaces / enabledPlugins が無い"
fi

# --- 2. SSOT に hooks ブロックが再混入しない（plugin native 統一） ---

if jq -e '.hooks' "$SSOT" >/dev/null 2>&1; then
  fail "plugin native 方針に反して SSOT に hooks ブロックが残存している（hooks は hooks/hooks.json に一元化、#720）"
else
  pass "SSOT に hooks ブロック不在（plugin native 配布、#720）"
fi

# --- 3. 【CISO 必須ゲート】plugin native 配布の hooks 登録維持 ---

# plugin.json が hooks/hooks.json を指す
if [ -f "$PLUGIN_JSON" ]; then
  if jq -e '.hooks == "./hooks/hooks.json"' "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass ".claude-plugin/plugin.json の hooks フィールドが \"./hooks/hooks.json\" を指す"
  else
    fail ".claude-plugin/plugin.json の hooks 参照が plugin native の標準パスから乖離"
  fi
else
  fail ".claude-plugin/plugin.json が存在しない"
fi

if [ ! -f "$HOOKS_MANIFEST" ]; then
  fail "hooks/hooks.json が存在しない"
  exit 1
fi

# PreToolUse が non-empty array
if jq -e '.hooks.PreToolUse | type == "array" and length > 0' "$HOOKS_MANIFEST" >/dev/null 2>&1; then
  pass "hooks/hooks.json の PreToolUse が non-empty array (plugin native 構造)"
else
  fail "hooks/hooks.json の PreToolUse が非配列または空 (plugin native 構造違反)"
fi

# 全 command が ${CLAUDE_PLUGIN_ROOT}/hooks/ 経路（経路固定）
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

# CISO 必須ゲート本体: hooks/ 配下の全フック .sh が hooks.json に登録維持されている（集合一致）。
# settings.json の死んだ hooks ブロック / 置き忘れ .claude/hooks/protect-branch.sh を掃除しても、
# branch 保護等が plugin 経由で発火し続けることを機械検証する。
FS_HOOKS=$(find "$HOOKS_DIR" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sed 's#.*/##' | sort -u)
REGISTERED_HOOKS=$(jq -r '[.hooks | to_entries[].value[].hooks[].command] | .[]' "$HOOKS_MANIFEST" \
  | sed 's#.*/##' | sort -u)

if [ "$FS_HOOKS" = "$REGISTERED_HOOKS" ]; then
  pass "CISO ゲート: hooks/ の全フック .sh が hooks/hooks.json に登録維持されている（集合一致）"
else
  fail "CISO ゲート: hooks/ のフックと hooks/hooks.json 登録が乖離している"
  echo "--- hooks/ 配下 ---"; printf '%s\n' "$FS_HOOKS"
  echo "--- hooks.json 登録 ---"; printf '%s\n' "$REGISTERED_HOOKS"
fi

# branch 保護フックが明示的に登録されている（掃除で消えていないことの直接確認）
if printf '%s\n' "$REGISTERED_HOOKS" | grep -q '^protect-branch\.sh$'; then
  pass "CISO ゲート: protect-branch.sh が hooks/hooks.json に登録されている（branch 保護が plugin 経由で発火）"
else
  fail "CISO ゲート: protect-branch.sh が hooks/hooks.json に登録されていない（branch 保護が失われる）"
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
