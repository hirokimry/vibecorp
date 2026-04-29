# CFO コスト判断記録インデックス

このファイルは目次。CFO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-04-28 — Issue #247 実装 PR（commit 05ac7ec） — §3 課金構造準拠レビュー、MUST/MUST NOT 全遵守・テスト 16/16 PASS 確認、承認
- 2026-04-28 — Issue #247（第2版） — max_issues_per_run 最適値の再判断（Claude Max 20 前提）、per_run=3 撤回・per_run=7 + per_day=14 に引き上げ推奨
- 2026-04-28 — Issue #247（第1版） — max_issues_per_run 最適値の CFO 判断、per_run=3 への引き下げ推奨（後に撤回）、cycle 単価を $22→$25 に訂正
- 2026-04-23 — プラン別 SKIP 性 条件付き承認の充足確認 — 条件1（デフォルト値の docs/cost-analysis.md 明記）充足、条件2（full 起動時の API キー検出警告）は未充足・継続監視
- 2026-04-20 — Issue #361 — /issue 承認ゲート3者並列化（CPO 単独 → CISO + CPO + SM）でコスト約3倍に増加、承認
- 2026-04-18 — Issue #328 — vibecorp 知見閉ループ再設計（/session-harvest 導入）
- 2026-04-18 — プラン別 SKIP 性のコスト観点判断（CEO 直接依頼）
- 2026-04-17 — Issue #329 — VIBECORP_ISOLATION=1 下の /login 失敗修正
- 2026-04-16 — Issue #318 Phase 3a — install.sh macOS 隔離レイヤ配置ロジック統合

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
