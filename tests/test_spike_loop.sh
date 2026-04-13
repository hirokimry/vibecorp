#!/bin/bash
# test_spike_loop.sh — spike-loop スキルのテスト
# 使い方: bash tests/test_spike_loop.sh

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
TEMPLATE_FILE="$PROJECT_DIR/templates/claude/skills/spike-loop/SKILL.md"
LOCAL_FILE="$PROJECT_DIR/.claude/skills/spike-loop/SKILL.md"
# テンプレートを正とする（.claude/skills/ は gitignored で CI に存在しない場合がある）
SKILL_FILE="$TEMPLATE_FILE"

echo "=== spike-loop スキル テスト ==="

# --- テスト1: SKILL.md の存在 ---

echo ""
echo "--- テスト1: SKILL.md の存在 ---"

if [[ -f "$SKILL_FILE" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  echo ""
  echo "==========================="
  echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
  echo "==========================="
  exit 1
fi

# --- テスト2: frontmatter の検証 ---

echo ""
echo "--- テスト2: frontmatter の検証 ---"

if head -1 "$SKILL_FILE" | grep -q '^---$'; then
  pass "frontmatter 開始区切りが存在する"
else
  fail "frontmatter 開始区切りが存在しない"
fi

if grep -q "^name: spike-loop$" "$SKILL_FILE"; then
  pass "name フィールドが 'spike-loop' である"
else
  fail "name フィールドが 'spike-loop' でない"
fi

if grep -q '^description:' "$SKILL_FILE"; then
  pass "description フィールドが存在する"
else
  fail "description フィールドが存在しない"
fi

# --- テスト3: 必須セクションの存在 ---

echo ""
echo "--- テスト3: 必須セクションの存在 ---"

if grep -q '## 使用方法' "$SKILL_FILE"; then
  pass "使用方法セクションが存在する"
else
  fail "使用方法セクションが存在しない"
fi

if grep -q '## ワークフロー\|## フロー' "$SKILL_FILE"; then
  pass "ワークフローセクションが存在する"
else
  fail "ワークフローセクションが存在しない"
fi

# --- テスト4: コア機能の検証 ---

echo ""
echo "--- テスト4: コア機能の検証 ---"

# 4-1: ヘッドレス Claude 起動に claude -p を使用
if grep -q 'claude.*-p\|claude.*--print' "$SKILL_FILE"; then
  pass "ヘッドレス Claude 起動に claude -p を使用している"
else
  fail "ヘッドレス Claude 起動に claude -p を使用していない"
fi

# 4-2: permission-mode dontAsk の指定
if grep -q 'permission-mode.*dontAsk\|dontAsk' "$SKILL_FILE"; then
  pass "permission-mode dontAsk の指定がある"
else
  fail "permission-mode dontAsk の指定がない"
fi

# 4-3: stuck 判定ロジックへの言及
if grep -q 'stuck' "$SKILL_FILE"; then
  pass "stuck 判定への言及がある"
else
  fail "stuck 判定への言及がない"
fi

# 4-4: docker logs --since を使用した stuck 監視
if grep -q 'docker logs --since' "$SKILL_FILE"; then
  pass "docker logs --since を使用した監視への言及がある"
else
  fail "docker logs --since を使用した監視への言及がない"
fi

# 4-5: 成功判定（PR 作成の確認）
if grep -q 'gh pr\|PR.*作成\|成功判定' "$SKILL_FILE"; then
  pass "成功判定（PR 確認）への言及がある"
else
  fail "成功判定（PR 確認）への言及がない"
fi

# 4-6: docker stop による強制停止への言及
if grep -q 'docker stop' "$SKILL_FILE"; then
  pass "docker stop による強制停止への言及がある"
else
  fail "docker stop による強制停止への言及がない"
fi

# 4-7: findings の保存
if grep -q 'findings\|スナップショット\|snapshot' "$SKILL_FILE"; then
  pass "findings/スナップショット保存への言及がある"
else
  fail "findings/スナップショット保存への言及がない"
fi

# 4-8: 最大ループ回数の制限
if grep -q 'max.*run\|最大.*回\|ループ.*上限' "$SKILL_FILE"; then
  pass "最大ループ回数の制限がある"
else
  fail "最大ループ回数の制限がない"
fi

# --- テスト5: コードブロックの言語指定 ---

echo ""
echo "--- テスト5: コードブロックの言語指定 ---"

BARE_OPEN_COUNT=$(awk '
  /^```/ {
    if (in_block) {
      in_block = 0
    } else {
      in_block = 1
      if ($0 == "```") bare++
    }
  }
  END { print bare+0 }
' "$SKILL_FILE")
if [[ "$BARE_OPEN_COUNT" -eq 0 ]]; then
  pass "全てのコードブロックに言語指定がある"
else
  fail "言語指定なしのコードブロックが ${BARE_OPEN_COUNT} 箇所ある"
fi

# --- テスト6: テンプレートとローカルの一致 ---

echo ""
echo "--- テスト6: テンプレートとローカルの一致 ---"

if [[ -f "$TEMPLATE_FILE" ]]; then
  pass "テンプレートファイルが存在する"
else
  fail "テンプレートファイルが存在しない"
fi

if [[ -f "$LOCAL_FILE" ]]; then
  if diff -q "$TEMPLATE_FILE" "$LOCAL_FILE" > /dev/null 2>&1; then
    pass "ローカルとテンプレートが一致する"
  else
    fail "ローカルとテンプレートが一致しない"
  fi
else
  pass "ローカルファイルが存在しない（CI 環境では正常）"
fi

# --- テスト7: コンテナモード検証 ---

echo ""
echo "--- テスト7: コンテナモード検証 ---"

# 7-1: docker run による起動
if grep -q 'docker run' "$SKILL_FILE"; then
  pass "docker run による起動への言及がある"
else
  fail "docker run による起動への言及がない"
fi

# 7-2: vibecorp/claude-sandbox:dev イメージの使用
if grep -q 'vibecorp/claude-sandbox:dev' "$SKILL_FILE"; then
  pass "vibecorp/claude-sandbox:dev イメージへの言及がある"
else
  fail "vibecorp/claude-sandbox:dev イメージへの言及がない"
fi

# 7-3: /state/run bind mount の記載
if grep -q '/state/run' "$SKILL_FILE"; then
  pass "/state/run bind mount への言及がある"
else
  fail "/state/run bind mount への言及がない"
fi

# 7-4: SESSION_ID の記載
if grep -q 'SESSION_ID' "$SKILL_FILE"; then
  pass "SESSION_ID への言及がある"
else
  fail "SESSION_ID への言及がない"
fi

# 7-5: command-log への言及が削除されていること
if grep -q 'command-log' "$SKILL_FILE"; then
  fail "command-log への言及が残っている（コンテナモードでは不要）"
else
  pass "command-log への言及が削除されている"
fi

# 7-6: kill <PID> への言及が削除されていること
if grep -q 'kill <PID>' "$SKILL_FILE"; then
  fail "kill <PID> への言及が残っている（コンテナモードでは不要）"
else
  pass "kill <PID> への言及が削除されている"
fi

# 7-7: pgrep への言及が削除されていること
if grep -q 'pgrep' "$SKILL_FILE"; then
  fail "pgrep への言及が残っている（コンテナモードでは不要）"
else
  pass "pgrep への言及が削除されている"
fi

# ============================================
echo ""
echo "=== Docker 統合テスト ==="
# ============================================

# Docker 利用可能時のみ実行
DOCKER_AVAILABLE=true

if ! command -v docker >/dev/null; then
  echo "SKIP: docker コマンドが見つからないため統合テストをスキップします"
  DOCKER_AVAILABLE=false
fi

if [[ "$DOCKER_AVAILABLE" = true ]] && ! docker info >/dev/null 2>&1; then
  echo "SKIP: docker daemon が起動していないため統合テストをスキップします"
  DOCKER_AVAILABLE=false
fi

if [[ "$DOCKER_AVAILABLE" = true ]] && ! docker image inspect vibecorp/claude-sandbox:dev >/dev/null 2>&1; then
  echo "SKIP: vibecorp/claude-sandbox:dev イメージが未ビルドのため統合テストをスキップします"
  DOCKER_AVAILABLE=false
fi

if [[ "$DOCKER_AVAILABLE" = true ]]; then

  CAPS_ARGS=(--cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID)
  SPIKE_TEST_NAME="vibecorp-spike-loop-test-$$"
  SPIKE_TEST_RUN_DIR=$(mktemp -d)
  chmod 777 "$SPIKE_TEST_RUN_DIR"

  cleanup_spike_test() {
    (
      set +e
      docker rm -f "$SPIKE_TEST_NAME" >/dev/null 2>&1
      rm -rf "$SPIKE_TEST_RUN_DIR" >/dev/null 2>&1
    )
  }
  trap cleanup_spike_test EXIT

  # --- テスト8: コンテナライフサイクル検証 ---

  echo ""
  echo "--- テスト8: コンテナライフサイクル検証 ---"

  # 8-1: docker run -d で container が起動する
  if docker run -d --name "$SPIKE_TEST_NAME" --init --read-only \
      --tmpfs /tmp:rw,size=16m \
      --tmpfs /home/claude/.cache:rw,size=16m \
      --tmpfs /home/claude/.claude:rw,size=16m,uid=1000,gid=1000 \
      "${CAPS_ARGS[@]}" \
      -v "$SPIKE_TEST_RUN_DIR:/state/run:rw" \
      vibecorp/claude-sandbox:dev \
      sleep 30 >/dev/null; then
    pass "docker run -d で container が起動する"
  else
    fail "docker run -d で container が起動しない"
  fi

  # 8-2: docker logs --since=30s で行数カウントが取得できる
  if LINE_COUNT=$(docker logs --since=30s "$SPIKE_TEST_NAME" 2>/dev/null | wc -l) \
      && [[ "$LINE_COUNT" =~ ^[0-9]+$ ]]; then
    pass "docker logs --since=30s で行数カウントが取得できる (${LINE_COUNT}行)"
  else
    fail "docker logs --since=30s で行数カウントが取得できない"
  fi

  # 8-3: docker stop + docker rm で停止・削除できる
  if docker stop -t 1 "$SPIKE_TEST_NAME" >/dev/null && docker rm "$SPIKE_TEST_NAME" >/dev/null; then
    pass "docker stop + docker rm で停止・削除できる"
  else
    fail "docker stop + docker rm で停止・削除できない"
  fi

  # --- テスト9: セキュリティ境界検証 ---

  echo ""
  echo "--- テスト9: セキュリティ境界検証 ---"

  # 9-1: /state/run に書き込めること
  WRITE_OUTPUT=$(docker run --rm --read-only \
      --tmpfs /tmp:rw,size=16m \
      "${CAPS_ARGS[@]}" \
      -v "$SPIKE_TEST_RUN_DIR:/state/run:rw" \
      vibecorp/claude-sandbox:dev \
      sh -c 'echo ok > /state/run/write_test && cat /state/run/write_test') || true
  if [[ "$WRITE_OUTPUT" = "ok" ]]; then
    pass "/state/run への書き込みが成功する"
  else
    fail "/state/run への書き込みが失敗した (出力: $WRITE_OUTPUT)"
  fi

  # 9-2: /workspace への書き込みが失敗すること
  if docker run --rm --read-only \
      --tmpfs /tmp:rw,size=16m \
      "${CAPS_ARGS[@]}" \
      -v "$SPIKE_TEST_RUN_DIR:/state/run:rw" \
      vibecorp/claude-sandbox:dev \
      sh -c 'echo pwn > /workspace/leak.txt' >/dev/null 2>&1; then
    fail "read-only rootfs なのに /workspace/leak.txt に書き込めた"
  else
    pass "read-only rootfs で /workspace への書き込みが失敗する"
  fi

fi

# --- 結果出力 ---

echo ""
echo "==========================="
echo "結果: ${PASSED}/${TOTAL} 成功, ${FAILED} 失敗"
echo "==========================="

[[ $FAILED -eq 0 ]] || exit 1
