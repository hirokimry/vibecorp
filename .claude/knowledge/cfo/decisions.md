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
