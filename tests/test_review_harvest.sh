#!/bin/bash
# test_review_harvest.sh — /vibecorp:review-harvest スキルの構造テスト
# LLM 駆動スキルのため、SKILL.md の必須要素・関連ファイル削除状況を検証する
# 使い方: bash tests/test_review_harvest.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SCRIPT_DIR}/skills/review-harvest/SKILL.md"
OLD_SKILL_DIR="${SCRIPT_DIR}/skills/review-to-rules"
OLD_HOOK="${SCRIPT_DIR}/templates/claude/hooks/review-to-rules-gate.sh"
OLD_TEST="${SCRIPT_DIR}/tests/test_review_to_rules_gate.sh"
SETTINGS="${SCRIPT_DIR}/templates/claude/settings.json"
SETTINGS_TPL="${SCRIPT_DIR}/templates/settings.json.tpl"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL: $1"; }

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then pass "$desc"; else fail "$desc ($path が存在しない)"; fi
}

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -e "$path" ]; then pass "$desc"; else fail "$desc ($path が残っている)"; fi
}

assert_contains() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE -- "$pattern" "$file"; then pass "$desc"; else fail "$desc (パターン '$pattern' が $file に含まれない)"; fi
}

assert_not_contains() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if ! grep -qE -- "$pattern" "$file"; then pass "$desc"; else fail "$desc (パターン '$pattern' が $file にまだ含まれる)"; fi
}

# ============================================
echo "=== /vibecorp:review-harvest SKILL.md 存在 ==="
# ============================================

assert_file_exists "SKILL.md が存在する" "$SKILL_FILE"

if [ ! -f "$SKILL_FILE" ]; then
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# ============================================
echo ""
echo "=== SKILL.md frontmatter ==="
# ============================================

assert_contains "name フィールドが review-harvest" '^name: review-harvest$' "$SKILL_FILE"
assert_contains "description フィールドがある" '^description: ' "$SKILL_FILE"

# ============================================
echo ""
echo "=== SKILL.md 必須要素 ==="
# ============================================

assert_contains "knowledge_buffer_ensure 呼出を記載" 'knowledge_buffer_ensure' "$SKILL_FILE"
assert_contains "knowledge_buffer_lock_acquire 呼出を記載" 'knowledge_buffer_lock_acquire' "$SKILL_FILE"
assert_contains "knowledge_buffer_read_last_pr 呼出を記載" 'knowledge_buffer_read_last_pr' "$SKILL_FILE"
assert_contains "knowledge_buffer_write_last_pr 呼出を記載" 'knowledge_buffer_write_last_pr' "$SKILL_FILE"
assert_contains "knowledge_buffer_commit 呼出を記載" 'knowledge_buffer_commit' "$SKILL_FILE"
assert_contains "knowledge_buffer_push 呼出を記載" 'knowledge_buffer_push' "$SKILL_FILE"

assert_contains "sort:created-desc を採用（updated-desc を使用しない）" 'sort:created-desc' "$SKILL_FILE"
assert_not_contains "sort:updated-desc を使わない" 'sort:updated-desc"[^ ]' "$SKILL_FILE"

assert_contains "VIBECORP_HARVEST_MAX_PRS を参照" 'VIBECORP_HARVEST_MAX_PRS' "$SKILL_FILE"
assert_contains "VIBECORP_HARVEST_API_TIMEOUT を参照" 'VIBECORP_HARVEST_API_TIMEOUT' "$SKILL_FILE"
assert_contains "VIBECORP_TOKEN_RATIO を参照" 'VIBECORP_TOKEN_RATIO' "$SKILL_FILE"

assert_contains "指数バックオフ 3 回リトライを明記" '指数バックオフ|retry|リトライ' "$SKILL_FILE"
assert_contains "30K トークン切り詰めを明記" '30[,K,0]{0,4}[0 ]*' "$SKILL_FILE"
assert_contains "C*O 5 呼出制限を明記" '5 呼出|CTO.*CPO.*CISO.*CFO.*CLO' "$SKILL_FILE"

assert_contains "user.login 匿名化を明記" '<reviewer>|匿名化' "$SKILL_FILE"
assert_contains "CodeRabbit 出所明示を明記" 'CodeRabbit' "$SKILL_FILE"

assert_contains "push 失敗時 exit 3 を明記" 'exit 3' "$SKILL_FILE"
assert_contains "in_reply_to_id フィルタを明記" 'in_reply_to_id' "$SKILL_FILE"

assert_contains "課金モード警告を明記" 'ANTHROPIC_API_KEY' "$SKILL_FILE"

# ============================================
echo ""
echo "=== 旧 review-to-rules 関連ファイル削除 ==="
# ============================================

assert_file_not_exists "旧 /vibecorp:review-to-rules スキル削除" "$OLD_SKILL_DIR"
assert_file_not_exists "旧 review-to-rules-gate.sh 削除" "$OLD_HOOK"
assert_file_not_exists "旧 test_review_to_rules_gate.sh 削除" "$OLD_TEST"

# ============================================
echo ""
echo "=== settings.json エントリ削除 ==="
# ============================================

assert_not_contains "settings.json から review-to-rules-gate エントリ削除" 'review-to-rules-gate' "$SETTINGS"
assert_not_contains "settings.json.tpl から review-to-rules-gate エントリ削除" 'review-to-rules-gate' "$SETTINGS_TPL"

# ============================================
echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
