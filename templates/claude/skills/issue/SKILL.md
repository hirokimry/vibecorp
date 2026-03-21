---
name: issue
description: "GitHub Issue の起票を自動化。タイトル・本文からラベルを自動判定し、Assignees を設定して起票する。「/issue」「Issue作成」と言った時に使用。"
---

# 🎫 Issue 起票自動化

ユーザーから Issue 内容をヒアリングし、ラベル自動判定 + Assignees 設定で起票する。
**結果のみを簡潔に返すこと。途中経過は不要。**

## 📋 ワークフロー

### 1. 🔍 リポジトリ情報の取得

```bash
gh repo view --json owner,name,defaultBranchRef --jq '.owner.login + "/" + .name'
```

リポジトリオーナーを Assignees のデフォルトに使用する。

```bash
gh repo view --json owner --jq '.owner.login'
```

### 2. 💬 ユーザーから Issue 内容を取得

以下をユーザーに確認する:

- **タイトル**: Issue の内容（タイプは自動付与するため不要）
- **本文**: Issue の詳細（Markdown 形式）

ユーザーが一度に両方提供した場合はそのまま使用する。

### 3. 🏷️ タイプ判定・ラベル自動付与

タイトルと本文のテキストからキーワードベースでタイプを判定し、対応するラベルを付与する。
タイプは Conventional Commits 形式と統一する。

| タイプ | キーワード | ラベル |
|-------|-----------|--------|
| `feat` | 機能, 追加, 改善, feature, enhance | `enhancement` |
| `fix` | バグ, 不具合, エラー, bug, fix, crash | `bug` |
| `docs` | ドキュメント, README, docs | `documentation` |
| `test` | テスト, test, coverage | `testing` |
| `refactor` | リファクタ, refactor, 整理 | `refactor` |
| `design` | 設計, design, 計画, plan | `design` |
| `chore` | 雑務, CI, 依存, chore, deps | — |

**タイトル形式**: `<type>: <subject>`

- タイプはキーワードマッチで自動決定する
- 複数マッチした場合は最初にマッチしたタイプを採用し、ラベルは全て付与する
- マッチなしの場合はタイプなし（プレフィックスなし）、ラベルなしで起票する
- ユーザーが既にタイプ付きタイトルを入力した場合はそのまま使用する

### 4. 👤 Assignees 決定

1. `.claude/vibecorp.yml` に `issue.default_assignee` が定義されていればその値を使用
2. 未定義の場合はリポジトリオーナー（手順1で取得）を使用

### 5. 🚀 Issue 起票

```bash
gh issue create --title "<type>: <subject>" --body "<本文>" --assignee "<assignee>" --label "<label1>" --label "<label2>"
```

ラベルなしの場合は `--label` オプションを省略する。

### 6. ✅ 結果報告

起票した Issue の URL を返す。

## ⚠️ 制約

- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- ラベルが存在しない場合でも `gh issue create` はエラーにならない（GitHub が自動スキップする）
- `vibecorp.yml` が存在しない、または `issue.default_assignee` が未定義でも正常に動作すること

## 📤 返却フォーマット

```text
<Issue URL>
タイトル: <type>: <subject>
ラベル: <付与したラベル一覧（なしの場合は「なし」）>
担当者: <assignee>
```
