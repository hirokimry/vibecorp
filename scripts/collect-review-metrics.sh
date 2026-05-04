#!/bin/bash
# collect-review-metrics.sh — CodeRabbit と claude-action の並走比較メトリクス収集
#
# Issue #474: PR ごとに両ツールの指摘件数・severity 分布・重複率・固有率を集計し、
# `~/.cache/vibecorp/state/<repo-id>/review-metrics/` に揮発データとして保存する。
#
# 実行: bash scripts/collect-review-metrics.sh <PR番号>
#   - PR が merged 状態であることを前提とする
#   - knowledge / git には含めない（揮発データ）
#   - 月次レポートは生成しない（必要な時に手動で見る）
#
# 二重指摘の判定:
#   - 同じファイルパス内で、両ツールのコメント本文に共通キーワードが含まれていれば「重複」扱い
#   - embedding ベースの類似度判定はコスト高のため採用しない（Issue #474 確定 5）

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "使い方: bash scripts/collect-review-metrics.sh <PR番号>" >&2
  exit 1
fi

PR_NUMBER="$1"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh CLI が必要です" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq が必要です" >&2
  exit 1
fi

# 保存先: ~/.cache/vibecorp/state/<repo-id>/review-metrics/
# repo-id は vibecorp_repo_id ヘルパーと同じロジックで生成
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.claude/lib/common.sh"
METRICS_DIR="$(vibecorp_stamp_dir)/review-metrics"
mkdir -p "$METRICS_DIR"

PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state')
if [[ "$PR_STATE" != "MERGED" ]]; then
  echo "⚠️ PR #${PR_NUMBER} はマージされていません（state: ${PR_STATE}）。マージ済み PR のみ集計対象です。" >&2
  exit 1
fi

echo "=== PR #${PR_NUMBER} のレビュー比較メトリクス収集 ==="

# 1. 全レビューコメントを取得
all_review_comments=$(gh api "repos/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/pulls/${PR_NUMBER}/comments" --paginate)

# 2. CodeRabbit / claude-action それぞれの bot ユーザーで分類
# CodeRabbit の bot user: coderabbitai[bot]
# claude-action の bot user: github-actions[bot]（または anthropic 系）
coderabbit_count=$(echo "$all_review_comments" | jq '[.[] | select(.user.login == "coderabbitai[bot]")] | length')
claude_count=$(echo "$all_review_comments" | jq '[.[] | select(.user.login == "github-actions[bot]" or .user.login == "claude[bot]" or .user.login == "anthropic[bot]")] | length')

# 3. severity 分布（コメント本文から CodeRabbit 形式の severity マーカーを抽出）
# CodeRabbit のフォーマット: "🔴 Critical" / "🟠 Major" / "🟡 Minor" / "🔵 Trivial" / "⚪ Info"
get_severity_count() {
  local user="$1"
  local pattern="$2"
  echo "$all_review_comments" | jq --arg user "$user" --arg pattern "$pattern" \
    '[.[] | select(.user.login == $user) | select(.body | contains($pattern))] | length'
}

cr_critical=$(get_severity_count "coderabbitai[bot]" "Critical")
cr_major=$(get_severity_count "coderabbitai[bot]" "Major")
cr_minor=$(get_severity_count "coderabbitai[bot]" "Minor")
cr_trivial=$(get_severity_count "coderabbitai[bot]" "Trivial")
cr_info=$(get_severity_count "coderabbitai[bot]" "Info")

# 4. 重複判定（同じファイル内で共通キーワード）
# 簡易実装: 両ツールが同じファイルにコメントしているケースを「重複候補」としてカウント
cr_paths=$(echo "$all_review_comments" | jq -r '[.[] | select(.user.login == "coderabbitai[bot]") | .path] | unique[]' 2>/dev/null || echo "")
claude_paths=$(echo "$all_review_comments" | jq -r '[.[] | select(.user.login == "github-actions[bot]" or .user.login == "claude[bot]" or .user.login == "anthropic[bot]") | .path] | unique[]' 2>/dev/null || echo "")

duplicate_paths=$(comm -12 <(echo "$cr_paths" | sort) <(echo "$claude_paths" | sort) 2>/dev/null | wc -l | tr -d ' ')
cr_only_paths=$(comm -23 <(echo "$cr_paths" | sort) <(echo "$claude_paths" | sort) 2>/dev/null | wc -l | tr -d ' ')
claude_only_paths=$(comm -13 <(echo "$cr_paths" | sort) <(echo "$claude_paths" | sort) 2>/dev/null | wc -l | tr -d ' ')

# 5. メトリクス JSON 出力
collected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
out_file="${METRICS_DIR}/pr_${PR_NUMBER}.json"
jq -n \
  --argjson pr_number "$PR_NUMBER" \
  --arg collected_at "$collected_at" \
  --argjson cr_count "$coderabbit_count" \
  --argjson claude_count "$claude_count" \
  --argjson cr_critical "$cr_critical" \
  --argjson cr_major "$cr_major" \
  --argjson cr_minor "$cr_minor" \
  --argjson cr_trivial "$cr_trivial" \
  --argjson cr_info "$cr_info" \
  --argjson dup_paths "$duplicate_paths" \
  --argjson cr_only "$cr_only_paths" \
  --argjson claude_only "$claude_only_paths" \
  '{
    pr_number: $pr_number,
    collected_at: $collected_at,
    coderabbit: {
      total_count: $cr_count,
      severity: {
        critical: $cr_critical,
        major: $cr_major,
        minor: $cr_minor,
        trivial: $cr_trivial,
        info: $cr_info
      }
    },
    claude_action: {
      total_count: $claude_count
    },
    file_overlap: {
      both_tools: $dup_paths,
      coderabbit_only: $cr_only,
      claude_action_only: $claude_only
    }
  }' > "$out_file"

echo ""
echo "✅ メトリクスを保存: ${out_file}"
echo ""
cat "$out_file" | jq .
