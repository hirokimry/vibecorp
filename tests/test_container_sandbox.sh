#!/bin/bash
# test_container_sandbox.sh — docker/claude-sandbox/ の統合テスト
# 使い方: bash tests/test_container_sandbox.sh
# CI: GitHub Actions（ubuntu-latest のみ実行、macOS では skip）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker/claude-sandbox"
SECCOMP_PATH="${DOCKER_DIR}/seccomp.json"
IMAGE_TAG="vibecorp/claude-sandbox:test-$$"

# 本イメージは entrypoint.sh が root 権限で iptables を設定し setpriv で UID 1000 に降格する構成のため
# 最低限 NET_ADMIN / SETUID / SETGID を付与する必要がある
CAPS_ARGS=(--cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID)

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

# --- Docker 未導入時は skip（macOS CI runner 等） ---

if ! command -v docker >/dev/null; then
    echo "SKIP: docker コマンドが見つからないためテストをスキップします"
    exit 0
fi

if ! docker info >/dev/null; then
    echo "SKIP: docker daemon が起動していないためテストをスキップします"
    exit 0
fi

# --- クリーンアップ ---

cleanup() {
    # 終了コードに影響を与えないようサブシェルで隔離
    (
        set +e
        docker rmi -f "$IMAGE_TAG" >/dev/null 2>&1
    )
}
trap cleanup EXIT

# ============================================
echo "=== docker-sandbox ビルド検証 ==="
# ============================================

# ケース 1: ビルドが成功し 5 分以内に完了する
echo "--- ビルド開始（5 分以内が受け入れ基準）---"
BUILD_START=$(date +%s)
if timeout 300 docker build -t "$IMAGE_TAG" "$DOCKER_DIR"; then
    BUILD_END=$(date +%s)
    BUILD_DURATION=$((BUILD_END - BUILD_START))
    pass "ビルドが 300 秒以内に完了 (${BUILD_DURATION}s)"
else
    fail "docker build が失敗"
    echo ""
    echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
    exit 1
fi

# ============================================
echo ""
echo "=== 起動検証 ==="
# ============================================

# ケース 2: claude --version が正常終了する
if docker run --rm "${CAPS_ARGS[@]}" "$IMAGE_TAG" claude --version >/dev/null; then
    pass "claude --version が正常終了"
else
    fail "claude --version が失敗"
fi

# ============================================
echo ""
echo "=== non-root 降格検証 ==="
# ============================================

# ケース 3: id -un が claude を返す
UN=$(docker run --rm --read-only --tmpfs /tmp --tmpfs /state --tmpfs /home/claude/.cache \
    "${CAPS_ARGS[@]}" \
    "$IMAGE_TAG" id -un)
if [ "$UN" = "claude" ]; then
    pass "降格後のユーザーが claude"
else
    fail "降格後のユーザーが claude でない (実際: $UN)"
fi

# ============================================
echo ""
echo "=== read-only rootfs 検証 ==="
# ============================================

# ケース 4: rootfs への書き込みが失敗する
if docker run --rm --read-only --tmpfs /tmp --tmpfs /state --tmpfs /home/claude/.cache \
    "${CAPS_ARGS[@]}" \
    "$IMAGE_TAG" sh -c 'touch /etc/test-ro' >/dev/null 2>&1; then
    fail "read-only rootfs なのに /etc/test-ro に書き込めた"
else
    pass "read-only rootfs で /etc への書き込みが失敗"
fi

# ============================================
echo ""
echo "=== egress allowlist 検証 ==="
# ============================================

# ケース 5: 許可外ホストへの接続が失敗する
if docker run --rm --read-only --tmpfs /tmp --tmpfs /state --tmpfs /home/claude/.cache \
    "${CAPS_ARGS[@]}" \
    "$IMAGE_TAG" sh -c 'curl -fsS --max-time 5 https://example.com' >/dev/null 2>&1; then
    fail "example.com への接続が遮断されていない"
else
    pass "example.com への接続が遮断されている"
fi

# ケース 6: allowlist ホストの DNS 解決が成功する
if docker run --rm --read-only --tmpfs /tmp --tmpfs /state --tmpfs /home/claude/.cache \
    "${CAPS_ARGS[@]}" \
    "$IMAGE_TAG" sh -c 'getent hosts api.anthropic.com' >/dev/null 2>&1; then
    pass "api.anthropic.com の DNS 解決が成功"
else
    fail "api.anthropic.com の DNS 解決が失敗"
fi

# ============================================
echo ""
echo "=== seccomp プロファイル検証 ==="
# ============================================

# ケース 7a: seccomp.json が JSON として妥当
if jq empty "$SECCOMP_PATH" >/dev/null; then
    pass "seccomp.json が妥当な JSON"
else
    fail "seccomp.json が妥当な JSON でない"
fi

# ケース 7b: seccomp プロファイルを適用して起動できる
if docker run --rm --security-opt "seccomp=${SECCOMP_PATH}" \
    "${CAPS_ARGS[@]}" \
    "$IMAGE_TAG" claude --version >/dev/null; then
    pass "seccomp プロファイル適用で claude --version が成功"
else
    fail "seccomp プロファイル適用で claude --version が失敗"
fi

# ============================================
echo ""
echo "=== resource limit 検証 ==="
# ============================================

# ケース 8: --memory / --cpus / --pids-limit が docker inspect で反映されている
LIMITS_NAME="vibecorp-sandbox-limits-$$"
docker run -d --rm \
    --memory 2g --cpus 2 --pids-limit 512 \
    "${CAPS_ARGS[@]}" \
    --name "$LIMITS_NAME" \
    "$IMAGE_TAG" sleep 30 >/dev/null

# インスペクトして memory / pids-limit / nanocpus を取得
INSPECT=$(docker inspect "$LIMITS_NAME" --format '{{.HostConfig.Memory}} {{.HostConfig.PidsLimit}} {{.HostConfig.NanoCpus}}')
EXPECTED_MEM=$((2 * 1024 * 1024 * 1024))
EXPECTED_CPUS_NANO=$((2 * 1000000000))

# クリーンアップ
docker stop "$LIMITS_NAME" >/dev/null

if [ "$INSPECT" = "${EXPECTED_MEM} 512 ${EXPECTED_CPUS_NANO}" ]; then
    pass "resource limit が期待値と一致 (${INSPECT})"
else
    fail "resource limit が期待値と不一致 (実際: ${INSPECT}, 期待: ${EXPECTED_MEM} 512 ${EXPECTED_CPUS_NANO})"
fi

# ============================================
echo ""
echo "=== secret 注入方式の検証 ==="
# ============================================

# ケース 10: -e ANTHROPIC_API_KEY=... で起動するとエラーで拒否される
TOTAL=$((TOTAL + 1))
if docker run --rm "${CAPS_ARGS[@]}" -e ANTHROPIC_API_KEY="test-key" "$IMAGE_TAG" echo "should not reach" 2>&1 | grep -q "env で注入されています"; then
    pass "-e ANTHROPIC_API_KEY が拒否される"
else
    fail "-e ANTHROPIC_API_KEY が拒否されなかった"
fi

# ケース 11: -e GH_TOKEN=... で起動するとエラーで拒否される
TOTAL=$((TOTAL + 1))
if docker run --rm "${CAPS_ARGS[@]}" -e GH_TOKEN="test-token" "$IMAGE_TAG" echo "should not reach" 2>&1 | grep -q "env で注入されています"; then
    pass "-e GH_TOKEN が拒否される"
else
    fail "-e GH_TOKEN が拒否されなかった"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
