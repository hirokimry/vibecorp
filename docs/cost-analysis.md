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
| /vibecorp:diagnose 1回（full プリセット、15エージェント並列） | 入力 500K / 出力 100K | Opus 4.6 | 約 $15 |
| /vibecorp:ship 1回（標準的な Issue） | 入力 200K / 出力 50K | Sonnet 4.6 | 約 $1.4 |
| /vibecorp:ship-parallel 5 Issue 並列 | 入力 1M / 出力 250K | Sonnet 4.6 | 約 $7 |
| /vibecorp:issue 1回（CPO 単独ゲート、変更前） | 入力 25K / 出力 5K | Sonnet 4.6 | 約 $0.15 |
| /vibecorp:issue 1回（CISO + CPO + SM 3者並列ゲート、変更後） | 入力 75K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| /vibecorp:session-harvest 1回（セッション末尾、5 C\*O 委任） | 入力 60K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| /vibecorp:review-harvest 1回（30K 切り詰め後、5 C\*O 委任） | 入力 50K / 出力 10K | Sonnet 4.6 | 約 $0.35 |
| /vibecorp:knowledge-pr 1回（buffer ブランチ → PR 化） | 入力 5K / 出力 2K | Sonnet 4.6 | 約 $0.05 |

上記はあくまで想定値。実運用では Issue 規模・レビューループ回数により大きく変動するため、月次の実測値で補正すること。

**知見閉ループの追加コスト**: `/vibecorp:autopilot` は `/vibecorp:review-harvest` → `/vibecorp:knowledge-pr` を 1 サイクルで 1 回ずつ呼ぶ（合計 約 $0.40/サイクル）。`/vibecorp:session-harvest` はセッション末尾で任意起動（約 $0.45/回）。`/vibecorp:review-harvest` は `VIBECORP_HARVEST_MAX_PRS`（デフォルト 50）と 30K トークン切り詰めで上限を抑制している。空セッション・空差分時の無駄呼び出し回避は `/vibecorp:session-harvest` の diff-zero 早期終了で対応。

**Issue #361 による /vibecorp:issue コスト変化**: 起票承認ゲートが CPO 単独（約 $0.15/回）から CISO + CPO + SM の 3 エージェント並列（約 $0.45/回）に拡張され、1 回あたりのコストは約 3 倍になった。`/vibecorp:autopilot` が全 open Issue を対象化したことで `/vibecorp:ship-parallel` の実行数が増加しうる点にも注意が必要。Issue 量が多いリポジトリでは `/vibecorp:issue` の呼び出し頻度を月次コストレビューで定期確認すること。

### 推奨運用

- MUST: full プリセット導入前に `docs/cost-analysis.md` の本節を確認すること
- MUST: ANTHROPIC_API_KEY を設定する場合は Anthropic Console の使用量アラートを有効化すること
- SHOULD: 本番で full プリセットを常時運用する前に、1週間の試験運用でコスト実測を取ること

## 自律実行の上限ガードレール

`/vibecorp:diagnose` → `/vibecorp:autopilot` → `/vibecorp:ship-parallel` の自律改善ループが予算を超過しないよう、`.claude/vibecorp.yml` の `diagnose` セクションで起票数・変更ファイル数の上限をデフォルトで設けている。ここに記載の値は Source of Truth であり、`.claude/rules/autonomous-restrictions.md` により「課金構造」領域として自律変更禁止である。

### デフォルト値

| 設定キー | デフォルト値 | 意味 | 超過時の挙動 |
|---------|------------|------|-------------|
| `max_issues_per_run` | 7 | 1 回の `/vibecorp:diagnose` → `/vibecorp:autopilot` 実行あたりの最大起票数 | 超過分の候補を起票対象から除外（`/vibecorp:diagnose` ステップ6） |
| `max_issues_per_day` | 14 | 1 日あたりの最大起票数（diagnose ラベル付き Issue を当日 UTC で集計） | 当日の残枠を超えた候補を起票対象から除外 |
| `max_files_per_issue` | 10 | 1 Issue あたりの最大対象ファイル数 | 超過する改善候補を起票対象から除外（分割起票を促す） |

### 値の根拠（コスト観点）

> **丸めルール**: コスト概算は各サブステップの見積もりを合算し、サイクル単位で四捨五入している。端数の内訳は参考として記載するが、日次・月次の試算はサイクル単価（約 $25、Issue #361 以降の `/issue` ゲート追加分を反映）を基準に算出する。

- **`max_issues_per_run`: 7** — `/vibecorp:autopilot` 1 サイクルを「`/vibecorp:diagnose`（Opus 4.6, 約 $15）+ `/vibecorp:ship-parallel` 7 Issue 並列（Sonnet 4.6, 約 $9.80）+ `/issue` ゲート 7 回（Sonnet 4.6, 約 $0.45 × 7 = $3.15）+ `/vibecorp:review-harvest` + `/vibecorp:knowledge-pr`（合計 約 $0.40）」と想定し、1 サイクルの上限コストを約 $28（cycle 単価 $25 にレビューループ等の追加分を含む）に収める。CEO + CFO 議論（Issue #247）により、`/diagnose` 固定費 600K token を効率最大化するために 7 件で 14 件候補を 2 サイクルで完全消化する設計。`Claude Max 20` 定額環境では金銭限界費用ゼロのため、レート制限（5 時間あたりのトークン上限）の余裕確保が制約軸となる
- **`max_issues_per_day`: 14** — `max_issues_per_run` × 2 として導出した日次上限値。1 日に複数サイクル運用しても本値を超えないようガードする独立した上限であり、特定の cadence を前提としない。**推奨運用 cadence は 24 時間ごと**（旧 12 時間ごと運用ではレート制限が逼迫するため非推奨。次節の試算表で 24h 推奨は 7 Issue/日となる）。満枠運用時の月額概算は次節の試算表を参照
- **`max_files_per_issue`: 10** — 1 Issue のレビュー・マージ工程が破綻しない変更規模の経験則。10 を超える改善は分割起票が原則

### /vibecorp:autopilot 定期実行時のコスト試算

`/loop` や cron で `/vibecorp:autopilot` を定期実行する場合、全枠起票される最大ケースの概算（**推奨運用は 24 時間ごと**、Issue #247 の CFO 推奨に基づく）:

| 実行頻度 | 1 日あたりの起票上限 | 月額概算（満枠時） | 推奨度 |
|---------|--------------------|--------------------|-------|
| **24 時間ごと（1 日 1 回）** | **7 Issue** | **約 $840** | ✅ **推奨**（Q1 レート余裕 / Q2 失敗総量の最適バランス） |
| 12 時間ごと（例: `/loop /vibecorp:autopilot 12h`） | 14 Issue | 約 $1,680 | ⚠️ 非推奨（Claude Max 20 のレート制限に逼迫しやすい） |
| 週 1 回 | 7 Issue | 約 $112 | 🟢 低コスト運用 |

- 上記は 1 サイクル約 $28（`/vibecorp:diagnose` + `/vibecorp:ship-parallel` 7 並列 + `/issue` ゲート 7 回 + `/vibecorp:review-harvest` + `/vibecorp:knowledge-pr`）× 実行頻度で算出した満枠試算
- 実運用では改善候補がない日・CI 失敗によるリトライ・レビューループ回数により変動する
- MUST: `ANTHROPIC_API_KEY` を設定して `/vibecorp:autopilot` を定期実行する場合、Anthropic Console の使用量アラート（月額 80% / 100% 到達時通知）を必ず有効化すること
- NOTE: `Claude Max 20` 定額プラン（$200/月）で運用する場合、上記 API 換算は無効（プラン定額に集約）。代わりにレート制限（5 時間あたりのトークン上限）への接触余裕が制約軸となるため、**24 時間ごと運用での月間 token 消費 約 90M を目安**とする

### 変更時のルール

- MUST: `max_issues_per_run` / `max_issues_per_day` / `max_files_per_issue` の値を変更する場合、`.claude/vibecorp.yml` と本ドキュメントを同時に更新し、値の整合を保つこと
- MUST NOT: 自律改善ループ（`/vibecorp:diagnose` → `/vibecorp:autopilot`）がこれらの値を変更してはならない。`.claude/rules/autonomous-restrictions.md` の「課金構造」領域として自律変更禁止
- SHOULD: 値を変更する場合、CFO によるコスト影響評価（`/vibecorp:audit-cost`）を事前に実施すること

## 事後監査

`/vibecorp:audit-cost`（full プリセット限定）で CFO による週次コスト監査を自動化できる。直近7日間のコード変更を分析し、`knowledge/accounting/audit-YYYY-MM-DD.md` にレポートを保存する。Critical / Major 指摘がある場合は自動で `audit` ラベル付き Issue を起票する。

### 定期実行例

```bash
# 毎週月曜 09:00 JST に実行
/schedule weekly "0 0 * * 1" /vibecorp:audit-cost
```

または cron で:

```bash
# crontab -e
0 0 * * 1 cd /path/to/repo && claude -p "/vibecorp:audit-cost"
```

### 監査観点

- API 呼び出し箇所の増減
- `ANTHROPIC_API_KEY` を扱う箇所の変更
- ヘッドレス Claude 起動（`claude -p` / `npx` / `bunx`）の増減
- コスト上限設定（`max_issues_per_day` 等）の変更
- 従量課金到達リスクの変化
- エージェントのモデル指定（Opus / Sonnet / Haiku）の役割妥当性
  - C-suite・合議制分析員・プロセス管理（`sm`）での Haiku 指定は品質劣化リスク（Major）
  - 定型作業ロールでの Opus 指定は過剰指定（Major）
  - モデル未指定（親継承）は明示推奨（Minor）
  - 判定は本ドキュメントの「モデル単価」表と「プリセット別の想定運用モード」を根拠とし、CFO は警告のみ行う（自動変更は行わない）

## monthly cost cap 運用方針

vibecorp は月次コスト上限の自動制御機構を **意図的に持たない**。代わりに本節の手動運用ガイドラインを提供する。利用者は本節に従って自身の運用環境で上限管理を行うこと（Issue #471 / 親エピック #455）。

なお、本ドキュメント冒頭の「予算アラート」節（MUST: 月間予算の 100% 到達時に自動停止または承認フロー発動）における「100% 到達時」とは、後述の **Anthropic Console の 100% 通知を起点として利用者が手動で停止／承認フローを実施する運用**を指す。vibecorp 自体が自動停止する機構は実装しない。

### 設計判断の根拠

- **claude-code-action のデフォルトに任せる**: PR ごとの `max_tokens` / 大規模 PR の閾値は claude-code-action のデフォルト挙動（タイムアウト 10 分、Issue #466）に委ねる。vibecorp 独自の閾値設定キーは追加しない
- **新規キー追加は行わない**（`vibecorp.yml` 側 / claude-code-action 側ともに）: `vibecorp.yml` の `claude_action.enabled` と `claude_action.skip_paths` という既存 2 キー（Issue #468 確定）のみで運用する。月次コスト上限・PR ごとの max_tokens を表現する新規キーは本リリースでは `vibecorp.yml` にも claude-code-action 側設定にも追加しない
- **GitHub Actions minutes 監視機構も持たない**: GitHub Settings → Billing で利用者が手動確認する（後述）

### Claude Max 定額環境での実質上限（90M token/月）

`Claude Max 20`（$200/月）定額プランで `/vibecorp:autopilot` を **24 時間ごと cadence で運用した場合**の、**入力 + 出力の合算月間トークン消費 約 90M token を目安**とする。これは Issue #455 の CFO 条件付き承認における目安値であり、レート制限（5 時間あたりのトークン上限）への接触余裕を確保する基準である。

| 指標 | 目安 |
|------|------|
| 月間トークン消費上限（Claude Max 20 定額、入力 + 出力合算） | **約 90M token/月** |
| 前提運用条件 | full プリセット + `/vibecorp:autopilot` 24 時間ごと |
| 24 時間ごと運用での 1 日あたり消費（入力 + 出力合算） | 約 3M token/日 |
| 推奨運用 cadence | 24 時間ごと（`/loop /vibecorp:autopilot 24h`） |

90M token/月の目安値は Issue #475（実機検証期間）で実測補正する。Claude Max 定額内で動く限り追加課金は発生しないが、レート制限に到達した場合は `ANTHROPIC_API_KEY` への自動フォールバックが働く可能性があるため、Anthropic Console での使用量モニタリング（次節）と Monthly spend limit 設定（次節）を必ず併用すること。

### Anthropic Console 使用量アラート設定手順

`ANTHROPIC_API_KEY` を設定して vibecorp を運用する利用者は、Anthropic Console で月額使用量アラートを必ず有効化すること。vibecorp は API 経由で自動設定する機構を持たないため、利用者が手動で設定する。

#### 設定手順

1. [Anthropic Console](https://console.anthropic.com/) にログインする
2. 左サイドバー `Settings` → `Billing` → `Usage limits` を開く
3. `Monthly spend limit` は **CFO 承認の月次上限（約 90M token/月の想定 USD 換算額）に基づいて設定する**。換算の目安は本ドキュメントの「モデル単価」表（Sonnet 4.6: 入力 $3 / 出力 $15 per 1M token）と「概算コスト」表（`/vibecorp:autopilot` 1 サイクル 約 $28）から算出する。`/vibecorp:autopilot` 24 時間ごと運用なら **月額上限 約 $840**（cf. 「自律実行の上限ガードレール」節の試算表）を Monthly spend limit に設定するのが推奨。最小例（テスト用途）として $100 を設定してもよい
4. `Email notifications` セクションで以下を有効化する:
   - 80% 到達時通知（`Notify at 80% of limit`）
   - 100% 到達時通知（`Notify at 100% of limit`）
5. 通知先メールアドレスを Anthropic アカウントのメールに設定する

#### 推奨閾値

| 運用形態 | アラート設定 | 推奨 Monthly spend limit |
|---------|-------------|------------------------|
| Claude Max 定額のみ（`ANTHROPIC_API_KEY` 未設定） | 設定不要（追加課金が発生しないため） | — |
| `ANTHROPIC_API_KEY` 併用（Max フォールバック含む） | 月額予算の 80% / 100% アラート必須 | CFO 承認の月次上限（約 90M token/月想定で 約 $840、24h cadence 満枠時） |
| API Key のみ運用（Max なし） | 月額予算の 50% / 80% / 100% アラート推奨 | CFO 承認の月次上限（同上） |

- MUST: `ANTHROPIC_API_KEY` を設定する場合、Anthropic Console の使用量アラートを有効化すること（再掲、cf. 「実行モード別の課金モデル」節の推奨運用）
- SHOULD: Anthropic Console の `Usage` ダッシュボードを月次でレビューし、想定との乖離を確認すること

### GitHub Actions minutes の手動確認方法

claude-code-action は GitHub Actions 上で実行されるため、Actions minutes を消費する。vibecorp は独自の Actions minutes 監視機構を持たないため、GitHub ダッシュボードでの手動確認を推奨する。

#### 確認手順

1. GitHub の対象リポジトリまたは組織の `Settings` を開く
2. 左サイドバー `Billing and plans` → `Plans and usage` を開く
3. `Actions` セクションで以下を確認する:
   - 当月の使用 minutes（`Minutes used this month`）
   - 残 minutes（`Minutes remaining`）
   - 課金対象 minutes（プライベートリポジトリの場合）
4. 想定を超えている場合、`.github/workflows/` の trigger 条件（特に claude-code-action の `on:` 節）を見直す

#### 推奨確認頻度

| プラン | 推奨確認頻度 |
|-------|-------------|
| GitHub Free（個人 / Public リポジトリ） | minutes 課金なし、確認不要 |
| GitHub Free（個人 / Private リポジトリ、月 2,000 分無料枠） | 月次 |
| GitHub Team / Enterprise | 月次 |

- SHOULD: 月次で GitHub Settings → Billing → Plans and usage の Actions セクションを目視確認すること
- NOTE: vibecorp は GitHub Actions minutes の自動アラート機構を提供しない。閾値超過の即時検知が必要な利用者は GitHub Marketplace の「Actions usage monitoring」系サードパーティアクションを別途導入すること
