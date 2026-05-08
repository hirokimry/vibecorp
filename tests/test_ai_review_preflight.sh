#!/bin/bash
# test_ai_review_preflight.sh
# ─────────────────────────────────────────────
# Issue #509: ai-review.yml の preflight ガード（claude-code-action 起動前 OAUTH_TOKEN 空判定）の
# bash ロジック動的単体テスト。
#
# yaml 静的構造の検証は test_install_ai_review_workflow.sh が担当する。本テストは preflight ステップの
# `run:` ブロックを yaml から抽出して実際に bash で実行し、以下の 3 ケースで挙動を検証する:
#   1. OAUTH_TOKEN 空 + 既存警告コメントなし → gh pr comment 1 回呼出 + exit 1
#   2. OAUTH_TOKEN 空 + 既存警告コメントあり → gh pr comment は呼ばれず exit 1
#   3. OAUTH_TOKEN 設定済み                 → "✅ ... 通過" を出力して exit 0
#
# yaml 静的検証だけでは「ステップは存在するが空判定が壊れている」「重複防止が誤検知する」等の
# bash 実行時バグを検出できないため、本テストを必須に追加する（PR #508 で発覚した障害の再発防止強化）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/test_helpers.sh"

YML_TARGET="${SCRIPT_DIR}/.github/workflows/ai-review.yml"
YML_TEMPLATE="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"

# Issue #532: vibecorp.yml の claude_action.enabled が false の場合は自リポ版が削除されている
# ため、配布版（templates/ 配下）から preflight ロジックを抽出して検証する。
SELF_REPO_ENABLED="true"
VIBECORP_YML="${SCRIPT_DIR}/.claude/vibecorp.yml"
if [[ -f "$VIBECORP_YML" ]]; then
  ca_enabled=$(awk '
    /^claude_action:[[:space:]]*$/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
      sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$VIBECORP_YML")
  if [[ "$ca_enabled" == "false" ]]; then
    SELF_REPO_ENABLED="false"
  fi
fi

assert_file_exists "templates 配布版 ai-review.yml が存在する" "$YML_TEMPLATE"

if [[ "$SELF_REPO_ENABLED" == "true" ]]; then
  assert_file_exists "vibecorp 自リポ ai-review.yml が存在する" "$YML_TARGET"
  # 自リポ版と配布版が一致することを確認（preflight 内容も同期されている保証）
  if diff -q "$YML_TARGET" "$YML_TEMPLATE" >/dev/null; then
    pass "自リポ版と templates 配布版の ai-review.yml が完全一致"
  else
    fail "自リポ版と templates 配布版の ai-review.yml が乖離している"
    exit 1
  fi
  PREFLIGHT_SOURCE="$YML_TARGET"
else
  echo "  SKIP: vibecorp 自リポ ai-review.yml の検証（claude_action.enabled: false のため）"
  # 配布版テンプレートから preflight ロジックを抽出して検証する
  PREFLIGHT_SOURCE="$YML_TEMPLATE"
fi

# preflight ステップの run: ブロックを抽出する
# ヘッダ「- name: claude-code-action 起動前 preflight ガード」から次の「- name:」直前まで
# を切り出し、その中の「run: |」以降のインデント行を取り出して bash 実行可能な形に整形する。
extract_preflight_bash() {
  local yml="$1"
  awk '
    /^      - name: claude-code-action 起動前 preflight/ { in_step = 1; next }
    in_step && /^      - name:/ { exit }
    in_step && /^        run: \|/ { in_run = 1; next }
    in_run { sub(/^          /, ""); print }
  ' "$yml"
}

PREFLIGHT_BASH="$(extract_preflight_bash "$PREFLIGHT_SOURCE")"
if [[ -z "$PREFLIGHT_BASH" ]]; then
  fail "preflight ステップの run: ブロックが抽出できない"
  exit 1
else
  pass "preflight ステップの run: ブロックを抽出"
fi

TMPDIR_ROOT=""
cleanup() {
  if [[ -n "$TMPDIR_ROOT" && -d "$TMPDIR_ROOT" ]]; then
    rm -rf "$TMPDIR_ROOT" || true
  fi
}
trap cleanup EXIT

# gh モック: 呼び出しを ${TMPDIR_ROOT}/gh-calls.log に記録する。
#   - "pr view --json comments" → $1 (pr_view_result) を出力
#   - "pr comment" → コール記録のみ、exit 0
setup_gh_mock() {
  local pr_view_result="$1"
  cat > "${TMPDIR_ROOT}/gh" <<GHSH
#!/bin/bash
# モック gh: 呼び出しを記録するだけ
echo "\$@" >> "${TMPDIR_ROOT}/gh-calls.log"
case "\$1 \$2" in
  "pr view")
    echo "${pr_view_result}"
    ;;
  "pr comment")
    ;;
  *)
    ;;
esac
exit 0
GHSH
  chmod +x "${TMPDIR_ROOT}/gh"
  : > "${TMPDIR_ROOT}/gh-calls.log"
}

# run_preflight: $TMPDIR_ROOT を呼び出し元で設定済みであることを前提とする。
# rc を ${TMPDIR_ROOT}/rc に書き出し、コマンド置換を使わない（サブシェルで TMPDIR_ROOT が伝播しないため）
run_preflight() {
  local oauth_token="$1"
  local stdout_file="${TMPDIR_ROOT}/stdout"
  local stderr_file="${TMPDIR_ROOT}/stderr"
  local rc=0

  PATH="${TMPDIR_ROOT}:${PATH}" \
    OAUTH_TOKEN="$oauth_token" \
    GH_TOKEN="dummy-gh-token" \
    PR_NUMBER="999" \
    REPO="hirokimry/vibecorp" \
    bash -e -o pipefail -c "$PREFLIGHT_BASH" >"$stdout_file" 2>"$stderr_file" || rc=$?

  echo "$rc" > "${TMPDIR_ROOT}/rc"
}

count_gh_calls() {
  # grep -c はマッチ 0 件で exit 1 を返すため set -e 下では使えない。
  # awk で行頭一致をカウントする（regex は呼び出し側で渡される）。
  local pattern="$1"
  awk -v pat="$pattern" '$0 ~ pat { c++ } END { print c+0 }' "${TMPDIR_ROOT}/gh-calls.log"
}

# ============================================
# Case 1: OAUTH_TOKEN 空 + 既存警告コメントなし
#   → gh pr comment が呼ばれて exit 1
# ============================================
echo ""
echo "--- Case 1: OAUTH_TOKEN 空 + 既存警告コメントなし → gh pr comment 1 回 + exit 1 ---"
TMPDIR_ROOT="$(mktemp -d)"
setup_gh_mock "0"
run_preflight ""
rc="$(cat "${TMPDIR_ROOT}/rc")"
assert_eq "Case 1: exit 1" "1" "$rc"
pr_comment_count=$(count_gh_calls "^pr comment")
assert_eq "Case 1: gh pr comment 1 回呼び出し" "1" "$pr_comment_count"
pr_view_count=$(count_gh_calls "^pr view")
assert_eq "Case 1: gh pr view 1 回呼び出し（既存コメント検出）" "1" "$pr_view_count"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 2: OAUTH_TOKEN 空 + 既存警告コメントあり
#   → gh pr comment は呼ばれず exit 1
# ============================================
echo ""
echo "--- Case 2: OAUTH_TOKEN 空 + 既存警告コメントあり → gh pr comment 呼ばれず exit 1 ---"
TMPDIR_ROOT="$(mktemp -d)"
setup_gh_mock "1"
run_preflight ""
rc="$(cat "${TMPDIR_ROOT}/rc")"
assert_eq "Case 2: exit 1" "1" "$rc"
pr_comment_count=$(count_gh_calls "^pr comment")
assert_eq "Case 2: gh pr comment 0 回呼び出し（重複防止）" "0" "$pr_comment_count"
pr_view_count=$(count_gh_calls "^pr view")
assert_eq "Case 2: gh pr view 1 回呼び出し" "1" "$pr_view_count"
cleanup
TMPDIR_ROOT=""

# ============================================
# Case 3: OAUTH_TOKEN 設定済み
#   → "✅ ... 通過" 出力 + exit 0
# ============================================
echo ""
echo "--- Case 3: OAUTH_TOKEN 設定済み → exit 0 ---"
TMPDIR_ROOT="$(mktemp -d)"
: > "${TMPDIR_ROOT}/gh-calls.log"
# このケースでは gh が呼ばれないことを確認する（PATH には mock を置かない、real gh を使うが呼ばれないので影響なし）
stdout_file="${TMPDIR_ROOT}/stdout"
rc=0
OAUTH_TOKEN="dummy-non-empty-token-1234567890" \
  GH_TOKEN="dummy-gh-token" \
  PR_NUMBER="999" \
  REPO="hirokimry/vibecorp" \
  bash -e -o pipefail -c "$PREFLIGHT_BASH" >"$stdout_file" 2>/dev/null || rc=$?
assert_eq "Case 3: exit 0" "0" "$rc"
if grep -q "preflight 通過" "$stdout_file"; then
  pass "Case 3: '✅ ... preflight 通過' 出力"
else
  fail "Case 3: 通過メッセージが出力されない（stdout: $(cat "$stdout_file")）"
fi
cleanup
TMPDIR_ROOT=""

print_test_summary
