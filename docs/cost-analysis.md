# 💰 vibecorp コスト分析

> [!IMPORTANT]
> 読者像は CEO（経営者）と vibecorp 導入の利用者。
> 本ドキュメントはプロジェクトのコスト構造・予算管理の **Source of Truth**。
> 数値（90M token/月、$840、モデル単価、上限値）は予算判断の根拠として固定する。

## 初期投資（Fixed Costs）

初年度に必要な固定費の一覧を記載する。

| 項目 | 月額 | 年額 | 備考 |
|---|---|---|---|
| （項目名） | （金額） | （金額） | （備考） |

## 変動費

ユーザーあたり・処理あたりの変動費構造を整理する。

### 💸 API 利用コスト

| サービス | 単価 | 想定月間量 | 月額見積 |
|---|---|---|---|
| （サービス名） | （単価） | （想定量） | （見積額） |

### 🏗️ インフラコスト

スケーラブルなインフラ費用の構造を記載する。

## スケール時のコスト予測

Phase 別のコスト見積もりを記載する。

| Phase | ユーザー数 | 月間処理量 | 月額コスト | 備考 |
|---|---|---|---|---|
| Phase 1 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 2 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 3 | （想定数） | （想定量） | （見積額） | （備考） |

## コスト管理ポリシー

### 🚨 予算アラート

- ✅ MUST: 月間予算の 80% 到達時にアラートを発火すること。
- ✅ MUST: 月間予算の 100% 到達時に自動停止または承認フローを発動すること。

### 🗃️ キャッシュ制御

- ✅ MUST: API レスポンスは可能な限りキャッシュし、不要な再呼び出しを防ぐこと。
- ❌ MUST NOT: キャッシュ未設定のまま高頻度 API を本番投入しないこと。

### 🎁 無料枠の活用

各サービスの無料枠・割引プランの活用方針を記載する。

### 📊 コストレビュー

- ✅ MUST: 月次でコストレビューを実施し、予実差異を分析すること。
- ✅ MUST: 新規サービス導入時はコスト試算を事前に行うこと。

## 実行モード別の課金モデル

vibecorp のエージェント実行は、サブスクリプション種別と環境変数の有無で課金モデルが切り替わる。

- 種別: Claude Max 等の定額プラン。
- 環境変数: `ANTHROPIC_API_KEY` の有無。

ユーザーが意識せず full プリセットを導入すると、従量課金に到達して想定外請求のリスクが発生する。

### 🔀 切り替え条件

| 実行環境 | 課金モデル | 備考 |
|---|---|---|
| Claude Max / Pro（`ANTHROPIC_API_KEY` 未設定） | サブスクリプション定額内 | レート制限（5 時間あたり上限）まで追加課金なし |
| `ANTHROPIC_API_KEY` 設定あり | API 従量課金 | Anthropic API の 1M token あたり入出力料金が発生 |
| Claude Max でレート制限到達 + API キーあり | 自動的に API 従量課金にフォールバック | ユーザー通知なしで切り替わるため注意 |

### 🎚️ プリセット別の想定運用モード

| プリセット | 想定実行モード | 備考 |
|---|---|---|
| minimal | Claude Max 定額内で運用可能 | 直列実行中心、並列度が低い |
| standard | Claude Max 定額内で運用可能 | CTO/CPO 同時起動あり、並列度は低〜中 |
| full | **従量課金に到達しうる** | C-suite 6 + 分析員 3×3 が並列、Max レートを消費しやすい |

### 💵 モデル単価（Anthropic 公式価格、1M token あたり）

| モデル | 入力 | 出力 | プロンプトキャッシュ書込 | プロンプトキャッシュ読込 |
|---|---|---|---|---|
| Claude Opus 4.6 | $15 | $75 | $18.75 | $1.50 |
| Claude Sonnet 4.6 | $3 | $15 | $3.75 | $0.30 |
| Claude Haiku 4.5 | $1 | $5 | $1.25 | $0.10 |

最新価格は [Anthropic Pricing](https://www.anthropic.com/pricing) を参照する。

### 📈 概算コスト（目安）

| シナリオ | 想定トークン | モデル | 概算コスト |
|---|---|---|---|
| `/vibecorp:diagnose` 1 回（full、15 エージェント並列） | 入力 500K / 出力 100K | Opus 4.6 | 約 $15 |
| `/vibecorp:ship` 1 回（標準的な Issue） | 入力 200K / 出力 50K | Sonnet 4.6 | 約 $1.4 |
| `/vibecorp:ship-parallel` 5 Issue 並列 | 入力 1M / 出力 250K | Sonnet 4.6 | 約 $7 |
| `/vibecorp:issue` 1 回（CPO 単独ゲート、変更前） | 入力 25K / 出力 5K | Sonnet 4.6 | 約 $0.15 |
| `/vibecorp:issue` 1 回（CISO + CPO + SM 3 者並列、変更後） | 入力 75K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| `/vibecorp:session-harvest` 1 回（5 C\*O 委任） | 入力 60K / 出力 15K | Sonnet 4.6 | 約 $0.45 |
| `/vibecorp:review-harvest` 1 回（30K 切り詰め後、5 C\*O 委任） | 入力 50K / 出力 10K | Sonnet 4.6 | 約 $0.35 |
| `/vibecorp:knowledge-pr` 1 回（buffer ブランチ → PR 化） | 入力 5K / 出力 2K | Sonnet 4.6 | 約 $0.05 |

> [!NOTE]
> 上記はあくまで想定値。
> 実運用では Issue 規模・レビューループ回数で大きく変動する。
> 月次の実測値で補正すること。

### 📌 Issue #564 による `/vibecorp:ship` の入力トークン増分

`/vibecorp:plan` が Issue 全コメントを `gh api ... --paginate` で取り込む変更が入った。

- ⬆️ コメント数の多い Issue では `/vibecorp:ship` 1 回あたりの入力トークンが増加する。
- ✅ bot 投稿（CodeRabbit / GitHub Actions / Codecov / Dependabot 等）は jq で取得段階に除外。
  - → bot ノイズ分の課金は発生しない。
- ⬆️ 人間コメントが活発な Issue（数十件規模）は入力トークン +10K〜+100K 程度の目安。
- ⬆️ `/vibecorp:ship-parallel` 5 並列では増分が 5 倍同時発生。
- 💰 `ANTHROPIC_API_KEY` 従量課金時、コメント多い Issue は約 $1.4 から数 $10 程度の幅で変動。

### 📌 知見閉ループの追加コスト

知見蓄積系スキルのコスト構造を整理する。

- 🔁 `/vibecorp:autopilot` は `/vibecorp:review-harvest` → `/vibecorp:knowledge-pr` を 1 サイクルで 1 回ずつ呼ぶ。
  - 合計 約 $0.40/サイクル。
- ✋ `/vibecorp:session-harvest` はセッション末尾で任意起動。
  - 約 $0.45/回。
- 🚧 `/vibecorp:review-harvest` の上限抑制機構は以下。
  - `VIBECORP_HARVEST_MAX_PRS`（デフォルト 50）。
  - 30K トークン切り詰め。
- 🛑 空セッション・空差分時の無駄呼び出しは `/vibecorp:session-harvest` の diff-zero 早期終了で回避。

### 📌 Issue #361 による `/vibecorp:issue` コスト変化

起票承認ゲートが拡張された。

- ⬆️ CPO 単独（約 $0.15/回）→ CISO + CPO + SM の 3 エージェント並列（約 $0.45/回）。
- → 1 回あたりのコストは約 3 倍。
- ⬆️ `/vibecorp:autopilot` が全 open Issue を対象化したことで `/vibecorp:ship-parallel` の実行数が増加しうる。
- ✅ Issue 量が多いリポジトリでは `/vibecorp:issue` の呼び出し頻度を月次コストレビューで定期確認する。

### 🛠️ 推奨運用

- ✅ MUST: full プリセット導入前に `docs/cost-analysis.md` の本節を確認すること。
- ✅ MUST: `ANTHROPIC_API_KEY` 設定時は Anthropic Console の使用量アラートを有効化すること。
- ✅ SHOULD: 本番で full プリセットを常時運用する前に、1 週間の試験運用でコスト実測を取ること。

## Bot 経由 Claude Max OAuth のレート枯渇リスク

claude-code-action の Bot 認証で **リポジトリ管理者個人の Claude Max OAuth トークン**を使う場合がある。
このとき、対話用クォータが枯渇するリスクが発生する。

- 該当 secret: `CLAUDE_CODE_OAUTH_TOKEN`。
- Anthropic 公式が個人 OAuth の自動化用途利用に明示的に警告している事項。
- 本ドキュメントに転記する。

### ⚠️ リスクの本質

- `claude setup-token` で発行する OAuth トークンは **個人 Claude Max プランのレート枠を消費する**。
  - 単位: 5 時間あたりのトークン上限。
- `/vibecorp:ship-parallel` / `/vibecorp:autopilot` を多発させると、リポ管理者本人の対話用クォータも同枠から削られる。
- レート制限到達時の挙動はプラン依存。
  - Claude Max は遅延。
  - `ANTHROPIC_API_KEY` 設定時は通知なしで API 従量課金にフォールバック。

### 🔁 `/vibecorp:review` ローカル経路のコスト経路シフト（Issue #499）

`/vibecorp:review` のローカルレビュー経路が CodeRabbit CLI から Claude Code CLI 直接呼び出しに置換された。

- 旧: `cr review --plain`。
- 新: `claude -p`。

これによりコスト経路が以下のようにシフトしている。

| 経路 | 旧（CodeRabbit CLI） | 新（Claude Code CLI 直接呼び出し） |
|---|---|---|
| 課金主体 | CodeRabbit Free 枠（3 reviews/hour、無料） | Claude Max OAuth quota または API 従量課金 |
| 並列上限 | 3 並列で枯渇（`/vibecorp:ship-parallel` 5 並列で破綻） | Claude Max レート枠まで（5 並列で破綻しない） |
| チーム運用時の共有負担 | なし（無料） | あり（リポ管理者個人クォータを全員分のレビューで消費） |

ローカルレビューも claude-code-action と同じレート枯渇リスクに晒される。

本セクションの共有負担・緩和策はローカル経路にも適用される。

### 🚨 `/vibecorp:review` の `ANTHROPIC_API_KEY` 混在 fail-fast

`/vibecorp:review` のローカル経路は、起動時に `ANTHROPIC_API_KEY` 環境変数が設定されていれば exit 1 で停止する（fail-fast）。

理由を以下に整理する。

- ⚠️ `claude -p` 非対話モードは `ANTHROPIC_API_KEY` があると OAuth より優先する。
  - → API 従量課金経路に自動切替される。
- 💸 ローカルレビューは反復実行されるため、気づかない間に従量課金が積み上がるリスクが大きい。
- 📝 Issue #455 コメント 8 で CEO が「`ANTHROPIC_API_KEY` 混在環境を fail-fast」を明示指定済み。

fail-fast 時、エラーメッセージで以下の対処を案内する。

- `unset ANTHROPIC_API_KEY` で環境変数を解除する（OAuth 経路に切り替わる）。
- もしくは `docs/ai-review-auth.md` を参照して `claude setup-token` で OAuth トークンを発行する。

> [!NOTE]
> 意図的に `ANTHROPIC_API_KEY` で API 従量課金運用したい上級ユーザーは、`/vibecorp:review` を経由せず直接 `claude -p` をシェルで叩く運用を取れる。
> vibecorp は利用者のシェル運用を制限しない。

### 👥 チーム運用時の共有負担

複数メンバーが PR を出すチーム運用では、共有負担リスクが発生する。

- メンバー全員の PR レビューが「リポジトリ管理者」個人の Max クォータから消費される。
- 全員分のレビュー量がリポ管理者 1 人のレート枠を圧迫する。
- リポ管理者本人の対話用利用に影響が出る時間帯が発生しうる。
- メンバー数 × PR 頻度に比例してリポ管理者のクォータ消費が増える。

### 🛡️ 緩和策

| 対策 | 内容 | 推奨度 |
|---|---|---|
| cadence 伸長 | `/vibecorp:autopilot` の定期実行を 24 時間 → **36 時間**に伸ばす | ✅ 推奨 |
| Bot 専用 Max 別契約 | Bot 用メールアドレスで別途 Claude Max を契約 | 🟢 将来選択肢 |
| API 従量課金切替 | 高頻度運用時は `ANTHROPIC_API_KEY` に切替（コスト発生に注意） | ⚠️ コスト要試算 |

### ✅ 安心材料

Fork PR 経由ではクォータ消費は起きない。

- **Forked PR は claude-action 対象外**（secrets 不在で自動スキップ）。
- 公開リポジトリでも、赤の他人は必ず Fork 経由 PR となり、`CLAUDE_CODE_OAUTH_TOKEN` に触れない。
- 詳細仕様は [`docs/ai-review-auth.md`](ai-review-auth.md) の「Forked PR の対処方針」「個人 Claude Max OAuth クォータ枯渇リスク」を参照。

### 🛠️ 推奨運用

- 📌 注記: 本セクションの cadence 36h 推奨は以下に適用される。
  - 適用条件: `CLAUDE_CODE_OAUTH_TOKEN`（個人 Max OAuth）で claude-code-action を運用する場合。
  - Bot 専用 Max 別契約や `ANTHROPIC_API_KEY` 従量課金運用時は、次節のデフォルト 24h 推奨に従う。
  - 参照節: 「自律実行の上限ガードレール」。
- ✅ MUST: 個人 Max OAuth で claude-code-action を有効化する前に、本セクションの共有負担リスクをチームに周知すること。
- ✅ SHOULD: チーム運用かつ複数メンバーが日常的に PR を出す環境では cadence を 36 時間以上に伸ばすこと。
- ✅ SHOULD: 月次コストレビューで `CLAUDE_CODE_OAUTH_TOKEN` のレート枯渇発生有無を確認し、枯渇が常態化する場合は Bot 専用 Max 別契約への移行を検討すること。

## 自律実行の上限ガードレール

`/vibecorp:diagnose` → `/vibecorp:autopilot` → `/vibecorp:ship-parallel` の自律改善ループが予算を超過しないよう、上限を設けている。

- 設定場所: `.claude/vibecorp.yml` の `diagnose` セクション。
- ここに記載の値は Source of Truth。
- 🚫 `.claude/rules/autonomous-restrictions.md` により「課金構造」領域として自律変更禁止。

### 🛠️ デフォルト値

| 設定キー | デフォルト値 | 意味 | 超過時の挙動 |
|---|---|---|---|
| `max_issues_per_run` | 7 | 1 回の `/vibecorp:diagnose` → `/vibecorp:autopilot` 実行あたりの最大起票数 | 超過分を起票対象から除外 |
| `max_issues_per_day` | 14 | 1 日あたりの最大起票数（diagnose ラベル付き Issue を当日 UTC で集計） | 当日の残枠を超えた候補を除外 |
| `max_files_per_issue` | 10 | 1 Issue あたりの最大対象ファイル数 | 超過する改善候補を除外（分割起票を促す） |

### 💡 値の根拠（コスト観点）

> [!NOTE]
> 丸めルール: コスト概算は各サブステップの見積もりを合算し、サイクル単位で四捨五入している。
> 端数の内訳は参考として記載するが、日次・月次の試算はサイクル単価（約 $25）を基準に算出する。
> 単価は Issue #361 以降の `/issue` ゲート追加分を反映済み。

`max_issues_per_run: 7` の根拠を以下に整理する。

- 💸 1 サイクルの構成（コスト試算）。
  - `/vibecorp:diagnose`（Opus 4.6、約 $15）。
  - `/vibecorp:ship-parallel` 7 Issue 並列（Sonnet 4.6、約 $9.80）。
  - `/issue` ゲート 7 回（Sonnet 4.6、約 $0.45 × 7 = $3.15）。
  - `/vibecorp:review-harvest` + `/vibecorp:knowledge-pr`（合計 約 $0.40）。
- 🎯 1 サイクルの上限コストを約 $28 に収める。
- 📚 CEO + CFO 議論（Issue #247）の結論。
- 🔁 `/diagnose` 固定費 600K token を効率最大化するため、7 件で 14 件候補を 2 サイクルで完全消化する設計。
- 💼 `Claude Max 20` 定額環境では金銭限界費用ゼロ。
  - レート制限の余裕確保が制約軸となる。

`max_issues_per_day: 14` の根拠を以下に整理する。

- 🧮 `max_issues_per_run` × 2 として導出した日次上限値。
- 🛡️ 1 日に複数サイクル運用しても本値を超えないようガードする独立した上限。
- ⚙️ 特定の cadence を前提としない。
- ✅ **推奨運用 cadence は 24 時間ごと**。
  - 旧 12 時間ごと運用ではレート制限が逼迫するため非推奨。
  - 次節の試算表で 24h 推奨は 7 Issue/日となる。
- 💰 満枠運用時の月額概算は次節の試算表を参照。

`max_files_per_issue: 10` の根拠を以下に整理する。

- 🧪 1 Issue のレビュー・マージ工程が破綻しない変更規模の経験則。
- ✂️ 10 を超える改善は分割起票が原則。

### 📅 `/vibecorp:autopilot` 定期実行時のコスト試算

`/loop` や cron で `/vibecorp:autopilot` を定期実行する場合、全枠起票される最大ケースの概算を整理する。

- ✅ **推奨運用は 24 時間ごと**（Issue #247 の CFO 推奨）。

| 実行頻度 | 1 日あたりの起票上限 | 月額概算（満枠時） | 推奨度 |
|---|---|---|---|
| **24 時間ごと（1 日 1 回）** | **7 Issue** | **約 $840** | ✅ **推奨**（レート余裕と失敗総量の最適バランス） |
| 12 時間ごと（例: `/loop /vibecorp:autopilot 12h`） | 14 Issue | 約 $1,680 | ⚠️ 非推奨（Claude Max 20 のレート制限に逼迫しやすい） |
| 週 1 回 | 7 Issue | 約 $112 | 🟢 低コスト運用 |

試算前提を以下に整理する。

- 📊 1 サイクル 約 $28 × 実行頻度で算出した満枠試算。
  - 構成: `/vibecorp:diagnose` + `/vibecorp:ship-parallel` 7 並列 + `/issue` ゲート 7 回 + `/vibecorp:review-harvest` + `/vibecorp:knowledge-pr`。
- 🎲 実運用では改善候補がない日・CI 失敗によるリトライ・レビューループ回数で変動する。
- ✅ MUST: `ANTHROPIC_API_KEY` を設定して `/vibecorp:autopilot` を定期実行する場合は Anthropic Console の使用量アラートを必ず有効化する。
  - 月額 80% / 100% 到達時通知。
- 📝 NOTE: `Claude Max 20` 定額プラン（$200/月）で運用する場合、上記 API 換算は無効。
  - プラン定額に集約される。
  - 代わりにレート制限への接触余裕が制約軸となる。
  - **24 時間ごと運用での月間 token 消費 約 90M を目安**とする。

### 🔁 `/vibecorp:pr-fix-loop` の予算ガード

PR レビュー修正ループも自律改善の一種として時間軸の予算ガードを持つ。

- 📚 `docs/specification.md` の `/vibecorp:pr-fix-loop` 仕様と整合。
- 📚 `skills/pr-fix-loop/SKILL.md` の「予算ガード」節と整合。

| 設定キー | デフォルト値 | 意味 | 超過時の挙動 |
|---|---|---|---|
| `max iterations` | 20 | 1 回の `/vibecorp:pr-fix-loop` あたりの `/vibecorp:pr-fix` 同期呼び出し上限 | 上限到達で escalate（CEO に通知して停止） |
| `timeout` | 60 分 | 1 回の `/vibecorp:pr-fix-loop` の総経過時間上限 | 上限到達で escalate |

変更・運用ルールを以下に整理する。

- ⚠️ 上記値を変更する場合、`skills/pr-fix-loop/SKILL.md` のループ制御テーブル・予算ガード節と本セクションを **同時に更新** する。
  - 値の整合を保つため。
  - diagnose 系と同じ「片側のみ更新禁止」原則。
- 🧮 `pr-fix-loop` は起票数ベースのガードではなく、API 呼出回数 / 時間ベースのガードを採用する。
- 💰 1 ループの上限コスト概算。
  - `/vibecorp:pr-fix` 1 回 ≦ Sonnet 4.6 約 $0.30。
  - 最大 $6 程度（× 20 反復）。
- 🚫 `/vibecorp:pr-fix-loop` の値変更も自律改善ループからは禁止する（「課金構造」領域）。

### 📐 変更時のルール

- ✅ MUST: `max_issues_per_run` / `max_issues_per_day` / `max_files_per_issue` を変更する場合、`.claude/vibecorp.yml` と本ドキュメントを同時に更新する。
- ✅ MUST: `/vibecorp:pr-fix-loop` の `max iterations` / `timeout` を変更する場合、`skills/pr-fix-loop/SKILL.md` と本ドキュメントを同時に更新する。
- 🚫 MUST NOT: 自律改善ループ（`/vibecorp:diagnose` → `/vibecorp:autopilot`）がこれらの値を変更してはならない。
  - 根拠: `.claude/rules/autonomous-restrictions.md` の「課金構造」領域。
- ✅ SHOULD: 値を変更する場合、CFO によるコスト影響評価（`/vibecorp:audit-cost`）を事前に実施する。

## 事後監査

`/vibecorp:audit-cost`（full プリセット限定）で CFO による週次コスト監査を自動化できる。

- 📊 直近 7 日間のコード変更を分析する。
- 📝 `knowledge/accounting/audit-YYYY-MM-DD.md` にレポートを保存する。
- 🚨 Critical / Major 指摘がある場合は自動で `audit` ラベル付き Issue を起票する。

### 📅 定期実行例

```bash
# 毎週月曜 09:00 JST に実行
/schedule weekly "0 0 * * 1" /vibecorp:audit-cost
```

または cron で起動する。

```bash
# crontab -e
0 0 * * 1 cd /path/to/repo && claude -p "/vibecorp:audit-cost"
```

### 🔍 監査観点

`/vibecorp:audit-cost` で確認する観点を以下に整理する。

- 📞 API 呼び出し箇所の増減。
- 🔑 `ANTHROPIC_API_KEY` を扱う箇所の変更。
- 🤖 ヘッドレス Claude 起動（`claude -p` / `npx` / `bunx`）の増減。
- 🚧 コスト上限設定（`max_issues_per_day` 等）の変更。
- 💸 従量課金到達リスクの変化。
- 🎚️ エージェントの **モデル指定**（Opus / Sonnet / Haiku）の役割妥当性。
  - C-suite・合議制分析員・プロセス管理（`sm`）での Haiku 指定は品質劣化リスク（Major）。
  - 定型作業ロールでの Opus 指定は過剰指定（Major）。
  - モデル未指定（親継承）は明示推奨（Minor）。
  - 判定は本ドキュメントの「モデル単価」表と「プリセット別の想定運用モード」を根拠とする。
  - CFO は警告のみ行う（自動変更は行わない）。

## monthly cost cap 運用方針

vibecorp は月次コスト上限の自動制御機構を **意図的に持たない**。

代わりに本節の手動運用ガイドラインを提供する。

利用者は本節に従って自身の運用環境で上限管理を行う（Issue #471 / 親エピック #455）。

> [!NOTE]
> 本ドキュメント冒頭の「予算アラート」節における「100% 到達時」とは、後述の Anthropic Console の 100% 通知を起点として利用者が手動で停止／承認フローを実施する運用を指す。
> vibecorp 自体が自動停止する機構は実装しない。

### ⚖️ 設計判断の根拠

vibecorp が自動制御を持たない判断の根拠を以下に整理する。

- 🤝 **claude-code-action のデフォルトに任せる**。
  - PR ごとの `max_tokens` / 大規模 PR の閾値は claude-code-action のデフォルト挙動に委ねる。
  - vibecorp 独自の閾値設定キーは追加しない。
  - 参考: claude-code-action タイムアウト 10 分（Issue #466）。
- 🚫 **新規キー追加は行わない**。
  - `vibecorp.yml` の `claude_action.enabled` と `claude_action.skip_paths` の既存 2 キー（Issue #468 確定）のみで運用する。
  - 月次コスト上限・PR ごとの max_tokens を表現する新規キーは本リリースでは追加しない。
- 📊 **GitHub Actions minutes 監視機構も持たない**。
  - GitHub Settings → Billing で利用者が手動確認する。

### 🎯 Claude Max 定額環境での実質上限（90M token/月）

`Claude Max 20`（$200/月）定額プランで `/vibecorp:autopilot` を **24 時間ごと cadence で運用した場合**の目安。

- **入力 + 出力の合算月間トークン消費 約 90M token を目安**とする。
- 📚 Issue #455 の CFO 条件付き承認における目安値。
- 🛡️ レート制限（5 時間あたり上限）への接触余裕を確保する基準。

| 指標 | 目安 |
|---|---|
| 月間トークン消費上限（Claude Max 20 定額、入力 + 出力合算） | **約 90M token/月** |
| 前提運用条件 | full プリセット + `/vibecorp:autopilot` 24 時間ごと |
| 24 時間ごと運用での 1 日あたり消費（入力 + 出力合算） | 約 3M token/日 |
| 推奨運用 cadence | 24 時間ごと（`/loop /vibecorp:autopilot 24h`） |

90M token/月の目安値は Issue #475（実機検証期間）で実測補正する。

- ✅ Claude Max 定額内で動く限り追加課金は発生しない。
- ⚠️ レート制限到達時は `ANTHROPIC_API_KEY` への自動フォールバックが働く可能性がある。
- 🔔 Anthropic Console での使用量モニタリング（次節）と Monthly spend limit 設定（次節）を必ず併用する。

### 🚨 Anthropic Console 使用量アラート設定手順

`ANTHROPIC_API_KEY` を設定して vibecorp を運用する利用者は、Anthropic Console で月額使用量アラートを必ず有効化する。

- 🚫 vibecorp は API 経由で自動設定する機構を持たない。
- 🧑 利用者が手動で設定する。

#### 🛠️ 設定手順

1. [Anthropic Console](https://console.anthropic.com/) にログインする。
2. 左サイドバー `Settings` → `Billing` → `Usage limits` を開く。
3. `Monthly spend limit` を設定する。
   - **CFO 承認の月次上限**（約 90M token/月の想定 USD 換算額）に基づいて設定する。
   - 換算の目安は「モデル単価」表（Sonnet 4.6: 入力 $3 / 出力 $15 per 1M token）と「概算コスト」表から算出する。
   - `/vibecorp:autopilot` 24 時間ごと運用なら **月額上限 約 $840** を Monthly spend limit に設定するのが推奨。
   - 最小例（テスト用途）として $100 を設定してもよい。
4. `Email notifications` セクションで以下を有効化する。
   - 80% 到達時通知（`Notify at 80% of limit`）。
   - 100% 到達時通知（`Notify at 100% of limit`）。
5. 通知先メールアドレスを Anthropic アカウントのメールに設定する。

#### 📊 推奨閾値

| 運用形態 | アラート設定 | 推奨 Monthly spend limit |
|---|---|---|
| Claude Max 定額のみ（`ANTHROPIC_API_KEY` 未設定） | 設定不要（追加課金なし） | — |
| `ANTHROPIC_API_KEY` 併用（Max フォールバック含む） | 月額予算の 80% / 100% アラート必須 | CFO 承認の月次上限（約 $840、24h cadence 満枠時） |
| API Key のみ運用（Max なし） | 月額予算の 50% / 80% / 100% アラート推奨 | CFO 承認の月次上限（同上） |

運用ルールを以下に整理する。

- ✅ MUST: `ANTHROPIC_API_KEY` を設定する場合、Anthropic Console の使用量アラートを有効化する。
- ✅ SHOULD: Anthropic Console の `Usage` ダッシュボードを月次でレビューし、想定との乖離を確認する。

### 🕐 GitHub Actions minutes の手動確認方法

claude-code-action は GitHub Actions 上で実行されるため、Actions minutes を消費する。

- 🚫 vibecorp は独自の Actions minutes 監視機構を持たない。
- 👁️ GitHub ダッシュボードでの手動確認を推奨する。

#### 🛠️ 確認手順

1. GitHub の対象リポジトリまたは組織の `Settings` を開く。
2. 左サイドバー `Billing and plans` → `Plans and usage` を開く。
3. `Actions` セクションで以下を確認する。
   - 当月の使用 minutes（`Minutes used this month`）。
   - 残 minutes（`Minutes remaining`）。
   - 課金対象 minutes（プライベートリポジトリの場合）。
4. 想定を超えている場合、`.github/workflows/` の trigger 条件（特に claude-code-action の `on:` 節）を見直す。

#### 📅 推奨確認頻度

| プラン | 推奨確認頻度 |
|---|---|
| GitHub Free（個人 / Public リポジトリ） | minutes 課金なし、確認不要 |
| GitHub Free（個人 / Private、月 2,000 分無料枠） | 月次 |
| GitHub Team / Enterprise | 月次 |

運用ルールを以下に整理する。

- ✅ SHOULD: 月次で GitHub Settings → Billing → Plans and usage の Actions セクションを目視確認する。
- 📝 NOTE: vibecorp は GitHub Actions minutes の自動アラート機構を提供しない。
  - 閾値超過の即時検知が必要な利用者は GitHub Marketplace のサードパーティアクションを別途導入する。
