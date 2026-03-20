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

### 2. 妥当性検証

指摘された箇所の**実コードを読んで文脈を確認**した上で、以下の基準で分類する。

#### 判定基準

CodeRabbit の重要度分類に基づき、**Trivial 以上は修正、Info はスルー**する。

**修正すべき（actionable） — Critical / Major / Minor / Trivial:**

- **Critical**: セキュリティ脆弱性、データ損失、システム障害
- **Major**: バグ、未処理例外、リソースリーク、パフォーマンス問題
- **Minor**: ベストプラクティス違反、可読性の明らかな低下、プロジェクト規約（`.claude/rules/`）違反、テストの不足・不備
- **Trivial**: スタイル改善、命名規則、軽微な最適化

**却下（dismissed） — Info:**

- 情報提供のみのコメント（対応不要）
- 既存コード（今回の変更範囲外）に対する指摘
- 過剰な抽象化・設計変更の提案
- 誤検知・文脈を理解していない指摘
- サマリーコメント（CodeRabbitの概要コメント）

判断に迷う場合は「修正すべき」に分類する。設計方針に関わる大きな変更はユーザーに確認する。

### 3. 修正計画

要修正リストに対して、各指摘の具体的な修正計画を策定する。**このステップではコードの変更は行わない。**

手順:
1. 指摘箇所の実コードと周辺コードを読む
2. 既存の類似実装パターンを確認する
3. 修正による影響範囲を特定する
4. 具体的な修正手順を策定する

### 4. 修正実行

修正計画に従ってコードを修正する。

- **計画に記載された範囲のみを変更する**
- 修正後、関連するテスト・lint を実行して通過を確認する

### 5. コミットを作成

`/commit` を使用してコミットする。

### 6. リモートにpush

コメント返信前に、修正をリモートにpushする:

```bash
git push
```

### 7. 各コメントに返信

まず `git rev-parse HEAD` でコミットSHAを取得する:

```bash
git rev-parse HEAD
```

各コメントに対して、以下の内容で返信する:

- **修正した指摘**: コミットリンク + markdown での可読性の高い修正内容の説明
- **却下した指摘**: markdown での可読性の高い却下理由の説明（判定基準に基づく根拠を含める）

返信コマンド（SHAを直接埋め込む）:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -X POST \
  -f body="{markdown}" \
  -F in_reply_to={comment_id}
```

**重要**: `${COMMIT_SHA}` 等の変数展開は使わない。SHAは事前に取得し、コマンド文字列に直接埋め込むこと。

### 8. 結果報告

修正内容とコメント返信の結果をユーザーに報告:

| ファイル | コメントID | 対応 |
|---------|-----------|------|
| example.ts | 123456 | 修正済み・返信完了 |
| example.ts | 234567 | 却下・理由 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- 判断に迷う指摘はユーザーに確認する
- 修正前に必ず関連ファイルを読み込む
- **コメント返信には必ずコミットリンクを含める**
