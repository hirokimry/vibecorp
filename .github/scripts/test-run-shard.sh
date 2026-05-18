#!/usr/bin/env bash
# test.yml「シャード別テスト実行」ステップ用スクリプト
# Issue #340: test_install.sh を 4 シャード + other に分割して matrix 並列実行
# ubuntu / macos の両ジョブから同一スクリプトとして呼ばれる（同一 workflow 内のため共有）
# 環境変数: SHARD（args / preset / lock / update / other のいずれか）
set -euo pipefail

case "$SHARD" in
  args|preset|lock|update)
    bash "tests/test_install_${SHARD}.sh"
    ;;
  other)
    # 4 新規シャード以外の全 test_*.sh を実行（既存 test_install_claude_real.sh
    # / test_install_isolation.sh / test_install_orphan_hook.sh を含む）
    shopt -s nullglob
    files=(tests/test_*.sh)
    if [ ${#files[@]} -eq 0 ]; then
      echo "テストファイルが見つかりません"
      exit 1
    fi
    failed=0
    for f in "${files[@]}"; do
      base="${f##*/}"
      case "$base" in
        test_install_args.sh|test_install_preset.sh|test_install_lock.sh|test_install_update.sh)
          continue
          ;;
      esac
      echo "=== $f ==="
      bash "$f" || failed=1
    done
    exit "$failed"
    ;;
  *)
    echo "未知の shard 値: $SHARD"
    exit 1
    ;;
esac
