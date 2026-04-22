# vibecorp コスト分析

> このドキュメントはプロジェクトのコスト構造・予算管理を定義する Source of Truth です。

## 初期投資（Fixed Costs）

（初年度に必要な固定費の一覧を記載）

| 項目 | 月額 | 年額 | 備考 |
|------|------|------|------|
| （項目名） | （金額） | （金額） | （備考） |

## 変動費

（ユーザーあたり・処理あたりの変動費構造を記載）

### API 利用コスト

| サービス | 単価 | 想定月間量 | 月額見積 |
|----------|------|-----------|----------|
| （サービス名） | （単価） | （想定量） | （見積額） |

### インフラコスト

（スケーラブルなインフラ費用の構造を記載）

## スケール時のコスト予測

（Phase 別のコスト見積もりを記載）

| Phase | ユーザー数 | 月間処理量 | 月額コスト | 備考 |
|-------|-----------|-----------|-----------|------|
| Phase 1 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 2 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 3 | （想定数） | （想定量） | （見積額） | （備考） |

## コスト管理ポリシー

### 予算アラート

- MUST: 月間予算の80%到達時にアラートを発火すること
- MUST: 月間予算の100%到達時に自動停止または承認フローを発動すること

### キャッシュ制御

- MUST: API レスポンスは可能な限りキャッシュし、不要な再呼び出しを防止すること
- MUST NOT: キャッシュ未設定のまま高頻度 API を本番投入しないこと

### 無料枠の活用

（各サービスの無料枠・割引プランの活用方針を記載）

### コストレビュー

- MUST: 月次でコストレビューを実施し、予実差異を分析すること
- MUST: 新規サービス導入時はコスト試算を事前に行うこと

## 実行モード別の課金モデル

vibecorp のエージェント実行は Claude Code のサブスクリプション種別（Claude Max 等の定額プラン）と ANTHROPIC_API_KEY 環境変数の有無により、課金モデルが切り替わる。ユーザーが意識せず full プリセットを導入すると、従量課金に到達して想定外の請求が発生するリスクがある。

### 切り替え条件

| 実行環境 | 課金モデル | 備考 |
|----------|-----------|------|
| Claude Max / Pro サブスクリプション（ANTHROPIC_API_KEY 未設定） | サブスクリプション定額内 | レート制限（5時間あたりのトークン上限）に到達するまで追加課金なし |
| ANTHROPIC_API_KEY 設定あり | API 従量課金 | Anthropic API の 1M token あたり入出力料金が発生 |
| Claude Max でレート制限到達 + API キー設定あり | 自動的に API 従量課金にフォールバック | ユーザー通知なしで切り替わるため注意 |

### プリセット別の想定運用モード

| プリセット | 想定実行モード | 備考 |
|-----------|---------------|------|
| minimal | Claude Max 定額内で運用可能 | 直列実行中心、並列度が低い |
| standard | Claude Max 定額内で運用可能（CTO/CPO が同時起動する場合あり） | 合議制が入らないため並列度は低〜中 |
| full | **従量課金に到達しうる** | C-suite（6ロール）+ 分析員（3ロール × 3回独立実行）が並列起動、並列度が高く Max レート制限を消費しやすい |

### モデル単価（Anthropic 公式価格、1M token あたり）

| モデル | 入力 | 出力 | プロンプトキャッシュ書込 | プロンプトキャッシュ読込 |
|--------|------|------|-------------------------|-------------------------|
| Claude Opus 4.6 | $15 | $75 | $18.75 | $1.50 |
| Claude Sonnet 4.6 | $3 | $15 | $3.75 | $0.30 |
| Claude Haiku 4.5 | $1 | $5 | $1.25 | $0.10 |

最新価格は [Anthropic Pricing](https://www.anthropic.com/pricing) を参照すること。

### 概算コスト（目安）

| シナリオ | 想定トークン | モデル | 概算コスト |
|----------|-------------|-------|-----------|
| /diagnose 1回（full プリセット、15エージェント並列） | 入力 500K / 出力 100K | Opus 4.6 | 約 $15 |
| /ship 1回（標準的な Issue） | 入力 200K / 出力 50K | Sonnet 4.6 | 約 $1.4 |
| /ship-parallel 5 Issue 並列 | 入力 1M / 出力 250K | Sonnet 4.6 | 約 $7 |
| /issue 1回（CPO 単独ゲート、変更前） | 入力 25K / 出力 5K | Sonnet 4.6 | 約 $0.15 |
| /issue 1回（CISO + CPO + SM 3者並列ゲート、変更後） | 入力 75K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| /session-harvest 1回（セッション末尾、5 C\*O 委任） | 入力 60K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| /review-harvest 1回（30K 切り詰め後、5 C\*O 委任） | 入力 50K / 出力 10K | Sonnet 4.6 | 約 $0.35 |
| /knowledge-pr 1回（buffer ブランチ → PR 化） | 入力 5K / 出力 2K | Sonnet 4.6 | 約 $0.05 |

上記はあくまで想定値。実運用では Issue 規模・レビューループ回数により大きく変動するため、月次の実測値で補正すること。

**知見閉ループの追加コスト**: `/autopilot` は `/review-harvest` → `/knowledge-pr` を 1 サイクルで 1 回ずつ呼ぶ（合計 約 $0.40/サイクル）。`/session-harvest` はセッション末尾で任意起動（約 $0.45/回）。`/review-harvest` は `VIBECORP_HARVEST_MAX_PRS`（デフォルト 50）と 30K トークン切り詰めで上限を抑制している。空セッション・空差分時の無駄呼び出し回避は `/session-harvest` の diff-zero 早期終了で対応。

**Issue #361 による /issue コスト変化**: 起票承認ゲートが CPO 単独（約 $0.15/回）から CISO + CPO + SM の 3 エージェント並列（約 $0.45/回）に拡張され、1 回あたりのコストは約 3 倍になった。`/autopilot` が全 open Issue を対象化したことで `/ship-parallel` の実行数が増加しうる点にも注意が必要。Issue 量が多いリポジトリでは `/issue` の呼び出し頻度を月次コストレビューで定期確認すること。

### 推奨運用

- MUST: full プリセット導入前に `docs/cost-analysis.md` の本節を確認すること
- MUST: ANTHROPIC_API_KEY を設定する場合は Anthropic Console の使用量アラートを有効化すること
- SHOULD: 本番で full プリセットを常時運用する前に、1週間の試験運用でコスト実測を取ること

## 自律実行の上限ガードレール

`/diagnose` → `/autopilot` → `/ship-parallel` の自律改善ループが予算を超過しないよう、`.claude/vibecorp.yml` の `diagnose` セクションで起票数・変更ファイル数の上限をデフォルトで設けている。ここに記載の値は Source of Truth であり、`.claude/rules/autonomous-restrictions.md` により「課金構造」領域として自律変更禁止である。

### デフォルト値

| 設定キー | デフォルト値 | 意味 | 超過時の挙動 |
|---------|------------|------|-------------|
| `max_issues_per_run` | 5 | 1 回の `/diagnose` → `/autopilot` 実行あたりの最大起票数 | 超過分の候補を起票対象から除外（`/diagnose` ステップ6） |
| `max_issues_per_day` | 10 | 1 日あたりの最大起票数（kaizen ラベル付き Issue を当日 UTC で集計） | 当日の残枠を超えた候補を起票対象から除外 |
| `max_files_per_issue` | 10 | 1 Issue あたりの最大対象ファイル数 | 超過する改善候補を起票対象から除外（分割起票を促す） |

### 値の根拠（コスト観点）

- **`max_issues_per_run`: 5** — `/autopilot` 1 サイクルを「`/diagnose`（Opus 4.6, 約 $15）+ `/ship-parallel` 5 Issue 並列（Sonnet 4.6, 約 $7）+ `/review-harvest` + `/knowledge-pr`（合計 約 $0.40）」と想定し、1 サイクルの上限コストを約 $22 に抑える目的で設定している。5 を超えると `/ship-parallel` の並列度が上がり Claude Max レート制限（5 時間あたりのトークン上限）を消費しやすくなる
- **`max_issues_per_day`: 10** — `/autopilot` を 1 日 2 回（12 時間ごと）運用しても `max_issues_per_run` × 2 = 10 に収まる。満枠運用時の日次コスト上限は約 $44、月額で約 $1,320 を想定最大値とする
- **`max_files_per_issue`: 10** — 1 Issue のレビュー・マージ工程が破綻しない変更規模の経験則。10 を超える改善は分割起票が原則

### /autopilot 定期実行時のコスト試算

`/loop` や cron で `/autopilot` を定期実行する場合、全枠起票される最大ケースの概算:

| 実行頻度 | 1 日あたりの起票上限 | 月額概算（満枠時） |
|---------|--------------------|--------------------|
| 12 時間ごと（例: `/loop /autopilot 12h`） | 10 Issue | 約 $1,320 |
| 24 時間ごと（1 日 1 回） | 5 Issue | 約 $660 |
| 週 1 回 | 5 Issue | 約 $88 |

- 上記は 1 サイクル約 $22（`/diagnose` + `/ship-parallel` 5 並列 + `/review-harvest` + `/knowledge-pr`）× 実行頻度で算出した満枠試算
- 実運用では改善候補がない日・CI 失敗によるリトライ・レビューループ回数により変動する
- MUST: `ANTHROPIC_API_KEY` を設定して `/autopilot` を定期実行する場合、Anthropic Console の使用量アラート（月額 80% / 100% 到達時通知）を必ず有効化すること

### 変更時のルール

- MUST: `max_issues_per_run` / `max_issues_per_day` / `max_files_per_issue` の値を変更する場合、`.claude/vibecorp.yml` と本ドキュメントを同時に更新し、値の整合を保つこと
- MUST NOT: 自律改善ループ（`/diagnose` → `/autopilot`）がこれらの値を変更してはならない。`.claude/rules/autonomous-restrictions.md` の「課金構造」領域として自律変更禁止
- SHOULD: 値を変更する場合、CFO によるコスト影響評価（`/audit-cost`）を事前に実施すること

## 事後監査

`/audit-cost`（full プリセット限定）で CFO による週次コスト監査を自動化できる。直近7日間のコード変更を分析し、`knowledge/accounting/audit-YYYY-MM-DD.md` にレポートを保存する。Critical / Major 指摘がある場合は自動で `audit` ラベル付き Issue を起票する。

### 定期実行例

```bash
# 毎週月曜 09:00 JST に実行
/schedule weekly "0 0 * * 1" /audit-cost
```

または cron で:

```bash
# crontab -e
0 0 * * 1 cd /path/to/repo && claude -p "/audit-cost"
```

### 監査観点

- API 呼び出し箇所の増減
- `ANTHROPIC_API_KEY` を扱う箇所の変更
- ヘッドレス Claude 起動（`claude -p` / `npx` / `bunx`）の増減
- コスト上限設定（`max_issues_per_day` 等）の変更
- 従量課金到達リスクの変化
