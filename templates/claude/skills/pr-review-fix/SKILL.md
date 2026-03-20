---
name: pr-review-fix
description: "PRレビュー指摘の修正と返信を自動化。CodeRabbitのレビューコメントを取得し、指摘内容を分析・修正、コミット作成・push後、各コメントに修正コミットへのリンクを返信する。ユーザーが「/pr-review-fix」「レビュー対応して」と言った時に使用。"
---

# PRレビュー指摘修正

PRのレビューコメントを取得し、指摘を修正してコメントに返信する。

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

取得したPR情報からレビューコメントを取得:

```bash
# PRレビューコメントを取得
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '.[] | select(.user.login | test("coderabbit"; "i")) | {id: .id, path: .path, line: .line, body: .body, user: .user.login}'
```

```bash
# PR全体のレビューも取得
gh pr view {pr_number} --repo {owner}/{repo} --json reviews,comments
```

### 2. 指摘内容を分析

取得したコメントから以下を識別:
- **修正が必要な指摘**: コード変更を伴うもの
- **対応不要な指摘**: 既に対応済み、サマリーコメント、または情報提供のみ
- **確認が必要な指摘**: 判断が難しいもの（ユーザーに確認）

### 3. 修正を実施

各指摘に対して:
1. 関連ファイルを読み込み
2. 指摘内容に基づいて修正

### 4. コミットを作成

`/commit` を使用してコミットする。

### 5. リモートにpush

コメント返信前に、修正をリモートにpushする:

```bash
git push
```

### 6. 各コメントに返信

**重要: 全てのコメント返信には必ずコミットリンクを含めること。**

まず `git rev-parse HEAD` でコミットSHAを取得し、**SHAを直接埋め込んだコマンド**を実行する:

```bash
git rev-parse HEAD
```

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -X POST \
  -f body="修正内容の説明 (https://github.com/{owner}/{repo}/pull/{pr_number}/commits/{SHA})" \
  -F in_reply_to={comment_id}
```

**重要**: `${COMMIT_SHA}` 等の変数展開は使わない。SHAは事前に取得し、コマンド文字列に直接埋め込むこと。

### 7. 結果報告

修正内容とコメント返信の結果をユーザーに報告:

| ファイル | コメントID | 対応 |
|---------|-----------|------|
| example.ts | 123456 | 修正済み・返信完了 |
| example.ts | 234567 | 対応不要・理由 |

## 対応しない指摘の扱い

以下の指摘は対応せず、理由をユーザーに報告:

- **linter/formatter で却下される提案**
- **設計方針に関わる大きな変更**: ユーザー判断が必要
- **情報提供のみのコメント**: 返信不要
- **サマリーコメント**: CodeRabbitの概要コメント（個別指摘ではない）

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- 判断に迷う指摘はユーザーに確認する
- 修正前に必ず関連ファイルを読み込む
- **コメント返信には必ずコミットリンクを含める**
