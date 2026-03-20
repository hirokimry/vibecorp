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

### 2. 終了条件を満たすまでループ

#### 2.1 CodeRabbitレビュー待ち

30秒間隔でポーリング。最大10分:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
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

未解決のCodeRabbitコメントを数える:

```bash
# CodeRabbitのトップレベルコメントID
CR_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.in_reply_to_id == null) | .id]')

# 返信済みID一覧
REPLY_TO_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.in_reply_to_id != null) | .in_reply_to_id] | unique')

# 未返信 = 未解決
echo "$CR_IDS" | jq --argjson replied "$REPLY_TO_IDS" \
  '[.[] | select(. as $id | $replied | index($id) | not)]'
```

- CI パス + 未解決0件 → **ループ終了、ステップ3へ**
- それ以外 → 2.4 へ

#### 2.4 レビュー指摘の修正

`/pr-review-fix` を実行して未解決コメントに対応する。修正後 push し、ループ先頭（2.1）に戻る。

### 3. レビュー指摘の規約・ナレッジ反映

マージ前に `/review-to-rules` を実行する。

ファイル変更の有無を確認:

```bash
if [ -n "$(git status --porcelain)" ]; then
  # 変更あり → コミット → push → ループ先頭（2.1）に戻る
  /commit
  git push
else
  # 変更なし → マージへ進む
fi
```

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
- レビュー修正: {n}回
- CI: パス
- マージ: 完了
```

## エラー時の挙動

| 状況 | 対応 |
|------|------|
| CodeRabbitレビュータイムアウト | コメント0件ならそのまま進行、あれば現状で修正 |
| CI失敗 | 失敗内容を報告してユーザーに判断を委ねる |
| マージコンフリクト | ユーザーに報告して停止 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- マージ先は PRの baseRefName
- ユーザーの明示的な指示なしに force push しない
