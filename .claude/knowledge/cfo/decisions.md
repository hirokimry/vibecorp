# CFO 判断記録

## 2026-04-16: Issue #318 Phase 3a — install.sh macOS 隔離レイヤ配置ロジック統合

- **合議状況**: 3名全員一致「問題なし」
- **判断**: 承認（コスト面で問題なし）
- **根拠**:
  - 本 PR の変更内容は install.sh によるファイル配置処理（シェルスクリプトのコピー・生成）のみ。Claude プロセス起動を含まず、API コール数・トークン消費量への影響はゼロ
  - PATH シム（`.claude/bin/claude`）は実際の claude 起動を横取りする仕組みだが、sandbox-exec 経由での起動はユーザーが `VIBECORP_ISOLATION=1` を明示設定したときのみ動作する。install.sh 実行自体に API コストは発生しない
  - `generate_activate_script` が唯一の activate.sh 生成源であり、`templates/claude/bin/activate.sh` は存在しない。二重書き込みリスクは実態として存在しない（Analyst 2 の低リスク指摘は根拠なし）
  - `~/.zshrc` への永続化オーバーヘッドはプロセス起動時の CPU コストであり、金銭コストには一切影響しない（Analyst 3 の低リスク指摘はコスト観点で無害と確認）
  - full プリセットの課金警告（`docs/specification.md` L109、`docs/cost-analysis.md` 参照リンク）は本 PR でも維持されており、MUST 制約違反なし
- **数値データ**:
  - API コスト増分: $0（ファイル配置処理のみ）
  - 追加される外部サービス利用: なし
  - sandbox-exec はmacOS 標準ツール（追加費用なし）
- **スケール観点**: 導入先リポジトリ数が増えても install.sh の実行コストは人件費のみ。API 課金への影響は引き続きゼロ

## 2026-04-17: Issue #329 — VIBECORP_ISOLATION=1 下の /login 失敗修正

- **合議状況**: 3名全員一致「問題なし」
- **判断**: 承認（コスト面で問題なし）
- **autonomous-restrictions.md #3 判定**: 抵触しない
- **根拠**:
  - 変更対象は `.claude/sandbox/claude.sb`（sandbox プロファイル）と `docs/SECURITY.md` のみ。API 呼び出し・モデル指定・ヘッドレス Claude 起動方式・コスト上限設定のいずれも変更なし
  - `ANTHROPIC_API_KEY` を使う箇所を変更しない。課金構造定義の変更ではなく、sandbox 内の OAuth state 書込許可（サイドカーファイル許可追加）という動作復旧
  - `docs/cost-analysis.md` の切り替え条件表に照らすと、sandbox 下での fallback 状態（API 従量課金）から Claude Max サブスクリプション定額内動作へ**戻す**方向の変更であり、コストリスクは下がる
  - 実装作業コストは /ship 1回分（Sonnet 4.6 想定、約 $1.4）。Claude Max 定額内で実施
- **数値データ**:
  - API コスト増分: $0（sandbox プロファイル変更のみ）
  - OAuth 復旧後の課金削減方向: ANTHROPIC_API_KEY fallback 発動リスクの解消
  - 追加される外部サービス利用: なし
- **スケール観点**: sandbox ユーザーが増えるほど OAuth 正常動作により ANTHROPIC_API_KEY fallback の発動リスクが下がる。スケール時のコスト影響はプラス方向（節減）のみ

## 2026-04-18: プラン別 SKIP 性のコスト観点判断（CEO 直接依頼）

- **合議状況**: CEO から直接の判断依頼（経理チーム合議なし）
- **判断**: 条件付き承認
- **条件**:
  1. `max_issues_per_day` / `max_issues_per_run` の具体的デフォルト値を `docs/cost-analysis.md` に明記すること
  2. full プリセット起動時に `ANTHROPIC_API_KEY` 設定を検出したらコスト警告を表示する実装を担保すること
- **根拠**:
  - 承認プロンプト待機時間は API トークンを消費しない。従量課金への直接影響はほぼゼロ（Claude Max レート制限ウィンドウの無駄消費という間接コストは存在する）
  - skip-permissions の暴走リスクは /autopilot ループ検出失敗と /spike-loop の終了条件崩壊が主シナリオ。/diagnose 1回 Opus 4.6 換算で約 $15 であり、誤起動・再起動が重なると1日 $50〜$100 超えうる
  - max_issues_per_day 等のガードレールは autonomous-restrictions.md で「課金構造」領域として自律変更禁止だが、現状の設定値が cost-analysis.md に明示されておらず監査の盲点になっている
- **プラン別推奨**:
  - minimal: ゲート Hook は残す。`--dangerously-skip-permissions` は不要。UX 改善はタイムアウト短縮で対応
  - standard: sync-gate / review-gate は残す。繰り返し確認の省略は可。ゲート除去は手戻りコストを招く
  - full: `--dangerously-skip-permissions` は必須（ヘッドレス並列で承認待ちが物理的に不可能）。上限ガードレールの強化が前提条件
- **課金境界維持のための必須制約**:
  - full 起動時の API キー検出警告の実装強制（現状は文書要件のみ）
  - Claude Max フォールバック防止: minimal/standard では `ANTHROPIC_API_KEY` の設定を抑制または警告する
- **推奨監視機構**:
  - weekly `/audit-cost` を full プリセットの必須設定として install.sh に組み込む
  - Anthropic Console 使用量アラート（80% 閾値）を `ANTHROPIC_API_KEY` 設定時の必須手順として明示
  - `/audit-cost` の監査観点に `max_issues_per_day` / `max_issues_per_run` の現在値チェックを追加する
- **数値データ**:
  - 承認待機のコスト増分: $0（トークン消費なし）
  - 暴走シナリオの最大リスク: /diagnose 誤起動 × 3回 = 約 $45/日（Opus 4.6 換算）
  - /ship 1回あたりの作業コスト: 約 $1.4（Sonnet 4.6 換算）
- **スケール観点**: full プリセット導入リポジトリが増えるほど、ガードレール値の未設定リスクが線形に拡大する。ドキュメント整備は早期に実施すべき
