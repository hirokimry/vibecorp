#!/bin/bash
# hook_fixtures.sh — hook テスト用補助関数
# Issue #707 (plugin native 配布) 以降、hook は plugin ルート hooks/ に配置され、
# 同じく plugin ルートの lib/ を ${HOOK_DIR}/../lib/ で参照するため、テスト時に
# lib を別途 staging する必要はなくなった。
#
# 過去の sync_lib_for_hook_tests は lib/ に lib を staging していたが、
# hooks/ が消えた今は不要のため no-op として維持する（既存テストの
# 後方互換のため呼び出しシグネチャは残す）。

# 機能: 後方互換のため残す no-op 関数（Issue #707 以降は不要）
sync_lib_for_hook_tests() {
  return 0
}
