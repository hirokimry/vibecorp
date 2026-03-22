---
name: pr-review-loop
description: "PR作成後、CodeRabbitレビュー待ち→指摘修正→CI待ちのループを自動実行する。マージは auto-merge に委ねる。「/pr-review-loop」「レビュー対応して」「PRレビュー修正して」と言った時に使用。"
---

# PRレビュー修正ループ

PR作成後、「CI パス + 未解決コメント0件」になるまでレビュー修正を繰り返す。マージは auto-merge に委ねる。

## 使用方法

```bash
/pr-review-loop                    # 現在のブランチのPRを自動検出
/pr-review-loop <PR URL>           # PR URLを直接指定
```

## 前提条件

- PRが既に作成されていること（未作成なら `/pr` を先に実行すること）
- 現在のブランチがPRのheadブランチであること

## 終了条件

以下の **両方** を満たしたら完了:
1. CI が全てパスしている
2. CodeRabbit の未解決コメントが0件

## ワークフロー

### 1. PR情報を取得

**PR URLが指定された場合**: URLからowner/repo/PR番号を抽出する。

**PR URLが未指定の場合**: 現在のブランチから自動検出する:

```bash
gh pr view --json number,url,headRefName,baseRefName --jq '{number, url, headRefName, baseRefName}'
```

PRが見つからない場合はエラー。

### 2. メインループ（最大10回）

以下のステップ 2.1〜2.9 を、終了条件を満たすまで繰り返す。**最大10回でループを打ち切る。上限到達時は未解決の状況を報告してユーザーに判断を委ねる。**

#### 2.1 CodeRabbitレビュー待ち

**まず `vibecorp.yml` の `coderabbit.enabled` を確認する:**

```bash
awk '/^coderabbit:/{found=1; next} found && /^[^ ]/{exit} found && /enabled:/{print $2}' \
  "$CLAUDE_PROJECT_DIR"/.claude/vibecorp.yml
```

- 結果が `false` → **CodeRabbit 無効。ステップ 2.1〜2.9 を全てスキップし、ステップ3（auto-merge確認）へ直接進む**
- 結果が `true` または空（未定義）→ CodeRabbit 有効。以下のポーリングを実行

30秒間隔でポーリング。最大5分:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i"))] | length'
```

- コメント数が0のまま5分経過 → **CodeRabbit 未導入と判断し、ステップ3へスキップ**
- コメント数が安定（2回連続同数） → レビュー完了と判断、2.2 へ
- 5分経過（コメントあり） → タイムアウト。現状のコメントで進める

**rate limit チェック**: レビュー待ち中に CodeRabbit の rate limit コメントを検出した場合、ユーザーに報告して停止する:

```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body | test("[Rr]ate limit"))] | length'
```

1以上なら「CodeRabbit が rate limit 中のため停止しています。rate limit 解除後に再実行してください」と報告して**停止する**。

#### 2.2 CI 状態の確認

```bash
gh pr checks {pr_number} --json name,state --jq '.[] | {name, state}'
```

#### 2.3 未解決スレッドの取得

GraphQL API で未解決の CodeRabbit レビュースレッドを取得する:

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

**CI パス + 未解決0件 → ループ終了、ステップ3へ。** それ以外 → 2.4 へ。

#### 2.4 妥当性検証

`.claude/rules/review-criteria.md` の判定基準に従い、指摘を分類する。
設計方針に関わる大きな変更はユーザーに確認する。

#### 2.5 修正計画

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

#### 2.6 修正実行

修正計画に従ってコードを修正する。

- **計画に記載された範囲のみを変更する**
- 修正後、関連するテスト・lint を実行して通過を確認する

#### 2.7 却下した指摘に返信・resolve

**修正した指摘**: 返信不要。次のステップ（2.8）の push 時に CodeRabbit の auto-resolve で自動的に resolved になる。

**却下した指摘**: 却下理由を返信した後、GraphQL mutation でスレッドを resolve する。

却下理由の返信:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -X POST \
  -f body="{却下理由の markdown}" \
  -F in_reply_to={comment_database_id}
```

- `{comment_database_id}` はステップ2.3で取得した先頭コメントの `databaseId`（REST API 整数ID）

返信後、即座にスレッドを resolve する:

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: { threadId: "{thread_node_id}" }) {
      thread { isResolved }
    }
  }'
```

- `{thread_node_id}` はステップ2.3で取得した各スレッドの `id` フィールド（例: `PRRT_xxx`）
- 返信 → resolve の順序で実行する（resolve 済みスレッドには CodeRabbit は再反応しない）

#### 2.8 コミット・push

`/commit` を使用してコミットし、リモートに push する:

```bash
git push
```

#### 2.9 規約・ナレッジ反映（オプション）

vibecorp.yml の `gates.review_to_rules` を確認する:

```bash
yq '.gates.review_to_rules // false' "$CLAUDE_PROJECT_DIR"/.claude/vibecorp.yml
```

- `false` → **ループ先頭（2.1）に戻る**
- `true` → `/review-to-rules` を実行し、結果を確認する:
  - **変更なし** → **ループ先頭（2.1）に戻る**（スタンプファイルが発行され、ゲートを通過可能になる）
  - **変更あり** → `/commit` でコミットし `git push` する。push により CodeRabbit が再レビューするため、**ループ先頭（2.1）に戻る。** rules/knowledge の変更もレビュー対象とし、品質を担保する

### 3. auto-merge 状態の確認

auto-merge が設定されているか確認する:

```bash
gh pr view {pr_number} --json autoMergeRequest --jq '.autoMergeRequest'
```

- auto-merge 設定済み → ステップ4へ
- auto-merge 未設定 → 設定する:

```bash
gh pr merge {pr_number} --squash --auto
```

### 4. 結果報告

```text
## /pr-review-loop 完了

- PR: #{pr_number}
- ループ回数: {n}回
- レビュー修正: {n}件
- 却下: {n}件
- 規約・ナレッジ反映: {n}件（gates.review_to_rules が true の場合のみ）
- auto-merge: 設定済み（CI パス + approve 後に GitHub が自動マージします）
```

**CodeRabbit 無効時（`coderabbit.enabled: false`）の結果報告:**

```text
## /pr-review-loop 完了

- CodeRabbit: 無効（vibecorp.yml で coderabbit.enabled: false）
- CI: {パス/失敗}
- auto-merge: 設定済み
- 注意: Require approvals が有効な場合、人間による approve が必要です
```

**CodeRabbit 未導入検出時の結果報告:**

```text
## /pr-review-loop 完了

- CodeRabbit レビュー: 未検出（CodeRabbit 未導入の可能性があります）
- CI: {パス/失敗}
- auto-merge: 設定済み
- 注意: Require approvals が有効な場合、人間による approve が必要です
```

## エラー時の挙動

| 状況 | 対応 |
|------|------|
| CodeRabbit レビュータイムアウト（コメントあり） | 現状のコメントで修正を進める |
| CodeRabbit 未導入（コメント0件のまま5分経過） | ループをスキップし、auto-merge 確認のみ実行 |
| CodeRabbit rate limit | rate limit コメントを検出したらユーザーに報告して停止 |
| CI 失敗 | 失敗内容を報告してユーザーに判断を委ねる |
| ループ上限（10回）到達 | 未解決の状況を報告してユーザーに判断を委ねる |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- 判断に迷う指摘はユーザーに確認する
- 修正前に必ず関連ファイルを読み込む
- **`@coderabbitai approve` の投稿は禁止** — approve は CodeRabbit が自動発行するか、人間が手動で行う
