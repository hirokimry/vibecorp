---
name: worktree
description: "ワークツリーのライフサイクル管理スキル。一覧表示、マージ済みワークツリーの自動削除、手動削除を行う。「/worktree list」「/worktree clean」「/worktree remove」と言った時に使用。"
---

# ワークツリー管理

git worktree のライフサイクルを管理する。
**結果のみを簡潔に返すこと。途中経過は不要。**

## 使用方法

```bash
/worktree list
/worktree clean
/worktree remove <ブランチ名>
```

## サブコマンド

### list — ワークツリー一覧

全ワークツリーの状態を表示する。

```bash
git worktree list
```

各ワークツリーについて、対応する PR の状態（open / merged / closed）を確認する。

```bash
gh pr list --head <ブランチ名> --state all --json number,state,title --jq '.[0] | .number + " " + .state + " " + .title'
```

#### 返却フォーマット

```text
| パス | ブランチ | PR | 状態 |
|------|---------|-----|------|
| /path/to/worktree | dev/62_xxx | #123 | open |
| /path/to/worktree2 | dev/99_yyy | #456 | merged |
```

### clean — マージ済みワークツリーの自動削除

マージ済みの PR に対応するワークツリーを自動削除する。

#### ワークフロー

1. `git worktree list` で全ワークツリーを取得（メインを除く）
2. 各ワークツリーのブランチについて PR の状態を確認
3. `merged` 状態の PR に対応するワークツリーを削除対象とする
4. 削除前に未コミットの変更がないか確認する

```bash
# 未コミット変更の確認（worktree のパスで実行）
git -C <worktree_path> status --porcelain
```

5. 未コミット変更がある場合はスキップしてユーザーに報告する
6. 変更がない場合はワークツリーとローカルブランチを削除する

```bash
git worktree remove <worktree_path>
git branch -d <ブランチ名>
```

#### 返却フォーマット

```text
削除: dev/62_xxx (/path/to/worktree)
削除: dev/99_yyy (/path/to/worktree2)
スキップ: dev/100_zzz (未コミット変更あり)
---
削除: 2件, スキップ: 1件
```

### remove — 指定ワークツリーの手動削除

指定したブランチ名のワークツリーを削除する。

#### ワークフロー

1. `git worktree list` から指定ブランチのパスを特定する
2. 未コミット変更がないか確認する
3. 未コミット変更がある場合はユーザーに確認を求める
4. ワークツリーとローカルブランチを削除する

```bash
git worktree remove <worktree_path>
git branch -d <ブランチ名>
```

`-d` で削除できない場合（未マージ）はユーザーに報告して停止する。`-D` は使用しない。

#### 返却フォーマット

```text
削除: <ブランチ名> (<worktree_path>)
```

## 制約

- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- `git branch -D`（強制削除）は使用しない
- 未コミット変更があるワークツリーは自動削除しない
- メインワークツリーは削除対象から除外する
