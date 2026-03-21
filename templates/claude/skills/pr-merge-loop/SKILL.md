---
name: pr-merge-loop
description: "PR作成後、CodeRabbitレビュー待ち→指摘修正→CI待ち→マージまでを全自動で行う。「/pr-merge-loop」「PRマージまでやって」と言った時に使用。"
---

# PR自動マージループ

PR作成後、「CI パス + 未解決コメント0件」になるまでレビュー修正を繰り返し、達成したらマージする。

## 使用方法

```bash
/pr-merge-loop                    # 現在のブランチのPRを自動検出
/pr-merge-loop <PR URL>           # PR URLを直接指定
```

## 前提条件

- PRが既に作成されていること（未作成なら `/pr` を先に実行すること）
- 現在のブランチがPRのheadブランチであること

## 終了条件

以下の **両方** を満たしたらマージに進む:
1. CI が全てパスしている
2. CodeRabbit の未解決コメントが0件

## ワークフロー

### 1. PR情報を取得

```bash
gh pr view --json number,url,headRefName,baseRefName --jq '{number, url, headRefName, baseRefName}'
```

### 2. メインループ（最大10回）

以下のステップ 2.1〜2.5 を、マージ条件を満たすまで繰り返す。**最大10回でループを打ち切る。上限到達時はマージせず、未解決の状況を報告してユーザーに判断を委ねる。**

#### 2.1 CodeRabbitレビュー待ち

30秒間隔でポーリング。最大10分:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i"))] | length'
```

- コメント数が0 → 30秒待って再確認（CodeRabbitがまだ処理中）
- コメント数が安定（2回連続同数） → レビュー完了と判断
- 10分経過 → タイムアウト。現状のコメントで進める

#### 2.2 CI 状態の確認

```bash
gh pr checks {pr_number} --json name,state --jq '.[] | {name, state}'
```

#### 2.3 終了条件の判定

GraphQL API で未解決の CodeRabbit レビュースレッド数を取得する:

```bash
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 1) {
              nodes {
                author { login }
                body
              }
            }
          }
        }
      }
    }
  }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes
    | [.[] | select(.isResolved == false)
    | select(.comments.nodes[0].author.login | test("coderabbit"; "i"))]
    | length'
```

- CI パス + 未解決0件 → **ループ終了、ステップ2.5 へ**
- それ以外 → 2.4 へ

#### 2.4 レビュー指摘の修正

`/pr-review-fix` を実行して未解決コメントに対応する。修正後 push し、**ループ先頭（2.1）に戻る。**

#### 2.5 レビュー指摘の規約・ナレッジ反映

vibecorp.yml の `gates.review_to_rules` を確認する:

```bash
yq '.gates.review_to_rules // false' "$CLAUDE_PROJECT_DIR"/.claude/vibecorp.yml
```

- `false` → スキップしてステップ3へ
- `true` → `/review-to-rules` を実行し、結果を確認する:
  - **変更なし** → **ステップ3へ**（スタンプファイルが発行され、ゲートを通過可能になる）
  - **変更あり** → `/commit` でコミットし `git push` する。push により CodeRabbit が再レビューするため、**ループ先頭（2.1）に戻る。** rules/knowledge の変更もレビュー対象とし、品質を担保する

### 3. CodeRabbit approve 確認

マージ前に CodeRabbit の approve レビューが存在するか確認する。
`request_changes_workflow: true` 環境では指摘なしで自動 approve されるはずだが、差分が小さい場合等に approve が発行されないケースがある。

#### 3.1 rate limit チェック（フォールバック前の必須ガード）

**approve 確認の前に**、CodeRabbit が rate limit 状態でないことを確認する。rate limit 中は CodeRabbit がレビューを実行できていないため、「approve がない」を「レビュー済みで問題なし」と解釈してはならない。

```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body | test("[Rr]ate limit"))] | length'
```

- **1以上（rate limit コメントあり）** → **フォールバック禁止**。ユーザーに「CodeRabbit が rate limit 中のためマージを保留しています。rate limit 解除後に再実行してください」と報告して**停止する**
- **0（rate limit なし）** → 3.2 へ進む

#### 3.2 approve 確認

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.state == "APPROVED")] | length'
```

- approve あり（1以上） → ステップ4へ
- approve なし → 以下のフォールバックを実行:

#### 3.3 フォールバック: approve 依頼

**発動条件（全て満たす場合のみ）:**
1. 3.1 の rate limit チェックを通過している（rate limit コメントなし）
2. CodeRabbit ステータスが `SUCCESS`
3. 未解決スレッドが0件

上記を全て満たす場合のみ、`@coderabbitai approve` を投稿して approve を促す。

```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  -X POST \
  -f body="@coderabbitai approve"
```

投稿後、30秒間隔で最大3分間 approve を待つ。approve が出たらステップ4へ進む。タイムアウトした場合はユーザーに報告する。

### 4. マージ

```bash
gh pr merge {pr_number} --squash --delete-branch
```

### 5. ベースブランチに切り替え

```bash
git checkout {baseRefName} && git pull
```

### 6. 結果報告

```text
## PR自動マージ完了

- PR: #{pr_number}
- ループ回数: {n}回
- レビュー修正: {n}件
- 規約・ナレッジ反映: {n}件（gates.review_to_rules が true の場合のみ）
- マージ: 完了
```

## エラー時の挙動

| 状況 | 対応 |
|------|------|
| CodeRabbitレビュータイムアウト | コメント0件ならそのまま進行、あれば現状で修正 |
| CodeRabbit rate limit | rate limit コメントを検出したらフォールバック禁止。ユーザーに報告して停止 |
| CodeRabbit approve 未発行 | rate limit チェック通過後、`@coderabbitai approve` を投稿して最大3分待機。タイムアウト時はユーザーに報告 |
| CI失敗 | 失敗内容を報告してユーザーに判断を委ねる |
| マージコンフリクト | ユーザーに報告して停止 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- マージ先は PRの baseRefName
- ユーザーの明示的な指示なしに force push しない
