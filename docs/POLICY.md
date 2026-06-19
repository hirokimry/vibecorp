# vibecorp ポリシー

> [!IMPORTANT]
> このドキュメントは vibecorp プロジェクト全体ポリシーの Source of Truth である。
> 読者: CEO・vibecorp 導入開発者（利用者）・コントリビューター。
> 実運用の細則は `.claude/rules/` 配下の各 SoT ファイルに委ねる。
> 本ファイルは大方針のみを定める。

## 🌿 開発ポリシー

### ブランチ戦略

ブランチ運用は Issue 駆動で行う。
📍 細則: [`.claude/rules/workflow.md`](../.claude/rules/workflow.md)

| 種別 | パターン | 例 |
|------|---------|-----|
| 通常 Issue | `dev/{Issue番号}_{要約}` | `dev/123_add_login` |
| 親エピック（feature ブランチ） | `feature/epic-{Issue番号}_{要約}` | `feature/epic-345_plan_epic_skill` |
| エピック配下の子 Issue | `dev/{Issue番号}_{要約}` | `dev/346_ship_epic_child` |

- 要約は英語スネークケース 2〜4 語
- `main` への直接作業は禁止
- マージ戦略は **squash merge**
- auto-merge が CI パス + approve 後に自動実行する
- 親エピック feature ブランチは `/vibecorp:plan-epic` が作成する
- 子 Issue の PR は親 feature ブランチを base に取る

### コードレビュー

全 PR は vibehawk または CodeRabbit のレビューが必須。
どのレビュアーを使うかは `vibecorp.yml` の独立トグル（`vibehawk.enabled` / `coderabbit.enabled`）で選ぶ（Issue #531、デフォルトは vibehawk のみ）。
📍 細則: [`.claude/rules/review-handling.md`](../.claude/rules/review-handling.md)

修正対象は **intent ラベル × severity** の掛け合わせで決定する。

| severity | 扱い |
|---------|------|
| 🔴 Critical | intent 問わず必ず対応 |
| 🟠 Major | intent 問わず必ず対応 |
| 🟡 Minor | intent の重視軸該当なら対応、外なら管轄外 |
| 🔵 Trivial | intent の重視軸該当なら対応、外なら管轄外 |
| ⚪ Info | intent の重視軸該当なら対応、外なら管轄外 |

severity 定義は CodeRabbit 公式仕様に準拠する。
📍 根拠: [`.claude/rules/severity/coderabbit.md`](../.claude/rules/severity/coderabbit.md)

- 1 Issue 1 intent を厳守する
- 複数 intent にまたがる変更は Issue を分割する
- PR には intent ラベルを付与しない（CC prefix が機械可読保険）
  📍 根拠: Issue #575 確定
- 承認基準: 「vibehawk または CodeRabbit の未解決指摘 0 件 + required CI パス」
- `/vibecorp:pr-review-loop` が PR をマージまで監視する
- auto-merge が GitHub 側で自動実行する

### デプロイ

- `main` へのマージは PR auto-merge のみで行う
- 手動 force push・直接 commit は禁止
- リリースは GitHub Release（タグ + リリースノート）で行う

**自律改善ループの制御**

自律改善ループ（`/vibecorp:diagnose` → `/vibecorp:autopilot` → `/vibecorp:ship-parallel`）は、不可領域 6 分類を CISO がフィルタリングする。
CEO（人間）の明示承認なしには自動実行されない。
📍 細則: [`.claude/rules/autonomous-restrictions.md`](../.claude/rules/autonomous-restrictions.md)

| # | 不可領域 |
|---|---------|
| 1 | 認証 |
| 2 | 暗号 |
| 3 | 課金構造 |
| 4 | ガードレール |
| 5 | MVV |
| 6 | CI エージェント権限 |

不可領域に踏み込む変更は、CEO 直接承認のもと手動で Issue 起票し `/vibecorp:ship` で実装する。

## 💬 コミュニケーションポリシー

CEO への対話応答・Issue 本文・PR 本文・コミットメッセージ・監査レポートは規約に従う。
📍 細則: [`communication.md`](../.claude/rules/communication.md)

GitHub 上で投稿するコメント（Issue / PR コメント・レビューコメント・Bot 通知コメント）は別ルールが SoT となる。
📍 細則（GitHub コメント）: [`comment-writing.md`](../.claude/rules/comment-writing.md)

- **動作主語で語る**
  - 「このソフトウェア／このフック／このスキルが〜になった」を使う
  - 関数名・ファイルパス・diff で語らない
- **マークダウンと状態絵文字を使う**
  - ✅ 完了 / ⚠️ 警告 / ❌ 失敗 / 🚀 リリース / 🔒 セキュリティ
  - 🐛 バグ / ✨ 新機能 / 📖 ドキュメント / 🔄 リファクタ / 🧪 テスト
  - 📍 根拠 / 🤖 エージェント
- **30 秒ルール**
  - CEO が 30 秒読んで「何が変わるか」を掴めることを目標にする
- **intent ラベル**
  - Issue には `intent/*` を 1 つだけ付与する
  - PR には付与しない（CC prefix が機械可読保険）
    📍 根拠: Issue #575 確定
  - 📍 細則: [`.claude/rules/intent-labels.md`](../.claude/rules/intent-labels.md)
- **言語**
  - 応答・コードコメント・ログ・エラーメッセージは全て **日本語** で書く
  - 変数名・関数名は英語可

## 🔬 品質ポリシー

### テスト

hooks やスクリプトを追加・変更した場合、対応するテストを必ず追加する。
📍 細則: [`.claude/rules/testing.md`](../.claude/rules/testing.md)

- テストファイルの命名規則: `test_*.sh`
- CI で自動実行される前提で書く
- 既存テストが壊れていないことを確認してからコミットする
- `set -euo pipefail` 下で前提ファイル不在時は `fail` 後に `exit 1` で早期終了する
- `trap cleanup EXIT` 内のリソース解放には `|| true` を付けて失敗を無害化する

カバレッジの最低基準: 変更箇所の挙動を再現できる回帰テストを必ず添える。

intent 別の必須テスト:

| intent | 必須テスト |
|--------|-----------|
| `intent/bugfix` | バグを再現する回帰テスト |
| `intent/feature` | エッジケーステスト |
| `intent/performance` | ベンチマーク |

📍 観点詳細: [`.claude/rules/review-observations.md`](../.claude/rules/review-observations.md)

### ドキュメント

ドキュメントは管轄を明確にし、各 SoT ファイルへの集約と相互リンクで運用する。

| SoT ファイル | 管轄 | 内容 |
|------------|------|------|
| `MVV.md` | CEO のみ編集可 | ミッション・ビジョン・バリュー |
| `docs/POLICY.md` | CLO 経由（legal-analyst は Write 権限なし） | プロジェクト全体ポリシー（本ファイル） |
| `docs/ai-organization.md` | SM | AI 組織運用方針 |
| `docs/SECURITY.md` | security-analyst（直接編集） | セキュリティ方針・脅威モデル |
| `docs/cost-analysis.md` | accounting-analyst（直接編集） | コスト分析・予算管理 |
| `docs/specification.md` | CTO（技術スタック）/ CPO（プロダクト仕様） | プロダクト仕様 |
| `docs/design-philosophy.md` | CTO | 技術設計指針 |
| `docs/screen-flow.md` | CPO | UI / 画面遷移 |
| `.claude/rules/*.md` | 全エージェント（管轄分） | 運用細則（本ファイルから委譲） |

ドキュメント運用の細則:

- **コードブロックには言語指定を付ける**
  - ` ```bash` / ` ```text` / ` ```markdown` 等を明示する
  - 📍 根拠: [`.claude/rules/markdown.md`](../.claude/rules/markdown.md)
- **コードコメントは実コードの挙動と一致させる**
  - 誤解を招くコメントはバグと同等に扱う
  - 📍 根拠: [`.claude/rules/code-comments.md`](../.claude/rules/code-comments.md)
- **管轄外ファイルの編集は禁止**
  - `role-gate.sh` フックが `docs/` 配下の書き込みを管轄エージェントに制限する
  - 管轄外の更新が必要な場合は管轄エージェントに承認を仰ぎ、管轄エージェントが代行する

## ⚖️ ライセンスポリシー

### vibecorp 本体のライセンス

vibecorp 本体は **MIT License** で配布される（Copyright (c) 2026 hirokimry）。

- LICENSE ファイルはリポジトリルート直下に配置する
- ライセンス変更は **CEO のみが決定できる**
  - CLO 経由で本セクションを更新する手順を踏む

### 第三者ランタイム依存とライセンス

vibecorp は以下の外部ツールをランタイムで利用する。
いずれも vibecorp の配布物にバイナリ・ソースを同梱しない。
ユーザー環境で別途インストールされたコマンドを子プロセス起動（exec）する形態をとる。

| ツール | ライセンス | 利用形態 | 同梱 |
|--------|-----------|---------|------|
| `bubblewrap` (bwrap) | LGPL-2.0-or-later | Linux 隔離レイヤ。`vibecorp-sandbox` から exec | なし（ユーザーが個別インストール） |
| `sandbox-exec` | Apple 提供（macOS 同梱） | macOS 隔離レイヤ。`vibecorp-sandbox` から exec | なし（macOS システムコンポーネント） |
| `gh` (GitHub CLI) | MIT | PR 作成・Issue 操作等のスキルから exec | なし |
| `jq` | MIT / (MIT OR CC0-1.0) 等 | JSON パース処理から exec | なし |
| `git` | GPL-2.0-only | バージョン管理操作から exec | なし |
| Claude Code | Anthropic 商用利用規約 | AI エージェントランタイム。ユーザーが個別契約 | なし |
| vibehawk | MIT | PR 自動レビュー（任意トグル、Issue #531）。`npx vibehawk setup` で利用者が導入。PR 差分は利用者の OAuth 経由で Anthropic に送信される。**データの取扱いは利用者の Anthropic 契約に基づき、利用者がデータ管理者となる。vibehawk・vibecorp は中継・代理を行わない**。📍 根拠: [vibehawk POLICY](https://github.com/hirokimry/vibehawk/blob/main/docs/POLICY.md)（2026-06 参照） | なし |

### vibehawk 依存の法務評価（参照時点: 2026-06-20）

vibehawk は独立 OSS であり、利用者が `npx vibehawk setup` で導入する。CLO が vibehawk の [POLICY](https://github.com/hirokimry/vibehawk/blob/main/docs/POLICY.md) / [SECURITY](https://github.com/hirokimry/vibehawk/blob/main/docs/SECURITY.md) を精査した結果、vibecorp が vibehawk に依存することは **法務上許容される**。

| 観点 | vibehawk の記述 | 評価 |
|------|----------------|------|
| データ管理者 | データ管理者（GDPR Controller）は利用者。PR 差分・メタデータは利用者の OAuth 経由で Anthropic に送信される | ✅ 本ポリシーの既存記載（利用者がデータ管理者・中継なし）と整合 |
| 中継・保存 | vibehawk 開発者は利用者リポジトリにアクセスせず、PR 内容のコピーを保持するサーバーを持たない | ✅ 中継・代理なしを確認 |
| ライセンス | vibehawk 本体 MIT、依存 claude-code-action MIT | ✅ MIT 同士で両立し、波及義務なし |
| PII | vibehawk は PII を保存・収集・第三者転送しない | ✅ 許容 |
| GitHub App 権限 | `pull-requests:write` / `issues:write` / `contents:read` のみ。`administration:write` / `secrets:write` / `workflows:write` / `id-token:write` は要求しない | ✅ 最小権限。`autonomous-restrictions.md` §6 の禁止権限を要求しない |
| Fork PR | `pull_request_target` を使用せず、Fork PR は実行対象外 | ✅ secrets 漏洩経路なし |
| 供給経路（npx 動的取得） | npm 2FA + GitHub Actions OIDC publish + provenance 署名（CISO Critical 3 条件）。利用者は `npm audit signatures` で二次防御。独立 App 設計で影響を実行者本人に限定 | ✅ 供給経路リスクは対策済み・影響限定 |

> [!NOTE]
> 観察事項: vibehawk の SECURITY.md に脆弱性報告の連絡先が明記されていない（2026-06-20 参照時点）。法務上許容の結論は揺るがないが、追従時の確認項目として記録する。

#### 🔄 追従運用（vibehawk POLICY 変更時）

vibehawk の POLICY / SECURITY は将来変更されうるため、本評価は **参照時点とセットで** 維持する。

- vibehawk の POLICY / SECURITY が変更された場合、CLO 経由で本サブセクションの 7 観点評価と参照時点を再精査・更新する。
- 更新手順は本セクション冒頭「第三者ランタイム依存とライセンス」の CLO 更新手順に従う。
- 参照時点（`参照時点: YYYY-MM-DD`）を必ず最新の精査日に書き換える。

### MIT 本体と LGPL/GPL コンポーネントの法的両立根拠

上記ツールを利用しても MIT ライセンスに LGPL・GPL の義務が波及しない。
根拠は以下の 3 点である。

- **exec による独立プロセス呼び出しはリンクに該当しない**
  - FSF 公式 GPL FAQ が明示している
  - 「独立したプログラムをパイプ・exec で呼ぶのはリンクではない」
  - Combined Work / Derivative Work の概念の外側にある
- **バイナリ非同梱・ソース非組み込みのため適用対象外**
  - LGPL-2.0+ 第4条（配布時のライセンス文書同梱義務）の適用対象外
  - GPL-2.0 第2条（配布時の完全ソース開示義務）の適用対象外
- **ユーザーが独自にインストールする外部コマンド**
  - vibecorp の配布行為はバイナリの再配布に該当しない

### 配布物への GPL/AGPL 系コード vendoring 禁止

vibecorp の配布物（templates/ 配下を含む）に GPL/AGPL 系コードを同梱することは禁止する。

| 区分 | 内容 |
|------|------|
| ❌ 禁止 | GPL/AGPL 系コードを `vendor/` / `lib/` 等に直接取り込む行為 |
| ❌ 禁止 | バイナリを配布物に同梱する行為 |
| ✅ 許容 | exec による外部コマンド呼び出し（本ポリシー「第三者ランタイム依存」の形態） |

疑義が生じた場合は CLO に諮問し、CEO が最終判断を下す。

### ライセンス変更手順

1. CEO が変更方針を決定する
2. CLO が法的影響を評価し、本セクションの更新案を起草する
3. CEO が最終承認し、LICENSE ファイルと本セクションを同時に更新する PR をマージする
