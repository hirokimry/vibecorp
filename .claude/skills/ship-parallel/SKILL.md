---
name: ship-parallel
description: "複数Issueを並列shipするオーケストレーションスキル。COOエージェントで並列判定し、TeamCreate + Agent worktreeで同時実行する。「/ship-parallel」「並列シップ」「まとめてship」と言った時に使用。"
---

**ultrathink**

# 並列 ship オーケストレーション

複数の Issue を並列に `/ship` 実行する。COO エージェントで依存関係を分析し、安全に並列実行できるグループを特定した上で、TeamCreate + Agent worktree を使って同時進行する。

## 使用方法

```bash
/ship-parallel <Issue URL 1> <Issue URL 2> [...]
/ship-parallel --all
```

- Issue URL を複数指定: 指定された Issue のみ対象
- `--all`: open な Issue を全て取得し、COO が選別

## 前提条件

- 現在のブランチがベースブランチ（main または release/* 等）であること
- GitHub CLI (`gh`) が認証済みであること
- ベースブランチが最新であること

## アーキテクチャ

#107 の検証結果に基づき、**TeamCreate + Agent isolation: "worktree"** 方式を採用する。

```text
COO（チームリード）
  ├─ 1. Issue 一覧を分析、並列可能なタスク群を特定
  ├─ 2. TeamCreate でチーム作成
  ├─ 3. 各 Issue に対して Agent(isolation: "worktree") でチームメイト起動
  │     └─ チームメイトが worktree 内で /ship を実行
  ├─ 4. 各チームメイトの完了報告を受信（SendMessage）
  │     └─ 必要に応じて介入（中断・優先度変更・方針変更）
  └─ 5. 結果統合、レポート出力
```

### 方式選定理由（#107 で検証済み）

- Agent worktree 内で `/ship` を含む全スキルが動作することが実機検証済み
- `.claude/`（skills, hooks, settings.json 含む）が自動同期される
- TeamCreate + SendMessage でリアルタイム進捗監視・介入が可能
- 1つのタスクの失敗時に COO が即座に判断できる

## ワークフロー

### 1. Issue 一覧の取得

**URL 直接指定の場合:**

各 URL から Issue 情報を取得する。

```bash
gh issue view <Issue URL> --json number,title,body --jq '{number, title, body}'
```

**`--all` の場合:**

open な Issue を一括取得する。

```bash
gh issue list --state open --json number,title,body,labels --limit 50
```

Issue が1件以下の場合は「並列実行の対象がありません。単一 Issue には `/ship` を使用してください」と報告して終了する。

### 2. COO 分析

Agent ツールで COO の役割を持つエージェントを起動し、Issue 群の並列実行可否を判定する。

エージェントに渡す情報:
- Issue 一覧（番号、タイトル、本文）
- 現在のリポジトリのファイル構造

エージェントから受け取る情報:
- 並列グループ（同時実行可能な Issue の集合）
- 直列チェーン（順序制約のある Issue のリスト）
- 保留（情報不足で判定できない Issue）
- コンフリクトリスク

COO エージェントが Agent ツールの利用可能タイプにない場合は、general-purpose エージェントに COO エージェント定義（`.claude/agents/coo.md`）の内容を渡して代用する。

### 3. 実行計画の提示・ユーザー確認

COO の分析結果をユーザーに提示し、実行の承認を求める。

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

### 4. チーム作成・Agent worktree 起動

承認後、TeamCreate でチームを組成し、各 Issue に対して Agent を起動する。

#### 4a. チーム作成

```text
TeamCreate(team_name: "ship-parallel-{timestamp}")
```

#### 4b. ベースブランチの決定

Issue 本文にベースブランチの指定がある場合はそれを使用する。ない場合は現在のブランチを使用する。

#### 4c. 並列グループの Agent 起動

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

#### 4d. 直列チェーンの順序実行

直列チェーンがある場合、前の Issue の Agent が完了してから次の Issue の Agent を起動する。
SendMessage で前の Agent の完了を確認し、成功していれば次を起動する。

### 5. 進捗監視・結果収集

TeamCreate + SendMessage によるリアルタイム監視:

- 各 Agent の完了報告を SendMessage で受け取る
- エラー発生時は即座に通知される
- 必要に応じて介入が可能（中断・優先度変更・方針変更）

### 6. 結果報告

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
| Issue が1件以下 | ステップ 1 |
| COO が全 Issue を保留に分類 | ステップ 2 |
| ユーザーが実行計画を承認しない | ステップ 3 |
| 個別の /ship が介入ポイントに到達 | ステップ 4 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- 介入ポイントではユーザーの指示を待つ（自動でスキップしない）
- 1つの Issue の失敗で他の並列実行を中断しない
- Agent worktree のブランチは PR 作成前に `dev/{Issue番号}_{要約}` にリネームする
