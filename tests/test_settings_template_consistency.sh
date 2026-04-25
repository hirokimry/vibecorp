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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="${REPO_ROOT}/templates/settings.json.tpl"
CLAUDE_SETTINGS="${REPO_ROOT}/templates/claude/settings.json"

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
# 順序不問で集合として比較する
TPL_HOOKS_SET=$(jq -S '.hooks.PreToolUse | map({matcher, hooks: (.hooks | map(.command) | sort)}) | sort_by(.matcher)' "$TPL")
CLAUDE_HOOKS_SET=$(jq -S '.hooks.PreToolUse | map({matcher, hooks: (.hooks | map(.command) | sort)}) | sort_by(.matcher)' "$CLAUDE_SETTINGS")

if [[ "$TPL_HOOKS_SET" == "$CLAUDE_HOOKS_SET" ]]; then
  pass "hooks.PreToolUse の matcher / hook 集合が両ファイルで一致"
else
  fail "hooks.PreToolUse の matcher / hook 集合が両ファイルで乖離している"
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
