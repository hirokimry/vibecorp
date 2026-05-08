# vibecorp プロダクト仕様書

> このドキュメントは vibecorp の **機能スコープの Source of Truth** です。プリセット定義、提供スキル / フック / エージェント、auto 体験射程、SKIP 性、非機能要件をここで規定します。
>
> 設計思想・判断根拠（なぜそうしたか）は [`docs/design-philosophy.md`](design-philosophy.md) を Source of Truth とし、本ファイルとは役割分担しています。

## 概要

vibecorp は AI エージェントを組織化してプロダクト開発を回すプラグインである。Claude Code の skills / hooks / agents / rules を一括セットアップし、導入先リポジトリに「開発組織」として機能する AI チームを構築する。

- **目的**: Issue 駆動の開発ループを AI に委譲し、ブランチ作成から PR の auto-merge までを一気通貫で実行可能にする
- **対象ユーザー**: Claude Code をチーム開発に組み込みたい個人開発者・チーム・AI 企業
- **提供価値**:
  - skills/hooks/agents/rules を一括導入し、プロジェクト横断の開発体験を揃える
  - プリセットによる段階的導入（個人 → チーム → AI 企業規模）
  - rules/ / knowledge/ / docs/ への自動反映フロー（review-to-rules / session-harvest / sync-check）による継続的な知識蓄積

## プリセット

組織規模に応じた 3 段階のプリセットを提供する。ユーザーは `install.sh --preset <preset>` で選択する。

| プリセット | 対象 | 課金モデル | 追加されるもの | auto 体験射程（公式サポート） | auto 体験射程（ユーザー裁量） | sandbox |
|---|---|---|---|---|---|---|
| **minimal** | 個人〜小規模 | Claude Max 定額内 | コア skills / 保護系 hooks | 単発 `/vibecorp:ship` → PR → auto-merge | `/loop` による cron 化 | 対象外 |
| **standard** | チーム開発 | Claude Max 定額内 | 知識蓄積 skills / ゲート hooks / CTO・CPO エージェント | minimal + ゲート強制（auto-merge 維持） | `/loop` による cron 化 | 対象外 |
| **full** | AI 企業・コンプライアンス重視 | **ANTHROPIC_API_KEY 従量課金に到達しうる** | `/vibecorp:diagnose` skill / C-suite 全員 + 分析員（14 ロール） | 並列 `/vibecorp:ship-parallel` + 単発 `/vibecorp:autopilot` + `/vibecorp:diagnose` | `/loop /vibecorp:autopilot 24h` 等 | macOS のみ推奨・opt-in（強制ではない） |

**sandbox opt-in の位置づけ**: vibecorp は sandbox を **強く推奨するだけで、強制はしない**。`full` プリセット + macOS で `install.sh` が `.claude/bin/` と `.claude/sandbox/` を自動配置するが、有効化は `source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` をユーザーが明示的に実行した場合のみ。`full` + sandbox OFF で並列実行する場合は「承認ダイアログの多発」または「ユーザーが `.claude/settings.local.json` の allow リストを自己調整」のいずれかとなり、自己責任の運用となる（[`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入) 参照）。

- 上位プリセットは下位プリセットの機能を全て含む（加算モデル）
- **full プリセット選択時**: install.sh が課金警告を表示する。ヘッドレス Claude を並列起動するスキル（`/vibecorp:autopilot`, `/vibecorp:ship-parallel`）は **full プリセット専用**。課金リスクを伴う大規模並列実行のため、誤爆リスクを抑える目的で minimal/standard では物理的に配置しない。親プロセスの認証が `ANTHROPIC_API_KEY` の場合は API 従量課金に到達しうる。課金モデル詳細は [`docs/cost-analysis.md`](./cost-analysis.md) を参照。macOS の `sandbox-exec` による隔離レイヤは **full プリセット + macOS 環境** のとき install.sh が `.claude/bin/` と `.claude/sandbox/` を自動配置し、`source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` で有効化する（opt-in）。Linux（bwrap）対応は Phase 2 で追加予定。Windows ネイティブは非対応（WSL2 を使用）
- **Agent Teams 動作環境**: `/vibecorp:ship-parallel` / `/vibecorp:autopilot` は Claude Code の Agent Teams 機能（experimental）に依存する。公式 docs に split-pane mode の要件が明記されている: `requires either tmux or iTerm2 with the it2 CLI`。not supported 環境は `VS Code's integrated terminal, Windows Terminal, or Ghostty`（[公式 docs](https://code.claude.com/docs/en/agent-teams#limitations)）。非対応環境で split-pane mode を使うと teammate 承認プロンプトが可視化されず、リモート閲覧からは承認不能。`.claude/settings.json` の `permissions.allow` には `.claude/knowledge/**` / `.claude/plans/**` / `.claude/rules/**` / `.claude/skills/**` / `~/.cache/vibecorp/{plans,state}/**` が事前登録されており（公式 docs の [Too many permission prompts 推奨](https://code.claude.com/docs/en/agent-teams#too-many-permission-prompts)）、これら領域の teammate 書込は承認要求が発生しない。導入ユーザー向け詳細は [`README.md`](../README.md) を参照

各プリセットに含まれる具体的なスキル・フック・エージェントの一覧は [`README.md`](../README.md) を Source of Truth とする。

## SKIP 性マトリクス

`vibecorp.yml` の `hooks:` トグルで明示的に `false` を指定しても **無効化できない hook** をプリセット別に整理する。保護・ゲート・API バイパス防止・ログの 4 系統は vibecorp の安全性とプロセス強制の根幹であり、SKIP 不可とする。

### プラン別 hook 必須性

| hook | minimal | standard | full | 種別 |
|---|---|---|---|---|
| `protect-files` | 必須 | 必須 | 必須 | 保護系 |
| `protect-branch` | 必須 | 必須 | 必須 | 保護系 |
| `block-api-bypass` | 必須 | 必須 | 必須 | API バイパス防止系 |
| `command-log` | 必須 | 必須 | 必須 | ログ系 |
| `sync-gate` | — | 必須 | 必須 | ゲート系 |
| `review-gate` | — | 必須 | 必須 | ゲート系 |
| `guide-gate` | — | 必須 | 必須 | ゲート系 |
| `role-gate` | — | — | 必須 | 保護系 |
| `diagnose-guard` | — | — | 必須 | 保護系 |
| `session-harvest-gate` | — | — | — | （後述「廃止された hook」参照） |
| `review-to-rules-gate` | — | — | — | （後述「廃止された hook」参照） |
| `team-auto-approve` | — | — | — | （後述「廃止された hook」参照） |

- **必須**: そのプリセットで必ず配置され、`hooks:` トグルで `false` にしても install.sh が再配置する
- **—**: そのプリセットでは物理配置されない（SKIP 性の議論対象外）

#### 廃止された hook

- `session-harvest-gate` / `review-to-rules-gate`: standard プリセットを「知識蓄積の自動強制（ゲート）」から「知識蓄積ツールの提供」に再定義した方針転換に伴い廃止された（後述「[知識蓄積スキルの責務](#知識蓄積スキルの責務)」参照）。`/vibecorp:session-harvest` / `/vibecorp:review-harvest` は任意実行スキルとして残り、自動収集は `/vibecorp:autopilot`（full プリセット）に集約される
- `team-auto-approve`: 承認フロー非介入方針（[`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入)）の確定に伴い Issue #336 で完全削除された。後方互換なし

### なぜ SKIP 不可か（種別別の理由）

| 種別 | 含まれる hook | SKIP 不可の理由 |
|---|---|---|
| **保護系** | protect-files / protect-branch / role-gate / diagnose-guard | ビジネスルール（MVV / base ブランチ直書き禁止 / エージェント管轄境界 / `/vibecorp:diagnose` 実行中の自己改変防止）の根幹を守る。SKIP すれば設定ファイル誤編集や暴走改変が素通りする |
| **ゲート系** | sync-gate / review-gate / guide-gate | プロセス強制（push 前 sync-check / PR 作成前 review / `.claude/` 配下編集前の公式仕様確認）の門番。SKIP すれば品質ゲートが空洞化する |
| **API バイパス防止系** | block-api-bypass | `gh api` による直接マージや `@coderabbitai approve` 投稿等、auto-merge 環境のレビュープロセスを迂回する経路をブロックする。SKIP すれば未レビューコードがマージされうる |
| **ログ系** | command-log | 全 Bash コマンドを `~/.cache/vibecorp/state/<repo-id>/command-log` に記録し、`/vibecorp:approve-audit` の棚卸し対象とする。SKIP すれば許可リスト最適化の入力源が失われる |

`vibecorp.yml` の `hooks:` トグルが効くのは上記マトリクスで「必須」とされていない hook（実質的にユーザー独自に追加した hook、または将来 SKIP 可能として導入される hook）に限る。

## 機能仕様

### コア機能

- **skills/**: Claude Code のスラッシュコマンド（`/vibecorp:ship`, `/vibecorp:plan`, `/vibecorp:review` 等）として Issue 駆動の開発ループを提供する
- **hooks/**: PreToolUse / PostToolUse でファイル保護・ブランチ保護・ゲート制御を行う。`guide-gate.sh`（standard 以上）は `.claude/` 配下テンプレートの Edit/Write/MultiEdit 時に `claude-code-guide` エージェントによる公式仕様確認を強制する
- **agents/**: standard 以上で CTO・CPO 等の役割別エージェントを提供。full では C-suite + 分析員の合議制で判断する
- **rules/**: 全エージェントが従うコーディング規約・プロジェクト規約

### 補助機能

- **knowledge/**: 役割別エージェントが蓄積する判断記録・ノウハウ（standard 以上）
- **vibecorp.yml / vibecorp.lock**: プロジェクト設定とバージョン固定

### インストール / アップデート

- `install.sh` 実行時（`--name` / `--update` 両モード）、旧バージョンで誤って tracked 化されたマシン固有 artifact（現状は `.claude/bin/claude-real`）を `git rm --cached` で自動 untrack する。通常は既存環境の移行時（`--update`）に意味を持つ
- `--no-migrate` オプションで自動 untrack をスキップ可能（詳細は README 参照）

#### plugin メタデータ (`.claude-plugin/plugin.json`) の Source-of-Truth

- vibecorp リポジトリ直下の `.claude-plugin/plugin.json` が plugin メタデータ（`name` / `version` / `description`）の **唯一の Source-of-Truth** である（Claude Code 公式仕様の正規パスに準拠）
- `install.sh` は consumer リポジトリの `.claude-plugin/plugin.json` に SoT を直接コピーする。`templates/` 経由の二重管理は drift の原因になるため廃止された（Issue #540）
- リリース時は `.claude-plugin/plugin.json` の `version` だけを bump すればよい。複数箇所の同期は不要

### 隔離レイヤ

full プリセットでは、OS ごとに隔離レイヤの提供状況が異なる（macOS は実隔離稼働、Linux は `bwrap` 検出と導入ガイダンスまで、Windows ネイティブは非対応で中断）。誤操作・プロンプトインジェクション経由の破壊操作・認証情報窃取に対する防御層として機能する。詳細な脅威モデルは [`docs/SECURITY.md` の脅威モデル節](SECURITY.md#脅威モデル) を参照。

#### プリセット別 権限モデル

| プリセット | 隔離方式 | 提供範囲 |
|---|---|---|
| **minimal** | なし | OS 標準のユーザー権限のみ。`protect-files.sh` フックで設定ファイル誤編集を防ぐ |
| **standard** | なし | minimal と同じ |
| **full / macOS** | `sandbox-exec` ベース | `.claude/bin/claude` shim 経由で `.claude/sandbox/claude.sb` プロファイルを適用。`~/Library/Application Support/Claude` / `~/.claude` 等を read-only 化 |
| **full / Linux** | `bwrap` (bubblewrap) 検出のみ | `install.sh` で `bwrap` 不在時に distro 別インストール手順 (`apt-get install bubblewrap` / `dnf install bubblewrap` / `apk add bubblewrap`) を表示し中断。実際の `bwrap` 起動による隔離は Phase 2 (#310) で対応 |
| **full / Windows ネイティブ** | 非対応 | `install.sh` が exit 2 で中断。WSL2 (Ubuntu 22.04+) 経由で Linux 環境を使用する |

#### 制約

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
ゲートフック（review-to-rules-gate.sh / session-harvest-gate.sh）は廃止され、スキルは任意実行可能に格下げ。
自動収集の価値は full プリセットの `/vibecorp:autopilot` に集約する。

**自動反映フロー**: 知見は全て `knowledge/buffer` ブランチに蓄積され、`/vibecorp:knowledge-pr` が Issue 起票 → PR 作成 →
auto-merge により main に反映される。これにより CodeRabbit レビュー・CI・人間の承認ポイントを knowledge の
変更にも通す設計を担保する。main への直接 push は一切発生しない。

| 経路 | buffer 化 | 補足 |
|---|:---:|---|
| `/vibecorp:session-harvest` | ✅ | 自動 |
| `/vibecorp:review-harvest` | ✅ | 自動 |
| `/vibecorp:audit-cost` | ✅ | Issue #442 で対応（`accounting/audit-log/YYYY-QN.md` 追記 + index 1 行サマリ） |
| `/vibecorp:audit-security` | ✅ | Issue #442 で対応（`security/audit-log/YYYY-QN.md` 追記 + index 1 行サマリ） |
| `/vibecorp:sync-edit` | ✅ | Issue #439 で対応（C*O 委任編集の `knowledge/{role}/`） |
| C*O 決定記録（CFO/CTO/CPO/CISO/CLO/SM） | ✅ | Issue #439 で対応（`decisions/{YYYY-QN}.md` / `decisions-index.md`） |
| 分析員監査記録（accounting/security/legal） | ✅ | Issue #442 で対応（`{role}/audit-log/{YYYY-QN}.md` / `audit-log-index.md`） |
| `/vibecorp:cycle-metrics` | ❌ | 揮発データ（`~/.cache/vibecorp/state/<repo-id>/cycle-metrics/YYYY-MM-DD.md` に保存、`.claude/knowledge/` 外） |
| `/vibecorp:harvest-all` | ❌ | ユーザー承認後に直接書込み（`harvest-all-active` スタンプで hook 通過。ただし `audit-log/` と `decisions/` は fail-secure で迂回不可） |

**ガードレール**: `templates/claude/hooks/protect-knowledge-direct-writes.sh`（Edit/Write 層）と `templates/claude/hooks/protect-knowledge-bash-writes.sh`（Bash 層）の 2 層 hook が以下を作業ブランチ直書きから deny する（buffer worktree 経由のみ許可）:

- `.claude/knowledge/{role}/decisions/`、`.claude/knowledge/{role}/decisions-index.md`（C*O 6 ロール: cfo/cto/cpo/ciso/clo/sm）
- `.claude/knowledge/{role}/audit-log/`（分析員 3 ロール: accounting/security/legal の 4 半期集約 + audit-log-index.md）

防御層の構成・Bash 層の検出パターン・harvest-all-active スタンプ仕様・fail-secure 原則の詳細は [`docs/SECURITY.md` の「knowledge ガードレール（多層防御）」](SECURITY.md#knowledge-ガードレール多層防御) を参照。救済手順は [`docs/migration-knowledge-buffer.md`](migration-knowledge-buffer.md) を参照。

### エピック運用

大規模な機能開発は「エピック」として運用する。エピック運用は full プリセット専用。

**ブランチ命名規約:**

| 種別 | パターン | 例 |
|------|---------|-----|
| 通常 Issue | `dev/{Issue番号}_{要約}` | `dev/123_add_login` |
| 親エピック（feature ブランチ） | `feature/epic-{Issue番号}_{要約}` | `feature/epic-345_plan_epic_skill` |
| エピック配下の子 Issue | `dev/{Issue番号}_{要約}` | `dev/346_ship_epic_child` |

**マージフロー（二段階マージ）:**

1. 子 Issue の PR は親 feature ブランチ（`feature/epic-*`）を base に作成される
2. 全子 Issue がマージされた後、`/release-epic` で feature ブランチから main への PR を作成する

**子 Issue の base 自動判定:**

`/ship` は GitHub API（`/repos/{owner}/{repo}/issues/{番号}/parent`）で sub-issue かどうかを判定する。sub-issue の場合、親エピックの feature ブランチを自動的に PR の base に設定する。sub-issue でない通常 Issue は従来通り default branch を base にする。

**関連スキル:**

- `/plan-epic`: 親エピックの Issue・子 Issue を一括作成し sub-issue で紐付ける
- `/ship`: 子 Issue の実装時に親 feature ブランチを自動検出して base に設定する
- `/release-epic`: feature ブランチから main への集約 PR を作成する

## 非機能要件

### パフォーマンス

- スキルワークフロー（`/vibecorp:ship` / `/vibecorp:pr-fix-loop` 等）はユーザー対話ターン内で完結する設計を取る（長時間バッチではない）
- 並列スキル（`/vibecorp:ship-parallel` / `/vibecorp:autopilot`）は full プリセット専用とし、`max_issues_per_run` / `max_issues_per_day`（`vibecorp.yml` の `diagnose:` セクション）で実行頻度を制御する。詳細は [`docs/cost-analysis.md`](cost-analysis.md) を参照

### セキュリティ

- **承認フロー非介入**: vibecorp は Claude Code の承認フローを書き換える hook（PreToolUse で `permissionDecision: "allow"` を返す類）を提供しない。承認はセキュリティの最後の砦であり、本体のガードレールを崩さない（[`docs/design-philosophy.md#承認フローへの非介入`](design-philosophy.md#承認フローへの非介入) 参照）
- **sandbox opt-in**: `full` プリセット + macOS では `sandbox-exec` ベースの隔離レイヤを `install.sh` が配置する。有効化は `source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` を **ユーザーが明示的に実行** した場合のみ。強制はしない
- **SKIP 不可 hook の堅持**: 保護系 / ゲート系 / API バイパス防止系 / ログ系の hook は `vibecorp.yml` の `hooks:` トグルで無効化できない（前述「[SKIP 性マトリクス](#skip-性マトリクス)」参照）。これによりユーザー設定ミスでガードレールが空洞化する経路を塞ぐ
- **knowledge ガードレール**: `.claude/knowledge/{role}/decisions/` `.claude/knowledge/{role}/audit-log/` への作業ブランチ直書きは Edit/Write 層 + Bash 層の 2 層フックで deny される（buffer worktree 経由のみ許可）。詳細は [`docs/SECURITY.md`](SECURITY.md#knowledge-ガードレール多層防御) を参照
- **脅威モデルと信頼境界**: 詳細は [`docs/SECURITY.md`](SECURITY.md#脅威モデル) を参照

### 可用性

- **承認体験の方針**:
  - `minimal` / `standard` プリセットは素の Claude Code の承認体験に従う（都度承認、sandbox なし）
  - `full` プリセットは sandbox opt-in を推奨し、`--dangerously-skip-permissions` との組み合わせで承認負荷を低減する。sandbox OFF で並列実行する場合は承認ダイアログの多発を許容するか、ユーザーが `settings.local.json` の allow リストを自己調整するかの自己責任となる
- **auto-merge による自動マージ**: `/vibecorp:ship` / `/vibecorp:pr` は `gh pr merge --auto --squash` を設定し、CI required checks パス + approve 後に GitHub が自動マージする。マージ自体に Claude Code セッションは不要（プロセス停止の影響を受けない）
- **install.sh の冪等性**: `--name` 初回実行 / `--update` 何度実行しても同じ状態に収束する。途中失敗しても再実行で復旧可能（local git config / Branch Protection / `.coderabbit.yaml` / `vibecorp.lock` 全てが冪等）。詳細は [`docs/design-philosophy.md`](design-philosophy.md) の「--update モードの設計判断」を参照

## 画面遷移・データフロー

（画面遷移図やデータフローの概要を記載）

## 用語集

| 用語 | 定義 |
|---|---|
| （用語） | （定義） |
