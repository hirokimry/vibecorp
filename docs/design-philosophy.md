# vibecorp 設計思想

## vibecorp とは

vibecorp は「AIエージェントを組織化してプロダクト開発を回す」仕組みをプラグインとして提供する。
バイブコーディング時代の AI企業キット。どのリポジトリにも導入できる。

## 3層アーキテクチャ

```
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

- **CLI実行型**: CodeRabbit CLI、flutter analyze 等 → スキル内で `Agent(model: haiku)` として起動
- **タスク実行型**: 計画に基づくコード修正 → スキル内で `Agent(model: sonnet, tools制限)` として起動
- **判断するがアイデンティティ不要**: レビュー妥当性判定、修正計画 → スキル内で `Agent(model: opus)` として起動

### 判断フローチャート

```
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

## プラグイン配布方式: gitignore展開（node_modulesパターン）

```
導入先リポジトリ:
├── .claude/vibecorp/    ← プラグイン実体（.gitignore対象、git管理外）
├── .claude/vibecorp.yml ← プロジェクト設定（git管理）
├── .claude/vibecorp.lock← バージョン固定（git管理）
├── .claude/rules/       ← 共通ルール（git管理）
├── .claude/settings.json← フック設定（git管理、マージ管理）
├── CLAUDE.md            ← プロジェクト指示（git管理）
└── MVV.md               ← 最上位方針（git管理）
```

設計上の重要な判断:
- プラグイン実体はgit管理外 → 導入先リポジトリが汚れない
- lockfile でバージョン固定 → チーム全員が同じバージョンを使える
- settings.json はマージ管理 → vibecorp由来フック（パスに `vibecorp/hooks/` を含む）のみ操作、ユーザー独自フックは保持
- vibecorp リポジトリ自体は **Public前提** で設計（テンプレートのみ、実データなし）

## 3つの組織規模プリセット

| プリセット | agents | skills | hooks | ユースケース |
|---|---|---|---|---|
| **minimal** | なし | /review, /review-to-rules, /pr-merge-loop, /pr-review-fix, /pr, /commit | protect-files, review-to-rules-gate | 個人〜小規模 |
| **standard** | CTO, CPO | +/review-loop, /sync-check | +sync-gate | チーム開発 |
| **full** | C-suite全員 + 分析員 | +/sync-edit | +role-gate | AI企業・コンプライアンス重視 |

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
