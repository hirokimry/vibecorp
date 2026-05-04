#!/bin/bash
# test_install_claude_action_secrets.sh
# ─────────────────────────────────────────────
# install.sh の verify_claude_action_secrets() のテスト
# Issue #462: claude-code-action OAuth 認証経路 docs 整備
#
# 検証対象:
#   - vibecorp.yml 不在時: no-op で return 0
#   - claude_action セクション不在時: no-op で return 0
#   - claude_action.enabled: false 時: no-op で return 0
#   - claude_action.enabled: true + gh 未導入: log_skip
#   - claude_action.enabled: true + gh 未認証: log_skip
#   - claude_action.enabled: true + secrets 登録あり: log_info
#   - claude_action.enabled: true + secrets 未登録: log_warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

# install.sh を source して verify_claude_action_secrets を呼べるようにする
# install.sh は末尾の if [[ BASH_SOURCE == 0 ]] ガードで main 自動起動を抑止している
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/install.sh"

# モック gh を作るためのテンポラリ PATH
MOCK_BIN_DIR=""

setup_mock_gh() {
  # 引数: $1 = "missing" | "noauth" | "registered" | "unregistered"
  # gh コマンドを置き換えてテストケースに応じた振る舞いをさせる
  local mode="$1"
  MOCK_BIN_DIR="$(mktemp -d)"

  case "$mode" in
    missing)
      # missing は run_verify 側で `command` シェル組込みを shadow して扱うため
      # ここでは gh モックを置かない（モックを置くと CI で逆効果になる）
      ;;
    noauth)
      cat > "${MOCK_BIN_DIR}/gh" <<'GHSH'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 1 ;;
esac
exit 1
GHSH
      chmod +x "${MOCK_BIN_DIR}/gh"
      ;;
    registered)
      cat > "${MOCK_BIN_DIR}/gh" <<'GHSH'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
esac
case "$1" in
  secret)
    if [[ "$2" == "list" ]]; then
      printf 'CLAUDE_CODE_OAUTH_TOKEN\t2026-01-01T00:00:00Z\n'
      printf 'OTHER_TOKEN\t2026-01-01T00:00:00Z\n'
      exit 0
    fi
    ;;
esac
exit 0
GHSH
      chmod +x "${MOCK_BIN_DIR}/gh"
      ;;
    unregistered)
      cat > "${MOCK_BIN_DIR}/gh" <<'GHSH'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
esac
case "$1" in
  secret)
    if [[ "$2" == "list" ]]; then
      printf 'OTHER_TOKEN\t2026-01-01T00:00:00Z\n'
      exit 0
    fi
    ;;
esac
exit 0
GHSH
      chmod +x "${MOCK_BIN_DIR}/gh"
      ;;
  esac
}

# install.sh の verify_claude_action_secrets を呼んで stderr を捕捉する
# 第 2 引数の mode に応じて gh モックを切り替える
#
# missing モードは単に PATH から gh を消すだけだと CI 環境（gh が /usr/bin/gh など
# 標準パスに入っている）で漏れるため、`command` シェル組込みを関数で shadow して
# `command -v gh` を強制的に失敗させる方式を採る。これによりホスト環境に依存せず
# 常に「gh 未導入」と同じ分岐を踏ませられる。
#
# 終了コードは RUN_VERIFY_RC グローバルに保存する。docs/ai-review-auth.md §5 の
# 「警告のみで install.sh は失敗扱いにしない（exit 0 継続）」要件を後段で
# `assert_run_verify_rc_zero` により検証するため、`|| true` で握りつぶさない。
RUN_VERIFY_RC=0

run_verify() {
  local repo_root="$1"
  local mode="$2"

  local saved_repo_root="${REPO_ROOT:-}"
  REPO_ROOT="$repo_root"

  local out
  local rc
  if [[ "$mode" == "missing" ]]; then
    # gh が PATH にあっても無くても、必ず not-found 扱いにする
    set +e
    out=$(
      command() {
        if [[ "$1" == "-v" && "$2" == "gh" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      verify_claude_action_secrets 2>&1 >/dev/null
    )
    rc=$?
    set -e
  else
    setup_mock_gh "$mode"
    # MOCK_BIN_DIR を PATH 先頭に置き、システム gh より優先する
    set +e
    out=$(PATH="${MOCK_BIN_DIR}:${PATH}" verify_claude_action_secrets 2>&1 >/dev/null)
    rc=$?
    set -e
    rm -rf "$MOCK_BIN_DIR" || true
    MOCK_BIN_DIR=""
  fi

  REPO_ROOT="$saved_repo_root"
  RUN_VERIFY_RC=$rc
  echo "$out"
}

# verify_claude_action_secrets は WARN を出しても exit 0 を維持する仕様
# （docs/ai-review-auth.md §5）。run_verify 直後に呼んで rc==0 をアサートする。
assert_run_verify_rc_zero() {
  local case_label="$1"
  if [[ "${RUN_VERIFY_RC}" -eq 0 ]]; then
    pass "${case_label}: verify_claude_action_secrets が exit 0 を維持する"
  else
    fail "${case_label}: verify_claude_action_secrets が非 0 で終了 (rc=${RUN_VERIFY_RC})"
  fi
}

# テスト用の vibecorp.yml を作成するヘルパー
# 第 1 引数 = 一時 repo ルート、第 2 引数 = vibecorp.yml の内容
write_yml() {
  local repo_root="$1"
  local content="$2"
  mkdir -p "${repo_root}/.claude"
  printf '%s\n' "$content" > "${repo_root}/.claude/vibecorp.yml"
}

echo ""
echo "=== verify_claude_action_secrets のテスト ==="

# ── ケース 1: vibecorp.yml 不在 → no-op ──────────────────
TMP1=$(mktemp -d)
OUT=$(run_verify "$TMP1" missing)
if [[ -z "$OUT" ]]; then
  pass "vibecorp.yml 不在時に出力なし"
else
  fail "vibecorp.yml 不在時に出力あり: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 1"
rm -rf "$TMP1" || true

# ── ケース 2: claude_action セクション不在 → no-op ──────
TMP2=$(mktemp -d)
write_yml "$TMP2" "name: test
preset: minimal"
OUT=$(run_verify "$TMP2" missing)
if [[ -z "$OUT" ]]; then
  pass "claude_action セクション不在時に出力なし"
else
  fail "claude_action セクション不在時に出力あり: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 2"
rm -rf "$TMP2" || true

# ── ケース 3: claude_action.enabled: false → no-op ──────
TMP3=$(mktemp -d)
write_yml "$TMP3" "name: test
preset: full
claude_action:
  enabled: false"
OUT=$(run_verify "$TMP3" missing)
if [[ -z "$OUT" ]]; then
  pass "claude_action.enabled: false で出力なし"
else
  fail "claude_action.enabled: false で出力あり: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 3"
rm -rf "$TMP3" || true

# ── ケース 4: claude_action.enabled: true + gh 未導入 → log_skip ──
TMP4=$(mktemp -d)
write_yml "$TMP4" "name: test
preset: full
claude_action:
  enabled: true"
OUT=$(run_verify "$TMP4" missing)
if echo "$OUT" | grep -q "gh CLI が見つかりません"; then
  pass "gh 未導入時に SKIP メッセージが出力される"
else
  fail "gh 未導入時の SKIP メッセージなし: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 4"
rm -rf "$TMP4" || true

# ── ケース 5: claude_action.enabled: true + gh 未認証 → log_skip ──
TMP5=$(mktemp -d)
write_yml "$TMP5" "name: test
preset: full
claude_action:
  enabled: true"
OUT=$(run_verify "$TMP5" noauth)
if echo "$OUT" | grep -q "gh が未認証"; then
  pass "gh 未認証時に SKIP メッセージが出力される"
else
  fail "gh 未認証時の SKIP メッセージなし: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 5"
rm -rf "$TMP5" || true

# ── ケース 6: claude_action.enabled: true + secrets 登録あり → log_info ──
TMP6=$(mktemp -d)
write_yml "$TMP6" "name: test
preset: full
claude_action:
  enabled: true"
OUT=$(run_verify "$TMP6" registered)
if echo "$OUT" | grep -q "CLAUDE_CODE_OAUTH_TOKEN が登録されています"; then
  pass "secrets 登録ありで INFO メッセージが出力される"
else
  fail "secrets 登録ありの INFO メッセージなし: ${OUT}"
fi
if echo "$OUT" | grep -q "WARN"; then
  fail "secrets 登録ありにも関わらず WARN が出力されている: ${OUT}"
else
  pass "secrets 登録ありで WARN が出力されない"
fi
assert_run_verify_rc_zero "ケース 6"
rm -rf "$TMP6" || true

# ── ケース 7: claude_action.enabled: true + secrets 未登録 → log_warn ──
TMP7=$(mktemp -d)
write_yml "$TMP7" "name: test
preset: full
claude_action:
  enabled: true"
OUT=$(run_verify "$TMP7" unregistered)
if echo "$OUT" | grep -q "CLAUDE_CODE_OAUTH_TOKEN が登録されていません"; then
  pass "secrets 未登録で WARN メッセージが出力される"
else
  fail "secrets 未登録の WARN メッセージなし: ${OUT}"
fi
if echo "$OUT" | grep -q "claude setup-token"; then
  pass "WARN 本文に claude setup-token の案内が含まれる"
else
  fail "WARN 本文に claude setup-token の案内が含まれない: ${OUT}"
fi
if echo "$OUT" | grep -q "docs/ai-review-auth.md"; then
  pass "WARN 本文に docs/ai-review-auth.md への参照が含まれる"
else
  fail "WARN 本文に docs/ai-review-auth.md への参照がない: ${OUT}"
fi
# 重要: 未登録時も WARN を出すだけで exit 0 を維持することを明示検証
# （docs/ai-review-auth.md §5「警告のみで install.sh は失敗扱いにしない」）
assert_run_verify_rc_zero "ケース 7"
rm -rf "$TMP7" || true

# ── ケース 8: 別のセクションの enabled キーが誤ってマッチしない ──
TMP8=$(mktemp -d)
write_yml "$TMP8" "name: test
preset: full
diagnose:
  enabled: true
claude_action:
  enabled: false"
OUT=$(run_verify "$TMP8" missing)
if [[ -z "$OUT" ]]; then
  pass "他セクションの enabled: true が claude_action にリークしない"
else
  fail "セクション境界が壊れて誤判定: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 8"
rm -rf "$TMP8" || true

# ── ケース 9: 部分一致するシークレット名が誤マッチしない ──
TMP9=$(mktemp -d)
write_yml "$TMP9" "name: test
preset: full
claude_action:
  enabled: true"
# CLAUDE_CODE_OAUTH_TOKEN_BACKUP を返すモックを直接書く
MOCK_BIN_DIR="$(mktemp -d)"
cat > "${MOCK_BIN_DIR}/gh" <<'GHSH'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
esac
case "$1" in
  secret)
    if [[ "$2" == "list" ]]; then
      printf 'CLAUDE_CODE_OAUTH_TOKEN_BACKUP\t2026-01-01T00:00:00Z\n'
      exit 0
    fi
    ;;
esac
exit 0
GHSH
chmod +x "${MOCK_BIN_DIR}/gh"
saved_repo_root="${REPO_ROOT:-}"
REPO_ROOT="$TMP9"
set +e
OUT=$(PATH="${MOCK_BIN_DIR}:${PATH}" verify_claude_action_secrets 2>&1 >/dev/null)
RUN_VERIFY_RC=$?
set -e
REPO_ROOT="$saved_repo_root"
rm -rf "$MOCK_BIN_DIR" || true
MOCK_BIN_DIR=""
if echo "$OUT" | grep -q "CLAUDE_CODE_OAUTH_TOKEN が登録されていません"; then
  pass "部分一致するシークレット名（_BACKUP）が誤マッチしない"
else
  fail "部分一致するシークレット名で誤マッチ発生: ${OUT}"
fi
assert_run_verify_rc_zero "ケース 9"
rm -rf "$TMP9" || true

# ── ケース 10: log_warn 関数が定義されている ──
if declare -F log_warn >/dev/null 2>&1; then
  pass "log_warn 関数が定義されている"
else
  fail "log_warn 関数が定義されていない"
fi

print_test_summary
