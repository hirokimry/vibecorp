#!/usr/bin/env bash
# test.yml「.github/scripts/ を shellcheck で検証」ステップ用スクリプト。
# .github/scripts/ 配下の *.sh を全件 shellcheck にかけて構文・スタイル違反を検出する。
# Issue #625: workflow から切り出したシェルスクリプトの静的解析を CI に組み込む。
#
# 自分自身（run-shellcheck.sh）も対象に含めるため、find -name '*.sh' で網羅する。
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

mapfile -t targets < <(find "$SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f | sort)

if [ "${#targets[@]}" -eq 0 ]; then
  echo "::warning::shellcheck 対象スクリプトが見つかりませんでした: $SCRIPTS_DIR"
  exit 0
fi

echo "shellcheck 対象: ${#targets[@]} スクリプト"
for f in "${targets[@]}"; do
  echo "  - ${f#"$SCRIPTS_DIR/"}"
done
echo ""

shellcheck --severity=warning "${targets[@]}"
echo ""
echo "shellcheck: 全 ${#targets[@]} スクリプトが warning 以上の指摘なしで通過しました"
