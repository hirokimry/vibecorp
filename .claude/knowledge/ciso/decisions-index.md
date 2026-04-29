# CISO セキュリティ判断記録インデックス

このファイルは目次。CISO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-04-29 — Issue #442 knowledge 構造統一（monitoring ログ四半期集約 refactor）— 承認: リスクなし（deny パターン拡大方向、buffer フロー境界維持）

- 2026-04-25 — 不可領域チェック: --plugin-dir 自動付与 scripts/dev.sh ラッパー方式 — OK（5分類いずれにも該当しない）

- 2026-04-25 — 不可領域チェック: --plugin-dir 自動付与シェル関数（~/.zshrc 追加） — OK（5分類いずれにも該当しない）

- 2026-04-22 — 承認ダイアログのスマホ remote app 非表示問題 — 除外（ガードレール領域: protect-files.sh 承認フロー変更リスク）
- 2026-04-20 — docs/SECURITY.md プリセット別動作表の誤記修正（standard 行 /autopilot を「動作しない」に訂正）
- 2026-04-20 — Issue #361 /issue と /autopilot の責務分離 + 3者承認ゲート導入（条件付き承認: SECURITY.md 更新・/diagnose ゲート確認を条件）
- 2026-04-19 — Issue #366 配布物の Source of Truth テンプレート化
- 2026-04-18 — Issue #296 protect-branch.sh worktree 誤検知修正
- 2026-04-18 — プリセット別安全性評価（full/standard/minimal × sandbox/Hook）
- 2026-04-17 — Issue #331 VIBECORP_ISOLATION=1 下の /login 失敗修正 Part2（XDG サイドカー拡張）
- 2026-04-17 — Issue #329 VIBECORP_ISOLATION=1 下の /login 失敗修正（サイドカー書込許可追加）
- 2026-04-17 — Issue #326 ゲートスタンプの XDG キャッシュ移動（docs/SECURITY.md 不整合修正）
- 2026-04-16 — Issue #320 合議制最終チェック（security-analyst ×3 メタレビュー）
- 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）
- 2026-04-16 — Issue #318 Phase 3a: install.sh macOS 隔離レイヤ配置ロジック統合
- 2026-04-16 — CR-001 CodeRabbit 第 2 回レビュー対応（WORKTREE ⊇ HOME 攻撃経路）
- 2026-04-16 — Issue #309 macOS sandbox-exec PoC（Phase 1）

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
