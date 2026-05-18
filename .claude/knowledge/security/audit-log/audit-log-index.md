# セキュリティ監査ログ索引

このファイルは目次。`/vibecorp:audit-security` および `security-analyst` 合議結果の四半期アーカイブを参照するための索引。

## 構成

- 詳細: `audit-log/YYYY-QN.md`（四半期集約）
- 1 行サマリ: 本ファイルに追記

## 索引

- 2026-05-16 — CISOセッション知見 — Link Following 脆弱性（TOCTOU と独立）、合議分裂運用基準、decisions-index 追記漏れ検出手順を記録
- 2026-04-25 — Issue #401 Plugin 名前空間 Phase 3 互換スタブ廃止 — 問題なし（rm -rf 2段防御が適切）
- 2026-04-19 — Issue #366 配布物 Source of Truth テンプレート化（3回合議） — 問題なし（Critical/High/Medium なし、symlink 通過は既存継続）
- 2026-04-18 — Issue #328 知見閉ループ再設計 — P328-006 プロンプトインジェクション対応済み、ガードレール復元済み
- 2026-04-18 — Issue #296 protect-branch.sh worktree 誤検知修正 — 問題なし（sed quote-aware 問題は既知・別 Issue）
- 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（3回合議） — 問題なし（Low/Info のみ、CISO 承認済み）
- 2026-04-16 — Issue #318 Phase 3a install.sh macOS 統合（2回合議） — High 2件検出（P318-H-001/H-002）エスカレーション
- 2026-04-16 — Issue #309 macOS sandbox-exec PoC Phase 1（3回合議 + CISO 対応） — High 3件対応済み、Phase 2 スコープ出し 11件

## 運用ルール

### エントリ書式

1 エントリ = 1 行:

```text
- YYYY-MM-DD — Issue #NNN または トピック名 — 結論の一行要約
```

### 四半期の命名

- 01-03 → Q1、04-06 → Q2、07-09 → Q3、10-12 → Q4
- 例: 2026-04-18 → `audit-log/2026-Q2.md`

### 追記手順

1. `audit-log/YYYY-QN.md` に詳細を追記（ファイルがなければ新規作成、`audit-log/` ディレクトリ自動作成）
2. 本ファイルの索引セクションに 1 行サマリを追記（新しい順で上に追加）

詳細仕様: `docs/migration-knowledge-buffer.md`
