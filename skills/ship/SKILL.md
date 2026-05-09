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

**1-1. owner / repo / 番号 を入力 Issue URL から確定:**

`owner/repo` と `<番号>`（子 Issue 番号）は **必ず入力 Issue URL** から確定する（手元の現在リポジトリに依存しない）。

```bash
# 入力 Issue URL（例: https://github.com/hirokimry/vibecorp/issues/123）をパースして取得
# owner/repo → "hirokimry/vibecorp"
# 番号 → "123"
```

**1-2. parent issue を GitHub API で取得:**

```bash
gh api "/repos/<owner>/<repo>/issues/<番号>/parent" --jq '.number // empty'
```

- jq の出力が数値の場合 → **sub-issue である**（ステップ 1-3 へ）
- jq の出力が空の場合 → **sub-issue ではない**（ステップ 1-4 へ）
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

実装計画の作成は **`/vibecorp:plan` スキルに完全委譲する**。ship は包括オーケストレーション、`/vibecorp:plan` は計画策定の単一責務、という責務分離。

ship 自身は計画策定に必要な情報取得（Issue 本文・完了条件・**全コメント**・コードベース調査）を直接行わない。これらは全て `/vibecorp:plan` の中で行われる:

- Issue 本文・完了条件の取得
- **Issue 全コメントの取得**（`gh api ... --paginate` で 30 件超の Issue でも全件取り込み、bot 投稿は jq フィルタで除外）
- コードベースの調査
- プロンプトインジェクション対策（コメントは外部入力として扱う）
- エラーハンドリング・空コメント・context window 圧迫対策

詳細は `skills/plan/SKILL.md` ステップ 1 を参照。

計画は以下に出力される（`/vibecorp:plan` スキルが `vibecorp_plans_dir` 経由で配置する）:

```text
~/.cache/vibecorp/plans/<repo-id>/{branch_name}.md
```

計画には以下が含まれる:
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

PR 作成は **`/vibecorp:pr` スキルに委譲する**。ship は包括オーケストレーション、`/vibecorp:pr` は PR 作成の単一責務、という責務分離（Issue #519）。

ship 自身は `gh pr create` を直接呼ばない。**Issue から intent ラベルを取得して `--label` で付与する責務、PR タイトル / 本文の生成、base 判定の最終整合などは全て `/vibecorp:pr` の中で行われる**（pr スキル側に既存実装あり）。

**9-1. push して `/vibecorp:pr` を呼ぶ:**

**worktree モード:**

```bash
cd <path> && git push origin HEAD
/vibecorp:pr --close --worktree <path>
```

**通常モード:**

```bash
git push origin HEAD
/vibecorp:pr --close
```

`--close` を渡すことで PR 本文の Issue リンクが `close <Issue URL>` 形式となり、PR マージ時に Issue が自動 close される。

**9-2. base ブランチが ship 側で確定している場合の挙動:**

ステップ 1 で **sub-issue 判定により親 feature ブランチを base に設定** している場合、`/vibecorp:pr` の自動 base 判定（merge-base 推定）と乖離する可能性がある。

`/vibecorp:pr` は最初に `gh pr view --json baseRefName` で既存 PR の baseRefName を取るが、新規 PR の場合は merge-base 推定 → DEFAULT_BRANCH の順で base を決める。sub-issue で親 feature ブランチを base にしたい場合、push 後の HEAD と親 feature ブランチの merge-base が直近となる構造のため、通常は merge-base 推定が正しく親 feature ブランチを選ぶ。

選ばれない場合は介入ポイント（CEO に報告）。

**9-3. auto-merge の有効化:**

`/vibecorp:pr` は内部で auto-merge を有効化する（呼び出し時に `gh pr merge --squash --auto` が実行される）。リポジトリ設定で auto-merge が無効、または CEO 指示で auto-merge を設定しない場合、`/vibecorp:pr` の挙動に従う。

ship 自身は `gh pr merge` を呼ばない（責務分離）。

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
