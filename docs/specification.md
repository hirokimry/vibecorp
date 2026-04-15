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
- **full プリセット選択時**: install.sh が課金警告を表示する。ヘッドレス Claude を並列起動するスキル（`/autopilot`, `/spike-loop`, `/ship-parallel`）は全プリセットで利用可能だが、親プロセスの認証が `ANTHROPIC_API_KEY` の場合は API 従量課金に到達しうる。課金モデル詳細は [`docs/cost-analysis.md`](./cost-analysis.md) を参照

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
- **自動反映フロー**: `/review-to-rules`, `/session-harvest`, `/sync-check` により PR レビュー・セッション知見・コード変更を rules/ / knowledge/ / docs/ に継続反映する（standard 以上）

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
