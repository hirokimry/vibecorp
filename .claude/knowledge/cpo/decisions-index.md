# CPO プロダクト判断記録インデックス

このファイルは目次。CPO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ
- 2026-05-10 — ship ステップ 11（マージ後 LLM 検証 + 未完了項目再帰実装）追加提案 — OK（透明性・規律の自動化バリュー合致。プリセットスコープと specification.md 反映は plan mode での確認事項）
- 2026-05-08 — Issue #311 Phase 3 隔離レイヤ仕様確定と OS サポート方針明文化 — OK（全 4 変更が specification.md・README.md に既反映済みと確認。OS サポート方針明文化は透明性バリュー、bwrap 不在 exit 1 は段階的成長バリュー、プリセット表「隔離」列は導入手軽さバリューに合致）
- 2026-05-06 — 配布物の Source-of-Truth ドキュメント完成と規約衝突解消（#360 子 Issue）— OK（POLICY.md・cost-analysis.md プレースホルダ埋め・organization.md と ai-organization.md の規約衝突解消を承認。透明性・規律の自動化バリュー適合）
- 2026-05-04 — Issue #468 sync-check 再確認（claude_action セクション追加）— OK（前回指摘のYAMLサンプル不在・説明段落なしが解消、specification.md・MVV整合）
- 2026-05-04 — Issue #465 REVIEW.md 配布に伴う README.md 整合性チェック — 要更新（インストールツリーへの REVIEW.md 追記・claude_action 説明段落への skip_paths 自動反映動作の記載が必要。specification.md は不要）
- 2026-05-04 — Issue #461 sync-check 再実行（ai-review.yml README 反映確認）— OK（前回指摘 2 点解消。インストールツリー追記・「リポジトリインフラ設定」セクション新設。MVV 透明性適合）
- 2026-05-04 — Issue #461 ai-review.yml 配布開始に伴う README.md 整合性チェック — 要更新（インストール構造ツリーへの ai-review.yml 追記・「リポジトリインフラ設定」セクションへの AI レビューワークフロー記載が必要。specification.md は不要）
- 2026-05-03 — README.md full プリセット スキル一覧に plan-epic / release-epic / cycle-metrics を追記（sync-edit） — specification.md L30「README を Source of Truth」原則に基づき3スキル追加。テーブル見出しも4→7に更新
- 2026-05-02 — CodeRabbit 代替候補評価（A〜D）— B（PR-Agent OSS）を standard/full 推奨、minimal は C 維持、reviewer.provider 切替設計への拡張を推奨、D 却下
- 2026-04-29 — PR #445 CodeRabbit 指摘 2 件（migration-knowledge-buffer.md glob 統一 / audit-cost・audit-security 誤検知防止）— OK（specification.md 自動反映フロー・deny glob と整合。README 未掲載は既存残留事項として分離）
- 2026-04-29 — Issue #452 docs更新計画メタレビュー（5ファイル多層防御反映） — OK（実装無変更・specification.md整合・MVV透明性適合。Bash層フックのpreset帰属と tpl同期確認項目の表現修正を要注意）
- 2026-04-29 — Issue #448 SECURITY.md / README.md への多層防御アーキテクチャ反映 — OK（全変更ドキュメント修正のみ・プリセット境界変更なし・透明性バリュー適合）
- 2026-04-29 — Issue #442 knowledge 構造統一計画（dev/442_unify_knowledge_structure）— OK（三領域統一・2段構成移行・揮発データ~/.cache/移動を承認、specification.md 更新スコープを確認事項として伝達）
- 2026-04-25 — ~/.zshrc へのシェル関数追記による --plugin-dir 自動付与 — 除外（Public Ready ガードレール・透明性バリューに抵触）
- 2026-04-25 — scripts/dev.sh ラッパーによる --plugin-dir 自動付与 — OK（リポジトリ内完結・Public Ready 適合・透明性バリュー整合）
- 2026-04-25 — Plugin 名前空間 Phase 3: `.claude/skills/` 互換スタブ廃止を OK と判定
- 2026-04-20 — Issue #361 README.md の不整合修正を実施（/issue の CPO 単独→3者ゲート、/autopilot のラベル縛り撤廃を反映）
- 2026-04-18 — 配布バグ軽量修正5件（Issue #360 抜粋）を OK と判定
- 2026-04-18 — 全スキル Plugin 化（#358）を条件付き GO と判定
- 2026-04-18 — プランのUX軸再定義（minimal/standard/fullの価値提案を明確化）
- 2026-04-18 — worktree 経由 Edit/Write を許可する protect-branch.sh の仕様明確化（Issue #296）
- 2026-04-18 — test_install.sh シャード分割・CI matrix 並列化を OK と判定
- 2026-04-18 — team-auto-approve.sh 完全削除と承認フロー非介入思想の明文化を OK と判定
- 2026-04-18 — max_issues_per_run 等の上限ガードレール値を cost-analysis.md に明記する Issue を OK と判定
- 2026-04-18 — install.sh への full プリセット用課金警告・sandbox 推奨警告実装を OK と判定
- 2026-04-18 — feature ブランチ自動close: GHA テンプレート配布方式に変更（/ship 追加案を撤回）
- 2026-04-18 — decisions.md のインデックス+アーカイブ2段構成への分割を OK と判定
- 2026-04-18 — auto 体験射程と SKIP 性マトリクスの specification.md 追加を OK と判定
- 2026-04-18 — FULLプリセット正式化・Proプラン・Issue親子関係・自動close提案のCPOレビュー
- 2026-04-18 — CEO への報告は「動作で語る」規約新設（communication.md）を OK と判定
- 2026-04-18 — /spike-loop 廃止と承認フロー非介入思想の適用を OK と判定
- 2026-04-18 — /issue への3者フィルタ追加・/autopilot のラベル縛り撤廃を OK と判定
- 2026-04-18 — .claude/.gitignore テンプレート配布化 + 配布系アーキテクチャ再設計 Issue を OK と判定
- 2026-04-17 — README.md ゲートスタンプのパスを XDG キャッシュ配下に更新（Issue #326）
- 2026-04-17 — /login がサンドボックス下で無効になるバグ修正を OK と判定（Issue #329）
- 2026-04-16 — specification.md の隔離レイヤ記述を Phase 1 PoC の opt-in 設計に整合させる
- 2026-04-16 — ship-parallel / autopilot を full プリセット専用に格下げ承認（Issue #308）
- 2026-04-16 — Phase 3a Issue（install.sh macOS 統合）をプロダクト方針に合致と判定
- 2026-04-16 — Issue #320 TUI ハング修正（claude.sb 境界拡張 + claude-real symlink）を OK と判定
- 2026-04-16 — CEO/主Claude役割定義をvibecorp本体に書くことを却下
- 2026-04-11 — /spike-loop を full プリセット専用スキルとして承認
- 2026-04-02 — review-gate.sh の README 未反映を要更新と判定
- 2026-04-02 — protect-branch.sh を全プリセット（minimal 以上）に追加
- 2026-04-02 — command-log.sh をゲートフックではなくログ専用フックとして実装
- 2026-03-22 — settings.json マージ時のフック重複排除を install.sh に組み込む
- 2026-03-22 — .claude/.gitignore の自動生成を install.sh が担う設計

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
