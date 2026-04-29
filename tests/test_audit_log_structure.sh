#!/bin/bash
# test_audit_log_structure.sh — Issue #442: 監査ログ構造（{role}/audit-log/YYYY-QN.md）の検証
# 使い方: bash tests/test_audit_log_structure.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"

echo "=== Issue #442: audit-log 構造テスト ==="

# --- テスト1: templates 配下の audit-log-index.md 存在 ---
echo ""
echo "--- テスト1: templates audit-log-index.md ---"

for role in accounting security legal; do
  index_file="${PROJECT_DIR}/templates/claude/knowledge/${role}/audit-log/audit-log-index.md"
  if [ -f "$index_file" ]; then
    pass "templates/${role}/audit-log/audit-log-index.md が存在する"
  else
    fail "templates/${role}/audit-log/audit-log-index.md が存在しない"
  fi
done

# --- テスト2: index 必須見出しの検証 ---
echo ""
echo "--- テスト2: 各 index に必須見出し ---"

assert_file_contains "accounting index に「経理監査ログ索引」の見出しがある" \
  "${PROJECT_DIR}/templates/claude/knowledge/accounting/audit-log/audit-log-index.md" \
  "# 経理監査ログ索引"
assert_file_contains "security index に「セキュリティ監査ログ索引」の見出しがある" \
  "${PROJECT_DIR}/templates/claude/knowledge/security/audit-log/audit-log-index.md" \
  "# セキュリティ監査ログ索引"
assert_file_contains "legal index に「法務監査ログ索引」の見出しがある" \
  "${PROJECT_DIR}/templates/claude/knowledge/legal/audit-log/audit-log-index.md" \
  "# 法務監査ログ索引"

# 全 index に「## 索引」見出しがある
for role in accounting security legal; do
  index_file="${PROJECT_DIR}/templates/claude/knowledge/${role}/audit-log/audit-log-index.md"
  if [ -f "$index_file" ]; then
    assert_file_contains "${role} index に「## 索引」見出しがある" "$index_file" "## 索引"
  fi
done

# --- テスト3: security/audit-log.md（旧パス）が存在しない ---
echo ""
echo "--- テスト3: 旧パス audit-log.md の不在 ---"

if [ -f "${PROJECT_DIR}/.claude/knowledge/security/audit-log.md" ]; then
  fail "旧パス .claude/knowledge/security/audit-log.md が残存している（移行されていない）"
else
  pass "旧パス .claude/knowledge/security/audit-log.md が存在しない（移行済み）"
fi

# --- テスト4: 移行先 security/audit-log/2026-Q2.md の存在 ---
echo ""
echo "--- テスト4: 移行先 audit-log/2026-Q2.md ---"

if [ -f "${PROJECT_DIR}/.claude/knowledge/security/audit-log/2026-Q2.md" ]; then
  pass ".claude/knowledge/security/audit-log/2026-Q2.md が存在する（git mv 移行済み）"
else
  fail ".claude/knowledge/security/audit-log/2026-Q2.md が存在しない"
fi

# --- テスト4b: 全 3 ロールの body 側 audit-log-index.md の存在（Issue #442 完了条件 #4） ---
echo ""
echo "--- テスト4b: body 側 audit-log-index.md ---"

for role in accounting security legal; do
  body_index="${PROJECT_DIR}/.claude/knowledge/${role}/audit-log/audit-log-index.md"
  if [ -f "$body_index" ]; then
    pass "${role}/audit-log/audit-log-index.md が body 側に配置されている"
  else
    fail "${role}/audit-log/audit-log-index.md が body 側に存在しない（templates のみで未配布）"
  fi
done

# --- テスト5: 旧フラット監査ファイルの遺物検出 ---
echo ""
echo "--- テスト5: 旧フラット audit-*.md の遺物検出 ---"

# accounting に audit-2*.md (audit-2026-04-29.md 等) が残っていないこと
accounting_legacy="$(find "${PROJECT_DIR}/.claude/knowledge/accounting" -maxdepth 1 -name 'audit-2*.md' 2>/dev/null || true)"
if [ -z "$accounting_legacy" ]; then
  pass "accounting に旧フラット audit-2*.md が存在しない"
else
  fail "accounting に旧フラット audit-2*.md が残存: $accounting_legacy"
fi

# legal に audit-*.md が残っていないこと（以前の audit-log.md 等）
legal_legacy="$(find "${PROJECT_DIR}/.claude/knowledge/legal" -maxdepth 1 -name 'audit-*.md' 2>/dev/null || true)"
if [ -z "$legal_legacy" ]; then
  pass "legal に旧フラット audit-*.md が存在しない"
else
  fail "legal に旧フラット audit-*.md が残存: $legal_legacy"
fi

# --- テスト6: cycle-metrics 旧パスの遺物検出（Issue #442） ---
echo ""
echo "--- テスト6: cycle-metrics 旧パス遺物検出 ---"

# cycle-metrics-YYYY-MM-DD.md が .claude/knowledge/accounting/ に残っていないこと
# template ファイル (cycle-metrics-template.md) は対象外
cycle_legacy="$(find "${PROJECT_DIR}/.claude/knowledge/accounting" -maxdepth 1 -name 'cycle-metrics-2*.md' 2>/dev/null || true)"
if [ -z "$cycle_legacy" ]; then
  pass "accounting に旧 cycle-metrics-2*.md が存在しない（~/.cache/ に移行済み）"
else
  fail "accounting に旧 cycle-metrics-2*.md が残存: $cycle_legacy"
fi

# --- テスト7: hook deny パターンが audit-log/ を含む ---
echo ""
echo "--- テスト7: hook deny パターン ---"

HOOK_FILE="${PROJECT_DIR}/templates/claude/hooks/protect-knowledge-direct-writes.sh"
assert_file_contains "hook に audit-log/ deny パターンがある" "$HOOK_FILE" 'audit-log/\*.md'

# --- テスト8: 分析員エージェント定義の audit-log 参照 ---
echo ""
echo "--- テスト8: 分析員エージェント定義 ---"

for role in accounting security legal; do
  agent_file="${PROJECT_DIR}/templates/claude/agents/${role}-analyst.md"
  if [ -f "$agent_file" ]; then
    assert_file_contains "${role}-analyst に audit-log/YYYY-QN.md パスがある" \
      "$agent_file" "audit-log/YYYY-QN.md"
    assert_file_contains "${role}-analyst に audit-log-index.md 言及がある" \
      "$agent_file" "audit-log-index.md"
    assert_file_contains "${role}-analyst に四半期計算ロジックがある" \
      "$agent_file" '(10#$month - 1) / 3 + 1'
  fi
done

print_test_summary
