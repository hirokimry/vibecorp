#!/usr/bin/env bash
# test.yml「bwrap 動作確認」ステップ用スクリプト
# bwrap install 直後に試し実行で user namespace の可用性を確認する。
# GitHub Actions の ubuntu-latest（Ubuntu 24.04）は AppArmor 4.0 の
# unprivileged_userns 制限により bwrap が起動できない（既知制約）。
# この場合 test_isolation_linux.sh / test_isolation_parity.sh は自身の
# 試し実行で skip するため、ここでは fail せずに警告のみ出して継続する。
# 自前ホスト等で bwrap 起動可能な環境では試し実行が成功し、隔離テストが
# 実機検証として走る。
set -euo pipefail

bwrap --version
if bwrap --unshare-pid --proc /proc --dev /dev --tmpfs /tmp -- /bin/sh -c :; then
  echo "bwrap 試し実行 OK: 隔離テストが実機検証として走ります。"
else
  echo "::warning::bwrap が user namespace 隔離を実行できません（GitHub Actions ubuntu-24.04 では既知制約）。"
  echo "::warning::  kernel.unprivileged_userns_clone / AppArmor プロファイルが制限している可能性があります。"
  echo "::warning::  test_isolation_linux.sh / test_isolation_parity.sh は自動 skip されます。実機検証は別途必要。"
fi
