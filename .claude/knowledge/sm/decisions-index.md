# SM プロセス管理判断記録インデックス

このファイルは目次。SM エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-04-23 — diagnose デフォルト値・forbidden_targets 設定整合確認 — vibecorp.yml diagnose セクション全設定値が不可領域 5 分類と整合。docs/cost-analysis.md が上限ガードレールの Source of Truth として確立
- 2026-04-20 — Issue #361 docs/ai-organization.md 不整合修正 — Issue 起票ゲートを CPO 単独から CISO+CPO+SM 3者承認に更新、起票側/ship 側の責務分離を追記

- 2026-04-18 — Issue #366 実装計画のメタレビュー — 実装着手を阻むブロッカーなし。SM-1（Phase 2 依存理由追記）のみ推奨
- 2026-04-18 — docs/design-philosophy.md の CPO 管轄追記（訂正） — 仕様は CPO、設計は CTO。design-philosophy.md は CTO 管轄に訂正
- 2026-04-18 — Issue #296 ガードレール領域変更の通過承認トレーサビリティ — CEO 主導実装のため自律実行禁止制約とは別枠で通過
- 2026-04-17 — Issue #329 実装計画のメタレビュー — 実装ブロッカーなし。Phase 直列順序妥当、HOME regex 等は別 Issue 推奨

## 運用ルール

### エントリ書式

1 エントリ = 1 行:

```text
- YYYY-MM-DD — Issue #NNN または CR-NNN または トピック名 — 結論の一行要約
```

### 四半期の命名

- 01-03 → Q1、04-06 → Q2、07-09 → Q3、10-12 → Q4
- 例: 2026-04-18 → `decisions/2026-Q2.md`

### 追記手順

1. `decisions/YYYY-QN.md` に詳細を追記（ファイルがなければ新規作成、`decisions/` ディレクトリ自動作成）
2. 本ファイルのエントリセクションに 1 行サマリを追記（新しい順で上に追加）

詳細仕様: `docs/migration-decisions-index.md`
