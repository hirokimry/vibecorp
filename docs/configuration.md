# 設定リファレンス

本ドキュメントは vibecorp の `vibecorp.yml` を中心とした全設定の Source of Truth。`README.md` には概要と一部のクイックリファレンスのみ残し、詳細は本ドキュメントに集約する。

## vibecorp.yml

`install.sh` 実行時に `.claude/vibecorp.yml` が生成される。プロジェクトごとの挙動を制御する中央設定ファイル。

```yaml
# vibecorp.yml — プロジェクト設定
name: your-project        # プロジェクト名
preset: minimal            # プリセット
language: ja               # 回答言語
base_branch: main          # ベースブランチ
protected_files:           # 編集を禁止するファイル
  - MVV.md
coderabbit:
  enabled: true            # CodeRabbit 設定ファイルの生成（true/false）
claude_action:
  enabled: true            # claude-code-action の有効化（true/false）
  skip_paths:              # AI レビュー対象から除外するパス（業界標準）
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"
# guide_gate:
#   extra_paths:            # デフォルトスコープに追加する監視パス
#     - templates/claude/
#     - install.sh
diagnose:
  enabled: true            # /vibecorp:diagnose の有効化
  max_issues_per_run: 7    # 1回の実行で起票する最大 Issue 数
  max_issues_per_day: 14   # 1日あたりの最大 Issue 数
  max_files_per_issue: 10  # 1 Issue あたりの最大対象ファイル数
  scope: ""                # 診断対象パス（空 = 全体）
  forbidden_targets:       # 診断で触れないファイル
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
# plan:
#   review_agents:         # /vibecorp:plan-review-loop で使用するレビューエージェント
#     - architect
#     - security
#     - testing
#     - performance
#     - dx
```

### protected_files

`protect-files.sh` フックにより、ここに指定したファイルは Claude Code からの編集がブロックされる。`MVV.md` はデフォルトで保護対象。

### coderabbit

`coderabbit.enabled` を `false` にすると `.coderabbit.yaml` の生成がスキップされる。

### claude_action

`claude_action.enabled` を `false` にすると claude-code-action による AI レビューが無効化される。`coderabbit.enabled: true` と併用することで CodeRabbit と claude-code-action の並走運用が可能。`skip_paths` で AI レビュー対象から除外するパス（lock ファイル・依存・ビルド成果物等）を指定する。`enabled: true` 時は `install.sh` 実行時に GitHub secrets に `CLAUDE_CODE_OAUTH_TOKEN` が登録されているか確認し、未登録なら警告を出す（詳細は `docs/ai-review-auth.md`）。

`skip_paths` は **単一の入力源** として以下に自動反映される。

- `REVIEW.md` の skip rules セクション（claude-code-action 用）
- `.coderabbit.yaml` の `path_filters`（CodeRabbit 用、各エントリに `!` プレフィックスが付く）

`vibecorp.yml` の値を変更して `--update` を実行すれば両方が一度に書き換わるため、CodeRabbit と claude-code-action の skip 設定が乖離しない。

### guide_gate

`guide-gate.sh` フックの追加監視パス。デフォルトスコープ（`.claude/hooks/`, `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/settings.json`, `*.mcp.json`）に加えて監視したいパスを `extra_paths` で指定する。未設定時はデフォルトスコープのみで動作する。

### diagnose

`/vibecorp:diagnose` スキルの実行制限。`forbidden_targets` で指定したファイルは診断対象から除外される。

### plan.review_agents

`/vibecorp:plan-review-loop` で起動するレビューエージェントを指定する。指定可能な値: `architect`, `security`, `testing`, `performance`, `dx`, `cost`（full 限定）, `legal`（full 限定）。コメントアウトを外して有効化する。

#### プリセット別デフォルト

| プリセット | デフォルト値 |
|-----------|------------|
| minimal | `[architect]` |
| standard | `[architect, security, testing]` |
| full | `[architect, security, testing, performance, dx, cost, legal]` |

### review.custom_commands（オプション）

`/vibecorp:review` スキル実行時に CodeRabbit CLI と並列で実行するカスタムコマンドを定義できる。

```yaml
review:
  custom_commands:
    - name: shellcheck
      command: "shellcheck **/*.sh"
```

デフォルトでは空。定義しなくても `/vibecorp:review` は正常に動作する。

## スキル・フックのトグル設定

プリセットで配置されたスキル・フックは `vibecorp.yml` で個別に無効化できる。

```yaml
skills:
  commit: true
  review-to-rules: false   # 無効化
hooks:
  protect-files: true
  sync-gate: false          # 無効化
```

- **opt-out 方式**: キー省略時は有効。明示的に `false` を指定した場合のみ無効化
- インストール時（初回・`--update` 両方）に評価され、無効化されたファイルはコピー対象から除外
- 無効化されたフックは `settings.json` からも除外される

## 必須 hook（トグルで無効化できない）

一部の必須 hook（保護系・ゲート系・API バイパス防止系・ログ系）は `vibecorp.yml` の `hooks: false` でも無効化できない。詳細は [`docs/specification.md#skip-性マトリクス`](specification.md#skip-性マトリクス) を参照。

## settings.json と permissions

`install.sh` は `.claude/settings.json` を生成し、`permissions.allow` と `hooks` を設定する。`permissions.allow` には公式 docs 推奨の事前登録パスが含まれる。

| 配信内容 | 配信元 |
|---------|--------|
| `permissions.allow` の事前登録（`.claude/knowledge/**` 等） | `settings.json.tpl` |
| プリセット別フックエントリ | プリセットに応じて `install.sh` がフィルタ |

詳細な settings.json 構造とフック登録例は [`docs/specification.md#フック登録構造-settingsjson`](specification.md#フック登録構造-settingsjson) を参照。

## XDG 環境変数

| 環境変数 | 用途 | デフォルト |
|---------|------|-----------|
| `XDG_CACHE_HOME` | スタンプ・state・plans の保存先ルート（絶対パスのみ有効） | `$HOME/.cache` |

`<repo-id>` は sanitized basename + sha256 先頭 8 桁で生成され、リポジトリ単位で分離される。

| 種類 | パス |
|------|------|
| ゲートスタンプ・state | `<XDG_CACHE_HOME>/vibecorp/state/<repo-id>/` |
| 計画ファイル | `<XDG_CACHE_HOME>/vibecorp/plans/<repo-id>/` |

## 関連

- スキル一覧の SoT: [`docs/specification.md`](specification.md)
- AI レビュー認証: [`docs/ai-review-auth.md`](ai-review-auth.md)
- インストール後ディレクトリ構造: [`docs/installation-layout.md`](installation-layout.md)
- 設計思想: [`docs/design-philosophy.md`](design-philosophy.md)
