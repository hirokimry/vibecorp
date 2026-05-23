#!/bin/bash
# hook_fixtures.sh — hook テスト時の lib 配置を runtime 状態に近づけるための補助
# Issue #701: lib/ を plugin ルートに移動した後、templates/claude/hooks/ 内 hook が
# 参照する ${HOOK_DIR}/../lib/ パスを runtime（.claude/hooks → .claude/lib）と同じく
# テスト時にも引けるように、テスト中だけ templates/claude/lib/ に lib をコピーする
#
# 使い方:
#   TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck disable=SC1091
#   source "${TESTS_DIR}/lib/hook_fixtures.sh"
#   sync_lib_for_hook_tests   # テスト本体の前に 1 回呼ぶ
#
# 制約:
#   - 既存の trap cleanup EXIT を阻害しない（自前の trap は登録しない）
#   - 呼び出し側の set -euo pipefail を変更しない
#   - templates/claude/lib/ に追加したファイルはテスト終了後に untracked として
#     残る。CI では runner ごと破棄されるため問題なし。ローカルでは
#     `git clean -df templates/claude/lib/` で消すか、エピック #700 完了後の
#     子 Issue #708 で templates/claude/lib/ 自体が削除されるまでの暫定対応。
#
# 機能: templates/claude/lib/ に lib/*.sh をコピーする
# WHY: hook 内の `${HOOK_DIR}/../lib/...` 参照が templates/claude/lib/ を見るため
sync_lib_for_hook_tests() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local plugin_lib="${repo_root}/lib"
  local templates_lib="${repo_root}/templates/claude/lib"

  if [[ ! -d "$plugin_lib" ]]; then
    return 0
  fi
  mkdir -p "$templates_lib"
  local src
  for src in "${plugin_lib}/"*.sh; do
    [[ -f "$src" ]] || continue
    cp "$src" "${templates_lib}/$(basename "$src")"
  done
}
