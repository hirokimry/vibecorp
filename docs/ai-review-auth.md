# claude-code-action OAuth 認証経路

> このドキュメントは vibecorp の AI レビュー（claude-code-action）における OAuth 認証経路の Source of Truth です。
> Issue #462 の CEO 議論結果（2026-05-04 確定）に基づく。

## 1. Bot 認証方式 — GitHub App

vibecorp は claude-code-action の Bot 認証に **GitHub App** を採用する。

### 採用理由

| 観点 | GitHub App | 個人 PAT | Bot 専用アカウント PAT |
|---|---|---|---|
| 組織管理 | ✅ Organization 単位で管理可能 | ❌ 個人依存 | △ 別アカウント運用が必要 |
| ローテーション | ✅ App 単位で鍵更新可能 | △ 個人作業必要 | △ 別アカウント作業必要 |
| 権限スコープ | ✅ Repository / Organization 単位で最小権限指定可能 | ❌ ユーザー全権限 | ❌ ユーザー全権限 |
| 業界推奨 | ✅ GitHub 公式推奨 | ⚠️ レガシー | ⚠️ アンチパターンとされる場合あり |
| `GITHUB_TOKEN` | — | — | — |

> `GITHUB_TOKEN` は GitHub Actions が自動発行する標準トークンだが、**自分自身が起こした PR に approve できない**仕様（review API の自己 approve 禁止）のため、Bot による approve には使えない。

### 設置手順（参考）

GitHub App の作成・インストール手順は claude-code-action 公式ドキュメントに従うこと。本ドキュメントは vibecorp 側の運用方針のみを定義する。

## 2. CLAUDE_CODE_OAUTH_TOKEN の調達

リポジトリ管理者個人の **Claude Max OAuth トークン**を `CLAUDE_CODE_OAUTH_TOKEN` シークレットとして登録する。

### 発行手順

```bash
# Anthropic 公式 CLI でトークンを発行する（ブラウザで OAuth 認可フローが開く）
claude setup-token
```

`claude setup-token` は **1 年間有効な OAuth トークン**を発行する。発行されたトークンを次の手順でリポジトリ secrets に登録する。

### secrets 登録

```bash
# リポジトリ secrets に登録する（token の値は画面に表示されない）
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
# → プロンプトで claude setup-token の出力値を貼り付ける
```

または GitHub Web UI から `Settings → Secrets and variables → Actions → New repository secret` で `CLAUDE_CODE_OAUTH_TOKEN` を登録する。

### 1 年経過時の更新

トークン有効期限の 1 年前後で `claude setup-token` を再実行し、新しいトークンを secrets に上書き登録する。失効後は claude-code-action が認証エラーで停止するため、有効期限の管理はリポジトリ管理者の責務とする。

## 3. Forked PR の対処方針 — AI レビュー対象外

**外部コントリビューターが Fork から出した PR は claude-code-action のレビュー対象外**とする。人間レビューのみで処理する。

### 根拠（GitHub 公式仕様）

- 外部コントリビューターは push 権限がないため、必ず Fork 経由で PR を出す
- Fork からの PR では、`pull_request` ワークフローに **secrets が渡らない**（`GITHUB_TOKEN` のみ例外的に渡る）
- → claude-code-action は `CLAUDE_CODE_OAUTH_TOKEN` を読めず、レビュー実行不可で自然にスキップされる

### `pull_request_target` を採用しない理由

`pull_request_target` トリガーを使えば Fork PR でも secrets を渡せるが、**OWASP リスク（Fork 側の悪意あるコードに secrets を握られる）が高い**ため採用しない。AI レビューを諦めて人間レビューに委ねる方が安全である。

### 防御的実装

ワークフロー側は通常の `pull_request` トリガーを使う。Fork PR では secrets 不在で claude-action が起動できず、自然にスキップされるが、**多層防御の観点から各ジョブに明示的な if 条件を設置する**:

```yaml
jobs:
  intent-label-check:
    if: github.event.pull_request.head.repo.full_name == github.repository
  claude-review:
    if: github.event.pull_request.head.repo.full_name == github.repository
```

理由:
- Fork PR では「secrets がないので落ちる」という暗黙の挙動に依存せず、明示的なゲートで早期 skip させる方がレビュー追跡上わかりやすい（`if:` 条件不一致時はジョブ失敗ではなく skip 扱い）
- 将来 `pull_request_target` を誤って混入した場合の事故を防ぐ
- CISO 要件 (#464) として「secrets スコープが認証領域を侵食しないこと」の機械的保証を満たす

### ワークフロー構成

`templates/.github/workflows/ai-review.yml`（vibecorp 配布版）の主要要素:

| 要素 | 値・条件 | 根拠 |
|---|---|---|
| `on.pull_request.types` | `[opened, synchronize, ready_for_review]` | 開封・push・draft 解除でレビュー起動 |
| ジョブ `if:` 条件 | `head.repo.full_name == github.repository && !github.event.pull_request.draft` | Fork PR と draft PR を多層防御で除外 |
| `permissions.contents` | `read` | コード読取のみ、書込不要（CISO 最小権限） |
| `permissions.pull-requests` | `write` | レビューコメント書込が必要 |
| `permissions.issues` | `write` | intent-label-check のコメント投稿が必要 |
| `concurrency.group` | `ai-review-${{ pr.number }}` | 同一 PR への push 連打を直列化してコスト抑制 |
| `concurrency.cancel-in-progress` | `true` | 古い実行は中断して最新コミットのみレビュー |
| `intent-label-check` ジョブ | `intent/*` ラベル数が 2 以上で fail コメント | 1 PR 1 intent ルール (#469) の機械的強制 |
| `claude-review` ジョブ | `anthropics/claude-code-action@v1` 呼び出し | OAuth Token 認証で起動 |

`types: [opened, synchronize, ready_for_review]` だけでは draft PR への push（`synchronize`）でもジョブが起動するため、ジョブの `if:` で `!github.event.pull_request.draft` を明示する。

## 4. secrets 漏洩時の revocation 手順

CLAUDE_CODE_OAUTH_TOKEN の漏洩を検知した場合、**リポジトリ管理者が手動で**以下の 4 ステップを実行する。

| # | 手順 | 実行場所 |
|---|------|---------|
| 1 | Anthropic Console で OAuth トークンを revoke する | https://console.anthropic.com/ |
| 2 | GitHub Repository Settings で `CLAUDE_CODE_OAUTH_TOKEN` シークレットを削除する | `Settings → Secrets and variables → Actions` |
| 3 | `claude setup-token` で新規トークンを発行する | ローカル端末 |
| 4 | 新トークンを secrets に再登録する | `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>` |

### 自動化方針

vibecorp は **revocation スクリプトを提供しない**。理由:

- Anthropic Console の revoke は API 公開されておらず、人間によるブラウザ操作が必須
- GitHub secrets の削除を自動化すると、誤操作で正常な secrets を削除するリスクがある
- 漏洩検知は人間判断を要するため、復旧手順全体を人間が実行する設計が安全

## 5. install.sh の secrets 検証

`install.sh` は `vibecorp.yml` の `claude_action.enabled: true` を検出した場合、`gh secret list` で `CLAUDE_CODE_OAUTH_TOKEN` の登録有無を確認する。未登録なら警告を出力する。

### 検証ロジックの仕様

| 条件 | install.sh の挙動 |
|---|---|
| `vibecorp.yml` 不在 | スキップ（return 0） |
| `claude_action` セクション不在（旧 vibecorp.yml） | `ensure_claude_action_section` が `enabled: true` でセクションを自動追加し、その後 `verify_claude_action_secrets` が走る |
| `claude_action.enabled: false` | スキップ（return 0） |
| `gh` CLI 未導入 | スキップログを出力して return 0 |
| `gh auth status` 失敗（未認証） | スキップログを出力して return 0 |
| `claude_action.enabled: true` + `CLAUDE_CODE_OAUTH_TOKEN` 登録あり | INFO ログ「登録済み」 |
| `claude_action.enabled: true` + `CLAUDE_CODE_OAUTH_TOKEN` 未登録 | WARN ログ + 設定方法案内 |

`ensure_claude_action_section` は **既存値を絶対に上書きしない**（利用者カスタマイズ尊重）。明示的に `enabled: false` を設定したリポジトリは `--update` 後も `false` のまま維持される。

### 警告メッセージの内容

未登録時は以下のメッセージで設定を促す:

```text
[WARN] CLAUDE_CODE_OAUTH_TOKEN が登録されていません
       claude-code-action を有効化するには以下を実行してください:
         claude setup-token
         gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
       詳細: docs/ai-review-auth.md
```

警告のみで `install.sh` は失敗扱いにしない（`exit 0` 継続）。

## 6. 個人 Claude Max OAuth クォータ枯渇リスク（Anthropic 公式警告）

Anthropic 公式は「個人 Claude Max OAuth トークンを高頻度な自動化用途で使うと、対話用クォータを枯渇させる可能性がある」と警告している。vibecorp 利用者は以下を理解した上で運用すること。

### リスクの本質

- `claude setup-token` で発行する OAuth トークンは **個人 Claude Max プランのレート枠（5 時間あたりのトークン上限）を消費する**
- claude-code-action でレビューを多発させると、リポジトリ管理者本人の対話用クォータも枯渇する
- レート制限到達時の挙動はプラン依存（Claude Max は遅延、API 従量課金は通知なしフォールバック）

### チーム運用時の注意

複数メンバーが PR を出す **チーム運用では、メンバー全員の PR レビューが「リポジトリ管理者」個人の Max クォータから消費される**（共有負担）。

- 全員分のレビュー量がリポ管理者 1 人のレート枠を圧迫する
- リポ管理者が対話用に Claude を使えなくなる時間帯が発生しうる

### 緩和策

| 対策 | 内容 |
|---|---|
| cadence 伸長 | `/vibecorp:autopilot` の定期実行を 24 時間 → 36 時間に伸ばす |
| Bot 専用 Max 別契約 | Bot 専用のメールアドレスで別途 Claude Max を契約し、その OAuth を使う（将来選択肢） |
| API 従量課金切替 | 高頻度運用時は `ANTHROPIC_API_KEY` で API 従量課金に切り替える（コスト発生に注意） |

### 安心材料

- **Forked PR は claude-action 対象外**なので、外部コントリビューターの PR ではクォータ消費は起きない（前項 3 を参照）
- 公開リポジトリでも、赤の他人は必ず Fork 経由で PR を出すため、secrets に触れない

### コスト影響の詳細

レート枯渇のコスト試算・cadence 推奨値の根拠は `docs/cost-analysis.md` の「Bot 経由 Claude Max OAuth のレート枯渇リスク」セクションを参照。

## 関連

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#462](https://github.com/hirokimry/vibecorp/issues/462)
- 後続: [#463](https://github.com/hirokimry/vibecorp/issues/463)（Branch Protection の Bot approve 経路）
- 後続: [#464](https://github.com/hirokimry/vibecorp/issues/464)（claude-code-action の権限スコープ）
- 後続: [#468](https://github.com/hirokimry/vibecorp/issues/468)（vibecorp.yml の `claude_action.enabled` 独立フラグ追加）
- セキュリティ方針: [docs/SECURITY.md](SECURITY.md)
- コスト方針: [docs/cost-analysis.md](cost-analysis.md)
