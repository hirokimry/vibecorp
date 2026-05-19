#!/usr/bin/env bash
# check-intent-label-issue.sh — Issue に許可された intent/* ラベル 1 つだけが
# 付与されていることを機械的に強制する。
#
# .github/workflows/intent-label-issue-check.yml から呼ばれる。
# Issue #469 残 #3「intent ラベル不在 Issue/PR は CI/hook で必須化（fail）」の Issue 側実装。
# Source of Truth: docs/conventional-commits.md, .claude/rules/intent-labels.md
#
# 終了コード:
#   0 — 許可 intent ラベルが 1 つだけ付与されている
#   1 — 未知の intent/* 混在 / intent 不在 / 複数 intent 付与（いずれも警告コメント投稿後 fail）
#
# 必須 env:
#   GH_TOKEN      GitHub CLI 認証トークン
#   ISSUE_NUMBER  対象 Issue 番号
#   REPO          owner/repo 形式のリポジトリ識別子

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER が未設定です}"
: "${REPO:?REPO が未設定です}"

# intent/* 全体数と許可 7 種のカウントを別々に取り、差分があれば未知 intent（intent/unknown 等）混入として fail させる
allowed='["intent/feature","intent/bugfix","intent/performance","intent/security","intent/refactor","intent/infra","intent/docs"]'
counts=$(gh api --paginate "repos/${REPO}/issues/${ISSUE_NUMBER}/labels" \
  | jq --argjson allowed "$allowed" '{
      total_intent: ([.[] | .name | select(startswith("intent/"))] | length),
      allowed_intent: ([.[] | .name | select(IN($allowed[]))] | length)
    }')
total_intent=$(jq -r '.total_intent' <<< "$counts")
allowed_intent=$(jq -r '.allowed_intent' <<< "$counts")
unknown_intent=$(( total_intent - allowed_intent ))

if [[ "$unknown_intent" -gt 0 ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
    --body "⚠️ 許可されていない intent/* ラベルが含まれています。1 Issue 1 intent ルールに従い、許可 7 種（intent/feature, intent/bugfix, intent/performance, intent/security, intent/refactor, intent/infra, intent/docs）から 1 つだけ付与してください。"
  exit 1
fi
if [[ "$allowed_intent" -eq 0 ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
    --body "⚠️ intent/* ラベルが付与されていません（許可 7 種のうち 1 つを付ける必要があります）。1 Issue 1 intent ルール（intent/feature, intent/bugfix, intent/performance, intent/security, intent/refactor, intent/infra, intent/docs から 1 つ）に従い、ラベルを 1 つ付与してください。詳細は .claude/rules/intent-labels.md を参照。"
  exit 1
fi
if [[ "$allowed_intent" -gt 1 ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
    --body "⚠️ 複数の intent ラベル（許可 7 種のうち）が付与されています。1 Issue 1 intent ルールに従い、ラベルを 1 つに修正してください。"
  exit 1
fi
