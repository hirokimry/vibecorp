# CTO 技術判断記録インデックス

このファイルは目次。CTO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ
- 2026-05-09 — PR #534 — workflow 削除 PR 自身を実機検証として採用。GitHub Actions ランタイムアサーション（API 検証）は heavy lift かつ静的保証で十分として却下 (from CodeRabbit review on PR #534)
- 2026-05-08 — PR #520 — race condition 修正での PR 分割却下。責務委譲と CI 削除は分離不可能な構成要素であり一括対応が正しい設計
- 2026-05-07 — PR #507 — CI ワークフローの graceful skip 却下。シークレット未登録時は fail-fast が正しい設計（緑なのに動いていない状態を防ぐ）(from CodeRabbit review on PR #507)
- 2026-04-29 — PR #453 — grep -qxF（行全体一致）vs -qF（部分一致）の使い分け。SoT ファイルの記述スタイル（単独行 vs 文中引用）に応じて選択 (from CodeRabbit review on PR #453)
- 2026-05-08 — Issue #532 — design-philosophy.md に ai-review-golden-test.yml 配布記述・遡及削除ロジックを追記。ai-review-auth.md / ai-review-dependency.md は role-gate により CTO 管轄外でブロック（管轄未定義の技術的負債を記録）
- 2026-05-08 — Issue #311 Phase 3 — 環境変数パス上書き・uname 偽装の 2 テスト容易性パターンを shell.md に標準化。テストファイル書き分け基準を testing.md に追記
- 2026-05-06 — Epic #455 — claude-action CHANGES_REQUESTED 残存問題。真因はGitHub review state の永続性とサーバーサイド状態管理欠如。REVIEW.md に「全スレッド resolved なら approve 発行」指示追加（案A採用）で構造的解決
- 2026-05-04 — Issue #469 — intent ラベル機構・CC 11 種ポリシー導入のドキュメント整合性チェック。ai-review-auth.md 行97 の「0 または 2 以上で fail」記述と ai-review.yml 実装（2 以上のみ）が矛盾。design-philosophy.md への intent ラベル参照追加は推奨（必須ではない）
- 2026-05-04 — Issue #468 — claude_action セクション追加に伴うドキュメント整合性チェック。実装に矛盾なし。design-philosophy.md に claude_action 設計意図の記載が欠落しており要更新
- 2026-05-04 — Issue #468 sync-check 再実行 — design-philosophy.md の claude_action 対応確認。前回「要更新」が解消、ai-review-auth.md §5 も整合あり。全ファイル OK
- 2026-05-04 — Issue #465 — REVIEW.md 新規追加・skip_paths 連動設計のドキュメント整合性チェック。design-philosophy.md は skip_paths の「単一入力源 → REVIEW.md + .coderabbit.yaml 双方反映」設計の記述漏れで要更新。矛盾なし
- 2026-05-04 — Issue #461 — ai-review.yml 実体追加のドキュメント整合性チェック。design-philosophy.md OK。ai-review-auth.md §3（明示 if 不要 vs 実装に if あり）矛盾・coderabbit-dependency.md 並走記述漏れで要更新 2 点
- 2026-05-04 — Issue #461 sync-check 再実行 — §3「防御的実装」書き換え確認。矛盾解消済み。ai-review.yml・テスト・install.sh 実装と整合。coderabbit-dependency.md 更新漏れは #472 で後送り。総合 OK
- 2026-05-03 — vibecorp 独自 severity 5段階の厳密定義設計 — Critical/Major/Minor/Trivial/Info の境界を「他環境影響有無・入力パス存在・MUST 条件違反・改善見込み」の4軸で客観定義
- 2026-05-03 — Issue #455 — 3 軸（CC type / 絵文字 / intent ラベル）を「読み手別責務分離」として設計確定。CC prefix はツール向け、絵文字は人間向け、intent はレビュー AI 向け。独自 type 14 種の CC 吸収ルールを策定。design type の条件分岐は Issue #469 に持ち越し
- 2026-05-02 — CodeRabbit 代替評価（A/B/C） — 第一推奨 C（カスタム強化）。A は OAuth クォータ枯渇リスク、B は AGPL-3.0 ライセンス感染リスクで不採用。`coderabbit.enabled: bool` → `review_provider.type` 移行を技術的負債として記録
- 2026-04-29 — diagnose 上限ガードレール補記 — PR #247 で max_issues_per_run/day が 7/14 に変更されたため 2026-04-23 エントリに補記
- 2026-04-29 — Source of Truth 起点の値同期検証パターン — vibecorp.yml を基準に5ファイル間の値同期を検証するテストパターンと awk 抽出関数を記録
- 2026-04-29 — PR #453 — knowledge ガードレール多層防御ドキュメント（SECURITY.md・ai-organization.md 等）が design-philosophy.md と矛盾なし・更新漏れなし
- 2026-04-29 — PR #445 sync-check (d97d677) — glob パターン統一・フォールバック検知スコープ修正の整合性確認、矛盾なし
- 2026-04-29 — .claude/knowledge/ 構成整合性評価（Issue #439 関連） — 構成 A（C*O 2段）は正当、構成 B（分析員フラット）は意図未文書化で技術的負債。Phase 1 でドキュメント整備、Phase 2 で監査ログ四半期集約構造への移行を推奨
- 2026-04-28 — Issue #427 — テストヘルパー（pass/fail/assert_*）重複定義削除で `test_agents_decisions.sh` のみ意図的に残存（出力スタイル差異のため対象外、PR 本文・実装計画に明記） (from CodeRabbit review on PR #427)
- 2026-04-25 — ~/.zshrc シェル関数による --plugin-dir 自動付与案のレビュー — 動作は正しいが重複指定挙動の確認と CLAUDE.md 明記を推奨（案B+C 組み合わせ方針と整合）
- 2026-04-25 — Plugin 名前空間 Phase 3 互換スタブ廃止 — plugin_skills セクションを照合基準に採用、廃止コードは生成ループ＋mkdir を一括削除
- 2026-04-25 — Issue #359 Phase 3 ドキュメント整合性チェック — design-philosophy.md と file-placement.md の3層アーキテクチャ図に廃止済み .claude/skills/ 行が残存。要更新
- 2026-04-25 — CodeRabbit 修正整合性チェック（file-placement.md, plugin-namespace.md, install.sh）— 3件の変更に新たな矛盾なし。file-placement.md の廃止済み .claude/skills/ 行の残存は別途確認推奨
- 2026-04-24 — Issue #352 フォローアップ — docs/design-philosophy.md プラグイン配布方式セクションに Plugin 名前空間移行検討中（Phase 1 完了・Phase 2 待ち）を現行方針と並記
- 2026-04-24 — Issue #352 — Plugin 名前空間 Phase 1 実機検証。Go 判定（`--plugin-dir .` で `vibecorp:review` の名前空間解決を実機確認。永続化方法が Phase 2 の課題）
- 2026-04-23 — diagnose 上限ガードレール文書化 — 3ファイル間（autonomous-restrictions.md・vibecorp.yml・cost-analysis.md）の整合性確認、矛盾なし
- 2026-04-23 — Issue #392 — `settings.json` の allow リストに `.claude/rules/**` の Write/Edit を追加（teammate の承認ダイアログ停止を解消）
- 2026-04-20 — Issue #361 — /issue を CISO + CPO + SM の3者承認ゲートに拡張、/autopilot のラベル縛り撤廃と起票側フィルタ集約（透過パイプ設計）
- 2026-04-19 — Issue #366 — 2026-04-16 の activate.sh heredoc 採用判断を撤回
- 2026-04-18 — （再評価）: Semgrep 採用見直し — YAGNI 原則により不採用
- 2026-04-18 — protect-branch.sh の worktree 誤検知問題 — 案1（ファイルパス基準）を正解設計として採用（Issue #296）
- 2026-04-18 — docs/design-philosophy.md の管轄を CTO として正式化（Issue #364 補足）
- 2026-04-18 — `.coderabbit.yaml` テンプレート配布の取り下げ（Issue #348 再評価）
- 2026-04-18 — Issue #364 — テンプレート整備・参照解消の設計判断（3件）
- 2026-04-18 — Hook と sandbox 隔離の役割分担評価（full = sandbox + skip-permissions 前提）
- 2026-04-18 — CodeRabbit による cross-PR 統合問題検出の技術評価
- 2026-04-17 — 原子的置換パターンの実挙動確認とSBPL設計（Issue #329）
- 2026-04-17 — ゲートスタンプの保存先を `.claude/` 外に切り出し（Issue #326）
- 2026-04-16 — 環境変数を認証・セキュリティ境界として使う場合の設計方針
- 2026-04-16 — ドキュメントの「正典委譲」パターン — パス列挙は実装ファイルに委譲
- 2026-04-16 — ゲートスタンプ XDG 移行に伴う実装上の技術判断（PR #327）
- 2026-04-16 — vibecorp-sandbox に symlink 解決 + 2 段階検証と WORKTREE ⊇ HOME 拒否を追加（PR #317 第 2 回レビュー対応）
- 2026-04-16 — ship-parallel / autopilot を full プリセット専用に格下げ（Issue #308）
- 2026-04-16 — install.sh に macOS 隔離レイヤ配置ロジックを統合（Phase 3a / Issue #318）
- 2026-04-16 — docs/design-philosophy.md にプロセス隔離（Phase 1 PoC）セクションを追加
- 2026-04-16 — claude TUI ハング修正 — sandbox-exec プロファイルへの `file-ioctl` 追加（Issue #320）
- 2026-04-16 — `git pull` による意図しない merge commit 混入の扱い
- 2026-04-11 — ヘッドレス Claude を子プロセスとして起動し PID 管理するアーキテクチャパターンの採用（spike-loop）
- 2026-04-11 — spike-loop を full プリセット専用とした判断（Issue #263 前提）
- 2026-04-11 — spike-loop SKILL.md の kill+cleanup セクションを自己矛盾のない手順に書き換え（PR #264）
- 2026-04-11 — command-log ベースの stuck 検出（10分閾値）と 30 秒間隔ポーリングの採用（spike-loop）
- 2026-04-11 — --dangerously-skip-permissions のコンテナ化隔離方式の評価
- 2026-04-10 — ship-parallel の Agent 起動に mode: "dontAsk" を指定（Issue #260）
- 2026-04-08 — team-auto-approve.sh — quote-aware セグメント分割への置き換え（Issue #252）
- 2026-04-08 — compound command の分割を SKILL.md で制約（Issue #258）
- 2026-04-05 — team-auto-approve.sh — Bash コマンドの多段検証とセグメント分割（Issue #233 対応）
- 2026-04-05 — /issue スキルへの preset 条件分岐型 CPO ゲートの採用
- 2026-04-03 — （再評価）: pr-review-loop の /loop 分割方式の評価
- 2026-04-03 — （ゼロベース再評価）: /loop 公式コマンド前提での pr-review-loop 設計評価
- 2026-04-03 — pr-review-loop の終了条件見直し提案の評価
- 2026-04-02 — protect-branch.sh — メインブランチ保護フックの追加
- 2026-04-02 — command-log.sh — コマンドログ型フックを新分類として追加（Issue #216）
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
