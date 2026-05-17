# 🔒 claude-code-action OAuth 認証経路

> [!IMPORTANT]
> 読者像は claude-code-action を運用する利用者・開発者。
> 本ドキュメントは AI レビューの OAuth 認証経路の **Source of Truth**。
> 基準: Issue #462（CEO 議論結果、2026-05-04 確定）。

現在の運用状態を以下に補足する。

> [!WARNING]
> vibecorp 本体は現在 `claude_action.enabled: false` で運用中（Issue #532）。
> CodeRabbit Bot 単独運用、vibehawk 完成までの暫定措置。
> 本ドキュメントは再有効化時／利用者が `enabled: true` で運用する場合の SoT として保持する。

## 1️⃣ Bot 認証方式 — GitHub App

vibecorp は claude-code-action の Bot 認証に **GitHub App** を採用する。

### 🎯 採用理由

| 観点 | GitHub App | 個人 PAT | Bot 専用アカウント PAT |
|---|---|---|---|
| 組織管理 | ✅ Organization 単位で管理可能 | ❌ 個人依存 | ⚠️ 別アカウント運用が必要 |
| ローテーション | ✅ App 単位で鍵更新可能 | ⚠️ 個人作業必要 | ⚠️ 別アカウント作業必要 |
| 権限スコープ | ✅ Repository / Organization 単位の最小権限 | ❌ ユーザー全権限 | ❌ ユーザー全権限 |
| 業界推奨 | ✅ GitHub 公式推奨 | ⚠️ レガシー | ⚠️ アンチパターンとされる場合あり |

> [!NOTE]
> `GITHUB_TOKEN` は GitHub Actions が自動発行する標準トークン。
> しかし **自分自身が起こした PR に approve できない仕様**（review API の自己 approve 禁止）。
> Bot による approve には使えない。

### 🛠️ 設置手順

GitHub App の作成・インストール手順は claude-code-action 公式ドキュメントに従う。

本ドキュメントは vibecorp 側の運用方針のみを定義する。

## 2️⃣ CLAUDE_CODE_OAUTH_TOKEN の調達

リポジトリ管理者個人の **Claude Max OAuth トークン**を `CLAUDE_CODE_OAUTH_TOKEN` シークレットとして登録する。

> [!IMPORTANT]
> claude-code-action は **2 系統の認証**を要求する。
>
> 1. **Claude API 認証**: `CLAUDE_CODE_OAUTH_TOKEN`（Claude Max OAuth、本節で扱う）
> 2. **GitHub App identity 認証**: `id-token: write` permission による GitHub OIDC token（workflow に必須、Issue #505 で例外承認済）
>
> どちらか一方が欠けると claude-code-action は起動失敗する。
> 例: `Could not fetch an OIDC token` エラー。
> `id-token: write` の permissions 設定は `templates/.github/workflows/ai-review.yml` で配布済み。

### 🔑 発行手順

```bash
# Anthropic 公式 CLI でトークンを発行する（ブラウザで OAuth 認可フローが開く）
claude setup-token
```

`claude setup-token` は **1 年間有効な OAuth トークン**を発行する。

発行されたトークンを次の手順でリポジトリ secrets に登録する。

### 🔐 secrets 登録

```bash
# リポジトリ secrets に登録する（token の値は画面に表示されない）
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
# → プロンプトで claude setup-token の出力値を貼り付ける
```

または GitHub Web UI から登録する。

- 経路: `Settings → Secrets and variables → Actions → New repository secret`
- 名前: `CLAUDE_CODE_OAUTH_TOKEN`

### 🔄 1 年経過時の更新

トークン有効期限の 1 年前後で更新作業をする。

- `claude setup-token` を再実行する。
- 新しいトークンを secrets に上書き登録する。
- ⚠️ 失効後は claude-code-action が認証エラーで停止する。
- 有効期限の管理はリポジトリ管理者の責務とする。

## 3️⃣ Forked PR の対処方針 — AI レビュー対象外

**外部コントリビューターが Fork から出した PR は claude-code-action のレビュー対象外**とする。

人間レビューのみで処理する。

### 📚 根拠（GitHub 公式仕様）

- 外部コントリビューターは push 権限がない。
  - 必ず Fork 経由で PR を出す。
- Fork からの PR では `pull_request` ワークフローに **secrets が渡らない**。
  - 例外: `GITHUB_TOKEN` のみ。
- → claude-code-action は `CLAUDE_CODE_OAUTH_TOKEN` を読めない。
- → レビュー実行不可で自然にスキップされる。

### ❌ `pull_request_target` を採用しない理由

`pull_request_target` トリガーを使えば Fork PR でも secrets を渡せる。

しかし採用しない。

- ⚠️ OWASP リスクが高い。
- Fork 側の悪意あるコードに secrets を握られる経路となる。
- AI レビューを諦めて人間レビューに委ねる方が安全。

### 🛡️ 防御的実装

ワークフロー側は通常の `pull_request` トリガーを使う。

Fork PR では secrets 不在で claude-action が起動できず、自然にスキップされる。

しかし多層防御の観点から各ジョブに明示的な if 条件を設置する。

```yaml
jobs:
  claude-review:
    if: github.event.pull_request.head.repo.full_name == github.repository && !github.event.pull_request.draft
```

> [!NOTE]
> Issue #575 確定で PR 側 `intent-label-check` ジョブは廃止。
> Issue 側 `intent-label-issue-check.yml` に SoT 集約された。

明示的なゲートを置く理由を以下に整理する。

- 🔍 Fork PR では「secrets がないので落ちる」という暗黙挙動に依存しない。
  - 明示的なゲートで早期 skip させる方が追跡上わかりやすい。
  - `if:` 条件不一致時はジョブ失敗ではなく skip 扱いとなる。
- 🚧 `!github.event.pull_request.draft` は draft 状態でも発火する GitHub 仕様を相殺する。
  - `ready_for_review` トリガー設計と整合させる。
- ⚙️ 将来 `pull_request_target` を誤って混入した場合の事故を防ぐ。
- 🔒 CISO 要件 (#464) を機械的に保証する。
  - 「secrets スコープが認証領域を侵食しないこと」。

### ⚙️ ワークフロー構成

`templates/.github/workflows/ai-review.yml`（vibecorp 配布版）の主要要素。

| 要素 | 値・条件 | 根拠 |
|---|---|---|
| `on.pull_request.types` | `[opened, synchronize, ready_for_review]` | 開封・push・draft 解除でレビュー起動 |
| ジョブ `if:` 条件 | `head.repo.full_name == github.repository && !github.event.pull_request.draft` | Fork PR と draft PR を多層防御で除外 |
| `permissions.contents` | `read` | コード読取のみ、書込不要（CISO 最小権限） |
| `permissions.pull-requests` | `write` | レビューコメント書込が必要 |
| `permissions.issues` | `write` | preflight ガード + claude-code-action 内部 Issues 書込経路 |
| `permissions.id-token` | `write` | OIDC token 発行に必須（#505 CISO 例外承認） |
| `concurrency.group` | `ai-review-${{ pr.number }}` | 同一 PR への push 連打を直列化してコスト抑制 |
| `concurrency.cancel-in-progress` | `true` | 古い実行は中断して最新コミットのみレビュー |
| `claude-review.timeout-minutes` | `10` | 中規模 PR 完走に十分（超過時は失敗、#466 確定 4-5） |
| `intent-label-check` ジョブ | Issue #575 確定で廃止 | Issue 側 `intent-label-issue-check.yml` に集約 |
| `claude-review` の REVIEW.md 読込 step | `cat REVIEW.md` をランダム delimiter heredoc で `$GITHUB_OUTPUT` の `prompt` に流す | REVIEW.md 本文に同名行が含まれた場合の事故を防ぐ |
| `claude-review` ジョブ | `anthropics/claude-code-action@v1` 呼び出し | OAuth Token 認証で起動、REVIEW.md をプロンプトに使用 |

draft PR の取り扱いを補足する。

`types: [opened, synchronize, ready_for_review]` だけでは draft への push でもジョブが起動する。

ジョブの `if:` で `!github.event.pull_request.draft` を明示することで除外する。

## 4️⃣ secrets 漏洩時の revocation 手順

`CLAUDE_CODE_OAUTH_TOKEN` の漏洩を検知した場合、**リポジトリ管理者が手動で**以下の 4 ステップを実行する。

| # | 手順 | 実行場所 |
|---|---|---|
| 1 | Anthropic Console で OAuth トークンを revoke | https://console.anthropic.com/ |
| 2 | `CLAUDE_CODE_OAUTH_TOKEN` シークレットを削除 | `Settings → Secrets and variables → Actions` |
| 3 | `claude setup-token` で新規トークンを発行 | ローカル端末 |
| 4 | 新トークンを secrets に再登録 | `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>` |

### 🚫 自動化方針

vibecorp は **revocation スクリプトを提供しない**。

理由を以下に整理する。

- 🔒 Anthropic Console の revoke は API 公開されていない。
  - 人間によるブラウザ操作が必須。
- ⚠️ GitHub secrets 削除を自動化すると、誤操作で正常な secrets を削除するリスクがある。
- 🧑 漏洩検知は人間判断を要する。
  - 復旧手順全体を人間が実行する設計が安全。

## 5️⃣ install.sh の secrets 検証

`install.sh` は `vibecorp.yml` の `claude_action.enabled: true` を検出した場合、secrets の登録有無を確認する。

未登録なら警告を出力する。

### ⚙️ 検証ロジックの仕様

| 条件 | install.sh の挙動 |
|---|---|
| `vibecorp.yml` 不在 | スキップ（return 0） |
| `claude_action` セクション不在 | `ensure_claude_action_section` が `enabled: true` で自動追加 |
| `claude_action.enabled: false` | スキップ（return 0） |
| `gh` CLI 未導入 | スキップログ出力で return 0 |
| `gh auth status` 失敗 | スキップログ出力で return 0 |
| `enabled: true` + `CLAUDE_CODE_OAUTH_TOKEN` 登録あり | INFO ログ「登録済み」 |
| `enabled: true` + `CLAUDE_CODE_OAUTH_TOKEN` 未登録 | WARN ログ + 設定方法案内 |

> [!NOTE]
> `ensure_claude_action_section` は **既存値を絶対に上書きしない**。
> 明示的に `enabled: false` を設定したリポジトリは `--update` 後も `false` のまま維持される。

### ⚠️ 警告メッセージの内容

未登録時は以下のメッセージで設定を促す。

```text
[WARN] CLAUDE_CODE_OAUTH_TOKEN が登録されていません
       claude-code-action を有効化するには以下を実行してください:
         claude setup-token
         gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
       詳細: docs/ai-review-auth.md
```

警告のみで `install.sh` は失敗扱いにしない（`exit 0` 継続）。

> [!WARNING]
> `gh secret list` は secret 名のみを返し、値を取得できない。
> secret 名が登録されていても値が空文字列のケースは install.sh では検出不可能。
> このパターンは `ai-review.yml` の preflight ガード（後述「8️⃣ claude-review ジョブの preflight ガード」）が PR コメントで動的に通知する。

## 6️⃣ 個人 Claude Max OAuth クォータ枯渇リスク

Anthropic 公式は「個人 Claude Max OAuth トークンを高頻度自動化用途で使うと、対話用クォータを枯渇させる可能性がある」と警告している。

vibecorp 利用者は以下を理解した上で運用する。

### ⚠️ リスクの本質

- `claude setup-token` で発行する OAuth トークンは **個人 Claude Max プランのレート枠を消費する**。
  - 単位: 5 時間あたりのトークン上限。
- claude-code-action でレビューを多発させると、リポジトリ管理者本人の対話用クォータも枯渇する。
- レート制限到達時の挙動はプラン依存。
  - Claude Max: 遅延。
  - API 従量課金: 通知なしフォールバック。

### 👥 チーム運用時の注意

複数メンバーが PR を出すチーム運用では、共有負担リスクが発生する。

- メンバー全員の PR レビューが「リポジトリ管理者」個人の Max クォータから消費される。
- 全員分のレビュー量がリポ管理者 1 人のレート枠を圧迫する。
- リポ管理者が対話用に Claude を使えなくなる時間帯が発生しうる。

### 🛡️ 緩和策

| 対策 | 内容 |
|---|---|
| cadence 伸長 | `/vibecorp:autopilot` の定期実行を 24 時間 → 36 時間に伸ばす |
| Bot 専用 Max 別契約 | Bot 専用メールアドレスで別途 Claude Max を契約（将来選択肢） |
| API 従量課金切替 | 高頻度運用時は `ANTHROPIC_API_KEY` に切り替え（コスト発生に注意） |

### ✅ 安心材料

Fork PR 経由のレビューはクォータを消費しない。

- **Forked PR は claude-action 対象外**。
- 外部コントリビューターの PR ではクォータ消費は起きない。
- 公開リポジトリでも、赤の他人は必ず Fork 経由で PR を出すため secrets に触れない。

### 💰 コスト影響の詳細

レート枯渇のコスト試算・cadence 推奨値の根拠は別ドキュメントを参照する。

参照先: `docs/cost-analysis.md` の「Bot 経由 Claude Max OAuth のレート枯渇リスク」セクション。

## 7️⃣ dismiss の責任分担（#466 確定）

レビューにおける 2 種類の dismiss は責任主体を明確に分離する。

重複・越権を避けるためである。

| dismiss 種別 | 責任主体 | 対象範囲 | タイミング |
|---|---|---|---|
| **approve dismiss**（review approval） | Branch Protection の `dismiss_stale_reviews: true`（#463） | push 毎に **全レビュアーの approve** を一括 dismiss | push が来たタイミング |
| **review thread dismiss**（インラインコメント） | claude-action 自身が REVIEW.md の指示で実行（#466） | **claude-action 自身のコメントのみ**、修正済み判定したもの | 再レビュー時、修正完了確認後 |

> [!WARNING]
> claude-action は CodeRabbit / 人間レビュアーのインラインコメントを触らない（越権禁止）。
> CodeRabbit 側は `auto_resolve.enabled: true` で自走運用する。
> 人間コメントは作成者が手動で resolve する。

## 8️⃣ claude-review ジョブの preflight ガード

`claude-review` ジョブは `anthropics/claude-code-action@v1` を呼ぶ前に preflight ステップで `CLAUDE_CODE_OAUTH_TOKEN` の値が空でないことを検査する。

### 📚 背景

空文字列のまま claude-code-action を呼ぶと内部 validation でエラー終了する。

- エラー: `Either ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN is required` (exit 1)。
- required check 未登録のため auto-merge を妨げない。
- → AI レビュー pipeline が静かに死ぬ問題が発覚した（PR #508、Issue #509）。

### ⚙️ 仕様

| 観点 | 内容 |
|---|---|
| 配置位置 | `claude-review` ジョブの先頭（チェックアウト step より前） |
| 検査対象 | `secrets.CLAUDE_CODE_OAUTH_TOKEN` |
| 空判定 | bash `[[ -z "${OAUTH_TOKEN}" ]]` で空文字列を検出 |
| 警告コメント | 空のときのみ PR に投稿、文言は固定 prefix で始まる |
| 重複防止 | `gh pr view --json comments --jq` で既存検出 |
| `gh` 引数 | workdir 空のため `--repo "$REPO"` を必須で明示 |
| 終了挙動 | 空判定にヒット → `exit 1`、後続未到達 |

### 🛡️ fail-safe 設計

`existing=$(gh pr view ...)` が `bash --noprofile --norc -e -o pipefail` 環境で失敗した場合、preflight step そのものが exit 1 で落ちる。

- コメント投稿に到達しない。
- 後続の claude-code-action 呼び出しに到達しない。
- これは **意図的な fail-safe**。
- `shell.md` の「コマンドそのまま実行」ルールに従い `|| echo "0"` のフォールバックは使わない。
- preflight は「真のガード」であり、コメント投稿失敗を握りつぶす方が危険。

### 📝 文言変更時の注意

警告コメントの prefix は重複検出キーとして使われる。

prefix: `⚠️ AI レビュー（claude-code-action）が起動できません`。

変更する際は以下 4 箇所を **同時に** 更新する。

1. `.github/workflows/ai-review.yml` の preflight ステップ（PR コメント投稿の `--body`）
2. `.github/workflows/ai-review.yml` の preflight ステップ（既存検出の `startswith("...")` 引数）
3. `templates/.github/workflows/ai-review.yml` の同位置
4. 本ドキュメントの記述

### 🧪 テスト

| ファイル | 種別 | 検証内容 |
|---|---|---|
| `tests/test_install_ai_review_workflow.sh` | 静的（yaml 構造） | preflight ステップ存在、env 受け取り、空判定、警告文言、`--repo` 明示 |
| `tests/test_ai_review_preflight.sh` | 動的（bash 実行） | 3 ケース: 空 token + 既存なし / 空 token + 既存あり / 設定済み |

> [!NOTE]
> yaml 静的検証だけでは「ステップは存在するが空判定が壊れている」「重複防止が誤検知する」等の bash 実行時バグを検出できない。
> 動的単体テストも必須として追加している。

## 9️⃣ PAT セットアップ（update-pr-branches ワークフロー用）

`update-pr-branches` ワークフローは `GITHUB_TOKEN` では `update-branch` API を実行できない。

リポジトリシークレットに PAT（Personal Access Token）を登録する必要がある。

`README.md` から本ドキュメントへ移譲した手順。

### 9-1️⃣ Fine-grained PAT の作成

1. GitHub → 右上プロフィールアイコン → **Settings**。
2. 左サイドバー最下部 → **Developer settings**。
3. **Personal access tokens** → **Fine-grained tokens** → **Generate new token**。
4. 以下を設定する。
   - **Token name**: `vibecorp-update-pr-branches`。
   - **Expiration**: 任意（デフォルト 30 days）。
   - **Repository access**: **Only select repositories** → 対象リポジトリを選択。
   - **Permissions**:
     - **Contents**: Read and write。
     - **Pull requests**: Read and write。
5. **Generate token** をクリックし、表示されたトークンをコピーする。

### 9-2️⃣ リポジトリシークレットへの登録

```bash
# 対話入力で設定（履歴に残らない）
gh secret set PAT
```

### 9-3️⃣ 確認

```bash
gh secret list
# PAT が表示されれば OK
```

### 9-4️⃣ 注意事項

- ✅ 対話入力を使う（コマンド引数にトークンを渡すとシェル履歴に残る）。
- 🚨 トークンが漏洩した場合は即座に revoke して再作成する。
- 🔄 有効期限が切れたら再作成・再登録が必要。
- ⚠️ PAT 未設定の場合、ワークフローは警告を出してスキップする（エラーにならない）。

## 🔗 関連

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#462](https://github.com/hirokimry/vibecorp/issues/462)
- 後続: [#463](https://github.com/hirokimry/vibecorp/issues/463)（Branch Protection の Bot approve 経路）
- 後続: [#464](https://github.com/hirokimry/vibecorp/issues/464)（claude-code-action の権限スコープ）
- 後続: [#468](https://github.com/hirokimry/vibecorp/issues/468)（`claude_action.enabled` 独立フラグ）
- セキュリティ方針: [docs/SECURITY.md](SECURITY.md)
- コスト方針: [docs/cost-analysis.md](cost-analysis.md)
