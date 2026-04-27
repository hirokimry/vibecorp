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

### プラグインのセットアップ（初回のみ）

インストール後、Claude Code を起動して以下を実行する:

```bash
/plugin marketplace add hirokimry/vibecorp
/plugin install vibecorp@vibecorp --scope project
```

これにより `/vibecorp:*` スキルが利用可能になる。スキルはプラグインキャッシュ（`~/.claude/plugins/cache/`）から配信されるため、導入先にスキルファイルは配置されない。

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

### 隔離レイヤの有効化（full プリセット・macOS のみ）

`full` プリセット + macOS 環境で `install.sh` を実行すると、`.claude/bin/` と `.claude/sandbox/` に macOS `sandbox-exec` ベースの隔離レイヤが自動配置される。

有効化は opt-in（環境変数）で行う。bash / zsh のセッションで以下を実行する:

```bash
# PATH の先頭に .claude/bin を追加
source .claude/bin/activate.sh

# 隔離を有効化（Claude プロセスが sandbox-exec 経由で起動される）
export VIBECORP_ISOLATION=1
```

永続化したい場合は `~/.zshrc` / `~/.bashrc` に上記 2 行を追記する（プロジェクトの絶対パスで `source` する）。

**動作確認:**

```bash
# shim のパスが返れば有効
which claude
# => /path/to/your-project/.claude/bin/claude
```

- fish 等の他シェルは未対応（bash / zsh のみ）
- Windows ネイティブは非対応（WSL2 を使用）
- Linux（bwrap 対応）は Phase 2 で対応予定

### Agent Teams 動作環境（公式 docs 記述）

`/vibecorp:ship-parallel` / `/vibecorp:autopilot` は Claude Code の Agent Teams 機能（[公式 docs](https://code.claude.com/docs/en/agent-teams)）に依存する。Anthropic は Agent Teams を **experimental** と明記しており、セッション再開・タスク調整・シャットダウン挙動に既知の制約がある。

#### 公式 docs に明記されている動作要件

- **In-process mode**: `works in any terminal, no extra setup required`
- **Split-pane mode**: `requires either tmux or iTerm2 with the it2 CLI`

#### 公式 docs に明記されている suggested entrypoint

> `tmux` traditionally works best on macOS. Using `tmux -CC` in iTerm2 is the suggested entrypoint into `tmux`.

#### 公式 docs に明記されている Split-pane mode not supported 環境

> Split-pane mode isn't supported in VS Code's integrated terminal, Windows Terminal, or Ghostty.

根拠: <https://code.claude.com/docs/en/agent-teams#limitations>

#### リモート運用時の注意

非対応環境で split-pane mode を使うと teammate の承認プロンプトが可視化されず、リモート閲覧（スマホ・Web）からは承認不能になる。Issue #369 で観測済み。`.claude/settings.json` の `permissions.allow` には `.claude/knowledge/**` / `.claude/plans/**` / `.claude/rules/**` / `~/.cache/vibecorp/{plans,state}/**` が事前登録されており（[公式 docs の "Too many permission prompts" 推奨](https://code.claude.com/docs/en/agent-teams#too-many-permission-prompts)に基づく）、これら領域の teammate 書込は承認要求が発生しない。

## インストール時に適用される git config（local）

`install.sh` は導入先リポジトリに以下の **local git config** を自動適用する。vibecorp の運用方針（Issue 駆動 + squash マージ + 短寿命ブランチ）と整合させ、`git pull origin main` 時に空の merge commit が生成される問題を防ぐ目的。

| 設定 | 値 | 根拠 |
|---|---|---|
| `merge.ff` | `only` | FF 可能時は merge commit を作らず、不可能時はエラー終了で手動判断させる（空 merge commit の生成を防止） |
| `pull.ff` | `only` | pull で非 FF となる状況（並行作業中など）でエラー終了し、手動で rebase / merge を選択させる |
| `pull.rebase`（local） | `--unset` | global 側の `pull.rebase merges` 等を活かすため local 値は持たない。既に未設定でもエラーにならない（冪等） |

- 設定対象は `--local` スコープのみ（global 設定は変更しない）
- 何度 `install.sh` を実行しても同じ状態に収束する
- 適用箇所: `install.sh` の `setup_git_config()` 関数（`configure_github_repo` の直後で実行）

## プリセット

組織規模に応じた3つのプリセットを用意している。

| プリセット | スキル | フック | エージェント | 課金モデル | ユースケース |
|---|---|---|---|---|---|
| **minimal** | /vibecorp:review, /vibecorp:review-loop, /vibecorp:pr-fix, /vibecorp:pr-fix-loop, /vibecorp:pr, /vibecorp:commit, /vibecorp:issue, /vibecorp:ship, /vibecorp:plan, /vibecorp:branch, /vibecorp:plan-review-loop, /vibecorp:worktree, /vibecorp:approve-audit | protect-files, protect-branch, block-api-bypass, command-log | なし | Claude Max 定額内 | 個人〜小規模 |
| **standard** | 上記 + /vibecorp:review-harvest, /vibecorp:sync-check, /vibecorp:sync-edit, /vibecorp:session-harvest, /vibecorp:harvest-all, /vibecorp:context7 | 上記 + sync-gate, review-gate | CTO, CPO | Claude Max 定額内 | チーム開発 |
| **full** | 上記 + /vibecorp:diagnose, /vibecorp:ship-parallel, /vibecorp:autopilot | 上記 + role-gate, diagnose-guard | C-suite全員 + SM + 分析員（14ロール） | **ANTHROPIC_API_KEY 従量課金に到達しうる**（[詳細](docs/cost-analysis.md#実行モード別の課金モデル)） | AI企業・コンプライアンス重視 |

## インストールされるもの

`install.sh` を実行すると、導入先リポジトリに以下の構造が生成される。

```text
your-project/
├── .claude-plugin/
│   └── plugin.json        # Plugin メタデータ
├── .claude/
│   ├── hooks/             # フック（ファイル保護・ゲート制御）
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
│   ├── ai-organization.md
│   ├── cost-analysis.md
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

### minimal プリセット（13スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:ship` | Issue URL を指定するだけでブランチ作成から PR 作成・auto-merge 設定までを全自動実行 |
| `/vibecorp:plan` | Issue の実装方針を策定し、計画ファイルとして `~/.cache/vibecorp/plans/<repo-id>/` に出力（Claude Code の `.claude/` 書込確認プロンプトを回避するため XDG cache に配置） |
| `/vibecorp:plan-review-loop` | 実装計画に対するレビュー → 修正の自動ループ。問題0件まで繰り返す |
| `/vibecorp:review` | CodeRabbit CLI + カスタムレビュアーで変更差分をレビュー |
| `/vibecorp:review-loop` | レビュー → 検証 → 修正を指摘ゼロになるまで繰り返す（最大5回） |
| `/vibecorp:pr` | GitHub PR を作成・更新。ブランチ名から Issue 番号を自動抽出し、auto-merge を設定 |
| `/vibecorp:pr-fix` | PR の未解決コメントを1回修正して push する。単発実行用 |
| `/vibecorp:pr-fix-loop` | PR の状態を `gh pr view` でポーリングし、`MERGED` / `CLOSED` に達するまで teammate のターン内で同期完遂する。`CHANGES_REQUESTED` 検知時は `/vibecorp:pr-fix` を同期呼び出しして指摘を消化する |
| `/vibecorp:commit` | 変更を分析し、Conventional Commits 形式で自動コミット |
| `/vibecorp:issue` | タイトル・本文からラベルを自動判定し、Assignees を設定して GitHub Issue を起票。standard 以上では起票前に CISO・CPO・SM の3者が認証/暗号/課金/ガードレール/MVV の5分類で安全性と方針整合をチェックし、問題がある場合は起票を見送る |
| `/vibecorp:branch` | Issue URL からブランチを自動作成（`dev/{Issue番号}_{要約}` 形式）。`--worktree` オプションで git worktree も同時作成 |
| `/vibecorp:worktree` | git worktree のライフサイクル管理。`list`（一覧）、`clean`（マージ済み削除）、`remove`（手動削除） |
| `/vibecorp:approve-audit` | コマンドログを棚卸しし、`settings.local.json` の allow リストへの追加を提案・実行 |

### standard プリセットで追加（6スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:review-to-rules` | PR レビュー指摘を分析し、CTO/CPO エージェントが再発防止のため rules / knowledge / docs に反映 |
| `/vibecorp:sync-check` | コード変更に対する docs / knowledge / README.md の整合性チェック（読み取り専用）。各職種エージェントに委任 |
| `/vibecorp:sync-edit` | `/vibecorp:sync-check` で検出された不整合を、各職種エージェントが管轄ファイルのみ編集して修正 |
| `/vibecorp:session-harvest` | セッション中の知見を rules / knowledge / docs に自動反映。マージ前に知識を蓄積する |
| `/vibecorp:harvest-all` | コードベース全体を棚卸しし、ドキュメント化されていない暗黙知を docs / rules / knowledge に反映 |
| `/vibecorp:context7` | Context7 CLI 経由でライブラリ・フレームワークの最新ドキュメントを取得・要約 |

### full プリセットで追加（4スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:diagnose` | コードベースを自律的に診断し、改善点を発見 → フィルタリング → GitHub Issue 起票。実装は行わない |
| `/vibecorp:ship-parallel` | 複数 Issue を並列に `/vibecorp:ship` 実行。SM エージェントで依存関係を分析し同時進行。full プリセット専用（課金リスクを伴う大規模並列実行のため） |
| `/vibecorp:autopilot` | `/vibecorp:diagnose` → `/vibecorp:ship-parallel` の自律改善サイクルを1回実行。全 open Issue を対象に実行（ラベルによる絞り込みなし）。デフォルトは ship 前にユーザー確認、`--auto` で省略可能。`/loop 12h /vibecorp:autopilot` で定期実行可能。full プリセット専用 |

## フック一覧

### ファイル保護型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `protect-files.sh` | minimal 以上 | `Edit`/`Write` | `vibecorp.yml` の `protected_files` で指定したファイルの編集をブロック。MVV.md はデフォルトで保護対象 |
| `protect-branch.sh` | minimal 以上 | `Edit`/`Write`/`Bash`（git commit） | メインブランチ（base_branch）での Edit/Write/git commit をブロック |
| `role-gate.sh` | full | `Edit`/`Write` | エージェントの管轄外ファイルの編集をブロック。ロールファイル（`~/.cache/vibecorp/state/<repo-id>/agent-role`）に書かれたロール名で判定。通常セッション（人間操作時）は制約なし |
| `diagnose-guard.sh` | full | `Edit`/`Write` | `/vibecorp:diagnose` 実行中に hooks/*.sh, vibecorp.yml, MVV.md, diagnose-guard.sh 自身への変更をブロック |

### ワークフローゲート型

| フック | プリセット | トリガー | ゲート対象 | 解除方法 |
|---|---|---|---|---|
| `sync-gate.sh` | standard 以上 | `Bash`（`git push`） | push | `/vibecorp:sync-check` を実行してスタンプを取得 |
| `review-gate.sh` | standard 以上 | `Bash`（`gh pr create`） | PR 作成 | `/vibecorp:review-loop` または `/vibecorp:review` を実行してスタンプを取得 |
| `guide-gate.sh` | standard 以上 | `Edit`/`Write`/`MultiEdit` | `.claude/` 配下テンプレート編集 | `claude-code-guide` エージェントで仕様確認後にスタンプを取得 |

### API バイパス防止型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `block-api-bypass.sh` | minimal 以上 | `Bash` | `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック。auto-merge 環境でのレビュープロセス迂回を防止 |

### コマンドログ型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `command-log.sh` | minimal 以上 | `Bash` | 全 Bash コマンドをログファイル（`~/.cache/vibecorp/state/<repo-id>/command-log`）に記録。判定は返さない（ログのみ）。`/vibecorp:approve-audit` で棚卸し・allow リスト追加に使用 |

### 承認フローへの非介入

vibecorp は Claude Code の承認フロー（permission flow）を書き換える hook を提供しない。並列実行時の承認負荷は sandbox + `--dangerously-skip-permissions` で低減する方針。詳細は [`docs/design-philosophy.md#承認フローへの非介入`](docs/design-philosophy.md#承認フローへの非介入) を参照。

## ゲートフックとスタンプ

ゲートフックはステートファイル（`~/.cache/vibecorp/state/<repo-id>/*`）で状態管理する。対応するスキルを実行するとステートが発行され、ゲートが通過可能になる。ステートは確認後に自動削除される（ワンタイム）。`<repo-id>` は sanitized basename + sha256 先頭8桁で生成され、リポジトリ単位で分離される。保存先は `XDG_CACHE_HOME` 環境変数でカスタマイズ可能（絶対パスのみ有効、XDG Base Directory 仕様準拠）。

| ゲートフック | ブロック対象 | 解除スキル | ステートファイル |
|---|---|---|---|
| `sync-gate.sh` | `git push` | `/vibecorp:sync-check` | `~/.cache/vibecorp/state/<repo-id>/sync-ok` |
| `review-gate.sh` | `gh pr create` | `/vibecorp:review-loop` または `/vibecorp:review` | `~/.cache/vibecorp/state/<repo-id>/review-ok` |
| `guide-gate.sh` | `.claude/` 配下の Edit/Write/MultiEdit | `claude-code-guide` エージェント参照 | `~/.cache/vibecorp/state/<repo-id>/guide-ok` |

ゲートフックは `vibecorp.yml` の `hooks:` セクションで個別に無効化できる。

### guide-gate スタンプの発行

`guide-gate.sh` のスタンプは `claude-code-guide` エージェントで Claude Code 公式仕様を確認した後に発行する。スタンプは `.claude/lib/common.sh` の `vibecorp_stamp_path` で解決されるパスに `touch` で作成する。

```bash
# common.sh を source してスタンプパスを解決
source .claude/lib/common.sh
STAMP_DIR="$(vibecorp_stamp_mkdir)"
touch "${STAMP_DIR}/guide-ok"
```

スタンプはワンタイム（1回の Edit/Write/MultiEdit で消費される）。複数ファイルを編集する場合は編集ごとにスタンプを再発行する必要がある。

## エージェント一覧（full プリセット）

### C-suite（単独判断）

| エージェント | ロール | 管轄 |
|---|---|---|
| `cto.md` | CTO（技術責任者） | コード品質・アーキテクチャ・技術的負債。rules/, knowledge/cto/ を管理 |
| `cpo.md` | CPO（プロダクト責任者） | プロダクト方針・仕様の一貫性。knowledge/cpo/, docs/ を管理 |
| `sm.md` | SM（Scrum Master） | プロセス管理・進捗把握・エージェント間調整・次タスク提案・並列実行判定。knowledge/sm/ を管理 |
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
│   └── cost-principles.md     # コスト管理ポリシー
├── sm/
│   ├── decisions-index.md     # プロセス判断の目次
│   ├── decisions/             # 四半期アーカイブ（関連時のみ読む）
│   └── organization.md        # 組織運営ナレッジ
├── cpo/
│   ├── decisions-index.md     # プロダクト判断の目次
│   ├── decisions/             # 四半期アーカイブ
│   └── product-principles.md  # プロダクト方針
├── cto/
│   ├── decisions-index.md     # 技術判断の目次
│   ├── decisions/             # 四半期アーカイブ
│   └── tech-principles.md     # 技術方針
├── cfo/
│   ├── decisions-index.md     # コスト判断の目次
│   └── decisions/             # 四半期アーカイブ
├── ciso/
│   ├── decisions-index.md     # セキュリティ判断の目次
│   └── decisions/             # 四半期アーカイブ
├── legal/
│   └── legal-principles.md    # 法務方針
└── security/
    └── security-principles.md # セキュリティ方針
```

C*O / SM は全員 `decisions-index.md`（目次）+ `decisions/YYYY-QN.md`（四半期アーカイブ）の2段構成で判断を記録する。詳細は `docs/migration-decisions-index.md` 参照。

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
# guide_gate:
#   extra_paths:            # デフォルトスコープに追加する監視パス
#     - templates/claude/
#     - install.sh
diagnose:
  enabled: true            # /vibecorp:diagnose の有効化
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
#   review_agents:         # /vibecorp:plan-review-loop で使用するレビューエージェント
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

#### guide_gate

`guide-gate.sh` フックの追加監視パス。デフォルトスコープ（`.claude/hooks/`, `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/settings.json`, `*.mcp.json`）に加えて監視したいパスを `extra_paths` で指定する。未設定時はデフォルトスコープのみで動作する。

#### diagnose

`/vibecorp:diagnose` スキルの実行制限。`forbidden_targets` で指定したファイルは診断対象から除外される。

#### plan.review_agents

`/vibecorp:plan-review-loop` で起動するレビューエージェントを指定する。指定可能な値: `architect`, `security`, `testing`, `performance`, `dx`。コメントアウトを外して有効化する。

#### review.custom_commands（オプション）

`/vibecorp:review` スキル実行時に CodeRabbit CLI と並列で実行するカスタムコマンドを定義できる。

```yaml
review:
  custom_commands:
    - name: shellcheck
      command: "shellcheck **/*.sh"
```

デフォルトでは空。定義しなくても `/vibecorp:review` は正常に動作する。

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

### /vibecorp:ship — Issue を全自動で出荷

```bash
/vibecorp:ship <Issue URL>
/vibecorp:ship <Issue URL> --worktree <path>
```

ブランチ作成 → 計画 → レビュー → 実装 → PR → auto-merge 設定までを一気通貫で実行する。最も頻繁に使うスキル。

### /vibecorp:ship-parallel — 複数 Issue を並列出荷

```bash
/vibecorp:ship-parallel <Issue URL 1> <Issue URL 2> [...]
/vibecorp:ship-parallel --all
```

SM エージェントが Issue 群の依存関係を分析し、TeamCreate + worktree で同時進行する。full プリセット専用（課金リスクを伴う大規模並列実行のため、誤爆リスクを抑える目的で minimal/standard では物理配置されない）。

### /vibecorp:diagnose — コードベース自律診断

```bash
/vibecorp:diagnose               # 発見→フィルタ→確認→起票
/vibecorp:diagnose --dry-run     # レポート出力のみ（起票しない）
```

コードベースを自律的に診断し、改善点を GitHub Issue として起票する。実装は行わない（起票と実装の分離で暴走を防止）。full プリセット専用。

### /vibecorp:harvest-all — 全量棚卸し

```bash
/vibecorp:harvest-all
/vibecorp:harvest-all --scope <path>   # 対象パスを限定
/vibecorp:harvest-all --dry-run        # レポートのみ
```

コードベース全体を走査し、ドキュメント化されていない暗黙知を docs / rules / knowledge に反映する。初期導入時や定期棚卸しに使用。

### /vibecorp:review-loop — レビュー自動修正

```bash
/vibecorp:review-loop
/vibecorp:review-loop --worktree <path>
```

変更差分に対してレビュー → 検証 → 修正のループを問題0件まで繰り返す。最大5回でループを打ち切り、未解決の指摘一覧を報告する。

### /vibecorp:context7 — 最新ドキュメント取得

```bash
/vibecorp:context7 <ライブラリ名>
/vibecorp:context7 <ライブラリ名> --tokens <トークン数>
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

### 旧 consumer 向け tracked artifact の自動 untrack

旧バージョンの install.sh は `.claude/bin/claude-real` をマシン固有の絶対パスを含んだファイルとしてリポジトリに書き出し、かつ `.gitignore` への記載漏れにより、誤って `git add` されるケースがあった。これを修正するため、install.sh 実行時に `migrate_tracked_artifacts()` が以下の処理を自動実行する。

- `templates/claude/.gitignore.tpl` の `# ---- machine-specific artifacts ----` マーカー配下にリストされた artifact（現状は `.claude/bin/claude-real`）が tracked 化されていれば `git rm --cached` で untrack する
- working tree のファイル実体は保持される（次回コミットで untrack が git history に反映される）
- 対象 artifact が tracked されていない場合は何もしない

通常は `--update` による既存環境の移行時に untrack 対象が存在するが、新規 `--name` モードでも legacy artifact を tracked 化した consumer が `--update` なしで再インストールしたケースに対応する。

#### --no-migrate オプション

自動 untrack をスキップしたい場合は `--no-migrate` を付与する。

```bash
path/to/vibecorp/install.sh --update --no-migrate
path/to/vibecorp/install.sh --name my-project --no-migrate
```

`--name` / `--update` の両モードで受け付けるが、通常は既存環境の移行時に意味を持つ（新規 `--name` 実行時は untrack 対象がそもそも存在しないケースが大半）。

## フック登録構造（settings.json）

フックは `settings.json` の `hooks.PreToolUse` に登録される。`permissions.allow` も同ファイルから配布される。

```json
{
  "permissions": {
    "allow": [
      "Write(.claude/knowledge/**)",
      "Edit(.claude/knowledge/**)",
      "Write(.claude/rules/**)",
      "Edit(.claude/rules/**)",
      "Write(.claude/plans/**)",
      "Edit(.claude/plans/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/diagnose-guard.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/role-gate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guide-gate.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/command-log.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-api-bypass.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sync-gate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/review-gate.sh" }
        ]
      }
    ]
  }
}
```

上記は `settings.json.tpl` の主要な内容（`permissions.allow` は実テンプレートではプラットフォーム別パス（`/Users/**`、`/home/**`）も含む）。`install.sh` 実行時にプリセット (`minimal` / `standard` / `full`) に応じて不要なフックエントリが除外される。`vibecorp.yml` の `hooks:` でトグルした場合も同様に反映される。`permissions` セクションはプリセットや `vibecorp.yml` に関わらずそのまま適用される。

## リポジトリインフラ設定

vibecorp はスキル・フックに加えて、開発ワークフローを支える以下の設定もテンプレートとして提供する。

### CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を macOS / Ubuntu で自動実行
- matrix ジョブの結果を `test` ジョブに集約（Branch Protection の required check として機能）
- `push` + `pull_request` でトリガー、`concurrency` で重複実行を防止

### CodeRabbit 設定（`.coderabbit.yaml`）

- `request_changes_workflow: true` — 指摘0件なら approve、全 resolve 後に approve へ切替
- `auto_resolve: true` — push 時に修正済みコメントを自動 resolve
- `/vibecorp:pr-fix-loop` のレビュー修正ループに必要な設定

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
