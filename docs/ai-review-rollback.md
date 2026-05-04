# AI レビュー ロールバック手順

vibecorp の AI レビュー機構（CodeRabbit + claude-code-action 並走）が想定どおりに機能しない／コスト超過した場合のロールバック手順を定義する。

## 適用条件

以下のいずれかが発生した場合に本手順を発動する。

- ⚠️ Claude Max レート消費が **90M token/月の目安** を超過しそうな兆候（週次サマリで判定）
- ⚠️ Bot approve 経路が機能せずマージが滞り続ける
- ⚠️ 4 契約（auto-review / approve 切替 / auto-resolve / 日本語）のいずれかが恒常的に動作しない
- ⚠️ レビューノイズ（誤検知率）が許容を超え、利用者の生産性を阻害する

## ロールバック対象

ロールバックの対象は **claude-code-action のみ**。CodeRabbit は並走のまま残す（4 契約は CodeRabbit が単独で全て履行できる）。

## 手順（CEO・利用者ともに同じ）

### 1. `vibecorp.yml` の設定を変更する

```yaml
claude_action:
  enabled: false   # true → false に書き換え
```

`coderabbit.enabled` は `true` のまま維持する。

### 2. `install.sh --update` を実行する

```bash
./install.sh --update
```

`install.sh` は `claude_action.enabled: false` を検出し、以下を行う:

- `.github/workflows/ai-review.yml` を削除する
- `REVIEW.md` を削除する
- 既存の Branch Protection 設定（`required_approvals` 等）は **そのまま残る**

### 3. 進行中の PR を確認する

claude-code-action による review が pending の PR があれば、`gh pr review --approve` で人間 approve するか、CodeRabbit のレビューだけでマージ可能になっているかを確認する。

### 4. Branch Protection 設定の戻し（任意・手動）

`branch_protection.required_approvals: 1` 以上に設定している場合、claude-action の Bot approve がなくなることでマージが滞る可能性がある。以下のどれかで対応する:

- (a) **そのまま維持**: 人間レビュアーが必ず approve するルールに戻す
- (b) **`required_approvals: 0` に下げる**: `vibecorp.yml` を編集 → `install.sh --update` で再生成（ただし保護機能が落ちることに注意）
- (c) **CodeRabbit が approve する設定**: `.coderabbit.yaml` の `request_changes_workflow: true`（既定）で CodeRabbit が approve / request_changes を発行する

> [!NOTE]
> `install.sh` は Branch Protection 設定の **削除は行わない**。設定の戻しは GitHub の UI または `gh api` で利用者が手動で実施する（自動削除すると意図しない緩和を招くため）。

## ロールバック後の状態

| 項目 | ロールバック後 |
|------|--------------|
| CodeRabbit | ✅ 有効（4 契約全て履行） |
| claude-code-action | ❌ 無効 |
| `.github/workflows/ai-review.yml` | 削除済み |
| `REVIEW.md` | 削除済み |
| `vibecorp.yml` の `claude_action.skip_paths` | 残存（再有効化時に再利用） |
| Branch Protection | 設定維持（手動で戻す） |

## 再有効化（解決後の戻し）

claude-action 無効化の原因が解決したら、以下で戻す:

```yaml
claude_action:
  enabled: true   # false → true
```

```bash
./install.sh --update
```

`install.sh` は `.github/workflows/ai-review.yml` と `REVIEW.md` を再配布する。

## 検証期間中のロールバック判断

検証期間（2 週間並走）中に上記「適用条件」のいずれかが観測された場合:

- **CEO が手動で判断する**（自動ロールバックは実装しない、Issue #475 確定）
- 判断は週次サマリ（`.claude/knowledge/cfo/decisions/` 配下）に記録する
- ロールバック実施時は `decisions/2026-Q2.md` 等に「実機検証期間中ロールバック」として詳細を残す

## スクリプト化はしない

Issue #475 議論結論: 「シンプル手順、スクリプト化はしない」。
本手順は人間が実行する前提で文書化のみ提供する。

## 関連

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#475](https://github.com/hirokimry/vibecorp/issues/475)
- 設定本体: `vibecorp.yml`
- 依存マップ: `docs/ai-review-dependency.md`
- 認証経路: `docs/ai-review-auth.md`
