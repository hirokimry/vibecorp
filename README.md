# vibecorp

AIエージェントを組織化してプロダクト開発を回すプラグイン。
どのリポジトリにも導入でき、Claude Code のスキル・フック・エージェント・ルールを一括セットアップする。

## クイックスタート

### 前提条件

- Git
- [jq](https://jqlang.github.io/jq/)
- [GitHub CLI (`gh`)](https://cli.github.com/)
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

### バージョン指定インストール

```bash
# 特定バージョンを指定してインストール
path/to/vibecorp/install.sh --name your-project --version v1.0.0
```

### アップデート

```bash
# vibecorp リポジトリを最新化
cd path/to/vibecorp && git pull

# 導入先リポジトリに移動してアップデート実行
cd your-project
path/to/vibecorp/install.sh --update
```

`--update` 実行時にバージョン差分がある場合、自動的に表示される。

### オプション

| オプション | 説明 | デフォルト |
|---|---|---|
| `--name <name>` | プロジェクト名（必須、英数字とハイフン、1-50文字） | — |
| `--preset <preset>` | 組織プリセット（後述） | `minimal` |
| `--language <lang>` | エージェントの回答言語 | `ja` |
| `--version <version>` | インストールする vibecorp のバージョン（例: `v1.0.0`） | 最新 |
| `--update` | 既存インストールを更新（vibecorp.yml から設定を読み取る） | — |

`--name` と `--update` は同時に指定できない。

## プリセット

組織規模に応じた3つのプリセットを用意している。

| プリセット | スキル | フック | エージェント | ユースケース |
|---|---|---|---|---|
| **minimal** | /review, /review-loop, /pr-review-fix, /pr-review-loop, /pr, /commit, /issue, /ship, /plan, /branch, /plan-review-loop, /ship-parallel, /worktree, /approve-audit | protect-files, protect-branch, block-api-bypass, command-log, team-auto-approve | なし | 個人〜小規模 |
| **standard** | 上記 + /review-to-rules, /sync-check, /sync-edit, /session-harvest, /harvest-all, /context7 | 上記 + review-to-rules-gate, sync-gate, session-harvest-gate, review-gate | CTO, CPO | チーム開発 |
| **full** | 上記 + /diagnose, /autopilot | 上記 + role-gate, diagnose-guard | C-suite全員 + 分析員（14ロール） | AI企業・コンプライアンス重視 |

## インストールされるもの

`install.sh` を実行すると、導入先リポジトリに以下の構造が生成される。

```text
your-project/
├── .claude/
│   ├── hooks/             # フック（ファイル保護・ゲート制御）
│   ├── skills/            # スキル（Claude Code の /コマンド）
│   ├── agents/            # エージェント（standard 以上）
│   ├── knowledge/         # 役割別の判断基準・判断記録（standard 以上）
│   ├── rules/             # コーディング規約
│   ├── vibecorp.yml       # プロジェクト設定
│   ├── vibecorp.lock      # バージョン固定 + マニフェスト
│   ├── settings.json      # フック設定
│   └── CLAUDE.md          # プロジェクト指示
├── docs/                  # 仕様書・設計ドキュメント群
│   ├── POLICY.md
│   ├── SECURITY.md
│   ├── design-philosophy.md
│   ├── specification.md
│   ├── team-permissions.md
│   ├── coderabbit-dependency.md
│   └── file-placement.md
├── .github/
│   ├── ISSUE_TEMPLATE/    # Issue テンプレート
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── config.yml
│   └── workflows/
│       └── test.yml       # CI ワークフロー
├── .coderabbit.yaml       # CodeRabbit 設定
└── MVV.md                 # Mission / Vision / Values
```

- `vibecorp.lock` がマニフェストとして機能し、vibecorp が管理するファイルを追跡する
- `settings.json` はマージ管理：vibecorp 由来フックのみ操作し、ユーザー独自フックは保持

## スキル一覧

### minimal プリセット（14スキル）

| スキル | 説明 |
|---|---|
| `/ship` | Issue URL を指定するだけでブランチ作成から PR 作成・auto-merge 設定までを全自動実行 |
| `/ship-parallel` | 複数 Issue を並列に `/ship` 実行。COO エージェントで依存関係を分析し同時進行 |
| `/plan` | Issue の実装方針を策定し、計画ファイルとして `.claude/plans/` に出力 |
| `/plan-review-loop` | 実装計画に対するレビュー → 修正の自動ループ。問題0件まで繰り返す |
| `/review` | CodeRabbit CLI + カスタムレビュアーで変更差分をレビュー |
| `/review-loop` | レビュー → 検証 → 修正を指摘ゼロになるまで繰り返す（最大5回） |
| `/pr` | GitHub PR を作成・更新。ブランチ名から Issue 番号を自動抽出し、auto-merge を設定 |
| `/pr-review-fix` | PR の未解決コメントを1回修正して push する。単発実行用 |
| `/pr-review-loop` | `/pr-review-fix` を5分間隔で定期実行し、マージまで自動で指摘対応を繰り返す |
| `/commit` | 変更を分析し、Conventional Commits 形式で自動コミット |
| `/issue` | タイトル・本文からラベルを自動判定し、Assignees を設定して GitHub Issue を起票。standard 以上では起票前に CPO エージェントが MVV・プロダクト方針との整合をチェックし、方針に合致しない場合は起票を見送る |
| `/branch` | Issue URL からブランチを自動作成（`dev/{Issue番号}_{要約}` 形式）。`--worktree` オプションで git worktree も同時作成 |
| `/worktree` | git worktree のライフサイクル管理。`list`（一覧）、`clean`（マージ済み削除）、`remove`（手動削除） |
| `/approve-audit` | コマンドログを棚卸しし、`settings.local.json` の allow リストへの追加を提案・実行 |

### standard プリセットで追加（6スキル）

| スキル | 説明 |
|---|---|
| `/review-to-rules` | PR レビュー指摘を分析し、CTO/CPO エージェントが再発防止のため rules / knowledge / docs に反映 |
| `/sync-check` | コード変更に対する docs / knowledge / README.md の整合性チェック（読み取り専用）。各職種エージェントに委任 |
| `/sync-edit` | `/sync-check` で検出された不整合を、各職種エージェントが管轄ファイルのみ編集して修正 |
| `/session-harvest` | セッション中の知見を rules / knowledge / docs に自動反映。マージ前に知識を蓄積する |
| `/harvest-all` | コードベース全体を棚卸しし、ドキュメント化されていない暗黙知を docs / rules / knowledge に反映 |
| `/context7` | Context7 CLI 経由でライブラリ・フレームワークの最新ドキュメントを取得・要約 |

### full プリセットで追加（2スキル）

| スキル | 説明 |
|---|---|
| `/diagnose` | コードベースを自律的に診断し、改善点を発見 → フィルタリング → GitHub Issue 起票。実装は行わない |
| `/autopilot` | `/diagnose` → `/ship-parallel` の自律改善サイクルを1回実行。デフォルトは ship 前にユーザー確認、`--auto` で省略可能。`/loop 12h /autopilot` で定期実行可能 |

## フック一覧

### ファイル保護型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `protect-files.sh` | minimal 以上 | `Edit`/`Write` | `vibecorp.yml` の `protected_files` で指定したファイルの編集をブロック。MVV.md はデフォルトで保護対象 |
| `protect-branch.sh` | minimal 以上 | `Edit`/`Write`/`Bash`（git commit） | メインブランチ（base_branch）での Edit/Write/git commit をブロック |
| `role-gate.sh` | full | `Edit`/`Write` | エージェントの管轄外ファイルの編集をブロック。ロールファイル（`/tmp/.{project}-agent-role`）に書かれたロール名で判定。通常セッション（人間操作時）は制約なし |
| `diagnose-guard.sh` | full | `Edit`/`Write` | `/diagnose` 実行中に hooks/*.sh, vibecorp.yml, MVV.md, diagnose-guard.sh 自身への変更をブロック |

### ワークフローゲート型

| フック | プリセット | トリガー | ゲート対象 | 解除方法 |
|---|---|---|---|---|
| `review-to-rules-gate.sh` | standard 以上 | `Bash`（`gh pr merge`） | PR マージ | `/review-to-rules` を実行してスタンプを取得 |
| `sync-gate.sh` | standard 以上 | `Bash`（`git push`） | push | `/sync-check` を実行してスタンプを取得 |
| `session-harvest-gate.sh` | standard 以上 | `Bash`（`gh pr merge`） | PR マージ | `/session-harvest` を実行してスタンプを取得 |
| `review-gate.sh` | standard 以上 | `Bash`（`gh pr create`） | PR 作成 | `/review-loop` または `/review` を実行してスタンプを取得 |

### API バイパス防止型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `block-api-bypass.sh` | minimal 以上 | `Bash` | `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック。auto-merge 環境でのレビュープロセス迂回を防止 |

### コマンドログ型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `command-log.sh` | minimal 以上 | `Bash` | 全 Bash コマンドをログファイル（`/tmp/.{project}-command-log`）に記録。判定は返さない（ログのみ）。`/approve-audit` で棚卸し・allow リスト追加に使用 |

### 自動承認型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `team-auto-approve.sh` | minimal 以上 | `PreToolUse` | チームモードでの安全なツールコールを自動承認。チームメイトが `settings.local.json` の allow リストを継承しない問題の回避策 |

> **注意**: `team-auto-approve.sh` をカスタマイズする場合、`permissionDecision` には必ず `"allow"` を使用すること。`"approve"` は deprecated であり、Write / Edit 等のツールに対して効果がない。

> **Bash コマンドの安全性判定**: `Bash` ツールに対しては、コマンドを `&&` / `;` で分割した各セグメントを個別に検証する。複合コマンドのいずれかのセグメントが安全でない場合はブロック。サブシェル（`$()` / バッククォート）・パイプ（`|` / `||`）を含むコマンドも通常フローに委ねる。`--rsh` 等の危険フラグを含むコマンドもブロック対象。

## ゲートフックとスタンプ

ゲートフックはスタンプファイル（`/tmp/.{project}-*`）で状態管理する。対応するスキルを実行するとスタンプが発行され、ゲートが通過可能になる。スタンプは確認後に自動削除される（ワンタイム）。

| ゲートフック | ブロック対象 | 解除スキル | スタンプファイル |
|---|---|---|---|
| `sync-gate.sh` | `git push` | `/sync-check` | `/tmp/.{project}-sync-ok` |
| `review-to-rules-gate.sh` | `gh pr merge` | `/review-to-rules` | `/tmp/.{project}-review-to-rules-ok` |
| `session-harvest-gate.sh` | `gh pr merge` | `/session-harvest` | `/tmp/.{project}-session-harvest-ok` |
| `review-gate.sh` | `gh pr create` | `/review-loop` または `/review` | `/tmp/.{project}-review-ok` |

ゲートフックは `vibecorp.yml` の `hooks:` セクションで個別に無効化できる。

## エージェント一覧（full プリセット）

### C-suite（単独判断）

| エージェント | ロール | 管轄 |
|---|---|---|
| `cto.md` | CTO（技術責任者） | コード品質・アーキテクチャ・技術的負債。rules/, knowledge/cto/ を管理 |
| `cpo.md` | CPO（プロダクト責任者） | プロダクト方針・仕様の一貫性。knowledge/cpo/, docs/ を管理 |
| `coo.md` | COO（番頭） | 組織全体の進捗把握・エージェント間調整・次タスク提案・並列実行判定。knowledge/coo/ を管理 |
| `cfo.md` | CFO（最高財務責任者） | コスト分析・API利用量管理。経理チームの合議結果をメタレビュー。knowledge/accounting/ を管理 |
| `clo.md` | CLO（最高法務責任者） | ライセンス・規約・コンプライアンス。法務チームの合議結果をメタレビュー。knowledge/legal/ を管理 |
| `ciso.md` | CISO（最高情報セキュリティ責任者） | セキュリティ。セキュリティチームの合議結果をメタレビュー。knowledge/security/ を管理 |

### 分析員（合議制: 3回独立実行 → C-suite がメタレビュー）

| エージェント | ロール | レビュー先 |
|---|---|---|
| `accounting-analyst.md` | 経理分析員 | コスト管理ポリシー遵守チェック・課金ロジック評価 → CFO |
| `legal-analyst.md` | 法務分析員 | ライセンス・規約チェック・著作権保護 → CLO |
| `security-analyst.md` | セキュリティ分析員 | 脆弱性スキャン・依存パッケージ監査・OWASP Top 10 → CISO |

### 計画レビュー専門家（plan-review-loop から起動）

| エージェント | ロール |
|---|---|
| `plan-architect.md` | 構造設計・責務分離・拡張性のレビュー |
| `plan-security.md` | 脆弱性・認証・認可・入力検証のレビュー |
| `plan-testing.md` | テストカバレッジ・境界値・E2E 設計のレビュー |
| `plan-performance.md` | ボトルネック・スケーラビリティのレビュー |
| `plan-dx.md` | 開発者体験（DX）・エラーハンドリング・可観測性のレビュー |

standard プリセットでは CTO と CPO のみ配置される。

## knowledge ディレクトリ構造

standard 以上のプリセットでインストールされる。エージェントが運用中に判断記録を蓄積する場所。`--update` でも削除されない。

```text
.claude/knowledge/
├── accounting/
│   └── cost-principles.md    # コスト管理ポリシー
├── coo/
│   └── organization.md       # 組織運営ナレッジ
├── cpo/
│   ├── decisions.md          # プロダクト判断記録
│   └── product-principles.md # プロダクト方針
├── cto/
│   ├── decisions.md          # 技術判断記録
│   └── tech-principles.md    # 技術方針
├── legal/
│   └── legal-principles.md   # 法務方針
└── security/
    └── security-principles.md # セキュリティ方針
```

## 設定リファレンス

### vibecorp.yml

インストール時に `.claude/vibecorp.yml` が生成される。

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
diagnose:
  enabled: true            # /diagnose の有効化
  max_issues_per_run: 5    # 1回の実行で起票する最大 Issue 数
  max_issues_per_day: 10   # 1日あたりの最大 Issue 数
  max_files_per_issue: 10  # 1 Issue あたりの最大対象ファイル数
  scope: ""                # 診断対象パス（空 = 全体）
  forbidden_targets:       # 診断で触れないファイル
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
# plan:
#   review_agents:         # /plan-review-loop で使用するレビューエージェント
#     - architect
#     - security
#     - testing
#     - performance
#     - dx
```

#### protected_files

`protect-files.sh` フックにより、ここに指定したファイルは Claude Code からの編集がブロックされる。MVV.md はデフォルトで保護対象。

#### coderabbit

`coderabbit.enabled` を `false` にすると `.coderabbit.yaml` の生成がスキップされる。

#### diagnose

`/diagnose` スキルの実行制限。`forbidden_targets` で指定したファイルは診断対象から除外される。

#### plan.review_agents

`/plan-review-loop` で起動するレビューエージェントを指定する。指定可能な値: `architect`, `security`, `testing`, `performance`, `dx`。コメントアウトを外して有効化する。

#### review.custom_commands（オプション）

`/review` スキル実行時に CodeRabbit CLI と並列で実行するカスタムコマンドを定義できる。

```yaml
review:
  custom_commands:
    - name: shellcheck
      command: "shellcheck **/*.sh"
```

デフォルトでは空。定義しなくても `/review` は正常に動作する。

### スキル・フックのトグル設定

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

## 主要スキルの使い方

### /ship — Issue を全自動で出荷

```bash
/ship <Issue URL>
/ship <Issue URL> --worktree <path>
```

ブランチ作成 → 計画 → レビュー → 実装 → PR → auto-merge 設定までを一気通貫で実行する。最も頻繁に使うスキル。

### /ship-parallel — 複数 Issue を並列出荷

```bash
/ship-parallel <Issue URL 1> <Issue URL 2> [...]
/ship-parallel --all
```

COO エージェントが Issue 群の依存関係を分析し、TeamCreate + worktree で同時進行する。全プリセットで利用可能。

### /diagnose — コードベース自律診断

```bash
/diagnose               # 発見→フィルタ→確認→起票
/diagnose --dry-run     # レポート出力のみ（起票しない）
```

コードベースを自律的に診断し、改善点を GitHub Issue として起票する。実装は行わない（起票と実装の分離で暴走を防止）。full プリセット専用。

### /harvest-all — 全量棚卸し

```bash
/harvest-all
/harvest-all --scope <path>   # 対象パスを限定
/harvest-all --dry-run        # レポートのみ
```

コードベース全体を走査し、ドキュメント化されていない暗黙知を docs / rules / knowledge に反映する。初期導入時や定期棚卸しに使用。

### /review-loop — レビュー自動修正

```bash
/review-loop
/review-loop --worktree <path>
```

変更差分に対してレビュー → 検証 → 修正のループを問題0件まで繰り返す。最大5回でループを打ち切り、未解決の指摘一覧を報告する。

### /context7 — 最新ドキュメント取得

```bash
/context7 <ライブラリ名>
/context7 <ライブラリ名> --tokens <トークン数>
```

Context7 CLI (`c7`) 経由でライブラリ・フレームワークの最新ドキュメントを取得する。古い知識やハルシネーションに基づくコード生成のリスクを軽減する。

## --update の挙動

`install.sh --update` は「vibecorp 管理ファイルの差し替え」と「ユーザー作成ファイルの保護」を両立する。

### 3-way マージ

ユーザーがカスタマイズしたファイルに対してテンプレートも更新されていた場合、`git merge-file` による 3-way マージが実行される。

1. ベーススナップショット（前回インストール時のテンプレート）をベースとして使用
2. カスタマイズ版とテンプレート新版を自動マージ
3. コンフリクト発生時はマーカー（`<<<<<<<`, `=======`, `>>>>>>>`）が埋め込まれ、手動解消を促す

### ファイル種別ごとの更新ルール

| ファイル種別 | 更新時の挙動 |
|---|---|
| **hooks** | カスタムなし→上書き、カスタムあり＆テンプレート未変更→スキップ、両方変更→3-way マージ、コンフリクト→マーカー付き出力 |
| **skills** | hooks と同じ（3-way マージ対象） |
| **agents** | 削除して再配置（3-way マージ対象外） |
| **knowledge** | 削除しない（運用中にエージェントが蓄積したデータを保護） |
| **rules** | テンプレート由来の rules を上書き。ユーザー独自追加分は影響なし |
| **docs** | 既存ファイルはスキップ（ユーザーカスタマイズ済みの前提） |
| **settings.json** | vibecorp 管理フックのみ差し替え、ユーザー独自フックは保持 |

### プリセット変更

`--update` 時に `--preset` を指定すると、プリセットの変更が反映される。vibecorp.yml の `preset` 値も更新される。

## フック登録構造（settings.json）

フックは `settings.json` の `hooks.PreToolUse` に登録される。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/diagnose-guard.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/role-gate.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/command-log.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-api-bypass.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/review-to-rules-gate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sync-gate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/review-gate.sh" }
        ]
      }
    ]
  }
}
```

上記は `settings.json.tpl` の全内容。プリセットに応じて不要なフックエントリが自動除外される。vibecorp.yml の `hooks:` でトグルした場合も同様に反映される。

> **注**: `session-harvest-gate.sh` と `team-auto-approve.sh` は settings.json ではなく、install.sh の generate_settings_json 関数で動的に登録される。

## リポジトリインフラ設定

vibecorp はスキル・フックに加えて、開発ワークフローを支える以下の設定もテンプレートとして提供する。

### CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を macOS / Ubuntu で自動実行
- matrix ジョブの結果を `test` ジョブに集約（Branch Protection の required check として機能）
- `push` + `pull_request` でトリガー、`concurrency` で重複実行を防止

### CodeRabbit 設定（`.coderabbit.yaml`）

- `request_changes_workflow: true` — 指摘0件なら approve、全 resolve 後に approve へ切替
- `auto_resolve: true` — push 時に修正済みコメントを自動 resolve
- `/pr-review-loop` のレビュー修正ループに必要な設定

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

## PAT セットアップ（update-pr-branches ワークフロー用）

`update-pr-branches` ワークフローは `GITHUB_TOKEN` では `update-branch` API を実行できないため、リポジトリシークレットに PAT を登録する必要がある。

### 1. Fine-grained PAT の作成

1. GitHub → 右上プロフィールアイコン → **Settings**
2. 左サイドバー最下部 → **Developer settings**
3. **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
4. 以下を設定:
   - **Token name**: `vibecorp-update-pr-branches`
   - **Expiration**: 任意（デフォルト 30 days）
   - **Repository access**: **Only select repositories** → 対象リポジトリを選択
   - **Permissions**:
     - **Contents**: Read and write
     - **Pull requests**: Read and write
5. **Generate token** をクリックし、表示されたトークンをコピー

### 2. リポジトリシークレットへの登録

```bash
# 対話入力で設定（履歴に残らない）
gh secret set PAT
```

### 3. 確認

```bash
gh secret list
# PAT が表示されれば OK
```

### 注意事項

- 対話入力を使うこと（コマンド引数にトークンを渡すとシェル履歴に残る）
- トークンが漏洩した場合は即座に revoke して再作成する
- トークンの有効期限が切れたら再作成・再登録が必要
- PAT 未設定の場合、ワークフローは警告を出してスキップする（エラーにはならない）

## 設計思想

詳細は [docs/design-philosophy.md](docs/design-philosophy.md) を参照。

## ライセンス

MIT
