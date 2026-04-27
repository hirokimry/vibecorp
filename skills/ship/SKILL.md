---
name: ship
description: "Issue URLを指定するだけでブランチ作成からPR作成・auto-merge設定までを全自動で実行する。「/ship」「シップして」「Issue対応して」と言った時に使用。"
---

**ultrathink**

# Issue → PR 全自動スキル

GitHub Issue URL を受け取り、ブランチ作成 → 計画 → レビュー → 実装 → PR → auto-merge 設定までを一気通貫で実行する。マージは auto-merge により GitHub が自動実行する。

## 使用方法

```bash
/vibecorp:ship <Issue URL>
/vibecorp:ship <Issue URL> --worktree <path>
```

## worktree モード

`--worktree <path>` が指定された場合、全操作を指定パス内で実行する。

- **Bash**: 全コマンドを `cd <path> && command` で実行する
- **Read/Write/Edit**: `<path>/` を基準とした絶対パスを使用する
- **サブスキル呼び出し**: `--worktree <path>` を引き継ぐ
- 未指定時は従来通り CWD で実行する（後方互換）

## 前提条件

- 現在のブランチが main（またはベースブランチ）であること（worktree モードでは不要）
- GitHub CLI (`gh`) が認証済みであること

## ワークフロー

### 1. ベースブランチの決定

PR の base ブランチを Issue の sub-issue 関係から決定する。エピック運用（親 feature ブランチに子 PR を集約）と通常 Issue 運用を両立させるため、以下の手順で決定する。

**1-1. owner / repo を取得:**

```bash
gh repo view --json owner,name --jq '.owner.login + "/" + .name'
```

**1-2. parent issue を GitHub API で取得:**

```bash
gh api "/repos/<owner>/<repo>/issues/<番号>/parent" --jq '.number'
```

- gh が `0` で終了し parent number を返した場合 → **sub-issue である**（ステップ 1-3 へ）
- gh が非 `0` で終了した場合（404 等）→ **sub-issue ではない**（ステップ 1-4 へ）

公式仕様: https://docs.github.com/en/rest/issues/sub-issues

**1-3. sub-issue の場合: 親 feature ブランチを探索する:**

ブランチ命名規約に従い `feature/epic-<親番号>_*` を origin から探索する。

```bash
git ls-remote --heads origin "feature/epic-<親番号>_*"
```

- **0 件**: 中断（介入ポイント、CEO に「親エピックの feature ブランチが見つかりません」と報告）
- **2 件以上**: 中断（介入ポイント、候補を列挙して CEO に判断を委ねる）
- **1 件**: そのブランチ名を **完全一致の文字列**（例: `feature/epic-345_plan_epic_skill`）として保持し、base ブランチとする

`gh pr create --head` および `--base` はワイルドカードをサポートしないため、完全一致のブランチ名を変数として保持しておくことが必須となる。

**1-4. sub-issue でない場合: default branch を base とする:**

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

通常 Issue は従来通り default branch（main 等）を base に設定する。

**1-5. 決定した base ブランチを保持:**

ステップ 2（ブランチ作成）と ステップ 9（PR 作成）で再利用する。

### 2. ブランチ作成

現在のブランチが `dev/` プレフィックスで始まる場合、ブランチ作成をスキップする（Agent worktree 等で既にブランチが作成済みのケース）。

**worktree モード**: worktree のブランチを `dev/{Issue番号}_{要約}` にリネームする。

```bash
cd <path> && git branch -m <現在のブランチ名> dev/{番号}_{要約}
```

worktree モードでは worktree 作成時に既に base が決まっているため、ステップ 1 で決定した base ブランチへの切替は行わない（呼出側の責務）。base 判定結果は PR 作成時の `--base` に渡すために保持しておく。

**通常モード**: Issue URL から `dev/{Issue番号}_{要約}` 形式のブランチを作成する。

```bash
gh issue view <Issue URL> --json number,title --jq '.number,.title'
```

タイトルを英語スネークケース2〜4語に要約し、ステップ 1 で決定した base ブランチから派生させる。

```bash
git fetch origin <ステップ1で決定したベースブランチ>
git checkout -b dev/{番号}_{要約} origin/<ステップ1で決定したベースブランチ>
```

これにより sub-issue の場合は親 feature ブランチを起点とする dev ブランチが作られ、PR 差分に他の commit が混入しない。

### 3. 実装計画の策定

Issue の本文・完了条件を読み込み、コードベースを調査して実装計画を作成する。

計画は以下に出力する（`/vibecorp:plan` スキルが `vibecorp_plans_dir` 経由で配置する）:

```text
~/.cache/vibecorp/plans/<repo-id>/{branch_name}.md
```

計画には以下を含める:
- 概要（Issue の要約）
- 影響範囲（変更が必要なファイル・モジュール）
- Phase 分けされたタスク一覧（各タスクにテスト項目を含む）
- 懸念事項

### 4. 計画レビュー・修正ループ

`/vibecorp:plan-review-loop` を実行する（worktree モードでは `--worktree <path>` を引き継ぐ）。

計画ファイルに対して以下のレビュー観点で評価し、問題0件になるまで修正を繰り返す（最大5回）。

**レビュー観点:**
- 網羅性（Issue の完了条件が全て計画に反映されているか）
- 実現可能性（参照しているファイル・関数が実在するか）
- 独立性（タスクが並行実行可能な粒度に分解されているか）
- テスト（各タスクにテスト項目が含まれているか）
- 影響範囲（変更による副作用が考慮されているか）
- 既存パターンとの整合（プロジェクトの規約と矛盾しないか）

### 5. Issue 本文の更新

計画の設計内容で Issue 本文を更新する。既存の💡概要、🎯背景等のセクションは保持し、設計セクションを追加・更新する。

```bash
gh issue edit <番号> --body "<更新後の本文>"
```

### 6. 実装

計画の Phase に従って順にコーディングを行う。

- 各タスクの完了後にテストを実行して通過を確認する
- テストが失敗した場合はその場で修正する
- 全タスク完了後、全体テストを実行する

### 7. コミット

`/vibecorp:commit` で変更をコミットする（worktree モードでは `--worktree <path>` を引き継ぐ）。

- ステージング対象は実装で変更したファイル + 計画ファイル
- Conventional Commits 形式
- Issue 番号をコミットメッセージに含める

### 8. レビュー・修正ループ

`/vibecorp:review-loop` を実行する（worktree モードでは `--worktree <path>` を引き継ぐ）。

コード変更に対してレビュー→修正を繰り返し、問題0件にする（最大5回）。

レビュー指摘を妥当性検証し、修正すべき指摘のみ修正する。修正後はコミットする。

### 9. PR 作成

PR の `--base` には **ステップ 1 で決定したベースブランチ** を渡す。sub-issue の場合は親 feature ブランチ、通常 Issue の場合は default branch となる。

**worktree モード:**

```bash
cd <path> && git push origin HEAD
cd <path> && gh pr create --title "<Issueタイトル>" --body "<PR本文>" --base <ステップ1で決定したベースブランチ>
```

**通常モード:**

```bash
git push origin HEAD
gh pr create --title "<Issueタイトル>" --body "<PR本文>" --base <ステップ1で決定したベースブランチ>
```

**auto-merge の有効化:**

```bash
gh pr merge --squash --auto
```

- PR タイトルは Issue タイトルをそのまま使用
- PR 本文に `close <Issue URL>` を含める
- PR テンプレートがあればそれに従う

### 10. レビュー修正ループ

`/vibecorp:pr-fix-loop` を実行する（worktree モードでは `--worktree <path>` を引き継ぐ）。

`vibecorp.yml` の `coderabbit.enabled` が `false` の場合、CodeRabbit レビュー待ちはスキップされ、CI パス確認と auto-merge 設定のみ実行される。
マージは auto-merge により、CI パス + approve 後に GitHub が自動実行する。

## 介入ポイント

以下の状況ではユーザーに報告して判断を委ねる:

| 状況 | タイミング |
|------|-----------|
| 親エピックの feature ブランチが見つからない / 複数候補がある | ステップ1 |
| 計画レビューが5回ループしても問題が残る | ステップ4 |
| テストが繰り返し失敗する | ステップ6 |
| コードレビューが5回ループしても問題が残る | ステップ8 |
| CI が失敗する | ステップ10 |
| レビュー修正ループが上限に達する | ステップ10 |

## 結果報告

```text
## /vibecorp:ship 完了

- Issue: #{issue_number}
- PR: #{pr_number}
- ブランチ: dev/{番号}_{要約}
- ベース: {default_branch} または feature/epic-<親番号>_<要約>（sub-issue の場合）
- 計画レビュー: {n}回
- コードレビュー: {n}回
- auto-merge: 設定済み
```

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- **jq では string interpolation `\(...)` を使わない** — Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
- **Bash は 1 コマンド 1 呼び出しに分割する** — `cd ... && cmd | head 2>/dev/null` のように cd + パイプ + リダイレクトを含む compound command は Claude Code 本体の built-in security check（path resolution bypass 検出）で止められるため（参照: #258）。単純な `cd && git ...` は対象外
- 介入ポイントではユーザーの指示を待つ（自動でスキップしない）
