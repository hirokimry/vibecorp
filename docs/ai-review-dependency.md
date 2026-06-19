# 🔄 AI レビュー依存マップ

> [!IMPORTANT]
> 読者像は AI レビュー機構を運用する利用者・開発者。
> vibecorp は **vibehawk** と **CodeRabbit** の 2 経路を **独立トグル** で選択する設計（Issue #531）。
> **デフォルトは vibehawk のみ**（vibehawk=on / coderabbit=off）。両方・片方・両方なしの 4 通りを選べる。
> 本ドキュメントは両者の責任分担、トグル別の効果、解約時の挙動の **Source of Truth**。

## 🦅 レビュー機能の vibehawk 移譲（Issue #531）

vibecorp は **AI レビュー本体を vibehawk へ外部化** した。

- 🔄 **Before**: vibecorp が `REVIEW.md` + `ai-review.yml` を配布し claude-code-action を自前ワークフローで動かしていた。
- 🟢 **After**: レビュー本体は vibehawk が担う。vibecorp は `.vibehawk.yaml` の生成と導線提供に徹する。

| 観点 | 旧（claude-code-action 並走） | 新（vibehawk 移譲） |
|---|---|---|
| レビュー実体 | vibecorp 配布の `ai-review.yml` が claude-code-action を起動 | vibehawk が配布する workflow が起動（vibecorp は vendoring しない） |
| 判断軸の注入先 | `REVIEW.md`（claude-code-action のプロンプト） | `.vibehawk.yaml` の `reviews.path_instructions` |
| 配布物 | `REVIEW.md` / `ai-review.yml` / `ai-review-golden-test.yml` | `.vibehawk.yaml`（vibecorp 生成）+ `npx vibehawk setup` 導線 |
| required status check | `test` のみ | `vibehawk`（`npx vibehawk setup` + CEO の branch protection 操作で登録） |

> [!NOTE]
> 旧 claude-code-action 実装（`REVIEW.md` / `ai-review.yml` / `ai-review-golden-test.yml`）は配布されなくなった。
> `--update` 時に vibecorp 管理下のこれらファイルは削除される（ユーザー編集済みファイルは残置）。

## 📊 vibehawk / CodeRabbit 独立トグル 4 通り

vibecorp は 2 つのレビュアーを `enabled` フラグで独立に切り替える。

| 設定 | vibehawk | CodeRabbit | 用途 |
|---|---|---|---|
| **vibehawk のみ（デフォルト）** | ✅ 有効 | ❌ 無効 | 標準構成。Claude ベースのレビューを単独運用 |
| **CodeRabbit のみ** | ❌ 無効 | ✅ 有効 | CodeRabbit 既存利用者・CodeRabbit エコシステム継続 |
| **両方** | ✅ 有効 | ✅ 有効 | 多層防御（片方が見逃した問題をもう片方が拾う） |
| **両方なし** | ❌ 無効 | ❌ 無効 | AI レビューを止め、人間レビューのみで運用 |

### ⚙️ 各トグルの効果

`install.sh` は各 `enabled` フラグを見て以下を行う。

| トグル | `enabled: true` の効果 | `enabled: false` の効果 |
|---|---|---|
| `vibehawk.enabled` | `.vibehawk.yaml` を生成 + `npx vibehawk setup` 導線を WARN 案内 | `.vibehawk.yaml`（管理下）を削除 |
| `coderabbit.enabled` | `.coderabbit.yaml` を生成 + required check `CodeRabbit` を branch protection に登録 | `.coderabbit.yaml` を生成しない／既存は触らない |

> [!IMPORTANT]
> vibehawk の required check `vibehawk` は **install.sh では登録しない**。
> App 作成・3 secrets 登録・workflow 配布は `npx vibehawk setup` の責務。
> required check `vibehawk` の branch protection 登録は CEO の操作とする。

### 🚀 vibehawk 導入には `npx vibehawk setup` が必要

vibehawk を有効化しても、`.vibehawk.yaml` 生成だけではレビューは稼働しない。

別途以下を実行する必要がある。

```bash
# GitHub App 作成・3 secrets 登録・workflow 配布 PR をウィザードが案内する
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

- 🔑 3 secrets: `VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`。
- 🛡️ workflow 配布後、CEO が branch protection で `vibehawk` を required status check に登録する。
- 📖 認証経路の詳細は `docs/ai-review-auth.md` を参照。

## ✅ デフォルト（vibehawk-only）と vibecorp 自身の一致（Issue #783 で解消）

> [!NOTE]
> 配布するデフォルトは **vibehawk-only**。vibecorp 本体も **vibehawk-only に移行済み**（Issue #783）で、配布デフォルトと一致する。

配布元自身がデフォルト構成をドッグフーディングしている。

- 🏠 vibecorp 自身の vibehawk 有効化（own-repo への App インストール・secrets 登録・branch protection: `vibehawk` required・approval 0）は Issue #783 で完了済み。
- ✅ 利用者が `install.sh` で導入する場合のデフォルトも vibehawk-only で配布される（配布元と一致）。
- 📦 過去（#531 マージ〜#783 完了まで）は配布元のみ暫定的に CodeRabbit 単独運用だったが、現在は解消済み。

## 並走運用の挙動（approve 2 個の AND ゲート）

vibehawk と CodeRabbit が両方有効な場合、GitHub のネイティブ挙動でマージ条件が決まる。

- 各レビュアーが独立して `approve` / `request_changes` を発行する。
- GitHub は **request_changes を優先**（厳しい方が勝つ AND ゲート的挙動）。
- どちらか 1 つでも `request_changes` ならマージブロック。
- 両者が `approve` なら `vibecorp.yml` の `branch_protection.required_approvals` に応じてマージ可（#463）。

これにより、片方が見逃した問題をもう片方が拾う多層防御が成立する。

### 🔁 重複指摘について

両ツールが同じ箇所を指摘することはある。

しかし利用者は両方を確認する必要はない。

- ✅ 修正対象が一致すれば 1 回の修正で両方のコメントが auto-resolve される。
- ⚖️ 片方の解釈が分かれた場合は `.claude/rules/review-handling.md` の捌き基準に従う。
  - 判定軸: intent × severity。

並走時の挙動詳細・指摘ノイズの観測は #474（並走比較メトリクス）で実機検証する。

## ツール解約時の挙動

`vibecorp.yml` の `enabled` フラグで各ツールを個別に無効化できる（4 通りは前述「[独立トグル 4 通り](#-vibehawk--coderabbit-独立トグル-4-通り)」を参照）。

`install.sh` は各 `enabled` フラグを見て以下を行う。

- `vibehawk.enabled: false` → `.vibehawk.yaml`（管理下＝テンプレート完全一致）を削除する。
  - ⚠️ ユーザー編集済み（ハッシュ不一致）の `.vibehawk.yaml` は残置する（誤削除防止）。
  - workflow / App / secrets の撤去は `npx vibehawk setup` 側の責務であり install.sh は触らない。
- `coderabbit.enabled: false` → `.coderabbit.yaml` を生成しない／既存ファイルは触らない。

両方無効化しても vibecorp の他機能（hooks、skills、CI 等）は動作する。

AI レビューだけが止まる。

## vibecorp.yml の設定例

```yaml
# vibecorp.yml — プロジェクト設定の AI レビュー部分
# デフォルトは vibehawk のみ（vibehawk=on / coderabbit=off）。
vibehawk:
  enabled: true   # vibehawk を使う（別途 npx vibehawk setup が必要）
  skip_paths:     # AI レビュー対象から除外するパス（業界標準 7 件）
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"

coderabbit:
  enabled: false  # CodeRabbit Bot を使う場合は true

branch_protection:
  required_approvals: 1   # マージに必要な approve 件数（人間 OR Bot どちらでも 1 件カウント）
```

> [!NOTE]
> 既存の `claude_action:` セクションは `install.sh --update` 実行時に `vibehawk:` へ自動移行される。
> `enabled` 値・`skip_paths` は本文ごと保持される（利用者カスタマイズを尊重）。

`vibehawk.skip_paths` は除外パスの入力源として、`.vibehawk.yaml` の `path_filters` に自動反映される。

## vibehawk 設定値の根拠（参考）

vibecorp が生成する `.vibehawk.yaml` の主要設定値。

| 設定 | 値 | 根拠 |
|---|---|---|
| `language` | `ja-JP` 等 | 日本語レビュー（`vibecorp.yml` の `language` を反映） |
| `reviews.size_limits` | full 30 / focused 80 / skip_inline 3000 | 段階的劣化のファイル数閾値（vibehawk デフォルト準拠） |
| `reviews.path_filters` | `vibehawk.skip_paths` から自動生成 | 除外設定の単一ソース化 |
| `reviews.path_instructions` | Issue 全要件充足チェック | vibecorp 独自の判断軸を注入（後述） |

> [!NOTE]
> severity 5 段階・approve / request_changes 切替・auto-resolve 等の判断軸は **vibehawk ツール側に内蔵** されている。
> vibecorp が `.vibehawk.yaml` で注入するのは「PR が対応 Issue の全要件を満たすこと」という独自の path_instructions のみ。

## CodeRabbit 設定値の根拠（参考）

`coderabbit.enabled: true` 運用時、CodeRabbit 側の `.coderabbit.yaml` の主要設定値。

| 設定 | 値 | 根拠 |
|---|---|---|
| `reviews.auto_review.enabled` | `true` | PR open / push で自動レビュー |
| `reviews.auto_review.drafts` | `false` | Draft PR ではコスト節約のためレビューしない |
| `reviews.auto_review.auto_incremental_review` | `true` | push 毎にインクリメンタルレビュー |
| `reviews.path_filters` | `coderabbit.skip_paths` から自動生成 | skip 設定の単一ソース化 |
| `reviews.request_changes_workflow` | `true` | approve 切替（auto-resolve も派生） |
| `language` | `ja-JP` | 日本語レビュー |
| `chat.auto_reply` | `true` | 却下スレッドの文脈完結 |

## 実機検証完了判定（Issue #475 確定・歴史的記録）

> [!WARNING]
> 本セクション以下は **claude-code-action 時代の検証基準の歴史的記録**。
> レビュー機能は Issue #531 で vibehawk へ移譲され、claude-code-action は配布されなくなった。
> vibecorp 本体は Issue #783 で vibehawk-only へ移行済み（CodeRabbit 単独運用は解消済み）。
> 以下の `claude_action` 前提の記述は当時の判定設計として保持する（現行運用の指針ではない）。

vibecorp 自身で `coderabbit.enabled: true` + `claude_action.enabled: true` の並走を 2 週間継続し、以下全てを充足した場合に検証完了とする。

### 完了判定基準（A + B）

| 要素 | 内容 | 判定方法 |
|---|---|---|
| A. レート消費 | Claude Max 90M token/月の目安以内 | 週次サマリ × 2 回の合計 |
| B. 4 契約動作 | auto-review / approve 切替 / auto-resolve / 日本語 全部機能 | 週次サマリ × 2 回で全 ✅ |

C（二重指摘ノイズ閾値）/ D（利用者不満ゼロ）は **判定外**。

並走で観測するが完了判定には含めない。

### C*O 合議による本番運用切替

完了判定を満たしたら、以下 4 役の合議で本番運用への切替を決定する。

| 役 | 評価観点 |
|---|---|
| CFO | レート消費・コスト面の評価 |
| CISO | 認証領域への影響なし確認 |
| CTO | 技術品質の評価（4 契約・既知問題・ロールバック手順） |
| CPO | 利用者体験の評価（レビューノイズ・誤検知率・回帰検出） |

4 役全員が OK 判定の場合のみ「本番運用」へ移行する。

1 名でも NG または保留の場合は検証期間を延長する。

### 「本番運用」の定義

vibecorp プロジェクト自身が claude-action 主軸で運用される状態を指す。

- vibecorp の PR レビューは claude-action を中心に運用する。
- CodeRabbit は並走継続（オプション扱い、利用者は無効化可能）。
- 利用者向けプリセット既定値（`coderabbit.enabled` / `claude_action.enabled`）の切替は別途検討。
  - 本 Issue では vibecorp 自身の運用切替のみ。

### 📉 超過時の cadence 調整

レート消費が 90M token/月を超過する見通しが立った場合、CFO 判断で以下のいずれかを実施する。

- (a) **cadence 24h → 36h に即伸長**: claude-action のスケジュール起動間隔を伸ばす。
- (b) **`claude_action.enabled: false` にロールバック**: `docs/ai-review-rollback.md` を参照。
- (c) **検証期間延長**: 様子見を 1 週間追加する。

判断は週次サマリで記録し、CEO の承認を得てから実施する。

### NG 時の対応

完了判定が NG（A or B 不足）の場合、CEO 判断で以下から選択する。

- 期間延長（さらに 1 週間並走）。
- スコープ縮小（`claude_action.enabled: false`、CodeRabbit のみ運用継続）。
- 設計再検討（Issue #475 を reopen して論点整理）。

### Bot approve 経路の動作確認と代替手段（CFO 承認条件 3）

Issue #455 CFO 条件付き承認の遵守事項 3 を充足する。

「Bot approve 代替手段の事前検討」の動作確認と代替手段を以下に定める。

#### 動作確認方法（週次サマリで記録）

検証期間中、毎週末に以下を確認し、週次サマリに結果を記入する。

- ✅ claude-action が `gh pr review --approve` または `--request-changes` を発行できているか。
- ✅ Branch Protection の `required_approvals` が満たされて auto-merge が発火するか。
- ✅ Bot 認証エラー時に警告コメントが投稿されるか（#467 確定の挙動）。
- ✅ マージが滞らないか（PR open から 24h 以内に approve / request_changes）。

#### 代替手段（Bot approve が機能しない場合）

代替案は CEO 判断で選択する。

発動タイミング: 検証期間中に発動した場合、または本番運用切替前に Bot approve が機能しないことが判明した場合。

| # | 代替手段 | 想定シナリオ |
|---|---|---|
| 1 | CodeRabbit が approve する設定を活用 | claude-action の Bot approve が機能しない場合 |
| 2 | 人間レビュアーが必ず approve するルール | 両 Bot とも approve 不可の場合 |
| 3 | `required_approvals: 0` に下げる | 緊急時のみ、保護機能を一時的に落とす（戻し手順は `docs/ai-review-rollback.md`） |
| 4 | GitHub App の認証経路を再構築 | OAuth Token / GitHub App の権限不足が原因の場合（恒久対応） |

#### 代替手段の発動判定基準

検証期間中に以下のいずれかが発生した場合、CEO は代替手段の発動を判断する。

- ⚠️ Bot approve 失敗が連続 3 PR 以上発生。
- ⚠️ Bot 認証エラーが連続 24h 以上継続。
- ⚠️ マージが 48h 以上滞る PR が 2 件以上発生。

判断結果は週次サマリの「ロールバック判断」セクションに記録する。

### 🔄 ロールバック手順

claude-action を一時的に無効化する手順は `docs/ai-review-rollback.md` を参照する。

スクリプト化は **しない**（Issue #475 議論結論）。

### 📝 週次サマリテンプレート

CFO が週次サマリを記録する際のテンプレートを以下に配置する。

参照先: `.claude/knowledge/cfo/templates/weekly-summary.md`。

## 既存 CodeRabbit CLI 利用者の移行パス（Issue #499）

`/vibecorp:review` のローカルレビュー経路が **CodeRabbit CLI から Claude Code CLI 直接呼び出しに置換** された。

- 旧経路: `cr review --plain` を内部で呼ぶ。
- 新経路: `claude -p` でレビュープロンプトを直接呼ぶ。
- 確定: Issue #499、親エピック #455 コメント 8 で CEO 確定。

本セクションは既存 CodeRabbit CLI 利用者の移行方針を整理する。

### 🔁 何が変わったか

| 観点 | 旧（〜本変更前） | 新（本変更後） |
|---|---|---|
| ローカル `/vibecorp:review` の実体 | `cr review --plain` を内部で呼ぶ | `claude -p` でレビュープロンプトを直接呼ぶ |
| 並列実行時のレート制限 | CodeRabbit Free 3 reviews/hour で枯渇 | Claude Max レート枠まで（5 並列でも破綻しない） |
| 認証経路 | CodeRabbit Pro 契約 or Free 枠 | Claude Max OAuth トークン |
| `coderabbit.enabled: false` 時のローカル経路 | スキップされる | **常に実行**（CodeRabbit と無関係になった） |

### ✅ CodeRabbit Bot（CI 側）は引き続き並走可能

`coderabbit.enabled: true` を維持すれば、CodeRabbit Bot は PR 自動レビューで従来どおり動作する（Pro / Free いずれも）。

- 本変更は **ローカル経路のみ** が対象。
- Bot 並走運用は影響を受けない。

並走時の挙動（approve 2 個の AND ゲート、重複指摘の捌き方）は本ドキュメント上節を参照する。

### 💡 `cr` を直接叩く運用は禁止しない

`/vibecorp:review` を経由せず、シェルで直接 `cr review --plain` を叩く運用は引き続き可能。

- vibecorp は利用者のシェル運用を制限しない。
- CodeRabbit CLI の Free 枠 3 reviews/hour で十分な利用者は、この運用を選べる。

### ❌ `cr` 利用継続のオプトイン経路は新設しない

`vibecorp.yml` に `claude_action.local_review_tool: cr` のような設定キーを追加して旧挙動に戻すオプトイン経路は **新設しない**。

理由を以下に整理する。

- 🚧 `/vibecorp:ship-parallel` 5 並列で破綻する制約は本変更で解消したい根本問題そのもの。
  - デフォルトで残すと本変更の意義を損なう。
- 💸 設定キーを増やすとメンテナンスコストが恒常的に発生する。
- ✅ `cr` を直接叩く運用は前項のとおり禁止しない。
  - 利用継続したい利用者の選択肢は確保されている。
- 🔁 CodeRabbit Bot（CI 側）は `coderabbit.enabled: true` で並走継続できる。
  - CodeRabbit エコシステムからの完全離脱は強制されない。

### 📖 `coderabbit.enabled` フラグの意味論変更

本変更により、`coderabbit.enabled` フラグの意味論は以下に絞られる。

- `coderabbit.enabled: true` — `.coderabbit.yaml` を配布し、CodeRabbit Bot を有効化する。
- `coderabbit.enabled: false` — `.coderabbit.yaml` を配布しない、CodeRabbit Bot は無効化される。
  - **ローカル `/vibecorp:review` には影響しない**（Claude Code CLI 直接呼び出しは常に実行）。

完了条件「`coderabbit.enabled: false` 設定でも `/vibecorp:review` が完走する後方互換」は本変更により自動充足される。

CodeRabbit 依存が消えたため。

### 💰 コスト影響

ローカル `/vibecorp:review` のコスト経路がシフトする。

- 旧: CodeRabbit Free 3/hour quota（無料）。
- 新: Claude Max OAuth quota（個人クォータ）消費。

チーム運用時の共有負担リスクは `docs/cost-analysis.md` の以下を参照する。

- 「Bot 経由 Claude Max OAuth のレート枯渇リスク」セクション。
- 「`/vibecorp:review` ローカル経路のコスト経路シフト（Issue #499）」セクション。

> [!WARNING]
> `/vibecorp:review` 起動時に `ANTHROPIC_API_KEY` が設定されていると exit 1 で fail-fast する。
> 意図しない API 従量課金を防ぐためのガード（Issue #455 コメント 8 で CEO 指定）。

## 導入先スモークテストの assert 方針

`vibehawk.enabled` / `coderabbit.enabled` の値は配置先で切り替えられる。

スモークテストで `.vibehawk.yaml` / `.coderabbit.yaml` の **存在 / 不在を絶対値で assert しない**こと。

- `enabled: false` 前提で「不在」を assert すると、`enabled: true` 切替時にテストが落ちる。
- 逆も同様。

### ✅ 推奨パターン: `vibecorp.yml` の `enabled` を読んで分岐

```bash
# 例: smoke test テンプレート（bash）
enabled=$(awk '/^vibehawk:/{f=1; next} f && /^[^ ]/{f=0} f && /^[[:space:]]+enabled:/{sub(/^[[:space:]]+enabled:[[:space:]]*/, ""); print; exit}' .claude/vibecorp.yml)

if [ "$enabled" = "true" ]; then
  # enabled: true 運用 → .vibehawk.yaml が配布されていること
  test -f .vibehawk.yaml || { echo ".vibehawk.yaml missing"; exit 1; }
else
  # enabled: false 運用 → ファイル不在を assert しない（過去の残骸が残っていても無視）
  echo "vibehawk.enabled=${enabled:-false}: smoke skip"
fi
```

または、配布対象ファイル一覧を直接 assert せずに **「現設定との整合」** にとどめる。

例: `.vibehawk.yaml` / `.coderabbit.yaml` 内のキーが正しい、`vibecorp.yml` がパース可能。

> [!NOTE]
> vibehawk workflow 本体 / required check `vibehawk` の存在は `npx vibehawk setup` + CEO の branch protection 操作で整う。
> install.sh は配布しないため、スモークテストでこれらの存在を絶対値で assert しない。

**絶対値 assert は `enabled` 切替で必ず壊れることを前提に書かない**。

## 🔗 関連

- 認証経路: `docs/ai-review-auth.md`
- 設定ファイル本体: `vibecorp.yml`（`vibehawk` / `coderabbit` / `branch_protection` セクション）
- vibehawk 設定: `.vibehawk.yaml`（**`vibehawk.enabled: true` 運用時に install.sh が生成**）
- vibehawk 導入導線: `npx vibehawk setup`（App + 3 secrets + workflow 配布、vibehawk リポジトリが SoT）
- 捌き基準: `.claude/rules/review-handling.md`
- severity 定義: `.claude/rules/severity/coderabbit.md` / `.claude/rules/severity/claude-action.md`
- レビュー観点: `.claude/rules/review-observations.md`
- レビューコメント / Bot 通知コメントの書式: `.claude/rules/comment-writing.md`
- intent ラベル: `.claude/rules/intent-labels.md`
- ロールバック手順: `docs/ai-review-rollback.md`

## 🔗 関連 Issue

- vibehawk 移譲: [#531](https://github.com/hirokimry/vibecorp/issues/531)（vibehawk / coderabbit 独立トグル、デフォルト vibehawk-only）
- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#472](https://github.com/hirokimry/vibecorp/issues/472)
- 依存元: [#461](https://github.com/hirokimry/vibecorp/issues/461)（ワークフロー骨格）
- 依存元: [#465](https://github.com/hirokimry/vibecorp/issues/465)（REVIEW.md）
- 依存元: [#466](https://github.com/hirokimry/vibecorp/issues/466)（auto-resolve）
- 依存元: [#467](https://github.com/hirokimry/vibecorp/issues/467)（approve / request_changes 発行）
