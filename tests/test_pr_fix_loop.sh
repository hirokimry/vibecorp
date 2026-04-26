#!/bin/bash
# test_pr_fix_loop.sh — /vibecorp:pr-fix-loop の同期ループ仕様ガード
# 使い方: bash tests/test_pr_fix_loop.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_DIR/skills/pr-fix-loop/SKILL.md"

echo "=== /vibecorp:pr-fix-loop 同期ループ仕様ガード テスト ==="
echo ""

# --- テスト1: SKILL.md の存在 ---

echo "--- テスト1: SKILL.md の存在 ---"

if [ -f "$SKILL_FILE" ]; then
  pass "pr-fix-loop SKILL.md が存在する"
else
  fail "pr-fix-loop SKILL.md が存在しない: $SKILL_FILE"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

echo ""

# --- テスト2: frontmatter ---

echo "--- テスト2: frontmatter ---"

FIRST_LINE=$(head -1 "$SKILL_FILE")
if [ "$FIRST_LINE" = "---" ]; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りがない（先頭行: $FIRST_LINE）"
fi

NAME_VALUE=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "$SKILL_FILE")
if [ "$NAME_VALUE" = "pr-fix-loop" ]; then
  pass "name フィールドが 'pr-fix-loop' である"
else
  fail "name フィールドが期待値と異なる（実際: '$NAME_VALUE'）"
fi

echo ""

# --- テスト3: scheduler 依存の不在 ---

echo "--- テスト3: scheduler 依存の不在 ---"

# 制約セクション以外で /loop コマンドを呼び出していないことを確認する。
# 制約セクション内で「/loop を使わない」という記述は許容するため、
# 末尾の禁止事項リストを除外して検査する。
STRIPPED_FILE="$(mktemp)"
trap 'rm -f "$STRIPPED_FILE"' EXIT
awk '/^## 制約/{exit} {print}' "$SKILL_FILE" > "$STRIPPED_FILE"

if grep -q -e '/loop 5m' "$STRIPPED_FILE"; then
  fail "/loop 5m への依存記述が残っている（scheduler 依存除去が不完全）"
else
  pass "ワークフロー本文に /loop 5m への依存記述がない"
fi

# ScheduleWakeup は導入文の「依存しない」という否定文脈での言及のみ許容する
if grep -q -e 'ScheduleWakeup` のような非同期スケジューラには依存しない' "$SKILL_FILE"; then
  pass "ScheduleWakeup を使わない方針が導入文で明示されている"
else
  fail "ScheduleWakeup を使わない方針が導入文で明示されていない"
fi

# 制約セクション側で「/loop や ScheduleWakeup を使わない」が明示されていることを確認する
if grep -q -e '/loop.*ScheduleWakeup.*使わない\|/loop.*ScheduleWakeup を使わない\|`/loop` や `ScheduleWakeup` を使わない' "$SKILL_FILE"; then
  pass "制約セクションに /loop / ScheduleWakeup の禁止記述が存在する"
else
  fail "制約セクションに /loop / ScheduleWakeup の禁止記述が存在しない"
fi

echo ""

# --- テスト4: 同期ポーリングループの記述 ---

echo "--- テスト4: 同期ポーリングループの記述 ---"

if grep -q -e '同期ポーリングループ\|同期ループ\|同期版' "$SKILL_FILE"; then
  pass "同期ループの記述が存在する"
else
  fail "同期ループの記述が存在しない"
fi

if grep -q -e 'gh pr view' "$SKILL_FILE"; then
  pass "gh pr view による状態取得記述が存在する"
else
  fail "gh pr view による状態取得記述が存在しない"
fi

# 状態取得 JSON フィールド
JSON_FIELDS=("state" "mergeStateStatus" "reviewDecision" "autoMergeRequest")
for field in "${JSON_FIELDS[@]}"; do
  if grep -q -e "$field" "$SKILL_FILE"; then
    pass "JSON フィールド '$field' が記述されている"
  else
    fail "JSON フィールド '$field' が記述されていない"
  fi
done

echo ""

# --- テスト5: 状態遷移表の記述 ---

echo "--- テスト5: 状態遷移表の記述 ---"

STATES=("MERGED" "CLOSED" "CHANGES_REQUESTED" "CLEAN" "BLOCKED" "DIRTY" "DRAFT")
for state in "${STATES[@]}"; do
  if grep -q -e "$state" "$SKILL_FILE"; then
    pass "状態 '$state' が記述されている"
  else
    fail "状態 '$state' が記述されていない"
  fi
done

# CHANGES_REQUESTED 時に /vibecorp:pr-fix を同期呼び出しすることが明示されている
if grep -Eq '/vibecorp:pr-fix([^[:alnum:]-]|$)' "$SKILL_FILE"; then
  pass "pr-fix の同期呼び出し記述が存在する"
else
  fail "pr-fix の同期呼び出し記述が存在しない"
fi

echo ""

# --- テスト6: ループ制御値（iterations / timeout / polling 間隔） ---

echo "--- テスト6: ループ制御値（iterations / timeout / polling 間隔） ---"

# polling 間隔: 30 秒
if grep -q -e 'polling.*30 秒\|30 秒.*polling\|polling 間隔.*30' "$SKILL_FILE"; then
  pass "polling 間隔 30 秒の記述が存在する"
else
  fail "polling 間隔 30 秒の記述が存在しない"
fi

# max iterations: 20
if grep -q -e 'max iterations.*20\|反復.*20\|20 反復' "$SKILL_FILE"; then
  pass "max iterations 20 の記述が存在する"
else
  fail "max iterations 20 の記述が存在しない"
fi

# timeout: 60 分
if grep -q -e 'timeout.*60 分\|60 分.*timeout\|60 分以内\|3600 秒' "$SKILL_FILE"; then
  pass "timeout 60 分の記述が存在する"
else
  fail "timeout 60 分の記述が存在しない"
fi

echo ""

# --- テスト7: escalation 条件 ---

echo "--- テスト7: escalation 条件 ---"

if grep -q -e 'escalation\|escalate' "$SKILL_FILE"; then
  pass "escalation の記述が存在する"
else
  fail "escalation の記述が存在しない"
fi

# escalation の発火条件
ESCALATION_CONDITIONS=("max iterations" "timeout" "DIRTY" "DRAFT" "rate limit")
for cond in "${ESCALATION_CONDITIONS[@]}"; do
  if grep -q -e "$cond" "$SKILL_FILE"; then
    pass "escalation 条件 '$cond' が記述されている"
  else
    fail "escalation 条件 '$cond' が記述されていない"
  fi
done

# teammate 配下の SendMessage 通知
if grep -q -e 'SendMessage' "$SKILL_FILE"; then
  pass "SendMessage による team-lead 通知記述が存在する"
else
  fail "SendMessage による team-lead 通知記述が存在しない"
fi

if grep -q -e 'team-lead' "$SKILL_FILE"; then
  pass "team-lead 宛通知の記述が存在する"
else
  fail "team-lead 宛通知の記述が存在しない"
fi

echo ""

# --- テスト8: worktree モードの記述 ---

echo "--- テスト8: worktree モードの記述 ---"

if grep -q -e 'worktree モード\|--worktree' "$SKILL_FILE"; then
  pass "worktree モードの記述が存在する"
else
  fail "worktree モードの記述が存在しない"
fi

# サブスキル呼び出しに --worktree が引き継がれる
if grep -q -e '引き継' "$SKILL_FILE"; then
  pass "サブスキルへの --worktree 引き継ぎ記述が存在する"
else
  fail "サブスキルへの --worktree 引き継ぎ記述が存在しない"
fi

echo ""

# --- テスト9: CodeRabbit enabled=false 時のフォールバック ---

echo "--- テスト9: CodeRabbit enabled=false 時のフォールバック ---"

if grep -q -e 'coderabbit' "$SKILL_FILE"; then
  pass "coderabbit 設定への参照が存在する"
else
  fail "coderabbit 設定への参照が存在しない"
fi

if grep -q -e 'enabled' "$SKILL_FILE"; then
  pass "enabled キーへの参照が存在する"
else
  fail "enabled キーへの参照が存在しない"
fi

if grep -q -e 'スキップ\|skip' "$SKILL_FILE"; then
  pass "スキップ挙動の記述が存在する"
else
  fail "スキップ挙動の記述が存在しない"
fi

echo ""

# --- テスト10: コードブロック言語指定（rules/markdown.md 準拠） ---

echo "--- テスト10: コードブロック言語指定 ---"

bare_opens=$(awk '
  /^```[a-zA-Z]/ { in_fence = 1; next }
  /^```$/ {
    if (in_fence) { in_fence = 0 }
    else { count++ }
    next
  }
  END { print count + 0 }
' "$SKILL_FILE")

if [ "$bare_opens" -eq 0 ]; then
  pass "全てのコードブロックに言語指定がある"
else
  fail "言語指定なしのコードブロックが ${bare_opens} 件ある"
fi

echo ""

# --- 結果表示 ---

echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
