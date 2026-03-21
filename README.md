# vibecorp

AIエージェントを組織化してプロダクト開発を回すプラグイン。
どのリポジトリにも導入でき、Claude Code のスキル・フック・ルールを一括セットアップする。

## クイックスタート

### 前提条件

- Git
- [jq](https://jqlang.github.io/jq/)
- [Claude Code](https://claude.ai/code)

### インストール

```bash
# vibecorp をクローン
git clone https://github.com/hirokimry/vibecorp.git

# 導入先リポジトリに移動
cd your-project

# インストール実行
path/to/vibecorp/install.sh --name your-project
```

### オプション

| オプション | 説明 | デフォルト |
|---|---|---|
| `--name <name>` | プロジェクト名（必須、英数字とハイフン、1-50文字） | — |
| `--preset <preset>` | 組織プリセット（後述） | `minimal` |
| `--language <lang>` | エージェントの回答言語 | `ja` |

## プリセット

組織規模に応じた3つのプリセットを用意している。

| プリセット | スキル | フック | ユースケース |
|---|---|---|---|
| **minimal** | /review, /review-loop, /pr-merge-loop, /pr-review-fix, /pr, /commit | protect-files | 個人〜小規模 |
| **standard** | +/review-to-rules, /sync-check | +review-to-rules-gate, sync-gate | チーム開発 |
| **full** | +/sync-edit | +role-gate | AI企業・コンプライアンス重視 |

現在 `minimal` プリセットのみ利用可能。

## インストールされるもの

`install.sh` を実行すると、導入先リポジトリに以下の構造が生成される。

```text
your-project/
├── .claude/
│   ├── hooks/             # フック（ファイル保護等）
│   ├── skills/            # スキル（Claude Code の /コマンド）
│   ├── rules/             # コーディング規約
│   ├── vibecorp.yml       # プロジェクト設定
│   ├── vibecorp.lock      # バージョン固定 + マニフェスト
│   ├── settings.json      # フック設定
│   └── CLAUDE.md          # プロジェクト指示
├── .github/
│   └── workflows/
│       └── test.yml       # CI ワークフロー
├── .coderabbit.yaml       # CodeRabbit 設定
└── MVV.md                 # Mission / Vision / Values
```

- `vibecorp.lock` がマニフェストとして機能し、vibecorp が管理するファイルを追跡する
- `settings.json` はマージ管理：vibecorp 由来フックのみ操作し、ユーザー独自フックは保持

## 設定リファレンス

### vibecorp.yml

インストール時に `.claude/vibecorp.yml` が生成される。

```yaml
name: your-project        # プロジェクト名
preset: minimal            # プリセット
language: ja               # 回答言語
base_branch: main          # ベースブランチ
protected_files:           # 編集を禁止するファイル
  - MVV.md
```

#### protected_files

`protect-files.sh` フックにより、ここに指定したファイルは Claude Code からの編集がブロックされる。MVV.md はデフォルトで保護対象。

#### review.custom_commands（オプション）

`/review` スキル実行時に CodeRabbit CLI と並列で実行するカスタムコマンドを定義できる。

```yaml
review:
  custom_commands:
    - name: shellcheck
      command: "shellcheck **/*.sh"
```

デフォルトでは空。定義しなくても `/review` は正常に動作する。

## スキル一覧（minimal）

| スキル | 説明 |
|---|---|
| `/review` | CodeRabbit CLI + カスタムレビュアーで差分をレビュー |
| `/review-loop` | レビュー → 修正を指摘ゼロになるまで繰り返す |
| `/pr` | PR 作成 |
| `/pr-review-fix` | PR のレビューコメントを取得し修正 |
| `/pr-merge-loop` | レビュー修正 → Approve → マージまで自動ループ |
| `/commit` | Conventional Commits 形式で自動コミット |

## リポジトリインフラ設定

vibecorp はスキル・フックに加えて、開発ワークフローを支える以下の設定もテンプレートとして提供する。

### CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を macOS / Ubuntu で自動実行
- matrix ジョブの結果を `test` ジョブに集約（Branch Protection の required check として機能）
- `push` + `pull_request` でトリガー、`concurrency` で重複実行を防止

### CodeRabbit 設定（`.coderabbit.yaml`）

- `request_changes_workflow: true` — 指摘0件なら approve、全 resolve 後に approve へ切替
- `auto_resolve: true` — push 時に修正済みコメントを自動 resolve
- `/pr-merge-loop` の自動マージループに必要な設定

### GitHub リポジトリ設定

以下は `install.sh` が `gh api` で自動設定を試みる（権限不足時は推奨設定を表示）:

#### Branch Protection（`main` ブランチ）

- **Require a pull request before merging**
- **Require approvals** (1以上)
- **Dismiss stale approvals when new commits are pushed**
- **Required status checks**: `test`

#### マージ戦略

- **Allow squash merging** のみ有効化（merge commit, rebase merge は無効化）
- **Allow auto-merge** 有効化 — required checks + approve 後に自動マージ
- Default commit message: **Pull request title**

## 設計思想

詳細は [docs/design-philosophy.md](docs/design-philosophy.md) を参照。

## ライセンス

MIT
