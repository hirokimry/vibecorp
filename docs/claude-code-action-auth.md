# claude-code-action OAuth 認証経路

> このドキュメントは vibecorp が claude-code-action（GitHub Actions 上で Claude を起動する公式アクション）を運用するための認証経路の Source of Truth です。

## 概要

vibecorp は CodeRabbit の代替として claude-code-action を AI レビュー基盤に組み込む（親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)）。GitHub Actions のランナー上で Claude Code を `Claude Max 定額内` で動かすため、`CLAUDE_CODE_OAUTH_TOKEN` による OAuth 認証が必須となる。

このドキュメントは Issue #462 の成果物として、以下を確定する:

- Bot 用 **PAT vs GitHub App** の選定判断
- `CLAUDE_CODE_OAUTH_TOKEN` の **取得・登録手順**
- **Forked PR** で secrets が触れない問題への対処方針
- **Revocation 手順**（漏洩時の無効化）

並走する Issue [#461](https://github.com/hirokimry/vibecorp/issues/461) が `templates/.github/workflows/ai-review.yml` を配布する。本ドキュメントはそのワークフローが消費する secrets と認証の前提条件を定義する。

## 1. 認証方式の選定（PAT vs GitHub App）

claude-code-action がリポジトリに対して PR コメント・Review・Check Run を書き戻すには、GitHub 側の認証主体が必要になる。候補は 2 つ。

| 観点 | Bot 用 PAT（推奨） | GitHub App |
|---|---|---|
| 初期セットアップ | 個人アカウント or Bot アカウントで PAT を発行するだけ | App 登録 → installation → 権限承認の 3 段必要 |
| トークン管理 | リポジトリ secrets に 1 件登録（`CLAUDE_CODE_OAUTH_TOKEN`） | App private key を secrets で管理 + JWT 生成ロジックが必要 |
| 権限スコープ | PAT の scope（`repo`, `workflow`, `read:org` 等）で粗粒度に制御 | Fine-grained permissions（PR write、Issues write、Contents read 等）で細粒度に制御 |
| Forked PR 対応 | secrets が渡らないため `pull_request_target` 必須（後述） | 同左（GitHub App でも同じ制限） |
| 監査性 | PAT の最終使用日時のみ確認可能 | App の audit log で API 呼び出し単位の追跡が可能 |
| 取り消し（revocation） | PAT を 1 件 revoke すれば即停止 | App installation の suspend / uninstall |
| Anthropic 公式手順 | claude.ai / Claude Code CLI から OAuth トークンを発行する経路が公式に存在する | 現時点で claude-code-action 公式は PAT/OAuth トークン経路を推奨している |

### 判断記録

**vibecorp は Bot 用 PAT 方式を推奨**する。理由:

1. **Anthropic 公式の推奨経路**: `CLAUDE_CODE_OAUTH_TOKEN` は Claude Max サブスクリプションに紐づく OAuth トークンとして発行される。GitHub App では同等の Claude 側の認証経路を確立できない（Claude Max の課金主体が GitHub App ではなく個人アカウントに紐づくため）。
2. **セットアップ単純性**: vibecorp は `install.sh` で配布される設定一式が「動くまで 5 分」を目標としている。GitHub App は登録 / installation の手数が多く、初期導入コストが PAT より大幅に高い。
3. **revocation の即応性**: 漏洩時は PAT を revoke するだけで即停止できる。GitHub App の suspend は反映に遅延が出る場合がある。

**GitHub App は将来の選択肢**として保留する。Issue [#463](https://github.com/hirokimry/vibecorp/issues/463)（Branch Protection の Bot approve 経路）の決定によっては、複数リポジトリで一括管理する目的で App 化を再評価する。

## 2. `CLAUDE_CODE_OAUTH_TOKEN` の取得・登録手順

### 2.1 OAuth トークンの取得

Claude Max サブスクリプションに紐づく OAuth トークンを発行する。

```bash
# Claude Code CLI から発行（推奨）
claude auth token --scope claude-code-action
# => 表示された CLAUDE_CODE_OAUTH_TOKEN=... を控える
```

> ⚠️ 取得経路の表記は Anthropic 側の UI / CLI 仕様に追従する。CLI のサブコマンド名・オプションが変わった場合は Issue を起票して本ドキュメントを更新する。

代替経路として claude.ai のアカウント設定 → Developer → OAuth Tokens から発行することもできる（GUI 経路）。**個人 Claude Max 契約での発行を想定**しており、Team / Enterprise 契約での挙動は未検証。

### 2.2 リポジトリ secrets への登録

GitHub リポジトリの Settings → Secrets and variables → Actions で以下を登録する。

| Name | Value | 用途 |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | 上記で取得した OAuth トークン | claude-code-action のランタイム認証 |

`gh` CLI 経由なら以下:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
# stdin で値を貼り付け
```

### 2.3 ワークフローからの参照

Issue [#461](https://github.com/hirokimry/vibecorp/issues/461) で配布される `.github/workflows/ai-review.yml` が以下の形で参照する想定:

```yaml
jobs:
  ai-review:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

ワークフロー側の詳細仕様は #461 / `templates/.github/workflows/ai-review.yml` 配布時の README で確定する。

## 3. Forked PR での挙動規定

GitHub Actions は **fork からの PR では secrets を環境変数に渡さない**（公式仕様）。`pull_request` トリガーのまま放置すると、外部コントリビューターからの PR で claude-code-action が認証エラーで失敗する。

### 3.1 採用方針: `pull_request_target` + ラベルゲート

claude-code-action のレビューワークフローは **`pull_request_target` イベントでトリガー**し、PR のベースブランチ（信頼境界 = リポジトリオーナーの管理下）でチェックアウトする。

```yaml
on:
  pull_request_target:
    types: [opened, synchronize, reopened, labeled]

jobs:
  ai-review:
    # 信頼境界: ラベル `intent/ai-review-allowed` を付けた PR のみ対象
    if: contains(github.event.pull_request.labels.*.name, 'intent/ai-review-allowed')
    steps:
      - uses: actions/checkout@v4
        with:
          # ⚠️ ベースブランチを参照（fork のコードを実行しない）
          ref: ${{ github.event.pull_request.base.sha }}
      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### 3.2 セキュリティ境界

- **fork のコードを `pull_request_target` で実行しない**: `actions/checkout` で `pull_request.head.sha` を直接 checkout すると、fork のスクリプトが secrets 環境下で実行される（pwn-request 攻撃）。base SHA を checkout し、claude-code-action は **PR diff のみを読む** 用途に限定する。
- **ラベルゲート**: `intent/ai-review-allowed` ラベル（Issue [#469](https://github.com/hirokimry/vibecorp/issues/469) で整備予定）が無い PR は対象外。リポジトリオーナー / メンテナがラベルを付与した PR のみ AI レビューを走らせる。
- **権限スコープの最小化**: `permissions:` ブロックで `contents: read`, `pull-requests: write` 等に限定する（Issue [#464](https://github.com/hirokimry/vibecorp/issues/464) で確定）。

### 3.3 既知の制約

| 制約 | 内容 |
|---|---|
| 初回 PR の手動承認 | 外部コントリビューターの初回 PR では Actions が手動承認待ちになる（GitHub のデフォルト挙動）。リポジトリ側の Actions 設定で承認ポリシーを調整する |
| ラベル付与後の再 trigger | `labeled` イベントで再走行するため、メンテナがラベルを付けるまで AI レビューは走らない |
| fork → fork PR は非対応 | 上流のメンテナがラベル付与権限を持たないケースは対象外 |

## 4. Revocation 手順

`CLAUDE_CODE_OAUTH_TOKEN` が漏洩した、あるいは Bot アカウントの管理者が交代した場合に即時実行する手順。

### 4.1 即時無効化（インシデント対応）

```bash
# 1. リポジトリ secrets を削除
gh secret delete CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>

# 2. Anthropic 側で OAuth トークンを revoke
claude auth revoke --token <漏洩したトークンの先頭 8 文字等で識別>
# または claude.ai → Developer → OAuth Tokens → Revoke
```

ステップ 1 と 2 は **両方** 実行する。secrets 削除だけでは流出済みのトークンが他環境で使われ続ける可能性がある。

### 4.2 漏洩経路の確認

- 直近の Actions 実行ログを確認し、secrets が echo / cat 等で誤って出力されていないか確認
- リポジトリの commit history を `git log -p -- <設定ファイル>` で確認し、`.env` 等にハードコードされていないか確認
- Anthropic ダッシュボードで該当トークンの最終使用日時 / IP を確認

### 4.3 ローテーション運用（漏洩なし時）

定期的なローテーションを推奨するが、現時点では **手動運用** とする。CEO が四半期ごとに以下を実行:

1. 新しい `CLAUDE_CODE_OAUTH_TOKEN` を発行
2. リポジトリ secrets を更新（`gh secret set` で上書き）
3. 旧トークンを revoke

cron 等での自動ローテーション機構は本 Issue のスコープ外（後続検討）。

### 4.4 監査ログの記録

revocation を実行したら以下に記録する:

- リポジトリの Issue として `[security] CLAUDE_CODE_OAUTH_TOKEN revocation YYYY-MM-DD` を起票
- `knowledge/security/audit-log/YYYY-QN.md`（CISO 管轄）に追記（buffer worktree 経由）

## 5. 既知の制約・運用上の注意

| 制約 | 内容 |
|---|---|
| Bot コメントの表示主体 | claude-code-action は OAuth トークンの所有者（Bot アカウント）として PR コメントを書く。Bot アカウントの作成・命名は CEO の判断に委ねる |
| secrets スコープ | リポジトリ secrets として登録する想定。Organization secrets は管理粒度が異なるため本ドキュメントの対象外 |
| 自己ホスト ranner | 本認証経路は GitHub-hosted ranner 前提。self-hosted ranner では secrets の到達経路が異なるため別途検証が必要 |
| Claude Max 課金主体 | 個人アカウントの Claude Max 契約に紐づくため、契約者が組織を離脱するとトークンが失効する。離脱時は事前にトークンローテーション手順を実行する運用とする |

## 6. 後続対応

### install.sh の secrets 検証ロジック

Issue #462 の達成条件「✅ install.sh から secrets 設定有無を検証する仕組み（任意）」は、並走する Issue [#461](https://github.com/hirokimry/vibecorp/issues/461) が `install.sh` を編集するため **本 PR ではスコープ除外** している（コンフリクト回避）。

後続として「`install.sh` に `gh secret list` で `CLAUDE_CODE_OAUTH_TOKEN` の登録有無を検証し、未登録時に warning を出す」機能追加を別 Issue で起票する（または #461 マージ後に本ドキュメントから派生 Issue を切る）。

### Branch Protection との連携

Bot approve 経路の確立は Issue [#463](https://github.com/hirokimry/vibecorp/issues/463) で対応する。本ドキュメントの「PAT 推奨」判断は #463 の決定に追従する。

### 権限スコープの最小化

claude-code-action の `permissions:` ブロック設計は Issue [#464](https://github.com/hirokimry/vibecorp/issues/464) で対応する。本ドキュメントの「3.2 セキュリティ境界」は方針記述に留め、具体スコープは #464 を SoT とする。

## 関連 Issue

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 並走: [#461](https://github.com/hirokimry/vibecorp/issues/461)（ai-review.yml 配布）
- 後続依存: [#463](https://github.com/hirokimry/vibecorp/issues/463)（Branch Protection Bot approve）、[#464](https://github.com/hirokimry/vibecorp/issues/464)（権限スコープ）、[#469](https://github.com/hirokimry/vibecorp/issues/469)（intent ラベル機構）
