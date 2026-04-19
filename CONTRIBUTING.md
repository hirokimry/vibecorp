# コントリビューションガイド

vibecorp への貢献方法と、開発時に守るべきルールをまとめたガイドです。

## 開発フロー

1. `main` ブランチを最新化する
2. `dev/{Issue番号}_{要約}` ブランチを作成する
3. 実装・テストを行う
4. PR を作成する（Conventional Commits 形式）

## CI 実行ポリシー

GitHub Actions のコスト削減のため、`test.yml` のプラットフォーム matrix はトリガー別に分かれています。

| トリガー | 実行プラットフォーム |
|----------|----------------------|
| `pull_request` | `ubuntu-latest` のみ |
| `push: main` | `ubuntu-latest` + `macos-latest` |
| `schedule` (JST 02:00 nightly) | `macos-latest` のみ |
| `workflow_dispatch` | `ubuntu-latest` + `macos-latest` |

macOS GitHub runner は Ubuntu 比で分単価が 10 倍課金されるため、PR CI では Ubuntu のみを走らせています。macOS 固有リグレッションは push:main と nightly schedule で捕捉します。

### macOS 固有パスを変更する PR の手動実行

`test_isolation_macos.sh` など macOS 固有の挙動に依存するテスト・フック・スクリプトを変更する PR では、**PR 作成者が Actions タブから `test` workflow を `workflow_dispatch` で手動実行すること**。手順:

1. GitHub の Actions タブから `test` workflow を開く
2. 右上の `Run workflow` をクリック
3. 対象 PR のブランチを選択して実行
4. macOS ジョブがパスすることを確認してから PR をマージする

macOS 固有でない変更（POSIX sh / `mktemp` 等の共通パターン）では Ubuntu の PR CI のみで十分です。

## 新規ファイル追加チェックリスト

テンプレートに新しいファイル（hook, skill, agent, rule, doc, knowledge, issue_template）を追加する際は、以下の全項目を確認してください。

### 1. テンプレートにファイルを配置する

```text
templates/
├── claude/
│   ├── hooks/         ← hook スクリプト
│   ├── skills/        ← スキル定義（1スキル1ディレクトリ）
│   ├── agents/        ← エージェント定義
│   ├── rules/         ← コーディング規約
│   └── knowledge/     ← エージェント別ナレッジ
├── docs/              ← 公式ポリシー・仕様（.tpl 拡張子）
└── .github/
    └── ISSUE_TEMPLATE/ ← Issue テンプレート
```

### 2. `COPIED_*` 変数への追記が必要か確認する

`install.sh` は一部のファイル種別でコピー実績を `COPIED_*` 変数に記録し、`vibecorp.lock` に正確なファイル一覧を書き出しています。

| ファイル種別 | lock 判定方式 | `COPIED_*` 変数 |
|---|---|---|
| hooks | テンプレート存在 + 配置先存在 | 不要 |
| skills | テンプレート存在 + 配置先存在 | 不要 |
| agents | テンプレート存在 + 配置先存在 | 不要 |
| rules | コピー実績で判定 | `COPIED_RULES` |
| docs | コピー実績で判定 | `COPIED_DOCS` |
| knowledge | コピー実績で判定 | `COPIED_KNOWLEDGE` |
| issue_templates | コピー実績で判定 | `COPIED_ISSUE_TEMPLATES` |

**rules / docs / knowledge / issue_templates** を追加する場合、コピー処理で `COPIED_*` 変数に追記されていることを確認してください。この変数が正しくないと、lock に登録されず `--update` 時の管理対象から漏れます。

詳細は `.claude/knowledge/cto/install-traps.md` の「COPIED_* 変数による lock 精度」を参照してください。

### 3. プリセット別の削除リストを更新する

`install.sh` の `case "$PRESET"` ブロックで、minimal / standard プリセットに不要なファイルの削除が行われています。新しいファイルを追加したら、各プリセットで必要かどうかを判断し、不要な場合は削除リストに追記してください。

### 4. `--update` 時の挙動を確認する

ファイル種別によって `--update` 時の挙動が異なります。

| ファイル種別 | `--update` 時の挙動 |
|---|---|
| hooks / skills | 上書きする（テンプレートが source of truth） |
| agents | 既存ファイルがあればスキップ |
| knowledge | 削除しない（ユーザーが蓄積したデータ） |
| docs | 既存ファイルはスキップ |
| rules | 上書きする |

新規ファイルの種別がこの挙動に合っているか確認してください。

### 5. テストを追加する

`tests/` 配下に対応するテストを追加してください。

- テストファイルは `test_*.sh` の命名規則に従う
- 新規 hook を追加した場合は必ずテストケースを同時追加する
- 既存テストが壊れていないか確認する

### 6. ドキュメントを更新する

以下のドキュメントに影響がないか確認し、必要に応じて更新してください。

- `README.md` — 機能一覧に追加が必要か
- `docs/file-placement.md` — 配置ポリシーに変更が必要か
- `.claude/knowledge/cto/install-traps.md` — install.sh の仕様上の注意点に追記が必要か

## ファイル配置の原則

ファイルをどこに置くか迷った場合は `docs/file-placement.md` を参照してください。

## コーディング規約

`.claude/rules/` 配下のルールファイルに全規約が定義されています。主なルールは以下の通りです。

- **言語**: コード内コメント・ログメッセージ・エラーメッセージは全て日本語
- **Markdown**: フェンスコードブロックには必ず言語指定を付ける
- **コメント**: 設定ファイルのコメントは設定キーの公式な意味を正確に記述する
- **テスト**: hooks やスクリプトを追加・変更した場合は対応するテストを書く
- **シェルスクリプト**: `.claude/rules/shell.md` のパターンに従う
