---
name: ship-parallel
description: "複数Issueを並列shipするオーケストレーションスキル。COOエージェントで並列判定し、TeamCreate + Agent worktreeで同時実行する。「/ship-parallel」「並列シップ」「まとめてship」と言った時に使用。"
---

**ultrathink**

# 並列 ship オーケストレーション

複数の Issue を並列に `/ship` 実行する。**COO エージェントが Issue 群の依存関係を分析**し、その結果に基づいてスキル実行者が TeamCreate + Agent worktree で同時進行する。

**full プリセット専用**。COO エージェントによる並列判定が必要なため、standard 以下では利用不可。

## 使用方法

```bash
/ship-parallel <Issue URL 1> <Issue URL 2> [...]
/ship-parallel --all
```

- Issue URL を複数指定: 指定された Issue のみ対象
- `--all`: open な Issue を全て取得し、COO が選別

## 前提条件

- **full プリセット** であること（COO エージェントが必要）
- 現在のブランチがベースブランチ（main または release/* 等）であること
- GitHub CLI (`gh`) が認証済みであること
- ベースブランチが最新であること

## アーキテクチャ

**TeamCreate + Agent isolation: "worktree"** 方式を採用する。
COO は分析専任、オーケストレーションはスキル実行者が直接実行する。

```text
スキル実行者（オーケストレーター）
  ├─ 1. Agent(COO) で Issue 群の並列判定を取得
  │     └─ COO が依存関係を分析し、並列グループ・直列チェーン・保留を返す
  ├─ 2. 実行計画をユーザーに提示・確認
  ├─ 3. TeamCreate でチーム作成 + Agent(isolation: "worktree") で起動
  │     └─ チームメイトが worktree 内で /ship を実行
  ├─ 4. 各チームメイトの進捗を SendMessage で監視
  │     ├─ エラー報告 → スキル実行者が判断（中断/リトライ/スキップ）
  │     └─ 完了報告 → 結果を記録
  ├─ 5. 並列 PR 間のコンフリクト検知
  └─ 6. 結果統合、レポート出力
```

### 方式選定理由

- Agent worktree 内で `/ship` を含む全スキルが動作することが検証済み
- `.claude/`（skills, hooks, settings.json 含む）が自動同期される
- TeamCreate + SendMessage でリアルタイム進捗監視・介入が可能
- COO は分析専任とし、`/sync-check` 等と同じ「分析エージェント→メイン実行」パターンに統一

## ワークフロー

### 1. プリセット確認

`vibecorp.yml` の `preset` を確認する。

```bash
awk '/^preset:[[:space:]]*/ { sub(/^preset:[[:space:]]*/, ""); print; exit }' .claude/vibecorp.yml
```

`full` 以外の場合は「/ship-parallel は full プリセット専用です」と報告して終了する。

### 2. Issue 一覧の取得

**URL 直接指定の場合:**

各 URL から Issue 情報を取得する。

```bash
gh issue view <Issue URL> --json number,title,body --jq '{number, title, body}'
```

**`--all` の場合:**

open な Issue を一括取得する。

```bash
gh issue list --state open --json number,title,body,labels --limit 500
```

Issue が1件以下の場合は「並列実行の対象がありません。単一 Issue には `/ship` を使用してください」と報告して終了する。

### 3. COO エージェントによる並列判定

COO エージェントを Agent ツールで起動し、Issue 群の並列実行可否を判定させる。
COO は分析結果のみを返し、オーケストレーションには関与しない。

COO エージェントが Agent ツールの利用可能タイプにない場合は、general-purpose エージェントに COO エージェント定義（`.claude/agents/coo.md`）の内容を渡して代用する。

COO に渡すプロンプト:

```text
以下の Issue 群の並列実行可否を分析してください。

## Issue 一覧
{Issue 情報のリスト}

## 分析観点
- 各 Issue の影響範囲（変更対象ファイル・モジュール）
- Issue 間の依存関係（同一ファイル変更、機能的依存）
- コンフリクトリスク

## 出力フォーマット
以下の分類で結果を返してください:
- 並列グループ: 同時実行可能な Issue の集合（複数グループ可）
- 直列チェーン: 順序制約のある Issue のリスト（依存理由付き）
- 保留: 情報不足で判定できない Issue（理由付き）
- コンフリクトリスク: 並列実行時に衝突する可能性のあるファイル
```

### 4. 実行計画の提示・ユーザー確認

COO の分析結果に基づき、スキル実行者が実行計画をユーザーに提示し、承認を求める。

```text
## 並列 ship 実行計画

### 並列グループ 1
| Issue | タイトル | 影響範囲 |
|-------|---------|---------|
| #10 | xxx | .claude/skills/foo/ |
| #11 | yyy | tests/test_bar.sh |

### 直列チェーン
| 順序 | Issue | タイトル | 依存理由 |
|------|-------|---------|---------|
| 1 | #12 | zzz | - |
| 2 | #13 | www | #12 と同一ファイル変更 |

### 保留（実行対象外）
| Issue | 理由 |
|-------|------|
| #14 | 影響範囲が不明 |

実行しますか？ (y/n)
```

ユーザーが承認しない場合は終了する。

### 5. チーム作成・Agent worktree 起動

承認後、スキル実行者が TeamCreate でチームを組成し、各 Issue に対して Agent を起動する。

#### 5a. チーム作成

```text
TeamCreate(team_name: "ship-parallel-{timestamp}")
```

#### 5b. ベースブランチの決定

Issue 本文にベースブランチの指定がある場合はそれを使用する。ない場合は現在のブランチを使用する。

#### 5c. 並列グループの Agent 起動

並列グループ内の各 Issue に対して、Agent ツールを `isolation: "worktree"` で起動する。
**同一グループの全 Agent は1つのメッセージで同時に起動する**（並列実行を最大化）。

各 Agent に渡すプロンプト:

```text
あなたは Issue #{番号} の実装担当です。

以下の Issue を /ship で実装してください。

- Issue URL: <Issue URL>
- ベースブランチ: <ベースブランチ>

/ship のワークフローに従い、計画策定→実装→テスト→コミット→PR作成→auto-merge設定まで実行してください。
PR のベースブランチは <ベースブランチ> を指定してください。

注意:
- worktree 内のブランチ名は自動生成されています。PR 作成前に dev/{Issue番号}_{要約} 形式にリネームしてください:
  git branch -m <現在のブランチ名> dev/{Issue番号}_{要約}

完了したら以下を報告してください:
- PR URL
- 成功/失敗
- 失敗の場合は理由
```

#### 5d. 直列チェーンの順序実行

直列チェーンがある場合、前の Issue の Agent が完了してから次の Issue の Agent を起動する。
SendMessage で前の Agent の完了を確認し、成功していれば次を起動する。

### 6. 進捗監視・結果収集

TeamCreate + SendMessage によるリアルタイム監視:

- 各 Agent の完了報告を SendMessage で受け取る
- エラー発生時は即座に通知される
- 必要に応じて介入が可能（中断・優先度変更・方針変更）

### 7. 並列 PR コンフリクト検知

並列グループの全 Agent が完了した後、PR 間のコンフリクトを検知する。

```bash
# 各 PR のブランチを順にマージして衝突を検出（ドライラン）
git merge-tree $(git merge-base HEAD <branch_a>) HEAD <branch_a>
```

- コンフリクトが検出された場合、対象 PR とファイルをユーザーに報告する
- 解消方法の提案（どちらを先にマージすべきか等）を提示する
- **自動解消は行わない** — ユーザーの判断を待つ

### 8. 結果報告

```text
## /ship-parallel 完了

### 成功
| Issue | PR | ブランチ |
|-------|-----|---------|
| #10 | #20 | dev/10_xxx |
| #11 | #21 | dev/11_yyy |

### 失敗
| Issue | 理由 |
|-------|------|
| #12 | テスト失敗（詳細: ...） |

### 保留（未実行）
| Issue | 理由 |
|-------|------|
| #14 | 影響範囲が不明 |

### 後始末
完了した Agent worktree は `/worktree clean` で自動削除できます。
```

## 介入ポイント

以下の状況ではユーザーに報告して判断を委ねる:

| 状況 | タイミング |
|------|-----------|
| full プリセットでない | ステップ 1 |
| Issue が1件以下 | ステップ 2 |
| COO が全 Issue を保留に分類 | ステップ 3 |
| ユーザーが実行計画を承認しない | ステップ 4 |
| 個別の /ship が介入ポイントに到達 | ステップ 5 |
| 並列 PR 間でコンフリクト検出 | ステップ 7 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- 介入ポイントではユーザーの指示を待つ（自動でスキップしない）
- 1つの Issue の失敗で他の並列実行を中断しない
- Agent worktree のブランチは PR 作成前に `dev/{Issue番号}_{要約}` にリネームする
