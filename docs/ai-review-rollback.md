# 🔄 AI レビュー ロールバック手順

> [!IMPORTANT]
> 読者像は AI レビュー機構を運用する利用者・CEO。
> AI レビュー（CodeRabbit + claude-code-action 並走）が想定どおりに機能しない／コスト超過した場合の手順をまとめる。
> ロールバック対象は **claude-code-action のみ**。CodeRabbit は並走維持する。

## 1️⃣ 適用条件

以下のいずれかが発生した場合に本手順を発動する。

- ⚠️ Claude Max レート消費が **90M token/月の目安** を超過しそうな兆候。
  - 週次サマリで判定する。
- ⚠️ Bot approve 経路が機能せずマージが滞り続ける。
- ⚠️ 4 契約のいずれかが恒常的に動作しない。
  - auto-review / approve 切替 / auto-resolve / 日本語。
- ⚠️ レビューノイズ（誤検知率）が許容を超え、利用者の生産性を阻害する。

## 2️⃣ ロールバック対象

ロールバックの対象は **claude-code-action のみ**。

- CodeRabbit は並走のまま残す。
- CodeRabbit は 4 契約を単独で全て履行できる。

## 3️⃣ 手順（CEO・利用者ともに同じ）

### 3-1️⃣ `vibecorp.yml` の設定を変更

```yaml
claude_action:
  enabled: false   # true → false に書き換え
```

`coderabbit.enabled` は `true` のまま維持する。

### 3-2️⃣ `install.sh --update` を実行

```bash
./install.sh --update
```

`install.sh` は `claude_action.enabled: false` を検出し、以下を行う。

- ✅ `.github/workflows/ai-review.yml` を削除する（**vibecorp 管理下のファイルのみ**）。
- ✅ `REVIEW.md` を削除する（**vibecorp 管理下のファイルのみ**）。
- 🛡️ 既存の Branch Protection 設定（`required_approvals` 等）は **そのまま残る**。

> [!NOTE]
> 「vibecorp 管理下」とは `.claude/vibecorp.lock` に `base_hash` が記録されているファイルを指す。
> 利用者が手動で配置したファイル（`base_hash` 無し）は誤削除防止のため **残置** される。
> 該当処理: `install.sh:1328-1357`。
> `base_hash` の管理: `install.sh:1222-1245`。

### 3-3️⃣ 進行中の PR を確認

claude-code-action による review が pending の PR があれば対処する。

- `gh pr review --approve` で人間 approve する。
- または CodeRabbit のレビューだけでマージ可能になっているかを確認する。

### 3-4️⃣ Branch Protection 設定の戻し（任意・手動）

`branch_protection.required_approvals: 1` 以上に設定している場合、claude-action の Bot approve がなくなることでマージが滞る可能性がある。

以下のどれかで対応する。

- (a) **そのまま維持**: 人間レビュアーが必ず approve するルールに戻す。
- (b) **`required_approvals: 0` に下げる**: `vibecorp.yml` を編集 → `install.sh --update` で再生成。
  - ⚠️ 保護機能が落ちることに注意。
- (c) **CodeRabbit が approve する設定**: `.coderabbit.yaml` の `request_changes_workflow: true`（既定）。
  - CodeRabbit が approve / request_changes を発行する。

> [!NOTE]
> `install.sh` は Branch Protection 設定の **削除は行わない**。
> 設定の戻しは GitHub の UI または `gh api` で利用者が手動で実施する。
> 自動削除すると意図しない緩和を招くため。

## 4️⃣ ロールバック後の状態

| 項目 | ロールバック後 |
|---|---|
| CodeRabbit | ✅ 有効（4 契約全て履行） |
| claude-code-action | ❌ 無効 |
| `.github/workflows/ai-review.yml` | vibecorp 管理下なら削除 / 管理外なら残置 |
| `REVIEW.md` | vibecorp 管理下なら削除 / 管理外なら残置 |
| `vibecorp.yml` の `claude_action.skip_paths` | 残存（再有効化時に再利用） |
| Branch Protection | 設定維持（手動で戻す） |

## 5️⃣ 再有効化（解決後の戻し）

claude-action 無効化の原因が解決したら、以下で戻す。

```yaml
claude_action:
  enabled: true   # false → true
```

```bash
./install.sh --update
```

`install.sh` は `.github/workflows/ai-review.yml` と `REVIEW.md` を再配布する。

## 6️⃣ 検証期間中のロールバック判断

検証期間（2 週間並走）中に「適用条件」のいずれかが観測された場合の判断ルール。

- 🧑 **CEO が手動で判断する**（自動ロールバックは実装しない、Issue #475 確定）。
- 📝 判断は週次サマリ（`.claude/knowledge/cfo/decisions/` 配下）に記録する。
- 📌 ロールバック実施時は `decisions/2026-Q2.md` 等に詳細を残す。
  - タイトル例: 「実機検証期間中ロールバック」。

## 7️⃣ スクリプト化はしない

Issue #475 議論結論: 「シンプル手順、スクリプト化はしない」。

本手順は人間が実行する前提で文書化のみ提供する。

## 8️⃣ vibehawk → CodeRabbit ロールバック（Issue #783）

Issue #783 で vibecorp 自身が vibehawk-only 運用へ移行した。vibehawk が不調で PR レビュー / merge gate が機能しなくなった場合、CodeRabbit へ戻す手順を以下に示す。

> [!IMPORTANT]
> branch protection には **2 系統**（classic protection と ruleset）が存在し、GitHub は両者の **和集合（最も厳しい設定）** を適用する。
> required status check を切り替える際は **両系統を必ず揃える**。片方だけ変更すると `vibehawk` が required のまま残り、全 PR が永久にマージできなくなる。

### 8-1. 設定ファイルを CodeRabbit へ戻す

`.claude/vibecorp.yml` のトグルを反転する。

```yaml
coderabbit:
  enabled: true   # false → true
vibehawk:
  enabled: false  # true → false
```

`.coderabbit.yaml` は git 履歴から復元する（Issue #783 で削除済み）。

```bash
git checkout <#783 マージ前の commit> -- .coderabbit.yaml
```

最も確実なのは本 PR（#783）の git revert。設定 / docs / テストが一括で戻る。

### 8-2. branch protection の required check を戻す（CEO 手動・2 系統）

admin 権限を持つ CEO が classic protection と ruleset の両方を `[test, CodeRabbit]` / approval 1 に戻す。

| 系統 | 操作 |
|------|------|
| classic protection | `repos/<owner>/<repo>/branches/main/protection` の required_status_checks を `[test, CodeRabbit]`、required_approving_review_count を 1 に |
| ruleset | 「全ブランチ保護」ruleset の required_status_checks を `[test, CodeRabbit]`、pull_request の required_approving_review_count を 1 に |

`setup-rulesets.sh` を CodeRabbit 用に戻して再実行する経路でもよい（required_status_checks の context を `CodeRabbit`、approval を 1 に戻す）。

### 8-3. CodeRabbit の発火を確認する

ロールバック後に PR を 1 本作成し、CodeRabbit のレビューと `CodeRabbit` status check が発火することを確認する。発火しない場合は CodeRabbit の GitHub App インストール状態を確認する。

## 🔗 関連

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#475](https://github.com/hirokimry/vibecorp/issues/475)
- 設定本体: `vibecorp.yml`
- 依存マップ: `docs/ai-review-dependency.md`
- 認証経路: `docs/ai-review-auth.md`
