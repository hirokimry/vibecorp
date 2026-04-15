#!/bin/bash
# test_preset_workflow_regression.sh — /ship /autopilot のプリセット横断回帰テスト
# 使い方: bash tests/test_preset_workflow_regression.sh
#
# Issue #284 完了条件「既存ワークフロー（/ship /autopilot）の minimal/standard/full 各プリセットで回帰テストパス」対応。
# install.sh のプリセット別生成ロジックと、autopilot の full 限定ガードが崩れていないかを検証する。

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$PROJECT_DIR/install.sh"
AUTOPILOT_SKILL="$PROJECT_DIR/templates/claude/skills/autopilot/SKILL.md"
SHIP_SKILL="$PROJECT_DIR/templates/claude/skills/ship/SKILL.md"

echo "=== プリセット横断 ワークフロー回帰テスト ==="
echo ""

# --- テスト1: 前提ファイル存在 ---

echo "--- テスト1: 前提ファイル存在 ---"

for f in "$INSTALL_SCRIPT" "$AUTOPILOT_SKILL" "$SHIP_SKILL"; do
  if [[ -f "$f" ]]; then
    pass "$(basename "$f") が存在する"
  else
    fail "$f が存在しない"
    exit 1
  fi
done

echo ""

# --- テスト2: install.sh の generate_plan_yaml_section が各プリセットで期待通り出力する ---

echo "--- テスト2: plan.review_agents のプリセット別デフォルト ---"

FUNC_FILE="$(mktemp "${TMPDIR:-/tmp}/generate_plan_yaml.XXXXXX.sh")"
awk '/^generate_plan_yaml_section\(\)/,/^}/' "$INSTALL_SCRIPT" > "$FUNC_FILE"
trap 'rm -f "$FUNC_FILE"' EXIT

run_generate() {
  local preset="$1"
  PRESET="$preset" bash -c "source '$FUNC_FILE'; generate_plan_yaml_section"
}

assert_contains() {
  local out="$1"
  local needle="$2"
  local label="$3"
  if echo "$out" | grep -qE "^[[:space:]]*-[[:space:]]+${needle}$"; then
    pass "$label"
  else
    fail "$label（出力: $out）"
  fi
}

assert_not_contains() {
  local out="$1"
  local needle="$2"
  local label="$3"
  if echo "$out" | grep -qE "^[[:space:]]*-[[:space:]]+${needle}$"; then
    fail "$label（出力に含まれる: $needle）"
  else
    pass "$label"
  fi
}

MINIMAL_OUT="$(run_generate minimal)"
assert_contains "$MINIMAL_OUT" "architect" "minimal に architect が含まれる"
assert_not_contains "$MINIMAL_OUT" "security" "minimal に security が含まれない"
assert_not_contains "$MINIMAL_OUT" "cost" "minimal に cost が含まれない"
assert_not_contains "$MINIMAL_OUT" "legal" "minimal に legal が含まれない"

STANDARD_OUT="$(run_generate standard)"
for a in architect security testing; do
  assert_contains "$STANDARD_OUT" "$a" "standard に $a が含まれる"
done
assert_not_contains "$STANDARD_OUT" "cost" "standard に cost が含まれない"
assert_not_contains "$STANDARD_OUT" "legal" "standard に legal が含まれない"
assert_not_contains "$STANDARD_OUT" "performance" "standard に performance が含まれない"

FULL_OUT="$(run_generate full)"
for a in architect security testing performance dx cost legal; do
  assert_contains "$FULL_OUT" "$a" "full に $a が含まれる"
done

echo ""

# --- テスト3: autopilot が full プリセット限定であることを明示している ---

echo "--- テスト3: /autopilot の full プリセット限定ガード ---"

if grep -q "full プリセット専用" "$AUTOPILOT_SKILL"; then
  pass "autopilot SKILL.md に full 限定の記述がある"
else
  fail "autopilot SKILL.md に full プリセット専用の記述がない"
fi

if grep -qE "awk.*preset.*vibecorp\.yml" "$AUTOPILOT_SKILL"; then
  pass "autopilot SKILL.md に preset 判定ロジックがある"
else
  fail "autopilot SKILL.md に preset 判定ロジックがない"
fi

echo ""

# --- テスト4: /ship は全プリセットで利用可能（preset ガードなし） ---

echo "--- テスト4: /ship は全プリセットで利用可能 ---"

if grep -qE "full プリセット専用|minimal では使用不可" "$SHIP_SKILL"; then
  fail "/ship にプリセット限定記述がある（全プリセット対応であるべき）"
else
  pass "/ship はプリセット限定されていない"
fi

echo ""

# --- テスト5: vibecorp.yml 生成が各プリセットで preset 値を埋め込む ---

echo "--- テスト5: vibecorp.yml の preset 値埋め込み ---"

for preset in minimal standard full; do
  if grep -qE "^preset:.*\\\$\{PRESET\}" "$INSTALL_SCRIPT"; then
    :
  fi
done
if grep -cE "^preset:.*\\\$\{PRESET\}" "$INSTALL_SCRIPT" >/dev/null; then
  pass "install.sh が vibecorp.yml の preset に \${PRESET} を埋め込む"
else
  fail "install.sh が vibecorp.yml の preset を動的設定していない"
fi

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
