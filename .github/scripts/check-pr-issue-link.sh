#!/usr/bin/env bash
# check-pr-issue-link.sh — PR 本文に対応 Issue への参照（Refs / close / closes /
# fix / fixes / resolve / resolves）が含まれていない場合に fail させる。
#
# .github/workflows/pr-issue-link-check.yml から呼ばれる。
# Issue #469 残 #5「Issue 番号取れない PR は fail（Issue 経由起票必須）」の実装。
# Source of Truth: docs/conventional-commits.md, .claude/rules/intent-labels.md
#
# 終了コード:
#   0 — PR 本文に Issue 参照あり
#   1 — Issue 参照なし（警告コメント投稿後 fail）
#
# 必須 env:
#   GH_TOKEN   GitHub CLI 認証トークン
#   PR_NUMBER  対象 PR 番号
#   REPO       owner/repo 形式のリポジトリ識別子

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${PR_NUMBER:?PR_NUMBER が未設定です}"
: "${REPO:?REPO が未設定です}"

# GitHub の auto-close keywords（close/fix/resolve 形）と Refs を許容形式として認識する（大小文字区別なし）
body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body')
if echo "$body" | grep -qiE '(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+|(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+https?://[^[:space:]]+/issues/[0-9]+'; then
  echo "PR 本文に Issue 参照が見つかりました"
  exit 0
fi
# notification-prompt-extraction.md ルールに従い、CEO 向け通知文は個別 .md に切り出して参照する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESSAGE_FILE="${SCRIPT_DIR}/../workflows/messages/notify-pr-issue-link-missing.md"

gh pr comment "$PR_NUMBER" --repo "$REPO" \
  --body-file "$MESSAGE_FILE"
exit 1
