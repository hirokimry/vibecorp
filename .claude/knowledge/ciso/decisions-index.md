# CISO セキュリティ判断記録インデックス

このファイルは目次。CISO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ
- 2026-05-23 — plugin native 配布化のセキュリティ最終審査（#705 / 親エピック #700）— 条件付き承認: 8 観点全評価完了、新規脆弱性なし、子 #707 実装の絶対条件として 4 必須対策（marketplace.json 限定 / plugin cache chmod 推奨 / ユーザー独自フックは settings.local.json / fail-closed 起動）を付記
- 2026-05-16 — Issue #310 Linux bwrap 隔離レイヤ実装 メタレビュー #2 — 承認: symlink チェック修正確認済み、全件修正済みマージ可、新規脆弱性なし（CR-001 / Issue #311 と整合）
- 2026-05-16 — Issue #310 Linux bwrap 隔離レイヤ実装 メタレビュー #1 — 差し戻し: 全会一致ルール適用（analyst #3 = High）。source 前の symlink チェック（-L）欠如による Link Following 脆弱性（任意シェルコード実行経路）を検出
- 2026-05-10 — 不可領域チェック: ship が Issue チェックボックスをマージ後に自動検証し未完了項目を再帰実装するようになる（skills/ship/SKILL.md 拡張）— 条件付き OK（6分類非該当。再帰深度上限・安全弁・ヘッドレス呼び出し追加禁止の実装時条件 3 点を付記）
- 2026-05-08 — Issue #532 sync-check #2 再チェック（注釈追加後 + 0.33.6 互換遡及ロジック）— 承認: 全ドキュメント整合・autonomous-restrictions #6 抵触なし・SHA256 遡及ロジック妥当性確認済み
- 2026-05-08 — Issue #532 claude-code-action 無効化 PR セキュリティ合議メタレビュー — 承認: セキュリティリスクなし。rm -f + 固定パス/内部関数戻り値に外部制御経路なし。PR ブロック不要、別 Issue 起票推奨
- 2026-05-08 — Issue #311 Phase 3: install.sh Linux bwrap 統合 + Win 弾き + ドキュメント整備 — 承認（条件付き）: Analyst3 Major M-01 は偽陽性（log_error 表示選択のみ、実害なし）。Minor 2点（脅威#2記述ズレ・VIBECORP_OS_RELEASE_PATH コメント欠如）対応推奨
- 2026-05-06 — 不可領域チェック: claude-code-action が全 thread resolved 後に approve を発行する Step 5-A（REVIEW.md / templates/REVIEW.md.tpl 追加）— OK（6分類いずれにも非該当。プロンプト文字列変更のみ、permissions/secrets/トリガー/Fork PR 除外/GitHub App 権限スコープ変更なし）
- 2026-05-06 — 不可領域チェック: claude-code-action がレビューコメントを出さずにサイレント終了（REVIEW.md 指示書形式書き換え）— OK（6分類いずれにも非該当。permissions/secrets/トリガー/Fork PR 除外/GitHub App 権限スコープ変更なし）
- 2026-05-06 — 不可領域チェック: auto-approve/command-log/sandbox セキュリティ強化 Issue — OK（4件全て保護強化方向、不可領域1〜6非該当。自律実行起票可）
- 2026-05-06 — 不可領域チェック: PR_NUMBER 環境変数が渡されずレビューが空振りする問題（ai-review.yml env: セクション追加）— OK（6分類いずれにも非該当。env: 追加は公開情報の伝播のみ、permissions/secrets/トリガー/Fork PR 除外/GitHub App 権限スコープ変更なし）
- 2026-05-06 — 不可領域チェック: PR intent ラベル数チェックのレースコンディション修正（ai-review.yml needs: 依存追加）— OK（6分類いずれにも非該当、permissions/secrets/Fork PR 除外変更なし）
- 2026-05-06 — 不可領域チェック: Issue #360 子「配布スキル/フックの動作バグを一括修正」— 条件付き承認: 8件中 #3(diagnose-guard.sh)のみ不可領域4該当・CEO承認済みで人間承認ルート通過。自律起票は除外、/ship は可
- 2026-05-06 — 不可領域チェック: /ship が PR 作成時に Issue から intent ラベルを継承するようになる — OK（6分類いずれにも非該当。ai-review.yml 変更は継承ステップ削除のみ、permissions/secrets/Fork PR 除外変更なし）
- 2026-05-06 — Issue #513 管轄ドキュメント整合性チェック（command-log マスキング + claude.sb process-exec ホワイトリスト + SECURITY.md 更新）— 承認: 整合性問題なし、AWS_ACCESS_KEY_ID マスク補完を次 Issue で推奨
- 2026-05-04 — Issue #468 sync-check 再実行: docs/ai-review-auth.md §5 検証ロジック表更新 — 承認: 実装・ドキュメント・SECURITY.md 整合確認、セキュリティリスクなし
- 2026-05-04 — Issue #465 REVIEW.md prompt 引き渡し経路メタレビュー — 条件付き承認: 外部 prompt injection 封鎖確認、ai-review-auth.md §3 ワークフロー構成表への review_prompt ステップ追記を条件とする
- 2026-05-04 — Issue #461 sync-check 再実行（ai-review-auth.md §3 + ワークフロー構成節）— 承認: 前回指摘2点の解消確認、新たなセキュリティ的乖離なし
- 2026-05-04 — Issue #461 ai-review.yml 新規追加メタレビュー — 条件付き承認: secrets 流出リスクなし、ai-review-auth.md の Fork PR 除外方式記述更新を条件とする
- 2026-05-03 — claude-code-action GitHub App 権限スコープ設計 / autonomous-restrictions.md 該当性 — 条件付き承認: 最小スコープ制限・pull_request_target 禁止・CI エージェントカテゴリ追記の5条件を満たすこと
- 2026-04-29 — 不可領域チェック: docs/SECURITY.md・README.md の多層防御アーキテクチャ反映（Issue #439/#442/#448 docs 反映）— OK（5分類いずれにも非該当、ドキュメント更新のみ）
- 2026-04-29 — Issue #452 計画メタレビュー（protect-knowledge-bash-writes.sh 実装照合）— 承認: 計画の SECURITY.md 記述が実装と完全一致、Phase 1a/1b 実施可
- 2026-04-29 — Issue #448 修正コミット 41e0060 メタレビュー（実装後） — 承認: M-001/M-002/M-003 全修正確認、多層防御設計強度 OK、認証・credential 変更なし
- 2026-04-29 — Issue #448 protect-knowledge-bash-writes.sh 実装計画メタレビュー — 差し戻し: Major 3点（env プレフィックス単一除去・bash -c バイパス未検出・buffer prefix false allow）を修正後に再提出
- 2026-04-29 — Issue #442 knowledge 構造統一（monitoring ログ四半期集約 refactor）— 承認: リスクなし（deny パターン拡大方向、buffer フロー境界維持）
- 2026-04-25 — 不可領域チェック: --plugin-dir 自動付与シェル関数（~/.zshrc 追加） — OK（5分類いずれにも該当しない）
- 2026-04-25 — 不可領域チェック: --plugin-dir 自動付与 scripts/dev.sh ラッパー方式 — OK（5分類いずれにも該当しない）
- 2026-04-22 — 承認ダイアログのスマホ remote app 非表示問題 — 除外（ガードレール領域: protect-files.sh 承認フロー変更リスク）
- 2026-04-20 — docs/SECURITY.md プリセット別動作表の誤記修正（standard 行 /autopilot を「動作しない」に訂正）
- 2026-04-20 — Issue #361 /issue と /autopilot の責務分離 + 3者承認ゲート導入（条件付き承認: SECURITY.md 更新・/diagnose ゲート確認を条件）
- 2026-04-19 — Issue #366 配布物の Source of Truth テンプレート化
- 2026-04-18 — プリセット別安全性評価（full/standard/minimal × sandbox/Hook）
- 2026-04-18 — Issue #296 protect-branch.sh worktree 誤検知修正
- 2026-04-17 — Issue #331 VIBECORP_ISOLATION=1 下の /login 失敗修正 Part2（XDG サイドカー拡張）
- 2026-04-17 — Issue #329 VIBECORP_ISOLATION=1 下の /login 失敗修正（サイドカー書込許可追加）
- 2026-04-17 — Issue #326 ゲートスタンプの XDG キャッシュ移動（docs/SECURITY.md 不整合修正）
- 2026-04-16 — Issue #320 合議制最終チェック（security-analyst ×3 メタレビュー）
- 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）
- 2026-04-16 — Issue #318 Phase 3a: install.sh macOS 隔離レイヤ配置ロジック統合
- 2026-04-16 — Issue #309 macOS sandbox-exec PoC（Phase 1）
- 2026-04-16 — CR-001 CodeRabbit 第 2 回レビュー対応（WORKTREE ⊇ HOME 攻撃経路）

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
