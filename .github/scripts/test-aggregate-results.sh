#!/usr/bin/env bash
# test.yml「全ジョブの結果を確認」ステップ用スクリプト（集約ジョブ）
# Branch Protection の required check として機能する。
#
# 結果の扱い（実装と一致）:
#   - success: 通常完了（pass）
#   - skipped: event 条件で matrix が未実行（pass。例: PR では macOS が skip される）
#   - cancelled: 異常終了として fail 扱い（exit 1）
#     * 補足: concurrency.cancel-in-progress: true で前 run が cancel された場合は、
#       後続 run が新たに評価されるため required check 上は問題にならない
#       （required check は最新 run の結論を見る）。本ジョブは「現在 run 内の親ジョブが
#       cancelled になったら fail」とだけ判定すれば良く、cancel 経路の区別は不要
#   - failure / その他: fail（exit 1）
#
# 環境変数:
#   UBUNTU_RESULT: ${{ needs.test-ubuntu.result }}
#   MACOS_RESULT:  ${{ needs.test-macos.result }}
set -euo pipefail

# shellcheck disable=SC2153  # UBUNTU_RESULT / MACOS_RESULT は workflow 側 env: で渡される
ubuntu_result="${UBUNTU_RESULT}"
# shellcheck disable=SC2153  # workflow 側 env: で渡される（上記コメント参照）
macos_result="${MACOS_RESULT}"
echo "test-ubuntu: $ubuntu_result"
echo "test-macos: $macos_result"
for r in "$ubuntu_result" "$macos_result"; do
  case "$r" in
    success|skipped)
      # success: 全シャードが pass / skipped: event 条件で未実行 → 集約は pass
      ;;
    cancelled)
      # cancel-in-progress 由来の cancel は新 run に置き換わるため
      # required check 上は問題にならない。それ以外で cancelled に
      # なるのは異常終了として扱う。
      echo "ジョブがキャンセルされました（cancel-in-progress 由来でない場合は異常終了として fail 扱いします）"
      exit 1
      ;;
    *)
      echo "ジョブが失敗しました（result=${r}）"
      exit 1
      ;;
  esac
done
exit 0
