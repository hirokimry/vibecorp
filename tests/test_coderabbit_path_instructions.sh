#!/bin/bash
# test_coderabbit_path_instructions.sh — Issue #757: .coderabbit.yaml の path_instructions の
# 参照先パスが repo 内に実在することを検証する（stale path の再発防止）。
# 使い方: bash tests/test_coderabbit_path_instructions.sh
# CI: GitHub Actions で自動実行
#
# 背景: plugin native 移行（#700 / #358）で hooks/skills が repo root へ移動した後も
# `.coderabbit.yaml` の path_instructions に旧パス（templates/claude/hooks 等）が残り、
# シェル/スキル観点が二度と発火しなくなった（#757）。本テストは path_instructions の
# 各 path のベースディレクトリが実在することを確認し、再 stale 化を機械的に検知する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODERABBIT_YAML="${ROOT}/.coderabbit.yaml"

# 前提ファイル不在は後続テストを無意味にするため即終了する（testing.md 準拠）。
if [[ -f "$CODERABBIT_YAML" ]]; then
  pass ".coderabbit.yaml が存在する"
else
  fail ".coderabbit.yaml が存在しない"
  exit 1
fi

# ============================================
echo "=== path_instructions の path がベースディレクトリ実在を満たす ==="
# ============================================

# path_instructions の各エントリは `- path: "<glob>"` 形式。
# awk -F'"' で最初のダブルクォート間の値を抜き出す（path_filters の `- "!..."` は path: を持たないため対象外）。
paths=$(awk -F'"' '/^[[:space:]]*- path:/ {print $2}' "$CODERABBIT_YAML")

if [[ -z "$paths" ]]; then
  fail "path_instructions の path エントリを 1 つも抽出できなかった（書式変更 or パース失敗）"
  exit 1
fi

checked=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  checked=$((checked + 1))

  # "**" 単独は repo ルート全体を指すため常に有効（実在判定の対象外）。
  if [[ "$p" == "**" ]]; then
    pass "path \"**\"（repo ルート）は常に有効"
    continue
  fi

  # glob 末尾（/** や /*）と末尾スラッシュを剥がしてベースディレクトリを得る。
  base="${p%/\*\*}"   # hooks/** → hooks
  base="${base%/\*}"  # foo/*    → foo
  base="${base%/}"    # 末尾スラッシュ除去

  if [[ -e "${ROOT}/${base}" ]]; then
    pass "path_instructions \"${p}\" の参照先 \"${base}\" は実在する"
  else
    fail "path_instructions \"${p}\" の参照先 \"${base}\" が実在しない（stale path・Issue #757 再発）"
  fi
done <<<"$paths"

if [[ "$checked" -eq 0 ]]; then
  fail "path エントリを 1 件も検査しなかった"
  exit 1
fi

print_test_summary
