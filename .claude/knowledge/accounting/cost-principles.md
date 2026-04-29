# コスト判断原則

docs/cost-analysis.md のコスト構造と MVV.md から導出される、経理分析員の判断基準。
コスト分析の詳細は `docs/cost-analysis.md` を参照すること。

## コスト構造の前提

vibecorp は `ANTHROPIC_API_KEY` の有無と Claude サブスクリプション種別によって、コスト最適化の制約軸が切り替わる。

### 固定費

| 項目 | 月額 | 備考 |
|------|------|------|
| Claude Max 20 プラン | $200/月 | ANTHROPIC_API_KEY 未設定時の定額運用基準 |

Claude Max 20 定額プラン（`ANTHROPIC_API_KEY` 未設定）での運用時:

- 変動費ゼロ。月額 $200 固定
- 金銭コストではなく **5h レート制限（token quota）への接触余裕（margin）** が制約軸となる
- レート制限を超過するとエージェントがブロックされ、自律改善ループが中断する

### 変動費

`ANTHROPIC_API_KEY` を設定した場合のみ発生する。

| モデル | 入力 (1M token) | 出力 (1M token) | 備考 |
|--------|----------------|----------------|------|
| Claude Opus 4.6 | $15 | $75 | `/vibecorp:diagnose` 用 |
| Claude Sonnet 4.6 | $3 | $15 | `/vibecorp:ship` 系・合議制分析員用 |
| Claude Haiku 4.5 | $1 | $5 | 定型・軽量タスク用 |

Claude Max 定額環境でレート制限に到達し、かつ `ANTHROPIC_API_KEY` が設定されている場合、
**自動的に API 従量課金にフォールバックする**（ユーザー通知なし）。

## cycle 単価の基準値

Issue #247 の CFO 議論で確立した現行 cycle 単価と計算根拠。

### per_run=7 基準（現行）

| サブステップ | モデル | token 概算 | コスト |
|-------------|--------|-----------|--------|
| `/vibecorp:diagnose` 1 回 | Opus 4.6 | 入力 500K / 出力 100K | 約 $15 |
| `/vibecorp:ship-parallel` 7 Issue 並列 | Sonnet 4.6 | 入力 1M / 出力 250K | 約 $9.80 |
| `/vibecorp:issue` ゲート 7 回（3 者並列） | Sonnet 4.6 | 入力 75K × 7 | 約 $3.15 |
| `/vibecorp:review-harvest` + `/vibecorp:knowledge-pr` | Sonnet 4.6 | — | 約 $0.40 |
| **cycle 合計** | — | — | **約 $28** |

**丸めルール（`docs/cost-analysis.md` line 127 踏襲）**: 各サブステップの見積もりを合算し、サイクル単位で四捨五入する。端数の内訳は参考値として保持するが、日次・月次の試算には cycle 単価（約 $28）を基準に用いる。

### per_run=5 基準（旧）

Issue #361 の `/vibecorp:issue` ゲート拡張（CPO 単独 → CISO + CPO + SM 3 者並列）以前は cycle 単価 約 $25。
現在は per_run=5 でも `/issue` ゲートが 3 者並列のため、5 Issue 時の cycle 単価は:
- diagnose $15 + ship 5×$1.40 + issue ゲート 5×$0.45 + harvest $0.40 = 約 $22

per_run を変更する際は本テーブルを更新すること。

## 判断基準

コスト変更を含む PR をレビューする際の分類基準:

### 即却下

- 予算上限を設定せずに外部 API を呼び出す変更
- 従量課金サービスのレート制限・上限設定を削除する変更
- `max_issues_per_run` / `max_issues_per_day` の上限値を自律改善ループが変更する変更（`.claude/rules/autonomous-restrictions.md` 違反）

### 要注意

- 新しい有料サービス・API の導入
- 既存のコスト構造を大幅に変更するアーキテクチャ変更
- `max_issues_per_run` / `max_issues_per_day` の値変更（CFO によるコスト影響評価が必要）
- `ANTHROPIC_API_KEY` の扱いを変更する改修（従量課金フォールバックに影響）
- ヘッドレス Claude 起動（`claude -p` / `npx` / `bunx`）を新規追加または増加させる変更

### 許容

- コスト削減に寄与する最適化（キャッシュ導入、バッチ処理化等）
- 無料枠・既存サブスクリプション内での利用
- diagnose 固定費（Opus 4.6 $15/回）を維持したまま per_run を増やす場合（固定費は per_run と独立）

## スケール時の閾値

### token 消費量の目安（Claude Max 20 定額環境）

Issue #247 CFO 議論で確立したスケール時の閾値テーブル。

| 運用 cadence | 1 日あたりの起票上限 | 月間 token 消費（満枠） | 注意閾値 | 警告閾値 |
|-------------|--------------------|-----------------------|---------|---------|
| **24h ごと（推奨）** | 7 Issue | **約 90M** | 70M | 90M |
| 12h ごと（非推奨） | 14 Issue | **約 180M** | 140M | 180M |
| 週 1 回（低コスト） | 7 Issue | 約 22M | — | — |

- **24h cadence 満枠の月間 token 消費 約 90M** — Claude Max 20 ユーザーの標準目安
- **12h cadence 満枠（約 180M）** は Q1「1 週間でレート制限に当たりかけた」実績に対応する現実態。非推奨
- 70M を超えたらレート制限への接触リスクとして要注意報告
- 90M 到達（月間満枠）はレート逼迫として CFO へエスカレーション

### token 消費の線形モデル

per_run 変更時の追加 token 消費は線形:

| コンポーネント | 1 Issue 増加あたりの追加 token |
|--------------|-------------------------------|
| `/vibecorp:ship` 1 回分 | 約 250K（入力 200K + 出力 50K） |
| `/vibecorp:issue` ゲート 1 回分 | 約 90K（入力 75K + 出力 15K） |
| **1 Issue 増加あたり合計** | **約 340K** |
| diagnose 固定費 | 600K（per_run と独立） |

per_run を 7 → 8 にするとサイクルあたり約 340K 増加。月次コスト試算に反映すること。

### コスト指標の要注意・警告閾値

| 指標 | 注意閾値 | 警告閾値 |
|------|---------|---------|
| 月間 token 消費（24h cadence） | 70M | 90M |
| 月間 token 消費（12h cadence） | 140M | 180M |
| cycle 単価（per_run=7 基準） | $30 | $35 |
| `/vibecorp:issue` ゲートコスト/回 | $0.60 | $0.90 |
| 月額 API 換算（従量課金モード） | $800 | $1,200 |
