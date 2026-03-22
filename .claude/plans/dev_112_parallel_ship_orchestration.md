# 実装計画: 並列 ship オーケストレーションスキル (#112)

## 概要

複数の Issue URL を受け取り、COO エージェントで並列実行可否を判定した後、
並列可能な Issue 群を worktree ベースで同時に `/ship` 実行するスキル。

## 影響範囲

| 操作 | ファイル |
|------|---------|
| 新規 | `.claude/skills/ship-parallel/SKILL.md` |
| 新規 | `tests/test_ship_parallel.sh` |

既存ファイルへの変更なし。新規スキルの追加のみ。

## 設計

### スキル名・使用方法

```bash
/ship-parallel <Issue URL 1> <Issue URL 2> [...]
/ship-parallel --all    # open Issue を全て対象（COO が選別）
```

### ワークフロー

```text
1. Issue 一覧の取得
   ├── URL 直接指定 → そのまま使用
   └── --all → gh issue list で open Issue 取得

2. COO 分析（Agent ツール経由）
   ├── 並列グループ → 3 へ
   ├── 直列チェーン → 順序付きで 3 へ
   └── 保留 → ユーザーに報告

3. 実行計画の提示・ユーザー確認
   └── 承認後 → 4 へ

4. 並列グループの同時実行
   ├── 各 Issue に対して worktree を作成（/branch --worktree 相当）
   ├── Agent ツール（run_in_background）で /ship を並列起動
   └── 完了通知を待つ

5. 直列チェーンの順序実行
   └── 前の Issue の PR 作成完了後に次を開始

6. 結果集約・報告
```

### 既存スキルとの関係

- `/ship`: 単一 Issue の実行エンジン（変更なし）
- `/branch --worktree`: worktree 作成に使用（変更なし）
- COO エージェント: 並列判定に使用（変更なし）
- `/worktree clean`: 完了後の後始末に使用（変更なし）

### SKILL.md の設計ポイント

1. **ユーザー確認ポイント**: COO 分析結果を提示し、実行前に承認を求める
2. **Agent 起動**: 各 worktree で `/ship` を実行する Agent を `run_in_background` で起動
3. **直列チェーン**: 並列グループ内の直列チェーンは順序を守る
4. **エラーハンドリング**: 1つの Issue が失敗しても他は継続。最終報告で失敗を明示
5. **worktree クリーンアップ**: 完了後に `/worktree clean` を案内

## Phase

### Phase 1: SKILL.md 作成

`.claude/skills/ship-parallel/SKILL.md` を作成する。

内容:
- frontmatter（name, description）
- 使用方法
- ワークフロー（6ステップ）
- 介入ポイント
- 結果報告フォーマット
- 制約

テスト: SKILL.md が正しい frontmatter を持ち、マークダウンとして構文エラーがないこと

### Phase 2: テスト作成

`tests/test_ship_parallel.sh` を作成する。

テスト項目:
- SKILL.md が存在し、必須フィールド（name, description）を含む
- frontmatter の name が "ship-parallel" であること
- ワークフローセクションが存在すること
- 制約セクションが存在すること

## 懸念事項

- COO エージェントが Agent ツールの利用可能タイプに未登録（general-purpose で代用する設計にする）
- #107 の検証結果に基づき、TeamCreate + Agent isolation: "worktree" 方式を採用（Agent worktree 内で /ship を含む全スキルが動作することが実機検証済み）
- Agent worktree のブランチ名は自動命名（worktree-agent-{id}）のため、PR 作成前に dev/{Issue番号}_{要約} にリネームが必要
