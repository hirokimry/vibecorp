# vibecorp ポリシー

> このドキュメントはプロジェクト全体のポリシーを定義する Source of Truth です。実運用の細則は `.claude/rules/` 配下と各 SOT ドキュメントに委ね、本ファイルでは大方針のみを定める。

## 開発ポリシー

### ブランチ戦略

ブランチ運用は Issue 駆動で行う（細則: [`.claude/rules/workflow.md`](../.claude/rules/workflow.md)）。

| 種別 | パターン | 例 |
|------|---------|-----|
| 通常 Issue | `dev/{Issue番号}_{要約}` | `dev/123_add_login` |
| 親エピック（feature ブランチ） | `feature/epic-{Issue番号}_{要約}` | `feature/epic-345_plan_epic_skill` |
| エピック配下の子 Issue | `dev/{Issue番号}_{要約}` | `dev/346_ship_epic_child` |

- 要約は英語スネークケース 2〜4 語
- 直接 `main`（base_branch）で作業することは `protect-branch.sh` フックで禁止
- マージ戦略は **squash merge**（GitHub auto-merge により CI パス + approve 後に自動マージ）
- 親エピック feature ブランチは `/vibecorp:plan-epic`（full プリセット）が作成し、子 Issue の PR は親 feature ブランチを base に取る

### コードレビュー

全 PR は CodeRabbit Bot レビュー必須（細則: [`.claude/rules/review-handling.md`](../.claude/rules/review-handling.md)）。

修正対象の判定は **intent ラベル × severity** の掛け合わせで行う。

| severity | 扱い |
|---------|------|
| 🔴 Critical | intent 問わず必ず対応 |
| 🟠 Major | intent 問わず必ず対応 |
| 🟡 Minor | intent の重視軸該当なら対応、外なら管轄外 |
| 🔵 Trivial | intent の重視軸該当なら対応、外なら管轄外 |
| ⚪ Info | intent の重視軸該当なら対応、外なら管轄外 |

severity 定義は CodeRabbit 公式仕様に完全準拠する（[`.claude/rules/severity/coderabbit.md`](../.claude/rules/severity/coderabbit.md)）。1 Issue 1 intent を厳守し、複数 intent にまたがる変更は Issue を分割する（PR には intent ラベルを付与しない、Issue #575 確定）。

承認基準は「CodeRabbit Bot の未解決指摘 0 件 + required CI パス」。`/vibecorp:pr-review-loop` が PR をマージまで監視し、auto-merge が GitHub 側で自動実行する。

### デプロイ

- main へのマージは PR auto-merge により実行される（手動 force push / 直接 commit は禁止）
- リリースは GitHub Release（タグ + リリースノート）で行う
- 自律改善ループ（`/vibecorp:diagnose` → `/vibecorp:autopilot` → `/vibecorp:ship-parallel`）は `.claude/rules/autonomous-restrictions.md` に列挙された **不可領域 6 分類** を CISO がフィルタリングし、人間（CEO）の明示承認が無いと自動実行されない
  - 1: 認証 / 2: 暗号 / 3: 課金構造 / 4: ガードレール / 5: MVV / 6: CI エージェント権限
- 上記不可領域に踏み込む変更は CEO 直接承認のもと、手動 Issue 起票 + `/vibecorp:ship` で実装する

## コミュニケーションポリシー

CEO への対話応答・Issue 本文・PR 本文・コミットメッセージ・監査レポートは [`communication.md`](../.claude/rules/communication.md) 規約に従う。

- **動作主語で語る**: 「このソフトウェア／このフック／このスキルが〜になった／〜できるようになった」を使う。関数名・ファイルパス・diff で喋らない
- **マークダウンと状態絵文字**: ✅（完了） / ⚠️（警告） / ❌（失敗） / 🚀（リリース） / 🔒（セキュリティ） / 🐛（バグ） / ✨（新機能） / 📖（ドキュメント） / 🔄（リファクタ） / 🧪（テスト） / 📍（根拠） / 🤖（エージェント）
- **30 秒ルール**: CEO が 30 秒読んで「何が変わるか」を掴めることを目標にする
- **intent ラベル**: Issue には `intent/*` を 1 つだけ付与する（PR には付与しない、CC prefix が機械可読保険、Issue #575 確定。細則: [`.claude/rules/intent-labels.md`](../.claude/rules/intent-labels.md)）
- **言語**: 応答・コードコメント・ログメッセージ・エラーメッセージは全て **日本語**で書く（変数名・関数名は英語可）

## 品質ポリシー

### テスト

hooks やスクリプトを追加・変更した場合は、`tests/` 配下に対応するテストを必ず追加する（細則: [`.claude/rules/testing.md`](../.claude/rules/testing.md)）。

- テストファイル命名規則: `test_*.sh`
- CI で自動実行される前提で書く
- 既存テストが壊れていないことを確認してからコミットする
- `set -euo pipefail` 下のテストでは、前提ファイル不在時に `fail` だけでなく `exit 1` で早期終了する
- `trap cleanup EXIT` 内のリソース解放コマンドには `|| true` を付けて失敗を無害化する（テスト結果に影響させない）

カバレッジは「変更箇所の挙動が再現できる回帰テストを必ず添えること」を最低基準とする。intent ラベル別の重視軸（[`.claude/rules/review-observations.md`](../.claude/rules/review-observations.md)）に従い、bugfix では再現テスト、feature ではエッジケーステスト、performance ではベンチマークを必須とする。

### ドキュメント

ドキュメントは管轄を明確にし、各 SOT ファイルへの集約と相互リンクで運用する。

| SOT ファイル | 管轄 | 内容 |
|------------|------|------|
| `MVV.md` | CEO のみ編集可 | ミッション・ビジョン・バリュー（プロダクトの根幹） |
| `docs/POLICY.md` | CLO 経由（legal-analyst は Write 権限なし） | プロジェクト全体ポリシー（本ファイル） |
| `docs/ai-organization.md` | SM | AI 組織運用方針 |
| `docs/SECURITY.md` | security-analyst（直接編集） | セキュリティ方針・脅威モデル |
| `docs/cost-analysis.md` | accounting-analyst（直接編集） | コスト分析・予算管理 |
| `docs/specification.md` | CTO（技術スタック）/ CPO（プロダクト仕様） | プロダクト仕様 |
| `docs/design-philosophy.md` | CTO | 技術設計指針 |
| `docs/screen-flow.md` | CPO | UI / 画面遷移 |
| `.claude/rules/*.md` | 全エージェント（管轄分） | 運用細則（本ファイルから委譲） |

ドキュメント運用の細則:

- **Markdown のフェンスコードブロックには必ず言語指定を付ける**: ` ```bash` / ` ```text` / ` ```markdown` 等を明示する（[`.claude/rules/markdown.md`](../.claude/rules/markdown.md)）
- **コードコメントは実コードの挙動と一致させる**: 誤解を招くコメントはバグと同等に扱う（[`.claude/rules/comments.md`](../.claude/rules/comments.md)）
- **管轄外ファイルの編集は禁止**: `role-gate.sh` フックが docs/ 配下の書き込みを管轄エージェントに制限する。管轄外の更新が必要な場合は管轄エージェントに承認を仰ぎ、管轄エージェントが代行する

## ライセンスポリシー

### vibecorp 本体のライセンス

vibecorp 本体は **MIT License** で配布される（Copyright (c) 2025 hirokimry）。

- LICENSE ファイルはリポジトリルート直下に配置される（GitHub のライセンス自動認識に対応）
- ライセンス変更は **CEO のみが決定できる**（CLO 経由で本セクションを更新する手順を踏む）

### 第三者ランタイム依存とライセンス

vibecorp は以下の外部ツールをランタイムで利用する。いずれも vibecorp の配布物にバイナリ・ソースを同梱しておらず、ユーザー環境で別途インストールされたコマンドを子プロセス起動（exec）する形態をとる。

| ツール | ライセンス | 利用形態 | 配布物への同梱 |
|--------|-----------|---------|-------------|
| `bubblewrap` (bwrap) | LGPL-2.0-or-later | Linux 隔離レイヤ。`vibecorp-sandbox` から `bwrap` を exec する | なし（ユーザーが `apt-get install bubblewrap` 等で個別インストール） |
| `sandbox-exec` | Apple 提供（macOS 同梱） | macOS 隔離レイヤ。`vibecorp-sandbox` から exec する | なし（macOS システムコンポーネント） |
| `gh` (GitHub CLI) | MIT | PR 作成・Issue 操作等のスキルから exec する | なし |
| `jq` | MIT / (MIT OR CC0-1.0) 等 | JSON パース処理から exec する | なし |
| `git` | GPL-2.0-only | バージョン管理操作から exec する | なし |
| Claude Code | Anthropic 商用利用規約 | AI エージェントランタイム。ユーザーが個別契約 | なし |

### MIT 本体と LGPL/GPL コンポーネントの法的両立根拠

vibecorp が上記ツールを利用しても MIT ライセンスに LGPL・GPL の義務が波及しない根拠は以下の通りである。

- **exec による独立プロセス呼び出し**はライブラリの「リンク」に該当しない。FSF 公式 GPL FAQ は「独立したプログラムをパイプ・exec で呼ぶのはリンクではなく、Combined Work / Derivative Work の概念の外側にある」と明示している
- **バイナリ非同梱・ソース非組み込み**のため、LGPL-2.0+ 第4条（配布時のライセンス文書同梱義務）・GPL-2.0 第2条（配布時の完全ソース開示義務）の適用対象外となる
- **ユーザーが独自にインストールする外部コマンド**であるため、vibecorp の配布行為はこれらのバイナリを再配布する行為に該当しない

### 配布物への GPL/AGPL 系コード vendoring 禁止

vibecorp の配布物（templates/ 配下を含む）に GPL-2.0 / GPL-3.0 / AGPL-3.0 系のソースコードまたはバイナリを vendoring（取り込み・同梱・再配布）することは禁止する。

- 禁止対象: GPL/AGPL 系ライセンスのコードを `vendor/` / `lib/` 等に直接取り込む行為、バイナリを配布物に同梱する行為
- 許容: exec による外部コマンド呼び出し（本ポリシーの「第三者ランタイム依存」で定義した形態）
- 疑義が生じた場合は CLO に諮問し、CEO が最終判断を下す

### ライセンス変更手順

1. CEO が変更方針を決定する
2. CLO が変更の法的影響を評価し、本セクションの更新案を起草する
3. CEO が最終承認し、LICENSE ファイルと本セクションを同時に更新する PR をマージする
