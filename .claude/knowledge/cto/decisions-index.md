# CTO 技術判断記録インデックス

このファイルは目次。CTO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-04-25 — Plugin 名前空間 Phase 3 互換スタブ廃止 — plugin_skills セクションを照合基準に採用、廃止コードは生成ループ＋mkdir を一括削除
- 2026-04-24 — Issue #352 フォローアップ — docs/design-philosophy.md プラグイン配布方式セクションに Plugin 名前空間移行検討中（Phase 1 完了・Phase 2 待ち）を現行方針と並記
- 2026-04-24 — Issue #352 — Plugin 名前空間 Phase 1 実機検証。Go 判定（`--plugin-dir .` で `vibecorp:review` の名前空間解決を実機確認。永続化方法が Phase 2 の課題）
- 2026-04-23 — diagnose 上限ガードレール文書化 — 3ファイル間（autonomous-restrictions.md・vibecorp.yml・cost-analysis.md）の整合性確認、矛盾なし
- 2026-04-23 — Issue #392 — `settings.json` の allow リストに `.claude/rules/**` の Write/Edit を追加（teammate の承認ダイアログ停止を解消）
- 2026-04-20 — Issue #361 — /issue を CISO + CPO + SM の3者承認ゲートに拡張、/autopilot のラベル縛り撤廃と起票側フィルタ集約（透過パイプ設計）
- 2026-04-19 — Issue #366 — 2026-04-16 の activate.sh heredoc 採用判断を撤回
- 2026-04-18 — docs/design-philosophy.md の管轄を CTO として正式化（Issue #364 補足）
- 2026-04-18 — Issue #364 — テンプレート整備・参照解消の設計判断（3件）
- 2026-04-18 — protect-branch.sh の worktree 誤検知問題 — 案1（ファイルパス基準）を正解設計として採用（Issue #296）
- 2026-04-18 — `.coderabbit.yaml` テンプレート配布の取り下げ（Issue #348 再評価）
- 2026-04-18 — （再評価）: Semgrep 採用見直し — YAGNI 原則により不採用
- 2026-04-18 — CodeRabbit による cross-PR 統合問題検出の技術評価
- 2026-04-18 — Hook と sandbox 隔離の役割分担評価（full = sandbox + skip-permissions 前提）
- 2026-04-17 — 原子的置換パターンの実挙動確認とSBPL設計（Issue #329）
- 2026-04-17 — ゲートスタンプの保存先を `.claude/` 外に切り出し（Issue #326）
- 2026-04-16 — `git pull` による意図しない merge commit 混入の扱い
- 2026-04-16 — ゲートスタンプ XDG 移行に伴う実装上の技術判断（PR #327）
- 2026-04-16 — ドキュメントの「正典委譲」パターン — パス列挙は実装ファイルに委譲
- 2026-04-16 — claude TUI ハング修正 — sandbox-exec プロファイルへの `file-ioctl` 追加（Issue #320）
- 2026-04-16 — install.sh に macOS 隔離レイヤ配置ロジックを統合（Phase 3a / Issue #318）
- 2026-04-16 — vibecorp-sandbox に symlink 解決 + 2 段階検証と WORKTREE ⊇ HOME 拒否を追加（PR #317 第 2 回レビュー対応）
- 2026-04-16 — docs/design-philosophy.md にプロセス隔離（Phase 1 PoC）セクションを追加
- 2026-04-16 — 環境変数を認証・セキュリティ境界として使う場合の設計方針
- 2026-04-16 — ship-parallel / autopilot を full プリセット専用に格下げ（Issue #308）
- 2026-04-11 — spike-loop SKILL.md の kill+cleanup セクションを自己矛盾のない手順に書き換え（PR #264）
- 2026-04-11 — --dangerously-skip-permissions のコンテナ化隔離方式の評価
- 2026-04-11 — spike-loop を full プリセット専用とした判断（Issue #263 前提）
- 2026-04-11 — command-log ベースの stuck 検出（10分閾値）と 30 秒間隔ポーリングの採用（spike-loop）
- 2026-04-11 — ヘッドレス Claude を子プロセスとして起動し PID 管理するアーキテクチャパターンの採用（spike-loop）
- 2026-04-10 — ship-parallel の Agent 起動に mode: "dontAsk" を指定（Issue #260）
- 2026-04-08 — compound command の分割を SKILL.md で制約（Issue #258）
- 2026-04-08 — team-auto-approve.sh — quote-aware セグメント分割への置き換え（Issue #252）
- 2026-04-05 — /issue スキルへの preset 条件分岐型 CPO ゲートの採用
- 2026-04-05 — team-auto-approve.sh — Bash コマンドの多段検証とセグメント分割（Issue #233 対応）
- 2026-04-03 — （ゼロベース再評価）: /loop 公式コマンド前提での pr-review-loop 設計評価
- 2026-04-03 — （再評価）: pr-review-loop の /loop 分割方式の評価
- 2026-04-03 — pr-review-loop の終了条件見直し提案の評価
- 2026-04-02 — command-log.sh — コマンドログ型フックを新分類として追加（Issue #216）
- 2026-04-02 — protect-branch.sh — メインブランチ保護フックの追加
- 2026-03-29 — skills / hooks のトグル設定を opt-out 方式で実装（Issue #61）
- 2026-03-22 — templates/settings.json.tpl からレガシーパス .claude/vibecorp/hooks/sync-gate.sh を削除
- 2026-03-22 — settings.json マージ時に unique_by(.command) でフック重複を排除

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
