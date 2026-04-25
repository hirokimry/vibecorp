# worktree モード設計パターン

複数スキルが `--worktree <path>` をサポートしている。本ドキュメントでは、worktree モードの統一的な実装パターンと設計背景を明文化する。

## 概要

worktree モードは、`git worktree` で作成された独立ディレクトリ内で全操作を実行するための仕組み。主に `/vibecorp:ship-parallel` が複数 Issue を並列処理する際に使用される。

## 2つの実行パターン

worktree 内でのファイル操作は、ツールの種類に応じて2つのパターンに分かれる。

### パターン1: `cd <path> && command`（Bash コマンド用）

シェルコマンドはカレントディレクトリに依存するため、`cd` で worktree に移動してから実行する。

```bash
# git 操作
cd <path> && git status
cd <path> && git push origin HEAD

# gh 操作
cd <path> && gh pr create --title "タイトル" --body "本文"

# ファイル操作
cd <path> && cat some-file.txt
```

**選定理由:**

- `git -C <path>` は git コマンドのみ対応で、`gh` 等には使えない
- `cd && command` なら全コマンドに統一的に適用できる
- ワンライナーで完結し、状態を引きずらない

### パターン2: 絶対パス指定（Read / Write / Edit 用）

Claude Code の Read / Write / Edit ツールは CWD に依存しないため、`<path>/` を基準とした絶対パスを直接指定する。

```text
Read:  <path>/src/main.ts
Write: ~/.cache/vibecorp/plans/<repo-id>/dev_123_feature.md
Edit:  <path>/tests/test_foo.sh
```

計画ファイル（plans/）は worktree 内ではなく `~/.cache/vibecorp/plans/<repo-id>/` に配置する（#334）。`<repo-id>` は worktree パスごとに一意の値になるため、worktree 間で計画ファイルは自動的に分離される。

**選定理由:**

- Read / Write / Edit は絶対パスを受け取るツールであり、`cd` は不要
- CWD の状態に依存しないため、並列実行時にも安全

## `--worktree <path>` の引き継ぎルール

スキルチェーン（スキルが内部で別スキルを呼び出す構造）では、`--worktree <path>` を末端まで引き継ぐ。

```text
/vibecorp:ship --worktree <path>
  ├─ /vibecorp:plan-review-loop --worktree <path>
  ├─ /vibecorp:commit --worktree <path>
  ├─ /vibecorp:review-loop --worktree <path>
  │   └─ /vibecorp:review --worktree <path>
  ├─ /vibecorp:pr --worktree <path>
  └─ /vibecorp:pr-review-loop --worktree <path>
      ├─ /vibecorp:commit --worktree <path>
      └─ /vibecorp:review-to-rules --worktree <path>
```

**ルール:**

- 親スキルが `--worktree <path>` を受け取ったら、呼び出す全サブスキルに同オプションを渡す
- 未指定時は CWD で動作する（後方互換）
- 各スキルの SKILL.md に「worktree モード」セクションを記載し、パターン1・2の適用方法を明記する

## 対応スキル一覧

以下のスキルが `--worktree <path>` に対応している。

| スキル | 用途 |
|--------|------|
| `/vibecorp:ship` | Issue → PR 全自動（worktree モードの起点） |
| `/vibecorp:commit` | コミット |
| `/vibecorp:review` | レビュー実行 |
| `/vibecorp:review-loop` | レビュー → 修正ループ |
| `/vibecorp:pr` | PR 作成 |
| `/vibecorp:pr-review-loop` | PR レビュー修正ループ |
| `/vibecorp:plan-review-loop` | 計画レビューループ |
| `/vibecorp:review-to-rules` | レビュー指摘の規約反映 |
| `/vibecorp:session-harvest` | セッション知見の吸い上げ |
| `/vibecorp:harvest-all` | 全量棚卸し |
| `/vibecorp:context7` | ドキュメント取得 |
| `/vibecorp:branch` | ブランチ作成（`--worktree` で worktree 同時作成） |

## ship-parallel の手動 worktree + rsync 方式

### 背景

`/vibecorp:ship-parallel` は複数 Issue を並列に ship する。各 Agent が独立した作業ディレクトリを持つ必要がある。

### Agent の `isolation: "worktree"` を使わない理由

Claude Code の Agent ツールには `isolation: "worktree"` オプションがあるが、以下の理由で採用しなかった:

1. **TeamCreate との非互換**: `isolation: "worktree"` は TeamCreate 下で機能しない（検証済み）
2. **skills / hooks の同期が不確実**: Agent が自動作成する worktree には `.claude/` ディレクトリの内容が同期されない可能性がある

### 採用方式: 手動 worktree + rsync

オーケストレーターが事前に worktree を作成し、`.claude/` を明示的に同期する。

```bash
# プロジェクト名を取得
project=$(basename "$(pwd)")

# worktree を作成（ブランチも同時に作成）
git worktree add "../${project}.worktrees/dev_${Issue番号}_${要約}" -b "dev/${Issue番号}_${要約}"

# .claude/ ディレクトリを同期（hooks, settings.json 等）
rsync -a .claude/ "../${project}.worktrees/dev_${Issue番号}_${要約}/.claude/"

# skills/（plugin ルート）を同期
rsync -a skills/ "../${project}.worktrees/dev_${Issue番号}_${要約}/skills/"
```

**設計判断:**

| 方式 | TeamCreate 対応 | skills/hooks 同期 | SendMessage 通信 |
|------|:---:|:---:|:---:|
| `isolation: "worktree"` | 不可 | 不確実 | 不可 |
| 手動 worktree + rsync | 可 | 確実 | 可 |

### worktree 作成パス

```text
../${project}.worktrees/dev_${Issue番号}_${要約}
```

- プロジェクトルートの**親ディレクトリ**に `.worktrees/` を作成する
- プロジェクト名をプレフィックスに付けて他プロジェクトと衝突しない
- ブランチ名はスラッシュ (`/`) をアンダースコア (`_`) に変換してディレクトリ名として使用する

### Agent 起動

各 Agent は `isolation` なしで起動し、`/vibecorp:ship --worktree <path>` で全操作を worktree 内に限定する。TeamCreate + SendMessage により双方向通信が可能。

## worktree ライフサイクル管理

`/vibecorp:worktree` スキルが worktree のライフサイクルを管理する。

| サブコマンド | 機能 |
|------------|------|
| `/vibecorp:worktree list` | 全 worktree の状態を表示（PR 状態・Agent 状態を含む） |
| `/vibecorp:worktree clean` | マージ済み・孤立 worktree を自動削除 |
| `/vibecorp:worktree remove` | 指定 worktree を手動削除 |

削除の安全基準:

- **未コミット変更がある worktree は自動削除しない**
- Agent worktree は「未コミット変更なし + ベースブランチとの差分なし」の場合のみ孤立と判定し削除対象とする
- `git branch -D`（強制削除）は使用しない

## スキル実装者向けガイドライン

新しいスキルに worktree モードを追加する場合の手順:

1. SKILL.md の使用方法に `--worktree <path>` オプションを記載する
2. 「worktree モード」セクションを追加し、以下を明記する:
   - Bash コマンドは `cd <path> && command` で実行する
   - Read / Write / Edit は `<path>/` を基準にした絶対パスを使用する
   - サブスキル呼び出しには `--worktree <path>` を引き継ぐ
3. 未指定時は CWD で動作する後方互換を維持する
