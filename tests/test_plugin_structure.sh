#!/bin/bash
# test_plugin_structure.sh — Plugin 名前空間の構造テスト
# skills/ にプラグインスキルが配置され、.claude/skills/ がスタブになっていることを検証する
# 使い方: bash tests/test_plugin_structure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# ============================================
echo ""
echo "=== Plugin 構造テスト ==="
# ============================================

# --- A. vibecorp リポジトリ自体のプラグイン構造 ---

echo ""
echo "--- A. vibecorp リポジトリ自体のプラグイン構造 ---"

# A1. .claude-plugin/plugin.json が存在する
assert_file_exists ".claude-plugin/plugin.json 存在" "${SCRIPT_DIR}/.claude-plugin/plugin.json"

# A2. plugin.json に必須フィールドが含まれる
assert_file_contains "plugin.json に name" "${SCRIPT_DIR}/.claude-plugin/plugin.json" '"name"'
assert_file_contains "plugin.json に version" "${SCRIPT_DIR}/.claude-plugin/plugin.json" '"version"'
assert_file_contains "plugin.json に description" "${SCRIPT_DIR}/.claude-plugin/plugin.json" '"description"'

# A3. skills/ ディレクトリが存在する
assert_dir_exists "skills/ ディレクトリ存在" "${SCRIPT_DIR}/skills"

# A4. 主要スキルが skills/ に存在する
for skill in ship review commit plan pr issue branch; do
  assert_file_exists "skills/${skill}/SKILL.md 存在" "${SCRIPT_DIR}/skills/${skill}/SKILL.md"
done

# A5. .claude/skills/ がスタブになっている（install.sh 実行後のみ検証可能）
# CI 環境では .claude/skills/ のスタブは install.sh で自動生成されるため、
# checkout 直後にはスタブが揃わない。スタブの整合性はセクション B（install 後）で検証する。
STUB_COUNT=$(find "${SCRIPT_DIR}/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
PLUGIN_COUNT=$(find "${SCRIPT_DIR}/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [[ "$STUB_COUNT" -ge "$PLUGIN_COUNT" ]]; then
  for skill in ship review commit plan pr issue branch; do
    STUB_FILE="${SCRIPT_DIR}/.claude/skills/${skill}/SKILL.md"
    if [[ -f "$STUB_FILE" ]]; then
      if grep -q "vibecorp:${skill}" "$STUB_FILE"; then
        pass ".claude/skills/${skill} がスタブ（リダイレクト）"
      else
        fail ".claude/skills/${skill} がスタブでない（vibecorp:${skill} への参照がない）"
      fi
    else
      fail ".claude/skills/${skill}/SKILL.md が存在しない"
    fi
  done
  pass "plugin skills 数（${PLUGIN_COUNT}）= stub 数（${STUB_COUNT}）"
else
  pass "A5/A6: スタブ未生成（CI 環境）— install 後テスト（B4）で検証"
fi

# --- B. install.sh でのプラグインスキル配布 ---

echo ""
echo "--- B. install.sh でのプラグインスキル配布 ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# B1. skills/ がインストール先に作成される
assert_dir_exists "install 後 skills/ 存在" "${R}/skills"

# B2. 主要スキルが skills/ にコピーされている
for skill in ship review commit plan pr issue; do
  assert_file_exists "install 後 skills/${skill}/SKILL.md" "${R}/skills/${skill}/SKILL.md"
done

# B3. .claude-plugin/plugin.json がコピーされている
assert_file_exists "install 後 .claude-plugin/plugin.json" "${R}/.claude-plugin/plugin.json"

# B4. .claude/skills/ がスタブとしてコピーされている
for skill in ship review commit; do
  STUB_FILE="${R}/.claude/skills/${skill}/SKILL.md"
  if [[ -f "$STUB_FILE" ]]; then
    if grep -q "vibecorp:${skill}" "$STUB_FILE"; then
      pass "install 後 .claude/skills/${skill} がスタブ"
    else
      fail "install 後 .claude/skills/${skill} がスタブでない"
    fi
  else
    fail "install 後 .claude/skills/${skill}/SKILL.md が存在しない"
  fi
done

# B5. vibecorp.lock に plugin_skills セクションがある
assert_file_contains "lock に plugin_skills" "${R}/.claude/vibecorp.lock" "plugin_skills:"

# --- C. プリセット別のスキル削除 ---

echo ""
echo "--- C. プリセット別のスキル削除（minimal） ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# C1. minimal ではヘッドレス並列スキルが plugin skills からも削除されている
for skill in ship-parallel autopilot spike-loop diagnose; do
  if [[ -d "${R}/skills/${skill}" ]]; then
    fail "minimal で skills/${skill} が残っている"
  else
    pass "minimal で skills/${skill} が削除されている"
  fi
done

# C2. minimal でも基本スキルは plugin skills に残っている
for skill in ship review commit plan pr issue; do
  assert_file_exists "minimal で skills/${skill} が存在" "${R}/skills/${skill}/SKILL.md"
done

echo ""
echo "--- C. プリセット別のスキル削除（standard） ---"

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# C3. standard ではヘッドレス並列スキルが plugin skills からも削除されている
for skill in ship-parallel autopilot spike-loop diagnose; do
  if [[ -d "${R}/skills/${skill}" ]]; then
    fail "standard で skills/${skill} が残っている"
  else
    pass "standard で skills/${skill} が削除されている"
  fi
done

# C4. standard では sync-check 等が plugin skills に残っている
for skill in sync-check session-harvest; do
  assert_file_exists "standard で skills/${skill} が存在" "${R}/skills/${skill}/SKILL.md"
done

# --- D. テンプレート整合性 ---

echo ""
echo "--- D. テンプレート整合性 ---"

# D1. templates/claude-plugin/plugin.json が存在する
assert_file_exists "templates/claude-plugin/plugin.json" "${SCRIPT_DIR}/templates/claude-plugin/plugin.json"

# D2. templates/claude/skills/ が廃止されている（スタブは install.sh で自動生成）
if [[ -d "${SCRIPT_DIR}/templates/claude/skills" ]]; then
  fail "templates/claude/skills/ が残存している（廃止済み: スタブは install.sh で自動生成）"
else
  pass "templates/claude/skills/ が廃止されている"
fi

print_test_summary
