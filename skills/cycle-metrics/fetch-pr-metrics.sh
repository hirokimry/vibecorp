#!/bin/bash
# fetch-pr-metrics.sh — マージ済み PR のタイミング情報を gh API から収集する
#
# 出力: stdout に JSON 配列。各要素は以下のフィールドを持つ。
#   number, issue_number, title, head_ref, base_ref,
#   created_at, merged_at,
#   total_seconds, first_review_seconds, ci_seconds,
#   additions, deletions, commit_count
#
# 使い方:
#   bash skills/cycle-metrics/fetch-pr-metrics.sh [--limit N] [--base BRANCH]
#   bash skills/cycle-metrics/fetch-pr-metrics.sh --from-fixture path/to/fixture.json
#
# 制約:
#   - LLM を呼ばない（claude -p / npx / bunx 不使用）
#   - date -d を使わない（jq 'fromdateiso8601' で BSD/GNU 両対応）
#   - jq の string interpolation \(...) を使わない（+ で結合）

set -euo pipefail

LIMIT=20
BASE_BRANCH="main"
FIXTURE=""

usage() {
  cat <<'USAGE'
Usage: fetch-pr-metrics.sh [--limit N] [--base BRANCH] [--from-fixture PATH]

Options:
  --limit N         取得する PR 件数の上限（デフォルト: 20）
  --base BRANCH     対象のベースブランチ（デフォルト: main）
  --from-fixture P  gh CLI を呼ばず、指定 JSON をそのまま入力として使う（テスト用）
  -h, --help        このヘルプを表示

出力: stdout に PR ごとの集計を JSON 配列で出力する。
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --from-fixture) FIXTURE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# gh が無く fixture も指定されていない場合は明確にエラーにする
if [ -z "$FIXTURE" ] && ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI が見つかりません。--from-fixture を使うか gh をインストールしてください" >&2
  exit 3
fi

# PR 一覧を JSON で取得（または fixture を読む）
if [ -n "$FIXTURE" ]; then
  if [ ! -f "$FIXTURE" ]; then
    echo "fixture ファイルが見つかりません: ${FIXTURE}" >&2
    exit 4
  fi
  RAW_JSON=$(cat "$FIXTURE")
else
  RAW_JSON=$(gh pr list \
    --state merged \
    --base "$BASE_BRANCH" \
    --limit "$LIMIT" \
    --json number,title,headRefName,baseRefName,createdAt,mergedAt,additions,deletions,commits,reviews,statusCheckRollup)
fi

# jq でメトリクスを計算する
# - total_seconds: mergedAt - createdAt
# - first_review_seconds: 最初の reviews[].submittedAt - createdAt
# - ci_seconds: statusCheckRollup の最後の completedAt - 最初の startedAt
# - issue_number: headRefName から `dev/{番号}_*` パターンで抽出
echo "$RAW_JSON" | jq '
  def to_epoch:
    if . == null then null else fromdateiso8601 end;

  def first_review_epoch:
    [ .reviews[]?.submittedAt | to_epoch ]
    | map(select(. != null))
    | sort
    | (.[0] // null);

  def ci_first_started:
    [ .statusCheckRollup[]?.startedAt | to_epoch ]
    | map(select(. != null))
    | sort
    | (.[0] // null);

  def ci_last_completed:
    [ .statusCheckRollup[]?.completedAt | to_epoch ]
    | map(select(. != null))
    | sort
    | reverse
    | (.[0] // null);

  def issue_num:
    if (.headRefName | test("^dev/[0-9]+_"))
    then (.headRefName | capture("^dev/(?<n>[0-9]+)_") | .n | tonumber)
    else null
    end;

  map({
    number: .number,
    issue_number: issue_num,
    title: .title,
    head_ref: .headRefName,
    base_ref: .baseRefName,
    created_at: .createdAt,
    merged_at: .mergedAt,
    total_seconds: (
      if (.createdAt|to_epoch) and (.mergedAt|to_epoch)
      then (.mergedAt|to_epoch) - (.createdAt|to_epoch)
      else null
      end
    ),
    first_review_seconds: (
      (first_review_epoch) as $r
      | (.createdAt|to_epoch) as $c
      | if $r and $c then ($r - $c) else null end
    ),
    ci_seconds: (
      (ci_first_started) as $s
      | (ci_last_completed) as $e
      | if $s and $e then ($e - $s) else null end
    ),
    additions: (.additions // 0),
    deletions: (.deletions // 0),
    commit_count: ((.commits // []) | length)
  })
'
