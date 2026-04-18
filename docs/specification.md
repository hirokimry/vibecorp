# vibecorp プロダクト仕様書

> このドキュメントはプロダクトの公式仕様を定義する Source of Truth です。

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

| プリセット | 対象 | 課金モデル | 追加されるもの |
|---|---|---|---|
| **minimal** | 個人〜小規模 | Claude Max 定額内 | コア skills / 保護系 hooks |
| **standard** | チーム開発 | Claude Max 定額内 | 知識蓄積 skills / ゲート hooks / CTO・CPO エージェント |
| **full** | AI 企業・コンプライアンス重視 | **ANTHROPIC_API_KEY 従量課金に到達しうる** | `/diagnose` skill / C-suite 全員 + 分析員（14 ロール） |

- 上位プリセットは下位プリセットの機能を全て含む（加算モデル）
- **full プリセット選択時**: install.sh が課金警告を表示する。ヘッドレス Claude を並列起動するスキル（`/autopilot`, `/spike-loop`, `/ship-parallel`）は **full プリセット専用**。課金リスクを伴う大規模並列実行のため、誤爆リスクを抑える目的で minimal/standard では物理的に配置しない。親プロセスの認証が `ANTHROPIC_API_KEY` の場合は API 従量課金に到達しうる。課金モデル詳細は [`docs/cost-analysis.md`](./cost-analysis.md) を参照。macOS の `sandbox-exec` による隔離レイヤは **full プリセット + macOS 環境** のとき install.sh が `.claude/bin/` と `.claude/sandbox/` を自動配置し、`source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` で有効化する（opt-in）。Linux（bwrap）対応は Phase 2 で追加予定。Windows ネイティブは非対応（WSL2 を使用）

各プリセットに含まれる具体的なスキル・フック・エージェントの一覧は [`README.md`](../README.md) を Source of Truth とする。

## 機能仕様

### コア機能

- **skills/**: Claude Code のスラッシュコマンド（`/ship`, `/plan`, `/review` 等）として Issue 駆動の開発ループを提供する
- **hooks/**: PreToolUse / PostToolUse でファイル保護・ブランチ保護・ゲート制御を行う
- **agents/**: standard 以上で CTO・CPO 等の役割別エージェントを提供。full では C-suite + 分析員の合議制で判断する
- **rules/**: 全エージェントが従うコーディング規約・プロジェクト規約

### 補助機能

- **knowledge/**: 役割別エージェントが蓄積する判断記録・ノウハウ（standard 以上）
- **vibecorp.yml / vibecorp.lock**: プロジェクト設定とバージョン固定

### インストール / アップデート

- `install.sh --update` 実行時、旧バージョンで誤って tracked 化されたマシン固有 artifact（現状は `.claude/bin/claude-real`）を `git rm --cached` で自動 untrack する
- `--no-migrate` オプションで自動 untrack をスキップ可能（詳細は README 参照）

### 知識蓄積スキルの責務

| スキル | standard | full |
|---|---|---|
| `/session-harvest` | `/pr` から自動呼出（PR 作成後） | 同上 |
| `/review-harvest` | 手動実行 | `/autopilot` から自動呼出 |
| `/knowledge-pr` | 手動実行 | `/autopilot` から自動呼出 |
| `/sync-check` | 手動実行 | 同上 |
| `/harvest-all` | 手動実行 | 同上（作業ブランチ直接書込フロー、本 Issue スコープ外） |

**コンセプト**: standard プリセットは「知識蓄積の自動強制（ゲート）」ではなく「知識蓄積ツールの提供」。
ゲートフック（review-to-rules-gate.sh / session-harvest-gate.sh）は廃止され、スキルは任意実行可能に格下げ。
自動収集の価値は full プリセットの `/autopilot` に集約する。

**自動反映フロー**: 知見は全て `knowledge/buffer` ブランチに蓄積され、`/knowledge-pr` が Issue 起票 → PR 作成 →
auto-merge により main に反映される。これにより CodeRabbit レビュー・CI・人間の承認ポイントを knowledge の
変更にも通す設計を担保する。main への直接 push は一切発生しない。

## 非機能要件

### パフォーマンス

（応答時間、スループット等の要件を記載）

### セキュリティ

（認証・認可・データ保護等の要件を記載。詳細は SECURITY.md を参照）

### 可用性

（稼働率、障害復旧等の要件を記載）

## 画面遷移・データフロー

（画面遷移図やデータフローの概要を記載）

## 用語集

| 用語 | 定義 |
|---|---|
| （用語） | （定義） |
