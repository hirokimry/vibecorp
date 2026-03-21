---
name: pr-review-fix
description: "PRレビュー指摘の修正と返信を自動化。CodeRabbitの未解決レビュースレッドを取得し、指摘内容を分析・修正してpush（auto-resolve待ち）、却下した指摘には理由を返信してresolveする。ユーザーが「/pr-review-fix」「レビュー対応して」と言った時に使用。"
---

# PRレビュー指摘修正

PRの未解決レビュースレッドを取得し、指摘を修正・却下して対応する。修正した指摘は push 時の auto-resolve に委ね、却下した指摘には理由を返信して resolve する。

## 使用方法

```bash
/pr-review-fix                    # 現在のブランチからPRを自動検出
/pr-review-fix <PR URL>           # PR URLを直接指定
```

## ワークフロー

### 1. PR情報を取得

**PR URLが指定された場合**: URLからowner/repo/PR番号を抽出する。

**PR URLが未指定の場合**: 現在のブランチから自動検出する:

```bash
gh pr view --json number,url,headRefName --jq '.number'
```

PRが見つからない場合はエラー。

GraphQL API で未解決の CodeRabbit レビュースレッドのみを取得する:

```bash
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            id
            comments(first: 10) {
              nodes {
                id
                databaseId
                author { login }
                body
                path
                line
              }
            }
          }
        }
      }
    }
  }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes
    | [.[] | select(.isResolved == false)
    | select(.comments.nodes[0].author.login | test("coderabbit"; "i"))]'
```

- `isResolved == false` かつ先頭コメントが CodeRabbit のスレッドのみ抽出
- 各スレッドの `id`（thread node ID）は却下時の resolve mutation で使用する

### 2. 妥当性検証

`.claude/rules/review-criteria.md` の判定基準に従い、指摘を分類する。
設計方針に関わる大きな変更はユーザーに確認する。

### 3. 修正計画

要修正リストに対して、各指摘の具体的な修正計画を策定する。**このステップではコードの変更は行わない。**

手順:
1. 指摘箇所の実コードと周辺コードを読む
2. 既存の類似実装パターンを確認する
3. 修正による影響範囲を特定する
4. 具体的な修正手順を策定する

各指摘について以下を明記する:

- **修正内容**: 何をどう変更するか
- **影響範囲**: 変更が影響する他のファイル・テスト
- **注意点**: 修正時に気をつけるべきこと

### 4. 修正実行

修正計画に従ってコードを修正する。

- **計画に記載された範囲のみを変更する**
- 修正後、関連するテスト・lint を実行して通過を確認する

各修正について以下を記録する:

- **修正内容**: どのファイルの何を変更したか
- **テスト結果**: 関連するテスト・lint の PASS/FAIL

### 5. コミットを作成

`/commit` を使用してコミットする。

### 6. リモートにpush

コメント返信前に、修正をリモートにpushする:

```bash
git push
```

### 7. 却下した指摘に返信・resolve

**修正した指摘**: 返信不要。push 時に CodeRabbit の auto-resolve で自動的に resolved になる。

**却下した指摘**: 却下理由を返信した後、GraphQL mutation でスレッドを resolve する。

却下理由の返信:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -X POST \
  -f body="{却下理由の markdown}" \
  -F in_reply_to={comment_database_id}
```

- `{comment_database_id}` はステップ1で取得した先頭コメントの `databaseId`（REST API 整数ID）

返信後、即座にスレッドを resolve する:

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: { threadId: "{thread_node_id}" }) {
      thread { isResolved }
    }
  }'
```

- `{thread_node_id}` はステップ1で取得した各スレッドの `id` フィールド（例: `PRRT_xxx`）
- 返信 → resolve の順序で実行する（resolve 済みスレッドには CodeRabbit は再反応しない）

### 8. 結果報告

修正内容とコメント返信の結果をユーザーに報告:

| ファイル | スレッドID | 対応 |
|---------|-----------|------|
| example.ts | PRRT_xxx | 修正済み（auto-resolve待ち） |
| example.ts | PRRT_yyy | 却下・返信+resolve済み |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- 判断に迷う指摘はユーザーに確認する
- 修正前に必ず関連ファイルを読み込む
