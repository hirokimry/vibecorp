# ファイル配置ポリシー

vibecorp が管理・生成するファイルの配置場所と役割を定義する。

## vibecorp リポジトリの構造

vibecorp 自体（テンプレート配布元）のディレクトリ構成:

```text
vibecorp/
├── install.sh              ← インストーラ
├── MVV.md                  ← vibecorp 自身の最上位方針
├── README.md               ← プロジェクト概要（英語）
├── docs/                   ← 設計ドキュメント（日本語）
├── templates/              ← 導入先に配置するテンプレート群
│   ├── CLAUDE.md.tpl
│   ├── MVV.md.tpl
│   ├── settings.json.tpl
│   └── claude/
│       ├── hooks/          ← フックテンプレート
│       ├── rules/          ← ルールテンプレート
│       └── skills/         ← スキルテンプレート
├── tests/                  ← 自動テスト
└── .claude/                ← vibecorp 開発用の実行層
    ├── hooks/
    ├── skills/
    ├── rules/
    └── plans/
```

## 導入先リポジトリの構造

`install.sh` 実行後に導入先に生成される構成:

```text
導入先リポジトリ/
├── MVV.md                  ← 最上位方針（ファウンダーのみ編集）
├── .claude/
│   ├── CLAUDE.md           ← プロジェクト指示
│   ├── vibecorp.yml        ← プロジェクト設定
│   ├── vibecorp.lock       ← マニフェスト（管理ファイル一覧）
│   ├── settings.json       ← フック設定（マージ管理）
│   ├── hooks/              ← ゲート制御
│   ├── skills/             ← ワークフロー定義
│   ├── rules/              ← コーディング規約
│   ├── agents/             ← Role Agents（standard 以上）
│   └── knowledge/          ← 役割別判断記録（standard 以上）
└── (ユーザーのプロジェクトファイル)
```

この構成は [3層アーキテクチャ](design-philosophy.md#3層アーキテクチャ) に対応する:

| 層 | ファイル | 役割 |
|---|---|---|
| 方針層 | `MVV.md` | 全判断の最上位基準 |
| 設計層 | `docs/` | 仕様・設計の Source of Truth |
| 実行層 | `.claude/` | エージェント・スキル・フックの定義 |

## 各ディレクトリの役割と配置基準

### `docs/` — 設計ドキュメント

vibecorp の設計思想・仕様・ポリシーを記述する場所。

- 配置するもの: 設計思想、仕様書、ポリシー文書
- 言語: 日本語（`.md`）。英語版が必要な場合は `.en.md` をバリアントとして追加
- エージェントが参照・更新する Source of Truth

### `templates/` — テンプレート群

`install.sh` が導入先にコピーするファイルの原本。

- 配置するもの: `.tpl` ファイル（プレースホルダー付き）、hooks・skills・rules の原本
- `templates/claude/` 配下は導入先の `.claude/` にそのまま配置される
- プレースホルダー: `{{PROJECT_NAME}}`, `{{PRESET}}`, `{{LANGUAGE}}`

### `.claude/skills/` — ワークフロー定義

Claude Code の `/コマンド` として実行されるスキル。

- 配置するもの: `SKILL.md` ファイル（1スキル1ディレクトリ）
- 配置基準: アイデンティティや持続的知識蓄積が不要なタスク実行
- プリセット自己完結: スキルが参照するコマンドは同じプリセット内に存在すること

### `.claude/hooks/` — ゲート制御

Claude Code のイベントフックとして実行されるシェルスクリプト。

- 配置するもの: `.sh` ファイル
- 2つのパターン:
  - **ファイル保護型**: protect-files.sh（保護ファイルの編集ブロック）
  - **ワークフローゲート型**: review-to-rules-gate.sh（マージ前の完了確認強制）
- `settings.json` でイベントとの紐付けを定義

### `.claude/agents/` — Role Agents

持続的アイデンティティ・自律判断・knowledge蓄積を持つエージェント。

- 配置するもの: エージェント定義ファイル
- 配置基準: [agents vs skills の判断フローチャート](design-philosophy.md#判断フローチャート) に従う
- standard 以上のプリセットで使用

### `.claude/knowledge/` — 役割別判断記録

エージェントが運用中に蓄積する判断基準・判断記録。

- 配置するもの: `{role}/decisions.md` 等の判断記録
- 運用中にエージェントが自動的に更新する
- standard 以上のプリセットで使用

### `.claude/rules/` — コーディング規約

全エージェント共通のコーディング規約。

- 配置するもの: `.md` ファイル（1規約1ファイル）
- Claude Code が自動的に読み込み、全エージェントに適用される
- レビュー指摘から抽出された共通パターンも蓄積先

### `.claude/plans/` — 実装計画

Issue 対応時の実装計画ファイル。

- 配置するもの: `{ブランチ名}.md` 形式の計画ファイル
- Issue 駆動ワークフローの設計フェーズで生成
- PR マージ後も設計記録として保持

### `tests/` — 自動テスト

hooks・install.sh 等のシェルスクリプトの自動テスト。

- 配置するもの: `test_*.sh` の命名規則に従うテストファイル
- CI で自動実行される前提
- 新しい hook やスクリプトを追加したら、対応するテストを同時に追加すること

### ルートファイル

| ファイル | 配置場所 | 役割 |
|---|---|---|
| `MVV.md` | リポジトリルート | 最上位方針。ファウンダーのみ編集可 |
| `CLAUDE.md` | `.claude/` | プロジェクト指示。回答言語・rules 参照を定義 |
| `vibecorp.yml` | `.claude/` | プロジェクト設定（名前・プリセット・言語等） |
| `vibecorp.lock` | `.claude/` | マニフェスト。vibecorp 管理ファイルの一覧を記録 |
| `settings.json` | `.claude/` | フック設定。vibecorp 由来フックとユーザー独自フックをマージ管理 |

## 配置してはいけないもの

以下は vibecorp のどのディレクトリにも配置してはならない。

### 独自名前空間

`.claude/vibecorp/` のような独自ディレクトリは作らない。全ファイルを Claude Code の規約パス（`.claude/hooks/`, `.claude/skills/`, `.claude/rules/`）に直接配置する。Claude Code が認識しないパスにファイルを置くことは、プラグインとして意味がない。

### シークレット・認証情報

シークレット、トークン、APIキー、パスワードを絶対にコミットしない。`.env` ファイルや credentials もコミット対象外。git history に残ることも許容しない。

### 特定プロダクト名・ローカルパス依存

- 特定の別リポジトリやプロダクト名を直接記載しない
- 特定マシンのパスをハードコードしない（`/Users/xxx/` 等）
- 汎用的な表現（「導入先プロジェクト」「対象リポジトリ」等）を使う
- 環境変数で吸収する場合はデフォルト値を持たせるか、未設定時に明確なエラーを出す
