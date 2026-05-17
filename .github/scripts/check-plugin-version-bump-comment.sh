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

gh pr comment "$PR_NUMBER" --repo "$REPO" \
  --body "⚠️ \`.claude-plugin/marketplace.json\` の \`plugins[0].skills\` が変更されていますが、\`.claude-plugin/plugin.json\` の \`version\` が bump されていません。利用者は新しいスキルを取得するために version bump を必要とします（PR #459 と同種の取りこぼし防止）。マージ前に \`.claude-plugin/plugin.json\` の \`version\` を更新してください。本チェックは警告のみ・非ブロックです。"
