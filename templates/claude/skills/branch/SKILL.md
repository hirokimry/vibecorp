---
name: branch
description: "GitHub Issue URLからブランチを自動作成するスキル。「/branch https://github.com/owner/repo/issues/12345」のようにIssue URLを指定すると、Issueタイトルを要約してdev/{Issue番号}_{要約}形式のブランチ名を生成し、現在のブランチをベースに新規ブランチを作成・チェックアウトする。「ブランチ作成」「branch作成」と言われた時にも使用。"
---

# ブランチ自動作成

GitHub Issue URL からブランチを作成する。
**結果のみを簡潔に返すこと。途中経過は不要。**

## 使用方法

```bash
/branch <Issue URL>
```

## ワークフロー

### 1. Issue 情報の取得

引数から Issue URL を受け取り、Issue 番号とタイトルを取得する。

```bash
gh issue view <Issue URL> --json number,title --jq '.number,.title'
```

### 2. ブランチ名の生成

タイトルを英語の短い要約（スネークケース）に変換し、以下の形式でブランチ名を生成する。

```text
dev/{Issue番号}_{要約}
```

**要約ルール:**
- 英語のスネークケース（小文字 + アンダースコア）
- 最大30文字
- 絵文字・タイプ接頭辞（`feat:`, `fix:` 等）は除外
- 内容を端的に表す2〜4単語

例:
- `✨ feat: /ship Issue指定からマージまでの全自動スキル` → `dev/67_ship_auto_merge`
- `🐛 fix: mvv.md path notation inconsistency` → `dev/41_mvv_path_fix`

### 3. ベースブランチの最新化

```bash
git pull origin HEAD --ff-only
```

### 4. ブランチ作成・チェックアウト

```bash
git checkout -b <ブランチ名>
```

## 制約

- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- 既存のブランチ名と衝突する場合はユーザーに報告して停止

## 返却フォーマット

```text
<ブランチ名>
```
