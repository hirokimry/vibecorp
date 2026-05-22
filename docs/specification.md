# 📋 vibecorp プロダクト仕様書

> [!IMPORTANT]
> このドキュメントは vibecorp の **機能スコープの Source of Truth** である。
> プリセット定義 / 提供スキル / フック / エージェント / auto 体験射程 / SKIP 性 / 非機能要件をここで規定する。
> 設計思想・判断根拠（なぜそうしたか）は [`docs/design-philosophy.md`](design-philosophy.md) を SoT とする。

## 👥 読者像

このドキュメントは以下の読者向け。

- 🛠️ **利用者**: vibecorp を導入するプロジェクトオーナー / 開発者。「何ができるか・何を SKIP できるか」を把握したい
- 💻 **開発者**: vibecorp 本体のコントリビューター。「どこに何が定義されているか（SoT）」を把握したい

機能の意味を語る箇所は動作主語、構造の意味を語る箇所は構造主語で書く。

## 🎯 概要

vibecorp は AI エージェントを組織化してプロダクト開発を回すプラグインである。

Claude Code の skills / hooks / agents / rules を一括セットアップし、導入先リポジトリに「開発組織」として機能する AI チームを構築する。

| 観点 | 内容 |
|---|---|
| 🎯 **目的** | Issue 駆動の開発ループを AI に委譲し、ブランチ作成から PR の auto-merge までを一気通貫で実行可能にする |
| 👤 **対象ユーザー** | Claude Code をチーム開発に組み込みたい個人開発者・チーム・AI 企業 |
| 💎 **提供価値** | skills / hooks / agents / rules を一括導入し、プロジェクト横断の開発体験を揃える |
| 🪜 **段階導入** | プリセットによる minimal → standard → full（個人 → チーム → AI 企業） |
| ♻️ **継続的蓄積** | rules / knowledge / docs への自動反映（review-harvest / session-harvest / sync-check） |

## プリセット

組織規模に応じた 3 段階のプリセットを提供する。

ユーザーは `install.sh --preset <preset>` で選択する。

| プリセット | 対象 | 課金モデル | 追加されるもの | auto 体験射程（公式サポート） | auto 体験射程（ユーザー裁量） | sandbox |
|---|---|---|---|---|---|---|
| 🪄 **minimal** | 個人〜小規模 | Claude Max 定額内 | コア skills / 保護系 hooks | 単発 `/vibecorp:ship` → PR → auto-merge | `/loop` による cron 化 | 対象外 |
| 🛡️ **standard** | チーム開発 | Claude Max 定額内 | 知識蓄積 skills / ゲート hooks / CTO・CPO エージェント | minimal + ゲート強制（auto-merge 維持） | `/loop` による cron 化 | 対象外 |
| 🏢 **full** | AI 企業・コンプライアンス重視 | ⚠️ **ANTHROPIC_API_KEY 従量課金に到達しうる** | `/vibecorp:diagnose` skill / C-suite 全員 + 分析員（14 ロール） | 並列 `/vibecorp:ship-parallel` + 単発 `/vibecorp:autopilot` + `/vibecorp:diagnose` | `/loop /vibecorp:autopilot 24h` 等 | macOS のみ推奨・opt-in |

### 🧷 sandbox opt-in の位置づけ

vibecorp は sandbox を **強く推奨するだけで、強制はしない**。

- `full` プリセット + macOS で `install.sh` が `.claude/bin/` と `.claude/sandbox/` を自動配置する
- 有効化は `source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` を **ユーザーが明示的に実行** した場合のみ
- `full` + sandbox OFF で並列実行する場合は「承認ダイアログの多発」または「`.claude/settings.local.json` の allow リスト自己調整」のいずれかで自己責任の運用となる
- 根拠: [`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入)

### 🪜 加算モデル

- ✅ 上位プリセットは下位プリセットの機能を全て含む（加算モデル）
- ⚠️ **full プリセット選択時**: `install.sh` が課金警告を表示する
- 🔒 並列ヘッドレス Claude を起動するスキル（`/vibecorp:autopilot` / `/vibecorp:ship-parallel`）は **full プリセット専用**
  - 課金リスクを伴う大規模並列実行のため、誤爆リスクを抑える目的で minimal / standard では物理的に配置しない
  - 親プロセスの認証が `ANTHROPIC_API_KEY` の場合は API 従量課金に到達しうる
  - 課金モデル詳細は [`docs/cost-analysis.md`](./cost-analysis.md) を参照
- 🍎 macOS の `sandbox-exec` による隔離レイヤは **full + macOS 環境** のとき `install.sh` が `.claude/bin/` と `.claude/sandbox/` を自動配置する（正式サポート）
  - 🧪 Linux（bwrap）対応は Phase 2（#310）で実装済みだが **実験的サポート (experimental)** として位置づける（2026-05-23 #698）。実機検証は利用者環境での opt-in 運用となり、vibecorp 側は検証実施義務を持たない
  - Windows ネイティブは非対応（WSL2 を使用、WSL2 も実験的サポート）

### 🪟 Agent Teams 動作環境

`/vibecorp:ship-parallel` / `/vibecorp:autopilot` は Claude Code の Agent Teams 機能（experimental）に依存する。

| 観点 | 内容 |
|---|---|
| ✅ **対応** | `tmux` または `iTerm2 + it2 CLI` |
| ❌ **非対応** | VS Code 統合ターミナル / Windows Terminal / Ghostty |
| 📍 **出典** | [公式 docs](https://code.claude.com/docs/en/agent-teams#limitations) |

非対応環境で split-pane mode を使うと teammate 承認プロンプトが可視化されず、リモート閲覧からは承認不能となる。

`.claude/settings.json` の `permissions.allow` には公式 docs 推奨の事前登録パスが含まれる。

対象パス:

- `.claude/knowledge/**`
- `.claude/plans/**`
- `.claude/rules/**`
- `.claude/skills/**`
- `~/.cache/vibecorp/{plans,state}/**`

これら領域の teammate 書込は承認要求が発生しない（[Too many permission prompts 推奨](https://code.claude.com/docs/en/agent-teams#too-many-permission-prompts)）。

### 📚 SoT の所在

各プリセットに含まれる具体的なスキル・フック・エージェントの一覧は **本ドキュメントを Source of Truth** とする（後述の「スキル一覧」「フック一覧」「エージェント一覧」セクション）。

`README.md` には概要テーブルと本ドキュメントへのリンクのみ残す。

## SKIP 性マトリクス

`vibecorp.yml` の `hooks:` トグルで明示的に `false` を指定しても **無効化できない hook** をプリセット別に整理する。

保護・ゲート・API バイパス防止・ログの 4 系統は vibecorp の安全性とプロセス強制の根幹であり、SKIP 不可とする。

### 🔢 プラン別 hook 必須性

| hook | minimal | standard | full | 種別 |
|---|:-:|:-:|:-:|---|
| `protect-files` | ✅ 必須 | ✅ 必須 | ✅ 必須 | 🛡️ 保護系 |
| `protect-branch` | ✅ 必須 | ✅ 必須 | ✅ 必須 | 🛡️ 保護系 |
| `block-api-bypass` | ✅ 必須 | ✅ 必須 | ✅ 必須 | 🚧 API バイパス防止系 |
| `command-log` | ✅ 必須 | ✅ 必須 | ✅ 必須 | 📜 ログ系 |
| `sync-gate` | — | ✅ 必須 | ✅ 必須 | 🚪 ゲート系 |
| `review-gate` | — | ✅ 必須 | ✅ 必須 | 🚪 ゲート系 |
| `guide-gate` | — | ✅ 必須 | ✅ 必須 | 🚪 ゲート系 |
| `role-gate` | — | — | ✅ 必須 | 🛡️ 保護系 |
| `diagnose-guard` | — | — | ✅ 必須 | 🛡️ 保護系 |
| `session-harvest-gate` | — | — | — | 🪦 廃止（下記参照） |
| `review-to-rules-gate` | — | — | — | 🪦 廃止（下記参照） |
| `team-auto-approve` | — | — | — | 🪦 廃止（下記参照） |

- ✅ **必須**: そのプリセットで必ず配置され、`hooks:` トグルで `false` にしても `install.sh` が再配置する
- — : そのプリセットでは物理配置されない（SKIP 性の議論対象外）

#### 🪦 廃止された hook

- `session-harvest-gate` / `review-to-rules-gate`: standard プリセットを「知識蓄積の自動強制（ゲート）」から「知識蓄積ツールの提供」に再定義した方針転換に伴い廃止された（後述「[知識蓄積スキルの責務](#知識蓄積スキルの責務)」参照）
  - `/vibecorp:session-harvest` / `/vibecorp:review-harvest` は任意実行スキルとして残る
  - 自動収集は `/vibecorp:autopilot`（full プリセット）に集約される
- `team-auto-approve`: 承認フロー非介入方針（[`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入)）の確定に伴い Issue #336 で完全削除された。後方互換なし

### 🚫 なぜ SKIP 不可か（種別別の理由）

| 種別 | 含まれる hook | SKIP 不可の理由 |
|---|---|---|
| 🛡️ **保護系** | protect-files / protect-branch / role-gate / diagnose-guard | ビジネスルール（MVV / base ブランチ直書き禁止 / エージェント管轄境界 / `/vibecorp:diagnose` 実行中の自己改変防止）の根幹を守る。SKIP すれば設定ファイル誤編集や暴走改変が素通りする |
| 🚪 **ゲート系** | sync-gate / review-gate / guide-gate | プロセス強制（push 前 sync-check / PR 作成前 review / `.claude/` 配下編集前の公式仕様確認）の門番。SKIP すれば品質ゲートが空洞化する |
| 🚧 **API バイパス防止系** | block-api-bypass | `gh api` による直接マージや `@coderabbitai approve` 投稿等、auto-merge 環境のレビュープロセスを迂回する経路をブロックする。SKIP すれば未レビューコードがマージされうる |
| 📜 **ログ系** | command-log | 全 Bash コマンドを `~/.cache/vibecorp/state/<repo-id>/command-log` に記録し、`/vibecorp:approve-audit` の棚卸し対象とする。SKIP すれば許可リスト最適化の入力源が失われる |

`vibecorp.yml` の `hooks:` トグルが効くのは上記マトリクスで「必須」とされていない hook（実質的にユーザー独自に追加した hook、または将来 SKIP 可能として導入される hook）に限る。

## 🧰 機能仕様

### 🧱 コア機能

- ⚙️ **skills/**: Claude Code のスラッシュコマンド（`/vibecorp:ship` / `/vibecorp:plan` / `/vibecorp:review` 等）として Issue 駆動の開発ループを提供する
- 🪝 **hooks/**: `PreToolUse` / `PostToolUse` でファイル保護・ブランチ保護・ゲート制御を行う
  - `guide-gate.sh`（standard 以上）は `.claude/` 配下テンプレートの `Edit` / `Write` / `MultiEdit` 時に `claude-code-guide` エージェントによる公式仕様確認を強制する

### スキル一覧（Source of Truth）

#### minimal プリセット（13 スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:ship` | Issue URL を指定するだけでブランチ作成から PR 作成・auto-merge 設定までを全自動実行 |
| `/vibecorp:plan` | Issue の実装方針を策定し、計画ファイルを `~/.cache/vibecorp/plans/<repo-id>/` に出力 |
| `/vibecorp:plan-review-loop` | 実装計画に対するレビュー → 修正の自動ループ。問題 0 件まで繰り返す |
| `/vibecorp:review` | CodeRabbit CLI + カスタムレビュアーで変更差分をレビュー |
| `/vibecorp:review-loop` | レビュー → 検証 → 修正を指摘ゼロになるまで繰り返す（最大 5 回） |
| `/vibecorp:pr` | GitHub PR を作成・更新。ブランチ名から Issue 番号を自動抽出し、auto-merge を設定 |
| `/vibecorp:pr-fix` | PR の未解決コメントを 1 回修正して push する。単発実行用 |
| `/vibecorp:pr-fix-loop` | PR の状態を `gh pr view` でポーリングし、`MERGED` / `CLOSED` まで同期完遂。`CHANGES_REQUESTED` 検知時は `/vibecorp:pr-fix` を同期呼び出し |
| `/vibecorp:commit` | 変更を分析し、Conventional Commits 形式で自動コミット |
| `/vibecorp:issue` | タイトル・本文からラベルを自動判定し、Assignees を設定して GitHub Issue を起票。standard 以上では起票前に CISO・CPO・SM の 3 者ゲート |
| `/vibecorp:branch` | Issue URL からブランチを自動作成（`dev/{Issue番号}_{要約}` 形式） |
| `/vibecorp:worktree` | git worktree のライフサイクル管理。`list` / `clean` / `remove` / `kill-zombies` |
| `/vibecorp:approve-audit` | コマンドログを棚卸しし、`settings.local.json` の allow リストへの追加を提案・実行 |

#### standard プリセットで追加（6 スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:review-harvest` | マージ済み PR のレビュー指摘を `knowledge/buffer` ブランチに自動収集 |
| `/vibecorp:sync-check` | コード変更に対する docs / knowledge / README.md の整合性チェック（読み取り専用） |
| `/vibecorp:sync-edit` | `/vibecorp:sync-check` で検出された不整合を、各職種エージェントが管轄ファイルのみ編集して修正 |
| `/vibecorp:session-harvest` | セッション中の知見を `knowledge/buffer` ブランチに自動蓄積 |
| `/vibecorp:harvest-all` | コードベース全体を棚卸しし、ドキュメント化されていない暗黙知を docs / rules / knowledge に反映 |
| `/vibecorp:context7` | Context7 CLI 経由でライブラリ・フレームワークの最新ドキュメントを取得・要約 |

#### full プリセットで追加（11 スキル）

| スキル | 説明 |
|---|---|
| `/vibecorp:diagnose` | コードベースを自律的に診断し、改善点を発見 → フィルタリング → GitHub Issue 起票 |
| `/vibecorp:ship-parallel` | 複数 Issue を並列に `/vibecorp:ship` 実行。SM エージェントで依存関係分析 |
| `/vibecorp:autopilot` | `/vibecorp:diagnose` → `/vibecorp:ship-parallel` の自律改善サイクルを 1 回実行 |
| `/vibecorp:plan-epic` | 親エピックの Issue と子 Issue を一括作成し sub-issue で紐付け、feature ブランチを作成 |
| `/vibecorp:release-epic` | feature ブランチから main への集約 PR を作成（全子 Issue マージ後） |
| `/vibecorp:cycle-metrics` | 開発サイクル計測データ（スループット・リードタイム）を `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/` に出力 |
| `/vibecorp:docs-rewrite-all` | `docs/**/*.md` + `README.md` + `CHANGELOG.md` を `.claude/rules/document-writing.md` + `.claude/rules/comment-writing.md` 基準で一括棚卸し。領域別 C\*O 委譲 + diff 提案 → CEO 承認 → 書換の 2 段階で自動マージ禁止 |
| `/vibecorp:prompts-rewrite-all` | `skills/**/SKILL.md` + `.claude/agents/*.md` + `.claude/rules/*.md` を `.claude/rules/prompt-writing.md` + `.claude/rules/comment-writing.md` 基準で一括書き直し。claude-code-guide MUST 参照 + 3 軸検証（frontmatter / triggering / 行動主語）+ diff 提案 → CEO 承認 → 書換 |
| `/vibecorp:comments-rewrite-all` | `**/*.sh` / `**/*.js` / `**/*.ts` / `**/*.py` 等のコード内コメントを `.claude/rules/code-comments.md` 基準で一括書き直し。`node_modules` / `vendor` / 生成コードは除外。diff 提案 → CEO 承認 → 書換の 2 段階で自動マージ禁止 |
| `/vibecorp:notifications-extract-all` | `.github/workflows/**` と `hooks/**` に embed された CEO 向け通知文を `.claude/rules/notification-prompt-extraction.md` 基準で個別 `.md` ファイルに切り出す migration skill。diff 提案 → CEO 承認 → 書換の 2 段階で挙動不変を保証。自動マージ禁止、自律ループ対象外 |
| `/vibecorp:prompts-extract-all` | `skills/**/SKILL.md` に embed されたエージェント呼出プロンプトテンプレを `.claude/rules/notification-prompt-extraction.md` 基準で `skills/<skill>/prompts/<name>.md` に切り出す migration skill。diff 提案 → CEO 承認 → 書換の 2 段階で挙動不変を保証。自動マージ禁止、自律ループ対象外 |

その他、`/vibecorp:audit-cost` / `/vibecorp:audit-security` / `/vibecorp:knowledge-pr` / `/vibecorp:plan-epic` 等の運用補助スキルも full プリセットに同梱される。

### フック一覧（Source of Truth）

#### 🛡️ ファイル保護型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `protect-files.sh` | minimal 以上 | `Edit` / `Write` | `vibecorp.yml` の `protected_files` で指定したファイルの編集をブロック。`MVV.md` はデフォルトで保護対象 |
| `protect-branch.sh` | minimal 以上 | `Edit` / `Write` / `Bash`（git commit） | メインブランチ（base_branch）での `Edit` / `Write` / `git commit` をブロック |
| `role-gate.sh` | full | `Edit` / `Write` | エージェントの管轄外ファイルの編集をブロック。ロールファイル（`~/.cache/vibecorp/state/<repo-id>/agent-role`）に書かれたロール名で判定 |
| `diagnose-guard.sh` | full | `Edit` / `Write` | `/vibecorp:diagnose` 実行中に hooks/*.sh / vibecorp.yml / MVV.md / SECURITY.md / POLICY.md / skills/** / diagnose-guard.sh 自身への変更をブロック。シンボリックリンク経由の bypass は realpath 正規化で塞ぐ |

#### 🚪 ワークフローゲート型

| フック | プリセット | トリガー | ゲート対象 | 解除方法 |
|---|---|---|---|---|
| `sync-gate.sh` | standard 以上 | `Bash`（`git push`） | push | `/vibecorp:sync-check` を実行してスタンプを取得 |
| `review-gate.sh` | standard 以上 | `Bash`（`gh pr create`） | PR 作成 | `/vibecorp:review-loop` または `/vibecorp:review` を実行してスタンプを取得 |
| `guide-gate.sh` | standard 以上 | `Edit` / `Write` / `MultiEdit` | `.claude/` 配下テンプレート編集 | `claude-code-guide` エージェントで仕様確認後にスタンプを取得 |

#### 🚧 API バイパス防止型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `block-api-bypass.sh` | minimal 以上 | `Bash` | `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック |

#### 📜 コマンドログ型

| フック | プリセット | トリガー | 説明 |
|---|---|---|---|
| `command-log.sh` | minimal 以上 | `Bash` | 全 Bash コマンドをログファイル（`~/.cache/vibecorp/state/<repo-id>/command-log`）に記録。判定は返さない（ログのみ） |

### 🚪 ゲートフックとスタンプ

ゲートフックはステートファイル（`~/.cache/vibecorp/state/<repo-id>/*`）で状態管理する。

対応するスキルを実行するとステートが発行され、ゲートが通過可能になる。

ステートは確認後に自動削除される（ワンタイム）。

`<repo-id>` は sanitized basename + sha256 先頭 8 桁で生成され、リポジトリ単位で分離される。保存先は `XDG_CACHE_HOME` 環境変数でカスタマイズ可能（絶対パスのみ有効、XDG Base Directory 仕様準拠）。

| ゲートフック | ブロック対象 | 解除スキル | ステートファイル |
|---|---|---|---|
| `sync-gate.sh` | `git push` | `/vibecorp:sync-check` | `~/.cache/vibecorp/state/<repo-id>/sync-ok` |
| `review-gate.sh` | `gh pr create` | `/vibecorp:review-loop` or `/vibecorp:review` | `~/.cache/vibecorp/state/<repo-id>/review-ok` |
| `guide-gate.sh` | `.claude/` 配下の `Edit` / `Write` / `MultiEdit` | `claude-code-guide` エージェント参照 | `~/.cache/vibecorp/state/<repo-id>/guide-ok` |

ゲートフックは `vibecorp.yml` の `hooks:` セクションで個別に無効化できる（ただし「[SKIP 性マトリクス](#skip-性マトリクス)」で必須とされたものは無効化不可）。

#### 🏷️ guide-gate スタンプの発行

`guide-gate.sh` のスタンプは `claude-code-guide` エージェントで Claude Code 公式仕様を確認した後に発行する。

スタンプは `.claude/lib/common.sh` の `vibecorp_stamp_path` で解決されるパスに `touch` で作成する。

```bash
source .claude/lib/common.sh
STAMP_DIR="$(vibecorp_stamp_mkdir)"
touch "${STAMP_DIR}/guide-ok"
```

スタンプはワンタイム（1 回の `Edit` / `Write` / `MultiEdit` で消費される）。

複数ファイルを編集する場合は編集ごとにスタンプを再発行する必要がある。

### フック登録構造（settings.json）

フックは `settings.json` の `hooks.PreToolUse` に登録される。

`permissions.allow` も同ファイルから配布される。

```json
{
  "permissions": {
    "allow": [
      "Write(.claude/knowledge/**)",
      "Edit(.claude/knowledge/**)",
      "Write(.claude/rules/**)",
      "Edit(.claude/rules/**)",
      "Write(.claude/plans/**)",
      "Edit(.claude/plans/**)",
      "Write(.claude/skills/**)",
      "Edit(.claude/skills/**)"
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

上記は `settings.json.tpl` の主要な内容。

| 観点 | 内容 |
|---|---|
| `permissions.allow` | 実テンプレートではプラットフォーム別パス（`/Users/**` / `/home/**`）も含む |
| プリセット除外 | `install.sh` 実行時にプリセット別で不要なフックエントリを除外 |
| トグル反映 | `vibecorp.yml` の `hooks:` 設定も同様に反映 |
| `permissions` 適用 | プリセットや `vibecorp.yml` に関わらずそのまま適用 |

### 🏗️ リポジトリインフラ設定

vibecorp はスキル・フックに加えて、開発ワークフローを支える以下の設定もテンプレートとして提供する。

#### 🧪 CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を macOS / Ubuntu で自動実行する
- matrix ジョブの結果を `test` ジョブに集約する（Branch Protection の required check として機能）
- `push` + `pull_request` でトリガーし、`concurrency` で重複実行を防止する

#### 🤖 CodeRabbit 設定（`.coderabbit.yaml`）

- `request_changes_workflow: true` — 指摘 0 件なら approve、全 resolve 後に approve へ切替
- `auto_resolve: true` — push 時に修正済みコメントを自動 resolve
- `/vibecorp:pr-fix-loop` のレビュー修正ループに必要な設定

#### 🤖 AI レビューワークフロー（`.github/workflows/ai-review.yml`）

- `claude_action.enabled: true`（デフォルト）時のみ配置される。`false` 設定時は配置されない
- PR の `opened` / `synchronize` / `ready_for_review` でトリガー（`draft` ではコスト節約のため走らない）
- `permissions: contents: read / pull-requests: write / issues: write` の最小権限で動作
- Fork PR は secrets が渡らないため明示的な `if` 条件で除外（多層防御）
- CodeRabbit と並走運用可能（2 つのレビュアーが独立して動作）
- 認証: `CLAUDE_CODE_OAUTH_TOKEN` シークレットが必要（詳細は [`docs/ai-review-auth.md`](ai-review-auth.md)）
- 既存ファイルがある場合は `--update` で 3-way マージ（利用者カスタマイズは保持）
- Issue 側 `intent-label-issue-check.yml` ジョブが `intent/*` ラベルを 0 個または 2 個以上付与された Issue を fail コメント付きで止める（1 Issue 1 intent ルールの機械的強制）
  - 詳細は [`.claude/rules/intent-labels.md`](../.claude/rules/intent-labels.md) と [`docs/conventional-commits.md`](conventional-commits.md) を参照
  - PR には intent ラベルを付与しない（Issue #575 確定: SoT は Issue ラベル）

#### 🥇 AI レビュー Golden Test ワークフロー（`.github/workflows/ai-review-golden-test.yml`）

- `claude_action.enabled: true`（デフォルト）時のみ配置される（`ai-review.yml` と連動）
- claude-code-action のレビュー品質リグレッション検知用（既知 PR の期待結果と実出力を比較）
- `paths` トリガー対象: `REVIEW.md` / `templates/REVIEW.md.tpl` / `.claude/rules/severity/**` / `.claude/rules/review-handling.md` / `.claude/rules/review-observations.md` / `tests/golden/**` の変更時のみ走る
- `permissions: contents: read / pull-requests: read` のみ（コメント投稿しないため `write` 不要）
- Fork PR / draft PR 除外条件あり
- 認証: `CLAUDE_CODE_OAUTH_TOKEN` シークレット必要

> ⚠️ **状態 (Issue #532)**: vibecorp 本体は現在 `claude_action.enabled: false` で運用中（CodeRabbit Bot 単独運用、vibehawk 完成までの暫定措置）。再有効化または利用者運用時の AI レビューワークフロー仕様として本セクションを保持する。

#### ⚙️ GitHub リポジトリ設定

`install.sh` が `gh api` で自動設定を試みる（権限不足時は推奨設定を表示）。

##### Branch Protection（`main` ブランチ）

- **Require a pull request before merging**
- **Require approvals** (1 以上)
- **Dismiss stale approvals when new commits are pushed**
- **Required status checks**: `test`

##### マージ戦略

- ✅ **Allow squash merging** のみ有効化（merge commit / rebase merge は無効化）
- ✅ **Allow auto-merge** 有効化 — required checks + approve 後に自動マージ
- 📝 Default commit message: **Pull request title**

##### ラベル自動作成

`install.sh` が `gh label create` で以下のラベルを自動作成する（既存名は再作成しない）。

詳細は [`docs/conventional-commits.md`](conventional-commits.md) と [`.claude/rules/intent-labels.md`](../.claude/rules/intent-labels.md) を参照。

- 既存系: `bug` / `enhancement` / `documentation` / `question` / `good first issue` / `help wanted` / `design` / `testing` / `refactor` / `priority/high` / `priority/low`
- intent 系（**1 Issue / 1 intent 厳守**、PR には付与しない）: `intent/feature` / `intent/bugfix` / `intent/performance` / `intent/security` / `intent/refactor` / `intent/infra` / `intent/docs`

intent 系は Issue 側 `intent-label-issue-check.yml` ジョブが Issue ラベル付与数を機械的に検知（0 個 / 2 個以上で fail コメント）。

PR には intent ラベルを付与しない（Issue #575 確定: intent の SoT は Issue ラベル）。

レビュー判定（intent × severity）は `pr-fix` / `review-loop` が以下の **4 段フォールバック** で Issue 番号を解決し、`gh issue view --json labels` で intent を直接取得する:

1. `closingIssuesReferences`（GitHub 自動 close キーワード由来）
2. PR 本文 grep（`#N` 形式 + GitHub URL 形式、`pr-issue-link-check.yml` 互換）
3. ブランチ名（`dev/<num>_*` パターン）
4. 空（severity-only fallback: Critical / Major のみ修正対象、Minor 以下スキップ）

### 🪝 インストール時に適用される git config（local）

`install.sh` は導入先リポジトリに以下の **local git config** を自動適用する。

vibecorp の運用方針（Issue 駆動 + squash マージ + 短寿命ブランチ）と整合させ、`git pull origin main` 時に空の merge commit が生成される問題を防ぐ目的。

| 設定 | 値 | 根拠 |
|---|---|---|
| `merge.ff` | `only` | FF 可能時は merge commit を作らず、不可能時はエラー終了で手動判断させる |
| `pull.ff` | `only` | pull で非 FF となる状況でエラー終了し、手動で rebase / merge を選択させる |
| `pull.rebase`（local） | `--unset` | global 側の `pull.rebase merges` 等を活かすため local 値は持たない |

- 設定対象は `--local` スコープのみ（global 設定は変更しない）
- 何度 `install.sh` を実行しても同じ状態に収束する
- 適用箇所: `install.sh` の `setup_git_config()` 関数（`configure_github_repo` の直後で実行）

#### 🔍 `/vibecorp:diagnose` の分析観点（full 限定）

`/vibecorp:diagnose` は以下 4 つの観点でコードベースを並行分析し、改善候補を発見する。

| ステップ | 観点 | 担当 |
|---|---|---|
| 4a | 既存暗黙知の抽出 | `/vibecorp:harvest-all --dry-run` |
| 4b | 技術的負債・テスト不足・スピード/UX | CTO エージェント |
| 4c | MVV / プロダクト方針整合 | CPO エージェント |
| 4d | Claude Code 仕様準拠（hooks / skills / agents / settings.json / *.mcp.json） | `claude-code-guide` エージェント |

4d は Claude Code 公式仕様（`docs.claude.com`）との差分から **仕様ドリフト**（廃止イベント名・非推奨設定キー・新規必須フィールドの未指定等）を検出する。

`claude-code-guide` 利用不可時は 4d をスキップして 4a / 4b / 4c のみで続行する。

`guide-gate.sh`（事前ガード）と本観点（事後ドリフト検出）は補完的な関係にある。

発見された候補は CISO + CPO + SM の 3 者承認ゲートを通過したもののみが起票される。

- 🤝 **agents/**: standard 以上で CTO・CPO 等の役割別エージェントを提供する。full では C-suite + 分析員の合議制で判断する
- 📜 **rules/**: 全エージェントが従うコーディング規約・プロジェクト規約

### 🧰 補助機能

- 📚 **knowledge/**: 役割別エージェントが蓄積する判断記録・ノウハウ（standard 以上）
- ⚙️ **vibecorp.yml / vibecorp.lock**: プロジェクト設定とバージョン固定

### 🚚 インストール / アップデート

- `install.sh` 実行時（`--name` / `--update` 両モード）、旧バージョンで誤って tracked 化されたマシン固有 artifact（現状は `.claude/bin/claude-real`）を `git rm --cached` で自動 untrack する
  - 通常は既存環境の移行時（`--update`）に意味を持つ
- `--no-migrate` オプションで自動 untrack をスキップ可能

#### `--update` の挙動

`install.sh --update` は「vibecorp 管理ファイルの差し替え」と「ユーザー作成ファイルの保護」を両立する。

##### 🔀 3-way マージ

ユーザーがカスタマイズしたファイルに対してテンプレートも更新されていた場合、`git merge-file` による 3-way マージが実行される。

1. ベーススナップショット（前回インストール時のテンプレート）をベースとして使用
2. カスタマイズ版とテンプレート新版を自動マージ
3. コンフリクト発生時の挙動:
   - マーカー（`<<<<<<<` / `=======` / `>>>>>>>`）が埋め込まれる
   - 手動解消が必要

##### 🪂 ファイル種別ごとの更新ルール

| ファイル種別 | 更新時の挙動 |
|---|---|
| **hooks** | カスタムなし → 上書き、カスタムあり & テンプレート未変更 → スキップ、両方変更 → 3-way マージ、コンフリクト → マーカー付き出力 |
| **skills** | hooks と同じ（3-way マージ対象） |
| **agents** | 削除して再配置（3-way マージ対象外） |
| **knowledge** | 削除しない（運用中にエージェントが蓄積したデータを保護） |
| **rules** | テンプレート由来の rules を上書き。ユーザー独自追加分は影響なし |
| **docs** | 既存ファイルはスキップ（ユーザーカスタマイズ済みの前提） |
| **settings.json** | vibecorp 管理フックのみ差し替え、ユーザー独自フックは保持 |

##### 🪄 プリセット変更

`--update` 時に `--preset` を指定すると、プリセットの変更が反映される。

`vibecorp.yml` の `preset` 値も更新される。

##### 🧹 旧 consumer 向け tracked artifact の自動 untrack

旧バージョンの `install.sh` は `.claude/bin/claude-real` をマシン固有の絶対パスを含んだファイルとしてリポジトリに書き出し、かつ `.gitignore` への記載漏れにより、誤って `git add` されるケースがあった。

これを修正するため、`install.sh` 実行時に `migrate_tracked_artifacts()` が以下の処理を自動実行する。

- `templates/claude/.gitignore.tpl` の `# ---- machine-specific artifacts ----` マーカー配下にリストされた artifact が tracked 化されていれば `git rm --cached` で untrack
- working tree のファイル実体は保持される
- 対象 artifact が tracked されていない場合は何もしない

##### `--no-migrate` オプション

自動 untrack をスキップしたい場合は `--no-migrate` を付与する。

```bash
path/to/vibecorp/install.sh --update --no-migrate
path/to/vibecorp/install.sh --name my-project --no-migrate
```

`--name` / `--update` の両モードで受け付けるが、通常は既存環境の移行時に意味を持つ。

#### 🧷 plugin メタデータ (`.claude-plugin/plugin.json`) の Source-of-Truth

- vibecorp リポジトリ直下の `.claude-plugin/plugin.json` が plugin メタデータ（`name` / `version` / `description`）の **唯一の Source-of-Truth** である（Claude Code 公式仕様の正規パスに準拠）
- `install.sh` は consumer リポジトリの `.claude-plugin/plugin.json` に SoT を直接コピーする
  - `templates/` 経由の二重管理は drift の原因になるため廃止された（Issue #540）
- リリース時は `.claude-plugin/plugin.json` の `version` だけを bump すればよい。複数箇所の同期は不要

### 🧷 隔離レイヤ

full プリセットでは、OS ごとに隔離レイヤの提供状況が異なる。

- macOS: 実隔離稼働 (正式サポート)
- 🧪 Linux: `bwrap` (bubblewrap) 実隔離が **実験的サポート (experimental)** として稼働。実機検証は 利用者環境での opt-in 運用、vibecorp 側は動作保証義務を持たない (Phase 2 #310 実装、2026-05-23 #698 で experimental に格下げ)
- 🧪 WSL2: Linux 同等 (実験的サポート)
- Windows ネイティブ: 非対応で中断

誤操作・プロンプトインジェクション経由の破壊操作・認証情報窃取に対する防御層として機能する。

詳細な脅威モデルは [`docs/SECURITY.md` の脅威モデル節](SECURITY.md#脅威モデル) を参照。

#### 🧷 プリセット別 権限モデル

| プリセット | 隔離方式 | 提供範囲 |
|---|---|---|
| 🪄 **minimal** | なし | OS 標準のユーザー権限のみ。`protect-files.sh` フックで設定ファイル誤編集を防ぐ |
| 🛡️ **standard** | なし | minimal と同じ |
| 🍎 **full / macOS** | `sandbox-exec` ベース | `.claude/bin/claude` shim 経由で `.claude/sandbox/claude.sb` プロファイルを適用。`~/Library/Application Support/Claude` / `~/.claude` 等を read-only 化 |
| 🐧 **full / Linux**（🧪 experimental） | `bwrap` (bubblewrap) 実隔離（Phase 2 #310 実装済み、2026-05-23 #698 で **実験的サポート** に格下げ） | `bwrap` 不在時は distro 別手順（`apt-get install bubblewrap` / `dnf install bubblewrap` / `apk add bubblewrap`）を表示して中断。<br>`bwrap` 存在時は `.claude/bin/claude` shim で名前空間隔離が稼働。<br>SSH push 利用者は `vibecorp.yml` に `isolation.allow_ssh: true` を追加すると `~/.ssh` が read-only でマウントされる（デフォルト: `false`）。<br>**実験的サポート位置づけ**: 実機検証は 利用者環境での opt-in 運用、vibecorp 側は Linux 実機での動作保証義務を持たない。Phase 2.1 OAuth 動的サイドカー検証（#578）は撤廃済み。 |
| 🪟 **full / Windows ネイティブ** | 非対応 | `install.sh` が exit 2 で中断。WSL2 (Ubuntu 22.04+) 経由で Linux 環境を使用する |

#### ⚠️ 制約

- 隔離レイヤはネットワーク制限を行わない（Anthropic API への通信が必要なため）
- ユーザーが `.claude/bin/` を PATH に通すには `source .claude/bin/activate.sh` を実行する必要がある（自動化は永続化リスクのため行わない）
- OS サポート方針の根拠は [`docs/design-philosophy.md#os-support`](design-philosophy.md#os-support) を参照

### 知識蓄積スキルの責務

| スキル | standard | full |
|---|---|---|
| `/vibecorp:session-harvest` | `/vibecorp:pr` から自動呼出（PR 作成後） | 同上 |
| `/vibecorp:review-harvest` | 手動実行 | `/vibecorp:autopilot` から自動呼出 |
| `/vibecorp:knowledge-pr` | 手動実行 | `/vibecorp:autopilot` から自動呼出 |
| `/vibecorp:sync-check` | 手動実行 | 同上 |
| `/vibecorp:harvest-all` | 手動実行 | 同上（作業ブランチ直接書込フロー、本 Issue スコープ外） |

**コンセプト**: standard プリセットは「知識蓄積の自動強制（ゲート）」ではなく「知識蓄積ツールの提供」。

- ゲートフック（`review-to-rules-gate.sh` / `session-harvest-gate.sh`）は廃止された
- スキルは任意実行可能に格下げ
- 自動収集の価値は full プリセットの `/vibecorp:autopilot` に集約する

**自動反映フロー**: 知見は全て `knowledge/buffer` ブランチに蓄積され、`/vibecorp:knowledge-pr` が Issue 起票 → PR 作成 → auto-merge により main に反映される。

これにより CodeRabbit レビュー・CI・人間の承認ポイントを knowledge の変更にも通す設計を担保する。

main への直接 push は一切発生しない。

| 経路 | buffer 化 | 補足 |
|---|:-:|---|
| `/vibecorp:session-harvest` | ✅ | 自動 |
| `/vibecorp:review-harvest` | ✅ | 自動 |
| `/vibecorp:audit-cost` | ✅ | Issue #442 で対応（`accounting/audit-log/YYYY-QN.md` 追記 + index 1 行サマリ） |
| `/vibecorp:audit-security` | ✅ | Issue #442 で対応（`security/audit-log/YYYY-QN.md` 追記 + index 1 行サマリ） |
| `/vibecorp:sync-edit` | ✅ | Issue #439 で対応（C*O 委任編集の `knowledge/{role}/`） |
| C*O 決定記録（CFO / CTO / CPO / CISO / CLO / SM） | ✅ | Issue #439 で対応（`decisions/{YYYY-QN}.md` / `decisions-index.md`） |
| 分析員監査記録（accounting / security / legal） | ✅ | Issue #442 で対応（`{role}/audit-log/{YYYY-QN}.md` / `audit-log-index.md`） |
| `/vibecorp:cycle-metrics` | ❌ | 揮発データ（`~/.cache/vibecorp/state/<repo-id>/cycle-metrics/YYYY-MM-DD.md` に保存、`.claude/knowledge/` 外） |
| `/vibecorp:harvest-all` | ❌ | ユーザー承認後に直接書込み（`harvest-all-active` スタンプで hook 通過。ただし `audit-log/` と `decisions/` は fail-secure で迂回不可） |

**ガードレール**: `templates/claude/hooks/protect-knowledge-direct-writes.sh`（Edit/Write 層）と `templates/claude/hooks/protect-knowledge-bash-writes.sh`（Bash 層）の 2 層 hook が以下を作業ブランチ直書きから deny する（buffer worktree 経由のみ許可）。

- `.claude/knowledge/{role}/decisions/` / `.claude/knowledge/{role}/decisions-index.md`（C*O 6 ロール: cfo / cto / cpo / ciso / clo / sm）
- `.claude/knowledge/{role}/audit-log/`（分析員 3 ロール: accounting / security / legal の 4 半期集約 + audit-log-index.md）

防御層の構成・Bash 層の検出パターン・harvest-all-active スタンプ仕様・fail-secure 原則の詳細は [`docs/SECURITY.md` の「knowledge ガードレール（多層防御）」](SECURITY.md#knowledge-ガードレール多層防御) を参照。

救済手順は [`docs/migration-knowledge-buffer.md`](migration-knowledge-buffer.md) を参照。

### 🏁 ship のマージ後検証

`/vibecorp:ship` はステップ 10（`/vibecorp:pr-fix-loop`）が MERGED で正常終了した直後に、ステップ 11「マージ後の網羅検証」を実行する。

- Issue 本文と CEO 投稿コメント内のチェックボックスを LLM で main の最終コードと突き合わせて 2 値判定し、完了のみ ✅ に更新する
- 判定不能は未完了として扱う（保守的）
- 未完了があれば Issue を Reopen し、未完了項目（出所表記付き）と各判定の根拠（main の該当ファイル + 行番号 or 不在理由）をコメント追記する
- CEO は同じ Issue URL で `/vibecorp:ship` を再実行することで残作業を実装できる

**検証スコープ**:

| 出所 | 検証対象 | 更新可否 | 備考 |
|---|---|---|---|
| Issue 本文 | ✅ | 可（`gh issue edit`） | 主要対象 |
| CEO（リポジトリオーナー）投稿コメント | ✅ | 可（`gh api PATCH`） | 個人リポジトリのみ。組織リポジトリでは無効化 |
| 共同作業者コメント | ❌ | — | 現状スコープ外（将来拡張余地） |
| bot コメント（CodeRabbit / GHA / Codecov / Dependabot 等） | ❌ | — | レビュー指摘の checklist 等は別軸で扱う |

**プリセット対応**:

全プリセット（minimal / standard / full）対応。

ステップ 11 は既存 Claude Code セッション内の LLM 呼び出しのみで完結し、新規ヘッドレス LLM 呼び出し（`claude -p` / `npx` / `bunx` 等）は追加しない（`autonomous-restrictions.md` §3 抵触回避）。

**再 ship 時の挙動**:

Reopen された Issue を CEO が再 ship した時、`/vibecorp:plan` は本文 + CEO コメントの **⬜ 項目のみ** を計画ファイルに含める（過去の ✅ 項目は信用してスキップ）。

これにより同じ項目を二重実装しない。

過去 ✅ 判定が誤りだった場合は、CEO が手動で ⬜ に戻して再 ship する。

**組織リポジトリでの制約**:

`owner.type == "Organization"` のリポジトリでは、CEO（個人ユーザー）と repo owner（組織アカウント）が一致しないため、CEO コメント検証スコープを無効化する fallback を採用する。

本文のチェックボックスのみを検証対象とし、warning ログを出力する。

将来 `--ceo-login <user>` オプションで明示指定する余地は残す。

### 🪜 エピック運用

大規模な機能開発は「エピック」として運用する。

エピック運用は full プリセット専用。

**ブランチ命名規約:**

| 種別 | パターン | 例 |
|---|---|---|
| 通常 Issue | `dev/{Issue番号}_{要約}` | `dev/123_add_login` |
| 親エピック（feature ブランチ） | `feature/epic-{Issue番号}_{要約}` | `feature/epic-345_plan_epic_skill` |
| エピック配下の子 Issue | `dev/{Issue番号}_{要約}` | `dev/346_ship_epic_child` |

**マージフロー（二段階マージ）:**

1. 子 Issue の PR は親 feature ブランチ（`feature/epic-*`）を base に作成される
2. 全子 Issue がマージされた後、`/release-epic` で feature ブランチから main への PR を作成する

**子 Issue の base 自動判定:**

`/ship` は GitHub API（`/repos/{owner}/{repo}/issues/{番号}/parent`）で sub-issue かどうかを判定する。

- sub-issue の場合、親エピックの feature ブランチを自動的に PR の base に設定する
- sub-issue でない通常 Issue は従来通り default branch を base にする

**関連スキル:**

- `/plan-epic`: 親エピックの Issue・子 Issue を一括作成し sub-issue で紐付ける
- `/ship`: 子 Issue の実装時に親 feature ブランチを自動検出して base に設定する
- `/release-epic`: feature ブランチから main への集約 PR を作成する

## 📐 非機能要件

### ⚡ パフォーマンス

- スキルワークフロー（`/vibecorp:ship` / `/vibecorp:pr-fix-loop` 等）はユーザー対話ターン内で完結する設計を取る（長時間バッチではない）
- 並列スキル（`/vibecorp:ship-parallel` / `/vibecorp:autopilot`）は full プリセット専用とし、`max_issues_per_run` / `max_issues_per_day`（`vibecorp.yml` の `diagnose:` セクション）で実行頻度を制御する
  - 詳細は [`docs/cost-analysis.md`](cost-analysis.md) を参照

### 🔒 セキュリティ

- 🛡️ **承認フロー非介入**: vibecorp は Claude Code の承認フローを書き換える hook（`PreToolUse` で `permissionDecision: "allow"` を返す類）を提供しない
  - 承認はセキュリティの最後の砦であり、本体のガードレールを崩さない
  - 根拠: [`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入)
- 🧷 **sandbox opt-in**: `full` プリセット + macOS では `sandbox-exec` ベースの隔離レイヤを `install.sh` が配置する
  - 有効化は `source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` を **ユーザーが明示的に実行** した場合のみ
  - 強制はしない
- 🚫 **SKIP 不可 hook の堅持**: 保護系 / ゲート系 / API バイパス防止系 / ログ系の hook は `vibecorp.yml` の `hooks:` トグルで無効化できない（前述「[SKIP 性マトリクス](#skip-性マトリクス)」参照）
  - これによりユーザー設定ミスでガードレールが空洞化する経路を塞ぐ
- 🚪 **knowledge ガードレール**: `.claude/knowledge/{role}/decisions/` / `.claude/knowledge/{role}/audit-log/` への作業ブランチ直書きは Edit/Write 層 + Bash 層の 2 層フックで deny される（buffer worktree 経由のみ許可）
  - 詳細は [`docs/SECURITY.md`](SECURITY.md#knowledge-ガードレール多層防御) を参照
- 🛡️ **脅威モデルと信頼境界**: 詳細は [`docs/SECURITY.md`](SECURITY.md#脅威モデル) を参照

### 🚀 可用性

- **承認体験の方針**:
  - `minimal` / `standard` プリセットは素の Claude Code の承認体験に従う（都度承認、sandbox なし）
  - `full` プリセットは sandbox opt-in を推奨し、`--dangerously-skip-permissions` との組み合わせで承認負荷を低減する
  - sandbox OFF で並列実行する場合は承認ダイアログの多発を許容するか、ユーザーが `settings.local.json` の allow リストを自己調整するかの自己責任となる
- 🚀 **auto-merge による自動マージ**: `/vibecorp:ship` / `/vibecorp:pr` は `gh pr merge --auto --squash` を設定し、CI required checks パス + approve 後に GitHub が自動マージする
  - マージ自体に Claude Code セッションは不要（プロセス停止の影響を受けない）
- ♻️ **install.sh の冪等性**: `--name` 初回実行 / `--update` 何度実行しても同じ状態に収束する
  - 途中失敗しても再実行で復旧可能（local git config / Branch Protection / `.coderabbit.yaml` / `vibecorp.lock` 全てが冪等）
  - 詳細は [`docs/design-philosophy.md`](design-philosophy.md) の「`--update` モードの設計判断」を参照

## 🖼️ 画面遷移・データフロー

（画面遷移図やデータフローの概要を記載）

## 📖 用語集

| 用語 | 定義 |
|---|---|
| （用語） | （定義） |
