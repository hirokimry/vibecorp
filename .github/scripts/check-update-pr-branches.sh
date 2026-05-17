#!/usr/bin/env bash
# check-update-pr-branches.sh — main 更新時に全 open PR のブランチを自動更新する。
# コンフリクトが発生した PR はスキップして続行する。
#
# .github/workflows/update-pr-branches.yml から呼ばれる。
#
# 終了コード:
#   0 — 全 PR の更新が成功（コンフリクト・最新は許容）
#   1 — 1 件以上の更新失敗（PAT 未設定はスキップ扱いで 0）
#
# 必須 env:
#   GH_TOKEN  GitHub PAT（contents:write + pull-requests:write 権限）
#   REPO      owner/repo 形式のリポジトリ識別子

set -euo pipefail

: "${REPO:?REPO が未設定です}"

# PAT 未設定時はスキップ（GH_TOKEN を空文字許容のため `: "${GH_TOKEN:?...}"` は使わない）
if [ -z "${GH_TOKEN:-}" ]; then
  echo "::warning::PAT シークレットが未設定のためスキップします。README の「PAT セットアップ」セクションを参照してください。"
  exit 0
fi
export GH_TOKEN

# 全 open PR の番号を取得（ページネーション対応）
PR_NUMBERS=$(gh api --paginate "repos/${REPO}/pulls?state=open&base=main" --jq '.[].number')

if [ -z "$PR_NUMBERS" ]; then
  echo "更新対象の open PR はありません"
  exit 0
fi

UPDATED=0
CONFLICT=0
SKIPPED=0
FAILED=0
CONFLICT_PRS=""

for PR in $PR_NUMBERS; do
  echo "--- PR #${PR} を更新中 ---"
  # 現在の head SHA を取得（失敗時は致命的エラー）
  if ! HEAD_SHA=$(gh api "repos/${REPO}/pulls/${PR}" --jq '.head.sha' 2>&1); then
    echo "PR #${PR}: SHA 取得失敗（想定外エラー）"
    echo "${HEAD_SHA}"
    exit 1
  fi

  # ブランチ更新（終了コード + レスポンスボディで分岐）
  RESPONSE=$(gh api "repos/${REPO}/pulls/${PR}/update-branch" \
    --method PUT \
    --field expected_head_sha="${HEAD_SHA}" 2>&1) && {
    echo "PR #${PR}: 更新成功"
    UPDATED=$((UPDATED + 1))
  } || {
    if echo "${RESPONSE}" | grep -qi "merge conflict"; then
      echo "PR #${PR}: コンフリクトのためスキップ"
      CONFLICT=$((CONFLICT + 1))
      CONFLICT_PRS="${CONFLICT_PRS} #${PR}"
    elif echo "${RESPONSE}" | grep -qi "already up to date"; then
      echo "PR #${PR}: 既に最新"
      SKIPPED=$((SKIPPED + 1))
    else
      echo "PR #${PR}: 更新失敗 — ${RESPONSE}"
      FAILED=$((FAILED + 1))
    fi
  }
done

echo ""
echo "=== 結果 ==="
echo "更新成功: ${UPDATED} 件"
echo "コンフリクト: ${CONFLICT} 件"
echo "スキップ（既に最新）: ${SKIPPED} 件"
echo "失敗: ${FAILED} 件"

if [ -n "${CONFLICT_PRS}" ]; then
  echo ""
  echo "コンフリクト PR:${CONFLICT_PRS}"
fi

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
