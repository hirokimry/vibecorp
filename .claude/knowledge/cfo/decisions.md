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
