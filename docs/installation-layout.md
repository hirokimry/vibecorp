# 📦 インストール後ディレクトリ構造

> [!IMPORTANT]
> このドキュメントは `install.sh` 実行後に **導入先リポジトリにどんな構造が生まれるか** を示す Source of Truth である。
> 配置されるファイル・配置条件・プリセット別の差分はここに集約する。
> `README.md` には概要のみ残し、詳細は本ドキュメントを参照する。

## 👥 読者像

このドキュメントは以下の読者向け。

- 🛠️ **利用者**: `install.sh` を実行した結果、自分のリポジトリにどのファイルが配置されるかを把握したい人

「何が・どこに・どんな条件で」配置されるかを動作主語で記述する。

## 🏛️ 全体構造

```text
your-project/
├── .claude-plugin/
│   └── plugin.json        # Plugin メタデータ
├── .claude/
│   ├── hooks/             # フック（ファイル保護・ゲート制御）
│   ├── agents/            # エージェント（standard 以上）
│   ├── knowledge/         # 役割別の判断基準・判断記録（standard 以上）
│   ├── rules/             # コーディング規約
│   ├── vibecorp.yml       # プロジェクト設定
│   ├── vibecorp.lock      # バージョン固定 + マニフェスト
│   ├── settings.json      # フック設定
│   └── CLAUDE.md          # プロジェクト指示
├── docs/                  # 仕様書・設計ドキュメント群
│   ├── POLICY.md
│   ├── SECURITY.md
│   ├── ai-organization.md
│   ├── cost-analysis.md
│   ├── design-philosophy.md
│   ├── specification.md
│   ├── team-permissions.md
│   ├── ai-review-dependency.md
│   ├── conventional-commits.md
│   └── file-placement.md
├── .github/
│   ├── ISSUE_TEMPLATE/    # Issue テンプレート
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── config.yml
│   └── workflows/
│       ├── test.yml                       # CI ワークフロー
│       ├── ai-review.yml                  # AI レビューワークフロー（claude_action.enabled: true 時のみ）
│       ├── ai-review-golden-test.yml      # AI レビュー golden test（claude_action.enabled: true 時のみ）
│       └── close-on-feature-merge.yml     # feature/epic-* マージ時の Issue 自動 close（full プリセット限定 / opt-in）
├── REVIEW.md              # AI レビュープロンプト（claude_action.enabled: true 時のみ）
├── .coderabbit.yaml       # CodeRabbit 設定
└── MVV.md                 # Mission / Vision / Values
```

## 🗃️ マニフェストとマージ管理

| ファイル | 役割 |
|---|---|
| `.claude/vibecorp.lock` | vibecorp が管理するファイルを追跡するマニフェスト |
| `.claude/settings.json` | マージ管理：vibecorp 由来フックのみ操作し、ユーザー独自フックは保持 |

## 🧱 .claude/ 配下の責務

| ディレクトリ | 役割 | プリセット |
|---|---|---|
| 🪝 `hooks/` | ファイル保護・ゲート制御・API バイパス防止・ログ | minimal 以上 |
| 🤖 `agents/` | C-suite / 分析員 / 計画レビュー専門家 | standard 以上 |
| 🧠 `knowledge/` | 役割別の判断基準・判断記録（運用中に蓄積） | standard 以上 |
| 📜 `rules/` | コーディング規約（intent ラベル / severity / shell パターン 等） | minimal 以上 |
| 🛠️ `lib/` | シェル共通関数（`common.sh` / `knowledge_buffer.sh` 等） | minimal 以上 |

## 📚 docs/ の構成

vibecorp が配布する `docs/` は以下の責務を持つ。

| ファイル | 主な内容 |
|---|---|
| `specification.md` | プリセット仕様・SKIP 性マトリクス・skill / hook / agent 一覧の SoT |
| `configuration.md` | `vibecorp.yml` 全設定キーの詳細 |
| `installation-layout.md` | 本ドキュメント（インストール後の構造） |
| `ai-organization.md` | 組織思想・C\*O ゲート・エージェント一覧 |
| `ai-review-auth.md` | claude-code-action 用の OAuth 認証 + PAT セットアップ |
| `ai-review-dependency.md` | AI レビューの依存設計 |
| `ai-review-rollback.md` | AI レビューのロールバック手順 |
| `cost-analysis.md` | 課金構造の詳細（**編集不可・参照のみ**） |
| `design-philosophy.md` | 設計思想 |
| `conventional-commits.md` | CC prefix 厳格定義 + intent ラベル対応表 |
| `file-placement.md` | ファイル配置設計 |
| `POLICY.md` / `SECURITY.md` | コスト管理ポリシー / セキュリティポリシー |
| `preset-addition-checklist.md` | 新プリセット追加時のチェックリスト |
| `team-permissions.md` | Agent Teams の permissions 設計 |
| `worktree-patterns.md` | git worktree 利用パターン |
| `migration-decisions-index.md` | C\*O 判断記録の目次設計 |
| `migration-knowledge-buffer.md` | knowledge/buffer worktree 設計 |
| `known-limitations.md` | 既知の制約 |

## 🤖 .github/workflows/ の構成

| ワークフロー | 配置条件 | 役割 |
|---|---|---|
| `test.yml` | ✅ 常時 | macOS / Ubuntu でのテスト実行 |
| `ai-review.yml` | ⚙️ `claude_action.enabled: true` 時のみ | claude-code-action による AI レビュー |
| `ai-review-golden-test.yml` | ⚙️ `claude_action.enabled: true` 時のみ | claude-code-action のレビュー品質リグレッション検知 |
| `close-on-feature-merge.yml` | 🏢 full プリセット + opt-in | エピック feature ブランチマージ時の子 Issue 自動 close |

## 🧠 knowledge ディレクトリ構造

standard 以上のプリセットでインストールされる。

エージェントが運用中に判断記録を蓄積する場所。

`--update` でも削除されない。

```text
.claude/knowledge/
├── accounting/
│   └── cost-principles.md     # コスト管理ポリシー
├── sm/
│   ├── decisions-index.md     # プロセス判断の目次
│   ├── decisions/             # 四半期アーカイブ（関連時のみ読む）
│   └── organization.md        # 組織運営ナレッジ
├── cpo/
│   ├── decisions-index.md     # プロダクト判断の目次
│   ├── decisions/             # 四半期アーカイブ
│   └── product-principles.md  # プロダクト方針
├── cto/
│   ├── decisions-index.md     # 技術判断の目次
│   ├── decisions/             # 四半期アーカイブ
│   └── tech-principles.md     # 技術方針
├── cfo/
│   ├── decisions-index.md     # コスト判断の目次
│   └── decisions/             # 四半期アーカイブ
├── ciso/
│   ├── decisions-index.md     # セキュリティ判断の目次
│   └── decisions/             # 四半期アーカイブ
├── legal/
│   └── legal-principles.md    # 法務方針
└── security/
    └── security-principles.md # セキュリティ方針
```

C\*O / SM は全員 `decisions-index.md`（目次）+ `decisions/YYYY-QN.md`（四半期アーカイブ）の 2 段構成で判断を記録する。

詳細は [`docs/migration-decisions-index.md`](migration-decisions-index.md) を参照。

`.claude/knowledge/{role}/decisions/` および `{role}/audit-log/` への作業ブランチ直書きは、Edit/Write 層 + Bash 層の 2 つの `PreToolUse` hook で deny される。

書込みは `knowledge/buffer` worktree 経由のみ許可。

詳細は [`docs/SECURITY.md`](SECURITY.md) を参照。

## 🗄️ XDG cache（.claude/ 配下に置かない揮発データ）

スタンプ・state・plans は Claude Code の書込確認プロンプトを回避するため、リポジトリ外の XDG cache に配置される。

| 種類 | パス |
|---|---|
| ゲートスタンプ・state | `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/` |
| 計画ファイル | `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/plans/<repo-id>/` |

`<repo-id>` は sanitized basename + sha256 先頭 8 桁で生成され、リポジトリ単位で分離される。

## 🔗 関連

- 設定リファレンス: [`docs/configuration.md`](configuration.md)
- 仕様 SoT: [`docs/specification.md`](specification.md)
- 組織思想: [`docs/ai-organization.md`](ai-organization.md)
