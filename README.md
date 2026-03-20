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
│   ├── vibecorp/          # プラグイン実体（.gitignore 対象）
│   │   ├── hooks/         # フック（ファイル保護等）
│   │   ├── skills/        # スキル定義
│   │   └── VERSION
│   ├── vibecorp.yml       # プロジェクト設定（git 管理）
│   ├── vibecorp.lock      # バージョン固定（git 管理）
│   ├── rules/             # コーディング規約（git 管理）
│   ├── settings.json      # フック設定（git 管理）
│   └── CLAUDE.md          # プロジェクト指示（git 管理）
└── MVV.md                 # Mission / Vision / Values（git 管理）
```

- `install.sh` が導入先の `.gitignore` に `.claude/vibecorp/` を追加する。プラグイン実体のみ git 管理外となり、設定ファイルはチームで共有できる
- `vibecorp.lock` でチーム全員が同じバージョンを使える
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

## 推奨リポジトリ設定

以下の設定は vibecorp 側から制御できないため、GitHub リポジトリ側で手動設定を推奨する。

### マージ戦略

**Settings > General > Pull Requests** で以下を推奨:

- **Allow squash merging** のみ有効化（merge commit, rebase merge は無効化）
- Default commit message: **Pull request title**

squash merge によりブランチ単位で1コミットにまとまり、履歴がクリーンに保たれる。

### ブランチ保護

**Settings > Branches > Branch protection rules** で `main` ブランチに以下を推奨:

- **Require a pull request before merging**
- **Require approvals** (1以上)
- **Require status checks to pass before merging**（CI がある場合）

## 設計思想

詳細は [docs/design-philosophy.md](docs/design-philosophy.md) を参照。

## ライセンス

MIT
