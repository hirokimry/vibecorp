# AI レビュー依存マップ

vibecorp の AI レビュー機構は **CodeRabbit** と **claude-code-action**（vibecorp ワークフロー枠）の 2 経路を並走させる設計。本ドキュメントは両者の責任分担、運用挙動、解約時の挙動を整理する。

## 4 契約 × ツール 責任分担表

vibecorp が利用者に提供する AI レビューの 4 契約を、各ツールがどう実現するか:

| 4 契約 | CodeRabbit | claude-code-action + vibecorp ワークフロー枠 |
|--------|----------|--------------------------------------|
| ① auto-review | ◎ ネイティブ（PR open / push で自動レビュー） | ◎ vibecorp 配布の `ai-review.yml` ワークフローが起動 |
| ② approve / request_changes 切替 | ◎ ネイティブ（`request_changes_workflow: true`、指摘ありで request_changes、resolve 後 approve） | ◎ vibecorp が `gh pr review --approve` / `--request-changes` 発行（#467 参照） |
| ③ auto-resolve（自身のコメント dismiss） | ◎ ネイティブ（`auto_resolve.enabled: true`、push 時に修正済みコメントを自動 resolve） | ◎ vibecorp が `gh api` で claude-action 自身のコメントを dismiss（#466 参照） |
| ④ 日本語レビュー | ◎ 設定（`language: ja-JP`） | ◎ `REVIEW.md` で指示（#465 参照） |

両ツールが同じ 4 契約を独立に履行する。利用者は片方だけ・両方どちらでも運用可能。

## 並走運用の挙動（approve 2 個の AND ゲート）

CodeRabbit と claude-action が両方有効な場合、GitHub のネイティブ挙動でマージ条件が決まる:

- 各レビュアーが独立して `approve` / `request_changes` を発行
- GitHub は **request_changes を優先**（厳しい方が勝つ AND ゲート的挙動）
- どちらか 1 つでも `request_changes` ならマージブロック
- 両者が `approve` なら `vibecorp.yml` の `branch_protection.required_approvals` に応じてマージ可（#463 参照）

これにより、片方が見逃した問題をもう片方が拾う多層防御が成立する。

### 重複指摘について

両ツールが同じ箇所を指摘することはあるが、利用者は両方を確認する必要はない:

- 修正対象が一致すれば 1 回の修正で両方のコメントが auto-resolve される
- 片方の解釈が分かれた場合は `.claude/rules/review-handling.md` の捌き基準（intent × severity）に従って判定する

並走時の挙動詳細・指摘ノイズの観測は #474（並走比較メトリクス）で実機検証する。

## ツール解約時の挙動

`vibecorp.yml` の `enabled` フラグで各ツールを個別に無効化できる:

| 設定 | CodeRabbit | claude-action |
|------|----------|--------------|
| `coderabbit.enabled: false` のみ | ❌ 無効 | ✅ 有効 |
| `claude_action.enabled: false` のみ | ✅ 有効 | ❌ 無効 |
| 両方 `false` | ❌ 無効 | ❌ 無効（人間レビューのみ） |
| 両方 `true`（デフォルト） | ✅ 有効 | ✅ 有効（並走） |

`install.sh` は各 `enabled` フラグを見て:
- `coderabbit.enabled: false` → `.coderabbit.yaml` を生成しない / 既存ファイルは触らない
- `claude_action.enabled: false` → `.github/workflows/ai-review.yml` と `REVIEW.md` を配布しない / 管理下の既存ファイルは削除（#468 参照）

両方無効化しても vibecorp の他機能（hooks、skills、CI 等）は動作する。AI レビューだけが止まる。

## vibecorp.yml の設定例

```yaml
# vibecorp.yml — プロジェクト設定の AI レビュー部分
coderabbit:
  enabled: true   # CodeRabbit Bot を使う

claude_action:
  enabled: true   # claude-code-action を使う
  skip_paths:     # AI レビュー対象から除外するパス（業界標準 7 件、CodeRabbit / claude-action 双方に反映）
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"

branch_protection:
  required_approvals: 1   # マージに必要な approve 件数（人間 OR Bot どちらでも 1 件としてカウント）
```

`skip_paths` は単一の入力源として、`REVIEW.md` の skip rules セクションと `.coderabbit.yaml` の `path_filters` の両方に自動反映される（#465 参照）。

## CodeRabbit 設定値の根拠（参考）

CodeRabbit 側の `.coderabbit.yaml` の主要設定値:

| 設定 | 値 | 根拠 |
|------|---|------|
| `reviews.auto_review.enabled` | `true` | 4 契約 ① auto-review |
| `reviews.auto_review.drafts` | `false` | Draft PR ではコスト節約のためレビューしない |
| `reviews.auto_review.auto_incremental_review` | `true` | push 毎にインクリメンタルレビュー（4 契約 ③ の前提）|
| `reviews.path_filters` | `vibecorp.yml` の `claude_action.skip_paths` から自動生成（`!` プレフィックス）| 4 契約 各種 + skip 設定の単一ソース化 |
| `reviews.request_changes_workflow` | `true` | 4 契約 ② approve 切替 |
| `reviews.auto_resolve.enabled` | `true` | 4 契約 ③ auto-resolve |
| `language` | `ja-JP` | 4 契約 ④ 日本語レビュー、`vibecorp.yml` の `language` と連動 |
| `chat.auto_reply` | `true` | 却下スレッドの文脈完結 |

claude-code-action 側の挙動は `REVIEW.md`（vibecorp 配布のプロンプト）と `templates/.github/workflows/ai-review.yml`（ジョブ定義）で記述する。

## 実機検証完了判定（Issue #475 確定）

vibecorp プロジェクト自身で `coderabbit.enabled: true` + `claude_action.enabled: true` の並走を 2 週間継続し、以下全てを充足した場合に検証完了とする。

### 完了判定基準（A + B）

| 要素 | 内容 | 判定方法 |
|------|------|---------|
| A. レート消費 | Claude Max 90M token/月の目安以内 | 週次サマリ × 2 回の合計、`.claude/knowledge/cfo/decisions/` に記録 |
| B. 4 契約動作 | auto-review / approve 切替 / auto-resolve / 日本語 全部機能 | 週次サマリ × 2 回で全 ✅ |

C（二重指摘ノイズ閾値）/ D（利用者不満ゼロ）は **判定外**（並走で観測するが完了判定には含めない）。

### C*O 合議による本番運用切替

完了判定を満たしたら、以下 4 役の合議で本番運用への切替を決定する。

| 役 | 評価観点 |
|-----|---------|
| CFO | レート消費・コスト面の評価（Claude Max 90M token/月以内、超過時 cadence 調整方針） |
| CISO | 認証領域への影響なし確認（`.claude/rules/autonomous-restrictions.md` 全 6 領域への抵触なし） |
| CTO | 技術品質の評価（4 契約の挙動、既知の運用問題、ロールバック手順の動作） |
| CPO | 利用者体験の評価（レビューノイズ、誤検知率、回帰検出の有効性） |

4 役全員が OK 判定の場合のみ「本番運用」へ移行する。1 名でも NG または保留の場合は検証期間を延長する。

### 「本番運用」の定義

vibecorp プロジェクト自身が claude-action 主軸で運用される状態を指す。

- vibecorp の PR レビューは claude-action を中心に運用する
- CodeRabbit は並走継続（オプション扱い、利用者は無効化可能）
- 利用者向けプリセット既定値（`coderabbit.enabled` / `claude_action.enabled`）の切替は別途検討事項（本 Issue では vibecorp 自身の運用切替のみ）

### 超過時の cadence 調整

A 契約のレート消費が 90M token/月を超過する見通しが立った場合、CFO 判断で以下のいずれかを実施する。

- (a) **cadence 24h → 36h に即伸長**: claude-action のスケジュール起動間隔を伸ばす
- (b) **`claude_action.enabled: false` にロールバック**: `docs/ai-review-rollback.md` 参照
- (c) **検証期間延長**: 様子見を 1 週間追加

判断は週次サマリで記録し、CEO の承認を得てから実施する。

### NG 時の対応

完了判定が NG（A or B 不足）の場合、以下のいずれかを CEO 判断で選択する。

- 期間延長（さらに 1 週間並走）
- スコープ縮小（`claude_action.enabled: false`、CodeRabbit のみ運用継続）
- 設計再検討（Issue #475 を reopen して論点整理）

### Bot approve 経路の動作確認と代替手段（CFO 承認条件 3）

Issue #455 CFO 条件付き承認の遵守事項 3「Bot approve 代替手段の事前検討」を充足するため、検証期間中の Bot approve 経路の動作確認と、機能しない場合の代替手段を以下の通り定める。

#### 動作確認方法（週次サマリで記録）

検証期間中、毎週末に以下を確認し、週次サマリ「2. 4 契約動作確認（B 契約）」の `② approve / request_changes 切替` 行に結果を記入する。

- ✅ claude-action が `gh pr review --approve` または `--request-changes` を発行できているか
- ✅ Branch Protection の `required_approvals` が満たされて auto-merge が発火するか
- ✅ Bot 認証エラー時に警告コメントが投稿されるか（#467 確定の挙動）
- ✅ マージが滞らないか（PR open から 24h 以内に approve / request_changes が出ているか）

#### 代替手段（Bot approve が機能しない場合）

代替案は **検証期間中に発動した場合** または **本番運用切替前に Bot approve が機能しないことが判明した場合** に CEO 判断で選択する。

| # | 代替手段 | 想定シナリオ |
|---|---------|------------|
| 1 | **CodeRabbit が approve する設定を活用** | claude-action の Bot approve が機能しない場合、`.coderabbit.yaml` の `request_changes_workflow: true`（既定）で CodeRabbit を approve 役にする |
| 2 | **人間レビュアーが必ず approve するルール** | 両 Bot とも approve 不可の場合、Branch Protection の `required_approvals` を維持しつつ人間 approve を必須化する |
| 3 | **`required_approvals: 0` に下げる** | 緊急時のみ。Bot approve も人間 approve も使えず保護機能を一時的に落とす（`vibecorp.yml` 編集 → `install.sh --update`、戻し手順は `docs/ai-review-rollback.md` 参照）|
| 4 | **GitHub App の認証経路を再構築** | OAuth Token / GitHub App の権限不足が原因の場合、`docs/ai-review-auth.md` の手順で再構築する（恒久対応）|

#### 代替手段の発動判定基準

検証期間中に以下のいずれかが発生した場合、CEO は代替手段の発動を判断する。

- ⚠️ Bot approve 失敗が連続 3 PR 以上発生
- ⚠️ Bot 認証エラーが連続 24h 以上継続
- ⚠️ マージが 48h 以上滞る PR が 2 件以上発生

判断結果は週次サマリの「ロールバック判断」セクションに記録する。

### ロールバック手順

claude-action を一時的に無効化する手順は `docs/ai-review-rollback.md` 参照。スクリプト化は **しない**（Issue #475 議論結論）。

### 週次サマリテンプレート

CFO が週次サマリを記録する際のテンプレートは `.claude/knowledge/cfo/templates/weekly-summary.md` 参照。

## 関連

- 認証経路: `docs/ai-review-auth.md`
- 設定ファイル本体: `vibecorp.yml`（`coderabbit` / `claude_action` / `branch_protection` セクション）
- ワークフロー: `.github/workflows/ai-review.yml`
- claude-action プロンプト: `REVIEW.md`
- 捌き基準: `.claude/rules/review-handling.md`
- severity 定義: `.claude/rules/severity/coderabbit.md` / `.claude/rules/severity/claude-action.md`
- レビュー観点: `.claude/rules/review-observations.md`
- intent ラベル: `.claude/rules/intent-labels.md`

## 関連 Issue

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#472](https://github.com/hirokimry/vibecorp/issues/472)
- 依存元: [#461](https://github.com/hirokimry/vibecorp/issues/461)（ワークフロー骨格）
- 依存元: [#465](https://github.com/hirokimry/vibecorp/issues/465)（REVIEW.md）
- 依存元: [#466](https://github.com/hirokimry/vibecorp/issues/466)（auto-resolve）
- 依存元: [#467](https://github.com/hirokimry/vibecorp/issues/467)（approve / request_changes 発行）
