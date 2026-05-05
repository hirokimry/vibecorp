#!/bin/bash
# backfill-intent-labels.sh — 既存 open Issue に intent/* ラベルを遡及付与する一括棚卸しスクリプト
#
# Issue #469 残 #4「既存 Issue 遡及付与: open のみ一括棚卸し」の実装
#
# 動作:
#   1. open な Issue のうち、intent/* ラベルが付いていないものを列挙
#   2. 各 Issue のタイトル・本文を表示
#   3. 利用者に intent ラベル（7 種）を選ばせる
#   4. 選択したラベルを付与
#
# closed Issue は触らない（議論結論「open のみ」に準拠）。
# 1 Issue ずつ確認しながら進めるため、--dry-run で対象一覧だけ表示することも可能。

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLI が必要です" >&2
  exit 1
fi

if ! gh repo view >/dev/null 2>&1; then
  echo "エラー: GitHub リポジトリに接続されていません" >&2
  exit 1
fi

INTENT_LABELS=(
  "intent/feature"
  "intent/bugfix"
  "intent/performance"
  "intent/security"
  "intent/refactor"
  "intent/infra"
  "intent/docs"
)

echo "=== 既存 open Issue intent ラベル遡及付与 ==="
echo ""

# intent/* が付いていない open Issue を列挙
issues_json=$(gh issue list --state open --limit 500 --json number,title,labels)
target_count=$(echo "$issues_json" | jq '[.[] | select([.labels[].name | startswith("intent/")] | any | not)] | length')

if [[ "$target_count" -eq 0 ]]; then
  echo "intent/* ラベル不在の open Issue はありません。"
  exit 0
fi

echo "intent/* ラベル不在の open Issue: ${target_count} 件"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "--- 対象 Issue 一覧（--dry-run） ---"
  echo "$issues_json" | jq -r '.[] | select([.labels[].name | startswith("intent/")] | any | not) | "#\(.number): \(.title)"'
  exit 0
fi

# 1 件ずつ処理
# プロセス置換 < <(...) を使うことで while ループが pipe の subshell ではなく現シェルで走る。
# pipe で while を回すと内部の `read -r choice` が pipe の次行（次の Issue データ）を奪ってしまい、
# 対話入力にならないため必ずプロセス置換を使う。
while IFS= read -r issue; do
  num=$(echo "$issue" | jq -r '.number')
  title=$(echo "$issue" | jq -r '.title')

  echo "--- Issue #${num} ---"
  echo "タイトル: ${title}"
  echo ""
  echo "本文:"
  gh issue view "$num" --json body --jq '.body' | head -20
  echo ""
  echo "intent ラベル候補:"
  for i in "${!INTENT_LABELS[@]}"; do
    echo "  $((i+1))) ${INTENT_LABELS[$i]}"
  done
  echo "  s) スキップ"
  echo "  q) 終了"
  printf "選択: "
  # /dev/tty から直接読み取り。pipe / プロセス置換が stdin を奪っても確実にユーザー入力を読む
  read -r choice < /dev/tty

  case "$choice" in
    [1-7])
      label="${INTENT_LABELS[$((choice-1))]}"
      gh issue edit "$num" --add-label "$label"
      echo "✅ #${num} に '${label}' を付与"
      ;;
    s|S)
      echo "⏭ #${num} をスキップ"
      ;;
    q|Q)
      echo "終了"
      break
      ;;
    *)
      echo "無効な選択。スキップします。"
      ;;
  esac
  echo ""
done < <(echo "$issues_json" | jq -c '.[] | select([.labels[].name | startswith("intent/")] | any | not)')

echo "=== 完了 ==="
