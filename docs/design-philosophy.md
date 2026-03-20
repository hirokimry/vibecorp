# vibecorp 設計思想

## vibecorp とは

vibecorp は「AIエージェントを組織化してプロダクト開発を回す」仕組みをプラグインとして提供する。
バイブコーディング時代の AI企業キット。どのリポジトリにも導入できる。

## 3層アーキテクチャ

```text
MVV.md（最上位方針・ファウンダーのみ編集）
  ↓ 全エージェント・スキルの判断基準
docs/（Source of Truth・仕様書群）
  ↓ エージェントが参照・更新する設計情報
.claude/（実行層）
  ├── agents/    ← Role Agents のみ（判断 + knowledge蓄積する者）
  ├── skills/    ← ワークフロー定義（内部でAgent起動しモデル/ツール制御）
  ├── hooks/     ← ゲート制御（ファイル保護 + ワークフロー強制）
  ├── knowledge/ ← 役割別の判断基準・判断記録（運用中に蓄積）
  ├── rules/     ← 全エージェント共通のコーディング規約
  └── settings.json ← フック設定
```

## agents vs skills の設計原則

### agents に定義するもの（Role Agents）

持続的アイデンティティ + 自律判断 + knowledge蓄積を持つエンティティ:

- **C-suite**: CTO, CPO, COO, CFO, CLO, CISO -- MVVに基づいて判断する専門家
- **チーム分析員**: accounting, legal, security -- 3回独立実行し、C-suiteがレビュー

特徴:
- 持続的なアイデンティティがある（「私はCTOです」）
- 自律的に判断し、`knowledge/{role}/decisions.md` に蓄積する
- 他エージェントと権限境界がある（管轄ファイルが異なる）

### skills 内のステップにするもの

アイデンティティや持続的な知識蓄積が不要なタスク実行:

- **CLI実行型**: CodeRabbit CLI、カスタムレビューコマンド等
- **タスク実行型**: 計画に基づくコード修正
- **判断するがアイデンティティ不要**: レビュー妥当性判定、修正計画策定（共通基準は `.claude/rules/review-criteria.md` に定義）

いずれもスキル内のステップとして直接実行する。

### 判断フローチャート

```text
そのエンティティは...

1. 持続的なアイデンティティがある？（「私はCTOです」）
   → No → スキル内のステップ
   → Yes ↓

2. 自律的に判断し、knowledge に蓄積する？
   → No → スキル内のステップ（Agent起動時に model/tools を指定）
   → Yes ↓

3. 他エージェントと権限境界がある？
   → Yes → agents/ に定義する
```

## プラグイン配布方式: Claude Code 規約パスへの直接配置

```text
導入先リポジトリ:
├── .claude/
│   ├── hooks/           ← フック（ファイル保護等）
│   ├── skills/          ← スキル（Claude Code の /コマンド）
│   ├── rules/           ← コーディング規約
│   ├── vibecorp.yml     ← プロジェクト設定
│   ├── vibecorp.lock    ← バージョン固定 + マニフェスト
│   ├── settings.json    ← フック設定（マージ管理）
│   └── CLAUDE.md        ← プロジェクト指示
└── MVV.md               ← 最上位方針
```

設計上の重要な判断:

- **独自名前空間を持たない**
  `.claude/vibecorp/` のような独自ディレクトリは作らない。全ファイルを Claude Code の規約パス（`.claude/hooks/`, `.claude/skills/`, `.claude/rules/`）に直接配置する。Claude Code が認識しないパスにファイルを置くことは、プラグインとして意味がない

- **lock をマニフェストとして使う**
  `vibecorp.lock` に vibecorp が管理するファイルの一覧を記録する。lock に載っている = vibecorp 管理、載っていない = ユーザー作成。更新時は lock を参照して vibecorp 管理ファイルのみ差し替える

- **.gitignore の判断はユーザーに委ねる**
  vibecorp は `.gitignore` を操作しない。`.claude` を gitignore するか git 管理するかは導入先プロジェクトの判断。生成物を一括 gitignore する案（node_modules パターン）は却下した。vibecorp の生成物は rules, skills, CLAUDE.md 等のチームがレビュー・カスタマイズする人間可読な設定であり、node_modules のような第三者コードとは性質が異なる。PR でのレビューを可能にするため、git 管理を推奨する

- **settings.json はマージ管理**
  vibecorp 由来フック（パスに `.claude/hooks/` を含む）のみ操作し、ユーザー独自フックは保持

- **Public 前提**
  vibecorp リポジトリ自体はテンプレートのみで実データを含まない公開前提の設計

### 生成物をフックで保護しない理由

vibecorp が生成した skills, rules, hooks を protect-files フックで保護する案は却下した。

- **生成物はユーザーのもの**
  プラグインが生成したファイルであっても、ユーザーが自由に編集できるべき。npm が `node_modules/` を保護しないのと同じ原則
- **復元は再実行で可能**
  ユーザーが誤って壊しても `install.sh` を再実行すれば元に戻る
- **保護はビジネスルールに限定**
  protect-files が守るのは MVV.md のような「ファウンダーの方針」であり、「vibecorp が生成したから」という理由でファイルを保護するのはプラグインの越権行為

## 3つの組織規模プリセット

| プリセット | agents | hooks | ユースケース |
|---|---|---|---|
| **minimal** | なし | protect-files | 個人〜小規模 |
| **standard** | CTO, CPO | + review-to-rules-gate, sync-gate | チーム開発 |
| **full** | C-suite全員 + 分析員 | + role-gate | AI企業・コンプライアンス重視 |

各プリセットに含まれるスキル:

- **minimal**: /review, /review-loop, /pr-merge-loop, /pr-review-fix, /pr, /commit
- **standard**: 上記 + /review-to-rules, /sync-check
- **full**: 上記 + /sync-edit

## フック設計パターン

### ファイル保護型

- **protect-files.sh**: 保護ファイルの編集をブロック（`protected_files` で設定可能）
- **role-gate.sh**: エージェントの役割に応じたファイル編集権限制御（full のみ）

### ワークフローゲート型

- **review-to-rules-gate.sh**: `gh pr merge` 前に `/review-to-rules` 完了を強制
- **sync-gate.sh**: `git push` 前に `/sync-check` 完了を強制（standard 以上）

いずれもスタンプファイル（`/tmp/.{project}-*`）で状態管理。

## スキル設計原則

### プリセット自己完結の原則

各プリセットに含まれるスキルは、そのプリセット内で完結しなければならない。
スキルが参照するコマンド・スキルは、同じプリセットに必ず存在すること。

- NG: minimal の `/pr-merge-loop` が standard にしかない `/pr-review-fix` を呼ぶ
- OK: minimal の `/pr-merge-loop` が minimal の `/pr-review-fix` を呼ぶ

### 拡張ポイントの設計

ユーザー設定（vibecorp.yml）による拡張は許容するが、**デフォルトで動作する**ことが前提。
拡張ポイントはデフォルト空で、ユーザーが意図的に追加した場合にのみ動作する。

- `review.custom_commands`: デフォルト空。ユーザーが追加すれば `/review` 内で並列実行される
- スキルは `custom_commands` が空でも CodeRabbit CLI のみで正常に動作する

## ガードレール

- **Public Ready**: セキュリティ情報・特定プロダクト名・ローカルパス依存の混入禁止
- **品質基準**: 参照元の実装を全網羅し、品質・汎用性・堅牢性で上回る
- **テスト必須**: hooks / install.sh は自動テスト付き。テストなしで push しない
