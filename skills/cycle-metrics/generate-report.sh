#!/bin/bash
# generate-report.sh — PR メトリクス JSON と Agent メトリクス JSON から Markdown レポートを生成する
#
# 使い方:
#   bash skills/cycle-metrics/generate-report.sh PR_JSON AGENT_JSON OUTPUT_MD
#
# 入力:
#   PR_JSON     fetch-pr-metrics.sh の出力
#   AGENT_JSON  fetch-agent-metrics.sh の出力
#   OUTPUT_MD   出力先 Markdown パス
#
# 制約:
#   - LLM を呼ばない（claude -p / npx / bunx 不使用）
#   - jq の string interpolation \(...) を使わない（+ で結合）

set -euo pipefail

if [ "$#" -lt 3 ]; then
  cat >&2 <<'USAGE'
Usage: generate-report.sh PR_JSON AGENT_JSON OUTPUT_MD

  PR_JSON     fetch-pr-metrics.sh の JSON 出力
  AGENT_JSON  fetch-agent-metrics.sh の JSON 出力
  OUTPUT_MD   出力先 Markdown パス
USAGE
  exit 2
fi

PR_JSON="$1"
AGENT_JSON="$2"
OUTPUT_MD="$3"

if [ ! -f "$PR_JSON" ]; then
  echo "PR_JSON が見つかりません: ${PR_JSON}" >&2
  exit 3
fi
if [ ! -f "$AGENT_JSON" ]; then
  echo "AGENT_JSON が見つかりません: ${AGENT_JSON}" >&2
  exit 3
fi

TODAY=$(date -u +%Y-%m-%d)

# PR サマリ統計を計算
PR_SUMMARY=$(jq '
  def avg: if length == 0 then 0 else (add / length) end;
  def median:
    if length == 0 then 0
    else sort | (if length % 2 == 1 then .[length/2|floor] else (.[length/2 - 1] + .[length/2]) / 2 end)
    end;
  def to_hours($s): if $s == null then null else ($s / 3600.0) end;

  {
    pr_count: length,
    total_seconds_avg: ([.[].total_seconds | select(. != null)] | avg),
    total_seconds_max: ([.[].total_seconds | select(. != null)] | (if length == 0 then 0 else max end)),
    total_seconds_median: ([.[].total_seconds | select(. != null)] | median),
    first_review_seconds_avg: ([.[].first_review_seconds | select(. != null)] | avg),
    ci_seconds_avg: ([.[].ci_seconds | select(. != null)] | avg),
    additions_total: ([.[].additions // 0] | add),
    deletions_total: ([.[].deletions // 0] | add)
  }
' "$PR_JSON")

# Agent サマリ統計を計算
AGENT_SUMMARY=$(jq '
  {
    branch_count: (.branches | length),
    total_input_tokens: ([.branches[].total_input_tokens // 0] | add),
    total_output_tokens: ([.branches[].total_output_tokens // 0] | add),
    total_cache_creation_tokens: ([.branches[].total_cache_creation_tokens // 0] | add),
    total_cache_read_tokens: ([.branches[].total_cache_read_tokens // 0] | add),
    total_sidechain_count: ([.branches[].sidechain_count // 0] | add),
    models_aggregated: (
      [.branches[].models // {} | to_entries[]?]
      | group_by(.key)
      | map({
          key: .[0].key,
          value: {
            input_tokens: ([.[].value.input_tokens // 0] | add),
            output_tokens: ([.[].value.output_tokens // 0] | add),
            cache_creation_tokens: ([.[].value.cache_creation_tokens // 0] | add),
            cache_read_tokens: ([.[].value.cache_read_tokens // 0] | add),
            message_count: ([.[].value.message_count // 0] | add)
          }
        })
      | from_entries
    ),
    subagent_types_aggregated: (
      [.branches[].subagent_types // {} | to_entries[]?]
      | group_by(.key)
      | map({key: .[0].key, value: ([.[].value // 0] | add)})
      | from_entries
    )
  }
' "$AGENT_JSON")

# PR テーブル行を生成（Markdown）
PR_ROWS=$(jq -r '
  def fmt_hours($s): if $s == null then "—" else (($s / 3600.0) * 100 | round / 100 | tostring) + "h" end;
  def fmt_int($n): if $n == null then "—" else ($n | tostring) end;

  ([
    .[] | [
      ("#" + (.number|tostring)),
      (if .issue_number == null then "—" else ("#" + (.issue_number|tostring)) end),
      (.title // ""),
      fmt_hours(.total_seconds),
      fmt_hours(.first_review_seconds),
      fmt_hours(.ci_seconds),
      fmt_int(.additions),
      fmt_int(.deletions)
    ] | @tsv
  ])[]
' "$PR_JSON")

# ブランチ別テーブル行を生成
BRANCH_ROWS=$(jq -r '
  def fmt_int($n): if $n == null then "0" else ($n | tostring) end;

  (.branches[] | [
    .branch,
    (if .issue_number == null then "—" else ("#" + (.issue_number|tostring)) end),
    fmt_int(.session_count),
    fmt_int(.total_input_tokens),
    fmt_int(.total_output_tokens),
    fmt_int(.total_cache_creation_tokens),
    fmt_int(.total_cache_read_tokens),
    fmt_int(.sidechain_count)
  ] | @tsv)
' "$AGENT_JSON")

# ボトルネック特定（PR 単位で最も時間のかかった項目）
BOTTLENECK=$(jq -r '
  def fmt_hours($s): if $s == null or $s == 0 then "—" else (($s / 3600.0) * 100 | round / 100 | tostring) + "h" end;

  if (length == 0) then "（PR データなし）"
  else
    sort_by(.total_seconds // 0) | reverse | .[0] as $top
    | "- 最長サイクル: PR #" + ($top.number|tostring) + " (" + fmt_hours($top.total_seconds) + ")\n"
      + "  - 初回レビュー: " + fmt_hours($top.first_review_seconds) + "\n"
      + "  - CI: " + fmt_hours($top.ci_seconds)
  end
' "$PR_JSON")

# サマリ値を抽出（数値展開のためのバッファ）
PR_COUNT=$(echo "$PR_SUMMARY" | jq -r '.pr_count')
PR_AVG_HOURS=$(echo "$PR_SUMMARY" | jq -r '(.total_seconds_avg / 3600.0 * 100 | round / 100)')
PR_MAX_HOURS=$(echo "$PR_SUMMARY" | jq -r '(.total_seconds_max / 3600.0 * 100 | round / 100)')
PR_MED_HOURS=$(echo "$PR_SUMMARY" | jq -r '(.total_seconds_median / 3600.0 * 100 | round / 100)')
REVIEW_AVG_HOURS=$(echo "$PR_SUMMARY" | jq -r '(.first_review_seconds_avg / 3600.0 * 100 | round / 100)')
CI_AVG_HOURS=$(echo "$PR_SUMMARY" | jq -r '(.ci_seconds_avg / 3600.0 * 100 | round / 100)')
ADD_TOTAL=$(echo "$PR_SUMMARY" | jq -r '.additions_total')
DEL_TOTAL=$(echo "$PR_SUMMARY" | jq -r '.deletions_total')

BRANCH_COUNT=$(echo "$AGENT_SUMMARY" | jq -r '.branch_count')
TOK_IN=$(echo "$AGENT_SUMMARY" | jq -r '.total_input_tokens')
TOK_OUT=$(echo "$AGENT_SUMMARY" | jq -r '.total_output_tokens')
TOK_CC=$(echo "$AGENT_SUMMARY" | jq -r '.total_cache_creation_tokens')
TOK_CR=$(echo "$AGENT_SUMMARY" | jq -r '.total_cache_read_tokens')
SIDECHAIN_TOTAL=$(echo "$AGENT_SUMMARY" | jq -r '.total_sidechain_count')

MODELS_TABLE=$(echo "$AGENT_SUMMARY" | jq -r '
  if (.models_aggregated | length) == 0 then "| （データなし） | — | — | — | — | — |"
  else
    (.models_aggregated | to_entries[] | [
      .key,
      (.value.input_tokens|tostring),
      (.value.output_tokens|tostring),
      (.value.cache_creation_tokens|tostring),
      (.value.cache_read_tokens|tostring),
      (.value.message_count|tostring)
    ] | "| " + (. | join(" | ")) + " |")
  end
')

SUBAGENT_TABLE=$(echo "$AGENT_SUMMARY" | jq -r '
  if (.subagent_types_aggregated | length) == 0 then "| （呼び出しなし） | 0 |"
  else
    (.subagent_types_aggregated | to_entries[] | [.key, (.value|tostring)]
      | "| " + (. | join(" | ")) + " |")
  end
')

# PR テーブルを Markdown に変換
PR_MD_ROWS=""
if [ -n "$PR_ROWS" ]; then
  PR_MD_ROWS=$(printf '%s\n' "$PR_ROWS" | awk -F'\t' '{ printf("| %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8) }')
else
  PR_MD_ROWS="| （PR なし） | — | — | — | — | — | — | — |"
fi

BRANCH_MD_ROWS=""
if [ -n "$BRANCH_ROWS" ]; then
  BRANCH_MD_ROWS=$(printf '%s\n' "$BRANCH_ROWS" | awk -F'\t' '{ printf("| %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8) }')
else
  BRANCH_MD_ROWS="| （ブランチなし） | — | — | — | — | — | — | — |"
fi

# 出力ディレクトリを作成
mkdir -p "$(dirname "$OUTPUT_MD")"

# Markdown レポートを生成
cat > "$OUTPUT_MD" <<EOF
# Issue サイクル実測レポート

\`/cycle-metrics\` による実測データの記録。判断（Critical/Major、Issue 起票要否）は CFO の \`/audit-cost\` 側で行う。

## 実施日

${TODAY}（生成スキル: \`/vibecorp:cycle-metrics\`）

## 集計範囲

- 対象 PR: 直近 ${PR_COUNT} 件（マージ済み）
- 集計ブランチ: ${BRANCH_COUNT} 件（\`dev/\` プレフィックス付き）

## PR サマリ

| 指標 | 値 |
|---|---|
| PR 件数 | ${PR_COUNT} |
| 平均サイクル時間 | ${PR_AVG_HOURS} h |
| 最大サイクル時間 | ${PR_MAX_HOURS} h |
| 中央値サイクル時間 | ${PR_MED_HOURS} h |
| 平均初回レビュー待ち時間 | ${REVIEW_AVG_HOURS} h |
| 平均 CI 所要時間 | ${CI_AVG_HOURS} h |
| 総追加行数 | ${ADD_TOTAL} |
| 総削除行数 | ${DEL_TOTAL} |

## PR 別詳細

| PR | Issue | タイトル | 総時間 | 初回レビュー | CI | +行 | -行 |
|---|---|---|---|---|---|---|---|
${PR_MD_ROWS}

## エージェント・トークン消費（ブランチ別）

総トークン: input=${TOK_IN} / output=${TOK_OUT} / cache_creation=${TOK_CC} / cache_read=${TOK_CR}
サブエージェント呼び出し合計（sidechain）: ${SIDECHAIN_TOTAL}

| ブランチ | Issue | セッション数 | input | output | cache_creation | cache_read | sidechain |
|---|---|---|---|---|---|---|---|
${BRANCH_MD_ROWS}

## モデル別集計

| モデル | input | output | cache_creation | cache_read | message数 |
|---|---|---|---|---|---|
${MODELS_TABLE}

## サブエージェント別呼び出し回数

| subagent_type | 呼び出し回数 |
|---|---|
${SUBAGENT_TABLE}

## ボトルネック

${BOTTLENECK}

## 関連

- \`docs/cost-analysis.md\`（実測値で補正する前提データ）
- \`/audit-cost\`（本レポートを参照する CFO 監査スキル）
- Issue #353（本スキル新設の根拠）

## 生データ

- PR メトリクス JSON: \`fetch-pr-metrics.sh\` の出力を参照
- Agent メトリクス JSON: \`fetch-agent-metrics.sh\` の出力を参照
EOF

echo "Report written to: ${OUTPUT_MD}"
