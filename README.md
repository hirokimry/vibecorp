# vibecorp

🤖 **AI エージェントを役職ごとに組織化する Claude Code プラグイン**

Issue を渡すと、担当の専門役が実装から PR まで自動で回す。
各役職の判断は「知識」として時系列で蓄積される。
その知識を次の開発で読み戻し、チームとして成長していく。

- 🛠️ **対象**: Claude Code を使う開発者・チーム
- 🎯 **解く課題**: AI への指示が毎回その場限りで、知識が蓄積されない
- ⚡ **最短導入**: どのリポジトリにも 2 コマンドで導入できる（`install.sh` → `/plugin install`）

> [!IMPORTANT]
> このドキュメントは **外部 OSS 読者・導入開発者** 向けの入口ガイドです。
> 詳細仕様は [`docs/specification.md`](docs/specification.md) を参照してください。

---

## ⚡ クイックスタート

### 前提条件

- Git
- [jq](https://jqlang.github.io/jq/)
- [GitHub CLI (`gh`)](https://cli.github.com/)
- [Claude Code](https://claude.ai/code)

### インストール

```bash
# 1. vibecorp をクローン
git clone https://github.com/hirokimry/vibecorp.git

# 2. 導入先リポジトリに移動して install を実行
cd your-project
path/to/vibecorp/install.sh --name your-project
```

### プラグインのセットアップ（初回のみ）

インストール後、Claude Code を起動して以下を実行する。

```bash
/plugin marketplace add hirokimry/vibecorp
/plugin install vibecorp@vibecorp --scope project
```

これで `/vibecorp:*` スキルが利用可能になる。
スキルはプラグインキャッシュ（`~/.claude/plugins/cache/`）から配信される。

### よく使うインストールオプション

| オプション | 用途 |
|----------|------|
| `--name <name>` | プロジェクト名（必須、英数字 / ハイフン、1-50 文字） |
| `--preset <preset>` | `minimal` / `standard` / `full`（デフォルト: `minimal`） |
| `--language <lang>` | エージェントの回答言語（デフォルト: `ja`） |
| `--version <version>` | インストールする vibecorp のバージョン（例: `v1.0.0`） |
| `--update` | 既存インストールを更新（`vibecorp.yml` から設定を読む） |

`--name` と `--update` は同時指定不可。全オプション一覧と詳細仕様は [`docs/configuration.md`](docs/configuration.md) を参照。

---

## 🎁 何ができる？

| できること | 動線 |
|------------|----------|
| 🚀 Issue を実装・PR 化・auto-merge まで全自動 | `/vibecorp:ship <Issue URL>` の 1 行 |
| 🎁 個人 → チーム → AI 企業まで段階導入 | プリセット 3 段階（minimal / standard / full） |
| 🔒 品質ゲートが常時稼働 | `vibecorp.yml` でも無効化できない必須 hook |

機能レベルで「〜できるようにしたい」と Issue を渡すだけでよい。
COO が意図を解釈し、適切な担当へ割り振る。
技術は CTO、コストは CFO、安全は CISO、法務は CLO。

---

## ✨ 何がユニークか

標準的な AI コーディング支援との違いは一点。
**判断が「知識」として組織に残り、次の判断に効く**、その一点にある。

- 各役職は判断のたびに、結論・根拠・却下した代替案を記録する。
- 次に呼ばれたとき、その知識を読み戻してから判断する。
- 知識は役職別・時系列で蓄積される。
- 標準メモリーの個人・上書き型の記憶とは別物。

実際にこのリポジトリに蓄積されている知識の一部:

| 役職 | 残っている判断（実物） |
|---|---|
| 🧑‍🔬 CTO | Docker 隔離を撤回し sandbox-exec / bwrap へ転換（却下案: Hyper-V / Firejail） |
| 🔒 CISO | 「攻撃成立にはリポジトリ改ざんが前提」→ High を Minor に格下げ（Issue #318 と一貫） |
| 💰 CFO | `max_issues_per_run` を「3 へ」→ 再判断で「7 へ」自己撤回（月 $840 試算付き） |
| ⚖️ CLO | 「CodeRabbit 完全網羅」表現は廃棄を条件に可と裁定（著作権法 2 条・不正競争防止法 2 条 1 項 3 号） |
| 📋 CPO | Pro プラン新設を No-Go（4 段目は「導入の手軽さ」バリューに反する） |
| 🏃 SM | 7 件の同時並列は不可、最大 3 件並列が安全な上限（install.sh 競合を検出） |

> 📖 仕組みの詳細（役職別 knowledge の構造・読み戻し動線）は [`docs/ai-organization.md`](docs/ai-organization.md) / [`docs/design-philosophy.md`](docs/design-philosophy.md) を参照。
> vibecorp 自身の改善も vibecorp で回しており、上の知識はその過程で各役職が書き残したもの。

---

## 🛡️ 安全に手を離せる土台

自律で動くからこそ、暴走を構造で封じている。詳細は各リンク先を参照。

- ⚠️ **触れてはいけない領域は機械的に締め出す** — 認証 / 暗号 / 課金 / ガードレール / MVV / CI 権限の 6 領域は自律実行の対象外（[`docs/SECURITY.md`](docs/SECURITY.md)）
- 🚦 **意志力に頼らないゲート** — レビュー前の PR 作成・未整合の push を必須 hook が自動で止める（[🪝 フック概要](#-フック概要)）
- 💰 **コスト上限の明文化** — `max_issues_per_run` 等の上限を CFO が監査し証跡を残す（[`docs/cost-analysis.md`](docs/cost-analysis.md)）

---

## 🔄 アップデート

vibecorp の更新は **以下の 3 ステップを順番に実行する** のが正しい手順。

```bash
# 1. vibecorp リポジトリを最新化
cd path/to/vibecorp && git pull

# 2. 導入先リポジトリでインストーラを再実行
cd your-project
path/to/vibecorp/install.sh --update

# 3. Claude Code を起動して、スキル本体を最新版に更新
/plugin update vibecorp --scope project
```

### `install.sh --update` で更新されるもの／されないもの

| 配信経路 | 更新方法 |
|---------|---------|
| hooks / agents / rules / docs / knowledge / lib / settings.json / vibecorp.yml / `.claude-plugin/plugin.json`（version マニフェスト）/ CI workflow | `install.sh --update` |
| **skills（`/vibecorp:*`）** | **`/plugin update vibecorp --scope project`**（プラグインキャッシュ `~/.claude/plugins/cache/` 経由のため別経路） |

`install.sh --update` 実行時にバージョン差分があれば自動で表示される。
`/plugin update` は既に最新の場合「already at the latest version」と返す。
毎回実行しても安全。

3-way マージ・プリセット変更・`--no-migrate` 等の `--update` 詳細仕様は [`docs/specification.md#--update-の挙動`](docs/specification.md#--update-の挙動) を参照。

---

## 🎁 プリセット

組織規模に応じた 3 段階のプリセットを提供する。

| プリセット | 対象 | 課金モデル | 主な追加要素 | sandbox |
|---|---|---|---|---|
| **minimal** | 個人〜小規模 | Claude Max 定額内 | コア skills（13 個）+ 保護系 hooks | 対象外 |
| **standard** | チーム開発 | Claude Max 定額内 | 知識蓄積 skills（6 個）+ ゲート hooks + CTO・CPO エージェント | 対象外 |
| **full** | AI 企業・コンプライアンス重視 | ⚠️ **ANTHROPIC_API_KEY 従量課金に到達しうる** | 並列 / 自律 skills（10 個）+ C-suite 全員 + 分析員（14 ロール）+ 隔離レイヤ | macOS 推奨・opt-in |

### auto 体験射程

| プリセット | 公式サポート | ユーザー裁量 |
|---|---|---|
| **minimal** | 単発 `/vibecorp:ship` → PR → auto-merge | `/loop` による cron 化 |
| **standard** | minimal + ゲート強制（auto-merge 維持） | `/loop` による cron 化 |
| **full** | 並列 `/vibecorp:ship-parallel` + 単発 `/vibecorp:autopilot` + `/vibecorp:diagnose` | `/loop /vibecorp:autopilot 24h` 等 |

vibecorp は sandbox を **強く推奨するだけで強制はしない**。
`full` + sandbox OFF で並列実行する場合、次のいずれかとなる。

- 承認ダイアログが多発する
- ユーザーが `.claude/settings.local.json` の allow リストを自己調整する

自己責任の運用となる。
詳細は [`docs/design-philosophy.md#承認フローへの非介入`](docs/design-philosophy.md#承認フローへの非介入) を参照。

> ⚠️ **必須 hook について**: 一部の必須 hook（保護系・ゲート系・API バイパス防止系・ログ系）は `vibecorp.yml` の `hooks: false` でも無効化できません。詳細は [`docs/specification.md#skip-性マトリクス`](docs/specification.md#skip-性マトリクス) を参照。

### 隔離レイヤ（full + macOS、opt-in）

`full` プリセット + macOS で `install.sh` を実行すると、`.claude/bin/` と `.claude/sandbox/` に macOS `sandbox-exec` ベースの隔離レイヤが自動配置される。有効化は明示的な opt-in:

```bash
source .claude/bin/activate.sh
export VIBECORP_ISOLATION=1
```

永続化したい場合は `~/.zshrc` / `~/.bashrc` に上記 2 行を追記する。

🧪 Linux では `bwrap` (bubblewrap) による実隔離が **実験的サポート (experimental)** として稼働中（Phase 2 `#310` 実装済み、2026-05-23 `#698` で実験的サポートに格下げ）。
正式サポート OS は macOS のみ。Linux 実機での動作検証は利用者環境での opt-in 運用となる。

SSH push 利用者は `vibecorp.yml` に `isolation.allow_ssh: true` を追加する。
これにより `~/.ssh` が read-only でマウントされる。
Windows ネイティブは非対応（WSL2 を使用、WSL2 も実験的サポート）。
詳細は [`docs/design-philosophy.md`](docs/design-philosophy.md)。

---

## 🛠️ スキル一覧（概要）

主要スキルのみ俯瞰として掲載。**全スキルの SoT は [`docs/specification.md#スキル一覧source-of-truth`](docs/specification.md#スキル一覧source-of-truth) を参照**。

### 🚀 minimal（13 スキル — Issue 駆動の開発ループ）

| スキル | 何ができるようになるか |
|---|---|
| `/vibecorp:ship` | Issue URL を渡すだけで PR 化・auto-merge まで全自動 |
| `/vibecorp:plan` | Issue 実装方針を計画ファイルに出力 |
| `/vibecorp:review-loop` | レビュー → 修正を指摘 0 件まで繰り返す |
| `/vibecorp:pr-fix-loop` | PR の指摘を MERGED まで自動修正し続ける |
| `/vibecorp:commit` / `/vibecorp:pr` / `/vibecorp:issue` / `/vibecorp:branch` 等 | Conventional Commits / PR 作成 / Issue 起票 / ブランチ命名規約 |

### 🤝 standard で追加（6 スキル — 知識蓄積と整合性）

| スキル | 何ができるようになるか |
|---|---|
| `/vibecorp:review-harvest` / `/vibecorp:session-harvest` / `/vibecorp:harvest-all` | レビュー・セッションの知見をナレッジに自動蓄積する |
| `/vibecorp:sync-check` / `/vibecorp:sync-edit` | 仕様書と実装の整合性をチェック・自動修正する |
| `/vibecorp:context7` | 外部ライブラリの公式ドキュメントをコンテキストに取り込む |

### 🏢 full で追加（11 スキル — 並列・自律・エピック）

| スキル | 何ができるようになるか |
|---|---|
| `/vibecorp:ship-parallel` / `/vibecorp:autopilot` | 複数 Issue を並列実装・自律的に改善サイクルを回す |
| `/vibecorp:diagnose` | 改善候補を自動検出して Issue 起票する |
| `/vibecorp:plan-epic` / `/vibecorp:release-epic` | エピック単位の計画・リリースを管理する |
| `/vibecorp:cycle-metrics` | 開発サイクルの指標を計測・可視化する |
| `/vibecorp:docs-rewrite-all` / `/vibecorp:prompts-rewrite-all` / `/vibecorp:comments-rewrite-all` | ドキュメント・プロンプト・コード内コメントを基準に沿って一括書き直す |
| `/vibecorp:notifications-extract-all` / `/vibecorp:prompts-extract-all` | workflow / hook / SKILL.md に embed された通知文・プロンプトテンプレを個別 `.md` ファイルに切り出す（migration skill） |

> 📖 **詳細**: 各スキルの引数・挙動・依存関係は [`docs/specification.md#スキル一覧source-of-truth`](docs/specification.md#スキル一覧source-of-truth) に記載。

---

## 🪝 フック概要

`install.sh` がプリセットに応じてフックを配置する。詳細は [`docs/specification.md#フック一覧source-of-truth`](docs/specification.md#フック一覧source-of-truth) を参照。

| 系統 | 主なフック | 役割 |
|---|---|---|
| 🔒 ファイル保護型 | `protect-files.sh` / `protect-branch.sh` / `role-gate.sh` / `diagnose-guard.sh` | 設定ファイル誤編集・base ブランチ直書き・管轄外編集を防ぐ |
| 🚦 ワークフローゲート型 | `sync-gate.sh` / `review-gate.sh` / `guide-gate.sh` | push 前 sync-check / PR 前 review / `.claude/` 編集前の公式仕様確認を強制 |
| 🛑 API バイパス防止型 | `block-api-bypass.sh` | `gh api` 直接マージや `@coderabbitai approve` 投稿を遮断 |
| 📊 コマンドログ型 | `command-log.sh` | 全 Bash コマンドを記録し `/vibecorp:approve-audit` の入力源にする |

> 🔐 **承認フロー非介入**
>
> vibecorp は Claude Code の承認フローを書き換える hook を提供しない。
> 並列実行時の承認負荷は sandbox と `--dangerously-skip-permissions` で低減する。
>
> 詳細: [`docs/design-philosophy.md#承認フローへの非介入`](docs/design-philosophy.md#承認フローへの非介入)

---

## 🤖 エージェント概要（standard 以上）

`.claude/agents/` に role 別エージェントが配置され、各 C\*O / 分析員 / 計画レビュー専門家として動作する。

| 階層 | 役割 |
|---|---|
| 👔 **C-suite**（CTO / CPO / SM / CFO / CLO / CISO） | 各領域の単独判断（standard は CTO・CPO のみ、full で全員配置） |
| 📊 **分析員**（accounting / security / legal） | 3 回独立実行 → C-suite がメタレビューする合議制（full 限定） |
| 🔍 **計画レビュー専門家**（plan-architect / plan-security / plan-testing / plan-performance / plan-dx / plan-cost / plan-legal） | `/vibecorp:plan-review-loop` から起動して計画品質を多角チェック |

> 📖 **詳細一覧**: [`docs/ai-organization.md#エージェント一覧full-プリセット`](docs/ai-organization.md#エージェント一覧full-プリセット)

---

## 📚 詳細ドキュメント

| 知りたいこと | 参照先 |
|------------|-------|
| 🧩 全スキル / フック / エージェントの仕様 | [`docs/specification.md`](docs/specification.md) |
| ⚙️ `vibecorp.yml` 全設定キー | [`docs/configuration.md`](docs/configuration.md) |
| 📁 インストール後のディレクトリ構造 | [`docs/installation-layout.md`](docs/installation-layout.md) |
| 🤖 組織思想・C\*O ゲート・エージェント詳細 | [`docs/ai-organization.md`](docs/ai-organization.md) |
| 🎨 設計判断の根拠（なぜそうしたか） | [`docs/design-philosophy.md`](docs/design-philosophy.md) |
| 💰 コスト構造・課金モデル | [`docs/cost-analysis.md`](docs/cost-analysis.md) |
| 🔐 セキュリティポリシー・脅威モデル | [`docs/SECURITY.md`](docs/SECURITY.md) |
| 🔑 AI レビュー認証・PAT セットアップ | [`docs/ai-review-auth.md`](docs/ai-review-auth.md) |
| 📜 Conventional Commits + intent ラベル | [`docs/conventional-commits.md`](docs/conventional-commits.md) |
| 🏗️ 新プリセット追加時のチェックリスト | [`docs/preset-addition-checklist.md`](docs/preset-addition-checklist.md) |
| ⛔ 既知の制約 | [`docs/known-limitations.md`](docs/known-limitations.md) |

---

## 🎨 設計思想

詳細は [`docs/design-philosophy.md`](docs/design-philosophy.md) を参照。主要な配布判断:

- [統合問題は配布先のデフォルト CI で担保する](docs/design-philosophy.md#統合問題は配布先のデフォルト-ci-で担保する) — vibecorp が CI / レビュー設定を追加配布しない理由と、例外配布の判断基準

## 📜 ライセンス

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

このプロジェクトは [MIT License](LICENSE) で配布されている。第三者ランタイム依存（bubblewrap 等の LGPL-2.0+ コンポーネント）との適合性は [`docs/POLICY.md`](docs/POLICY.md#ライセンスポリシー) を参照。
