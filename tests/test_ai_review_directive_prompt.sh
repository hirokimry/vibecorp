#!/bin/bash
# test_ai_review_directive_prompt.sh
# ─────────────────────────────────────────────
# Issue #521: claude-code-action がレビューコメントを出さずにサイレント終了する問題の解消検証。
#
# 真因: REVIEW.md が「ルールブック」として書かれており、Claude が「実行すべき仕事がある」と
# 判定しないため 1 ターンで終了していた（PR #520 ログ: num_turns: 1, No buffered inline comments）。
#
# 修正:
#   1. REVIEW.md / templates/REVIEW.md.tpl を「指示書型」に書き換え
#      → 「あなたの仕事」「実行手順」「Step 1〜9」を明示
#   2. ai-review.yml の Claude Code Action 実行ステップに claude_args.--allowedTools を追加
#      → mcp__github_inline_comment__create_inline_comment, gh pr review/comment/diff/view を許可
#
# 本テストは上記 2 点が両方適用されていることを yaml/markdown 静的検証する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF_REVIEW="${SCRIPT_DIR}/REVIEW.md"
TEMPLATE_REVIEW="${SCRIPT_DIR}/templates/REVIEW.md.tpl"
SELF_AI_REVIEW="${SCRIPT_DIR}/.github/workflows/ai-review.yml"
TEMPLATE_AI_REVIEW="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"

assert_file_exists "vibecorp 自リポ REVIEW.md" "$SELF_REVIEW"
assert_file_exists "templates 配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"
assert_file_exists "vibecorp 自リポ ai-review.yml" "$SELF_AI_REVIEW"
assert_file_exists "templates 配布版 ai-review.yml" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 1: REVIEW.md / REVIEW.md.tpl が指示書型に書き換わっている
# ============================================
echo ""
echo "--- Case 1: REVIEW.md が指示書型である（命令文を含む） ---"

check_directive_form() {
  local label="$1"
  local file="$2"
  # 指示書型の必須キーワード
  local must_have=(
    "コードレビューを実施してください"
    "0 件でも必ず"
    "順番に実行"
    "Step 1: PR 差分を取得する"
    "Step 7: approve / request_changes を発行する"
  )
  for kw in "${must_have[@]}"; do
    if grep -q -F -- "$kw" "$file"; then
      pass "${label}: 「${kw}」を含む"
    else
      fail "${label}: 「${kw}」が無い（指示書型として不十分）"
    fi
  done
}

check_directive_form "自リポ版 REVIEW.md" "$SELF_REVIEW"
check_directive_form "配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"

# ============================================
# Case 2: REVIEW.md が必須ツール呼び出しを明示
# ============================================
echo ""
echo "--- Case 2: REVIEW.md が必須ツール呼び出しを明示している ---"

check_tool_mentions() {
  local label="$1"
  local file="$2"
  # ツール呼び出しの明示
  local tools=(
    "mcp__github_inline_comment__create_inline_comment"
    "gh pr diff"
    "gh pr review"
    "gh pr comment"
    "gh pr view"
  )
  for tool in "${tools[@]}"; do
    if grep -q -F -- "$tool" "$file"; then
      pass "${label}: 「${tool}」呼び出しを明示"
    else
      fail "${label}: 「${tool}」呼び出しが明示されていない"
    fi
  done
}

check_tool_mentions "自リポ版 REVIEW.md" "$SELF_REVIEW"
check_tool_mentions "配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"

# ============================================
# Case 3: REVIEW.md が「修正対象 0 件でも approve 必須」を明示
# ============================================
echo ""
echo "--- Case 3: 修正対象 0 件でも approve を発行することを明示 ---"

check_zero_approve() {
  local label="$1"
  local file="$2"
  if grep -q -F -- "0 件でも必ず" "$file"; then
    pass "${label}: 「0 件でも必ず approve」明示"
  else
    fail "${label}: 「0 件でも必ず approve」が明示されていない"
  fi
}

check_zero_approve "自リポ版 REVIEW.md" "$SELF_REVIEW"
check_zero_approve "配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"

# ============================================
# Case 4: ai-review.yml に claude_args.--allowedTools が含まれる
# ============================================
echo ""
echo "--- Case 4: ai-review.yml に claude_args が指定されている ---"

check_claude_args() {
  local label="$1"
  local file="$2"
  if grep -q -F -- "claude_args:" "$file"; then
    pass "${label}: claude_args 指定あり"
  else
    fail "${label}: claude_args が無い（Claude のツール呼び出し不可）"
  fi

  # 必須ツールが --allowedTools に含まれている
  local required_tools=(
    "mcp__github_inline_comment__create_inline_comment"
    "Bash(gh pr review:*)"
    "Bash(gh pr comment:*)"
    "Bash(gh pr diff:*)"
    "Bash(gh pr view:*)"
  )
  for tool in "${required_tools[@]}"; do
    if grep -q -F -- "$tool" "$file"; then
      pass "${label}: --allowedTools に「${tool}」を含む"
    else
      fail "${label}: --allowedTools に「${tool}」が無い"
    fi
  done
}

check_claude_args "自リポ版 ai-review.yml" "$SELF_AI_REVIEW"
check_claude_args "配布版 ai-review.yml" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 4b: Claude Code Action 実行ステップに env: PR_NUMBER, GITHUB_REPOSITORY が指定されている (Issue #523)
# ============================================
echo ""
echo "--- Case 4b: Claude Code Action 実行ステップの env: 必須変数（Issue #523） ---"

check_env_vars() {
  local label="$1"
  local file="$2"
  # Claude Code Action 実行ステップ範囲を抽出（次の `- name:` または ファイル末まで）
  local step_block
  step_block="$(awk '
    /^      - name: Claude Code Action 実行/ { in_step = 1; print; next }
    in_step && /^      - name:/ { exit }
    in_step { print }
  ' "$file")"

  if [ -z "$step_block" ]; then
    fail "${label}: Claude Code Action 実行ステップが見つからない"
    return
  fi

  if printf '%s' "$step_block" | grep -q -E "^[[:space:]]*env:[[:space:]]*$"; then
    pass "${label}: Claude Code Action 実行ステップに env: が指定されている"
  else
    fail "${label}: Claude Code Action 実行ステップに env: が無い（PR_NUMBER 等が Claude プロセスに渡らずサイレント終了する）"
  fi

  # PR_NUMBER が github.event.pull_request.number にマップされている（同一行で厳密チェック、CodeRabbit #524 指摘対応）
  # キーと値を別 grep で見ると将来マッピングが入れ替わっても通る誤検知が発生するため、
  # 1 行内で `KEY: ${{ EXPR }}` 形式を正規表現一発で照合する。
  if printf '%s\n' "$step_block" | grep -q -E '^[[:space:]]*PR_NUMBER:[[:space:]]*\$\{\{[[:space:]]*github\.event\.pull_request\.number[[:space:]]*\}\}[[:space:]]*$'; then
    pass "${label}: env で PR_NUMBER が github.event.pull_request.number にマップされている"
  else
    fail "${label}: env の PR_NUMBER 設定が不適切（github.event.pull_request.number にマップされるべき）"
  fi

  # GITHUB_REPOSITORY が github.repository にマップされている（同一行で厳密チェック、CodeRabbit #524 指摘対応）
  if printf '%s\n' "$step_block" | grep -q -E '^[[:space:]]*GITHUB_REPOSITORY:[[:space:]]*\$\{\{[[:space:]]*github\.repository[[:space:]]*\}\}[[:space:]]*$'; then
    pass "${label}: env で GITHUB_REPOSITORY が github.repository にマップされている"
  else
    fail "${label}: env の GITHUB_REPOSITORY 設定が不適切（github.repository にマップされるべき）"
  fi
}

check_env_vars "自リポ版 ai-review.yml" "$SELF_AI_REVIEW"
check_env_vars "配布版 ai-review.yml" "$TEMPLATE_AI_REVIEW"

# ============================================
# Case 5: 自リポ版と配布版 ai-review.yml が完全一致（drift 検知）
# ============================================
echo ""
echo "--- Case 5: 自リポ版と配布版 ai-review.yml が完全一致 ---"

if diff -q "$SELF_AI_REVIEW" "$TEMPLATE_AI_REVIEW" >/dev/null; then
  pass "自リポ版と配布版 ai-review.yml が完全一致"
else
  fail "自リポ版と配布版 ai-review.yml が乖離している"
fi

# ============================================
# Case 6: REVIEW.md が「ルールブック」型でなくなったことの確認
# ============================================
echo ""
echo "--- Case 6: 旧「ルールブック」型のフレーズが残存していない ---"

check_no_rulebook_phrase() {
  local label="$1"
  local file="$2"
  # 旧形式の特徴的な表現は冒頭から削除されているはず
  # （注: 補足セクションには残しても良いため、冒頭セクションのみ確認）
  local first_50_lines
  first_50_lines="$(head -50 "$file")"
  if echo "$first_50_lines" | grep -q -F "REVIEW.md 自体には実体ルールを書きません"; then
    fail "${label}: 旧「実体ルールを書きません」フレーズが冒頭付近に残存（指示書型と不整合）"
  else
    pass "${label}: 旧フレーズが冒頭から撤去されている"
  fi
}

check_no_rulebook_phrase "自リポ版 REVIEW.md" "$SELF_REVIEW"
check_no_rulebook_phrase "配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"

# ============================================
# Case 7: REVIEW.md が冒頭から命令文で開始する（Issue #525）
# ============================================
echo ""
echo "--- Case 7: REVIEW.md 冒頭が命令文（メタ説明禁止、Issue #525） ---"

check_imperative_opening() {
  local label="$1"
  local file="$2"
  # 最初の本文行（# タイトル行と空行を除く）を取得
  local first_body_line
  first_body_line="$(awk '/^[^#[:space:]]/ { print; exit }' "$file")"

  # メタ説明禁止語: 冒頭にこれらが含まれると Claude が「これは仕様書」と読み流す
  local meta_phrases=(
    "がレビュー実行時に読む"
    "ルールブックではなく実行手順書"
    "実行時に参照する"
  )
  local found_meta=0
  for phrase in "${meta_phrases[@]}"; do
    if echo "$first_body_line" | grep -q -F -- "$phrase"; then
      fail "${label}: 冒頭本文にメタ説明「${phrase}」が残存（命令文で始まっていない）"
      found_meta=1
    fi
  done
  if [ "$found_meta" -eq 0 ]; then
    pass "${label}: 冒頭本文にメタ説明が含まれていない"
  fi

  # 最初の本文行が命令文（「〜してください」または英語の動詞原形 = action verb）か
  if echo "$first_body_line" | grep -qE 'してください|してね|を実施|review of this PR|Perform|Review|Check|Run'; then
    pass "${label}: 冒頭本文が命令文で開始している（action item として認識される）"
  else
    fail "${label}: 冒頭本文が命令文で開始していない（冒頭本文: ${first_body_line}）"
  fi
}

check_imperative_opening "自リポ版 REVIEW.md" "$SELF_REVIEW"
check_imperative_opening "配布版 REVIEW.md.tpl" "$TEMPLATE_REVIEW"

# ============================================
# Case 8: ai-review.yml は変更されていない（main と同じ、Issue #525）
# ============================================
echo ""
echo "--- Case 8: ai-review.yml が main と一致（PR 動作確認のため変更禁止） ---"

# main ブランチが取得できる環境でのみ実行（CI 環境など）
if git rev-parse --verify --quiet origin/main >/dev/null; then
  if git diff --quiet origin/main -- .github/workflows/ai-review.yml templates/.github/workflows/ai-review.yml; then
    pass "ai-review.yml が main と完全一致（claude-code-action workflow validation を通過）"
  else
    fail "ai-review.yml が main と乖離している（PR 自身で claude-code-action が動作しない原因）"
  fi
else
  echo "  SKIP: origin/main が利用不可（local 開発環境）"
fi

print_test_summary
