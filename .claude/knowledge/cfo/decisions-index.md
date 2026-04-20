# CFO コスト判断記録インデックス

このファイルは目次。CFO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

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
