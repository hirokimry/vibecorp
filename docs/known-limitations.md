# 既知制限

vibecorp の既知の動作上の制約事項をまとめる。設計上の妥協点や、外部要因により回避困難な制限を記録する。

## protect-branch.sh の Bash 検出は cwd 依存

### 概要

`protect-branch.sh` は Edit/Write については `tool_input.file_path` から worktree を判定するが、Bash ツールは `tool_input.command` に対象ファイルパスを含まないため、worktree を確実に推定できない。Bash 経路では従来通り cwd 基準（`git -C "."`）でブランチを判定する。

### 影響

teammate（並列 ship の Agent）が `/ship --worktree <path>` で起動された worktree 内で **素の `git commit` を直接呼んだ場合**、フックは main repo の cwd を見て `base_branch`（main 等）と判定し、コミットを deny する可能性がある。

### 識別方法

deny メッセージの `permissionDecisionReason` に `[tool=Bash, check_dir=.]` が含まれていれば、本制限による deny と判別できる。

```text
main ブランチでは直接作業できません。フィーチャーブランチを作成してください。 [tool=Bash, check_dir=.]
```

### 回避策

worktree 内で git コマンドを実行する場合は cwd を明示する:

```bash
# OK: cd で worktree に入ってから commit
cd /path/to/worktree && git commit -m "..."

# OK: git -C で worktree を指定
git -C /path/to/worktree commit -m "..."

# NG: 素の git commit（cwd が main repo のままだと deny される）
git commit -m "..."
```

`/commit` スキルは内部で `cd <path> && git commit` 形式を使うため、スキル経由なら本制限の影響を受けない（`rules/use-skills.md` でスキル経由が推奨されている理由の一つ）。

### 解消の方向性（将来）

`tool_input.command` 内の `git -C <path>` パターンや、`cd <path> && ...` パターンから worktree を抽出して判定するロジックを追加すれば本制限を解消できる。ただし以下の課題があるため別 Issue として後続化する:

- shell パースの複雑性（quote / escape / heredoc 等）
- 複数 cd を含む compound command の扱い
- 偽陽性・偽陰性のバランス

### 関連

- Issue #296（本制限を生んだ修正）
- Issue #258（teammate Bash compound command 制限）
- `.claude/hooks/protect-branch.sh` ヘッダーコメント
