# CPO プロダクト判断記録インデックス

このファイルは目次。CPO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-04-28 — Issue #323 guide-gate.sh（Claude Code Guide 参照強制）を standard 以上に追加

- 2026-04-26 — marketplace 経由プラグイン自動ロード修正 Issue を OK と判定（install.sh の一括セットアップ完結とmarketplace.json公式準拠）

- 2026-04-20 — Issue #361 README.md の不整合修正を実施（/issue の CPO 単独→3者ゲート、/autopilot のラベル縛り撤廃を反映）
- 2026-04-18 — .claude/.gitignore テンプレート配布化 + 配布系アーキテクチャ再設計 Issue を OK と判定
- 2026-04-18 — 配布バグ軽量修正5件（Issue #360 抜粋）を OK と判定
- 2026-04-18 — worktree 経由 Edit/Write を許可する protect-branch.sh の仕様明確化（Issue #296）
- 2026-04-18 — 全スキル Plugin 化（#358）を条件付き GO と判定
- 2026-04-18 — /issue への3者フィルタ追加・/autopilot のラベル縛り撤廃を OK と判定
- 2026-04-18 — feature ブランチ自動close: GHA テンプレート配布方式に変更（/ship 追加案を撤回）
- 2026-04-18 — FULLプリセット正式化・Proプラン・Issue親子関係・自動close提案のCPOレビュー
- 2026-04-18 — /spike-loop 廃止と承認フロー非介入思想の適用を OK と判定
- 2026-04-18 — CEO への報告は「動作で語る」規約新設（communication.md）を OK と判定
- 2026-04-18 — test_install.sh シャード分割・CI matrix 並列化を OK と判定
- 2026-04-18 — install.sh への full プリセット用課金警告・sandbox 推奨警告実装を OK と判定
- 2026-04-18 — max_issues_per_run 等の上限ガードレール値を cost-analysis.md に明記する Issue を OK と判定
- 2026-04-18 — auto 体験射程と SKIP 性マトリクスの specification.md 追加を OK と判定
- 2026-04-18 — team-auto-approve.sh 完全削除と承認フロー非介入思想の明文化を OK と判定
- 2026-04-18 — プランのUX軸再定義（minimal/standard/fullの価値提案を明確化）
- 2026-04-18 — decisions.md のインデックス+アーカイブ2段構成への分割を OK と判定
- 2026-04-17 — /login がサンドボックス下で無効になるバグ修正を OK と判定（Issue #329）
- 2026-04-17 — README.md ゲートスタンプのパスを XDG キャッシュ配下に更新（Issue #326）
- 2026-04-16 — Issue #320 TUI ハング修正（claude.sb 境界拡張 + claude-real symlink）を OK と判定
- 2026-04-16 — Phase 3a Issue（install.sh macOS 統合）をプロダクト方針に合致と判定
- 2026-04-16 — specification.md の隔離レイヤ記述を Phase 1 PoC の opt-in 設計に整合させる
- 2026-04-16 — ship-parallel / autopilot を full プリセット専用に格下げ承認（Issue #308）
- 2026-04-16 — CEO/主Claude役割定義をvibecorp本体に書くことを却下
- 2026-04-11 — /spike-loop を full プリセット専用スキルとして承認
- 2026-04-02 — command-log.sh をゲートフックではなくログ専用フックとして実装
- 2026-04-02 — review-gate.sh の README 未反映を要更新と判定
- 2026-04-02 — protect-branch.sh を全プリセット（minimal 以上）に追加
- 2026-03-22 — .claude/.gitignore の自動生成を install.sh が担う設計
- 2026-03-22 — settings.json マージ時のフック重複排除を install.sh に組み込む

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
