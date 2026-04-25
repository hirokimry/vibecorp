#!/bin/bash
# test_plugin_autoload.sh — Plugin Marketplace 自動ロード設定の検証 (#405)
#
# 検証対象:
#   - .claude-plugin/marketplace.json が vibecorp ルートに存在し、構造が正しい
#   - templates/settings.json.tpl と templates/claude/settings.json に
#     extraKnownMarketplaces / enabledPlugins が含まれる
#   - install.sh の generate_settings_json() マージロジックで既存の
#     extraKnownMarketplaces / enabledPlugins が壊れない
#
# 目的:
#   `claude --plugin-dir .` を手入力せずに /vibecorp:* スキルが解決される
#   状態を継続的に保証する（#405）。
#
# 使い方: bash tests/test_plugin_autoload.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="${REPO_ROOT}/.claude-plugin/marketplace.json"
TPL="${REPO_ROOT}/templates/settings.json.tpl"
CLAUDE_SETTINGS="${REPO_ROOT}/templates/claude/settings.json"
INSTALL_SH="${REPO_ROOT}/install.sh"

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

echo "=== Plugin Marketplace 自動ロード検証 (#405) ==="

# --- A. .claude-plugin/marketplace.json の存在と構造 ---

if [[ -f "$MARKETPLACE" ]]; then
  pass ".claude-plugin/marketplace.json が存在する"
else
  fail ".claude-plugin/marketplace.json が存在しない"
  exit 1
fi

if jq . "$MARKETPLACE" >/dev/null 2>&1; then
  pass "marketplace.json の JSON 構文が妥当"
else
  fail "marketplace.json の JSON 構文エラー"
  exit 1
fi

mkt_name=$(jq -r '.name' "$MARKETPLACE")
if [[ "$mkt_name" == "vibecorp" ]]; then
  pass "marketplace.json の name が \"vibecorp\""
else
  fail "marketplace.json の name が期待値と異なる: $mkt_name"
fi

plugin_count=$(jq '.plugins | length' "$MARKETPLACE")
if [[ "$plugin_count" -ge 1 ]]; then
  pass "marketplace.json に plugins エントリが存在する（${plugin_count} 件）"
else
  fail "marketplace.json に plugins エントリが存在しない"
fi

plugin_name=$(jq -r '.plugins[0].name' "$MARKETPLACE")
if [[ "$plugin_name" == "vibecorp" ]]; then
  pass "marketplace.json の最初の plugin name が \"vibecorp\""
else
  fail "marketplace.json の最初の plugin name が期待値と異なる: $plugin_name"
fi

plugin_source=$(jq -r '.plugins[0].source' "$MARKETPLACE")
if [[ "$plugin_source" == "." ]]; then
  pass "marketplace.json の plugin source が \".\"（リポジトリルート）"
else
  fail "marketplace.json の plugin source が期待値と異なる: $plugin_source"
fi

# --- B. templates/settings.json.tpl の extraKnownMarketplaces / enabledPlugins ---

if jq -e '.extraKnownMarketplaces.vibecorp.source.repo == "hirokimry/vibecorp"' "$TPL" >/dev/null 2>&1; then
  pass "templates/settings.json.tpl に extraKnownMarketplaces.vibecorp が登録されている"
else
  fail "templates/settings.json.tpl の extraKnownMarketplaces.vibecorp が期待値と異なる"
fi

if jq -e '.enabledPlugins["vibecorp@vibecorp"] == true' "$TPL" >/dev/null 2>&1; then
  pass "templates/settings.json.tpl に enabledPlugins[\"vibecorp@vibecorp\"] が true で登録されている"
else
  fail "templates/settings.json.tpl の enabledPlugins[\"vibecorp@vibecorp\"] が期待値と異なる"
fi

# --- C. templates/claude/settings.json も同等の設定を持つ ---

if jq -e '.extraKnownMarketplaces.vibecorp.source.repo == "hirokimry/vibecorp"' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
  pass "templates/claude/settings.json に extraKnownMarketplaces.vibecorp が登録されている"
else
  fail "templates/claude/settings.json の extraKnownMarketplaces.vibecorp が期待値と異なる"
fi

if jq -e '.enabledPlugins["vibecorp@vibecorp"] == true' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
  pass "templates/claude/settings.json に enabledPlugins[\"vibecorp@vibecorp\"] が登録されている"
else
  fail "templates/claude/settings.json の enabledPlugins[\"vibecorp@vibecorp\"] が期待値と異なる"
fi

# --- D. install.sh の マージロジックがユーザー追加 marketplace を壊さないことの構文検証 ---
# install.sh 内の jq フィルタが extraKnownMarketplaces / enabledPlugins を保持する記述を含むこと

if grep -q "extraKnownMarketplaces" "$INSTALL_SH"; then
  pass "install.sh に extraKnownMarketplaces のマージロジックが含まれる"
else
  fail "install.sh に extraKnownMarketplaces のマージロジックが無い"
fi

if grep -q "enabledPlugins" "$INSTALL_SH"; then
  pass "install.sh に enabledPlugins のマージロジックが含まれる"
else
  fail "install.sh に enabledPlugins のマージロジックが無い"
fi

# 既存値を保持するパターン (.foo // {}) + $new で記述されていることを確認
if grep -qF '.extraKnownMarketplaces // {}' "$INSTALL_SH" && grep -qF '.enabledPlugins // {}' "$INSTALL_SH"; then
  pass "install.sh が既存の extraKnownMarketplaces / enabledPlugins をオーバーレイで保持する"
else
  fail "install.sh の既存値保持パターンが見つからない（ユーザーカスタムが上書きされる懸念）"
fi

# install.sh 構文
if bash -n "$INSTALL_SH" 2>/dev/null; then
  pass "install.sh の構文が妥当"
else
  fail "install.sh に構文エラーがある"
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
