#!/usr/bin/env bash
# check-plugin-version-bump-comment.sh — bump 漏れ警告コメントを PR に投稿する
#
# .github/workflows/plugin-version-bump-check.yml から呼ばれる。
# scripts/check-plugin-version-bump.sh が failure を返した場合に、利用者向けの
# 警告コメントを PR に投稿する。本処理は warning コメントのみ・非ブロック。
#
# 必須 env:
#   GH_TOKEN   GitHub CLI 認証トークン
#   PR_NUMBER  対象 PR 番号
#   REPO       owner/repo 形式のリポジトリ識別子

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${PR_NUMBER:?PR_NUMBER が未設定です}"
: "${REPO:?REPO が未設定です}"

# notification-prompt-extraction.md ルールに従い、CEO 向け通知文は個別 .md に切り出して参照する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESSAGE_FILE="${SCRIPT_DIR}/../workflows/messages/notify-plugin-version-bump-missing.md"

gh pr comment "$PR_NUMBER" --repo "$REPO" \
  --body-file "$MESSAGE_FILE"
