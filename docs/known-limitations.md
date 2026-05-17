# ⚠️ 既知制限

> [!IMPORTANT]
> 読者像は vibecorp を運用する利用者と開発者。
> 本ドキュメントは設計上の妥協点や、外部要因により回避困難な制限をまとめる。
> 各制限には「何が起きるか」「どう避けるか」「将来どう解消するか」を整理する。

## 1️⃣ protect-branch.sh の Bash 検出は cwd 依存

### 📚 概要

`protect-branch.sh` のフックには次の制約がある。

- ✅ Edit/Write は `tool_input.file_path` から worktree を判定できる。
- ❌ Bash は `tool_input.command` に対象ファイルパスを含まない。
  - → worktree を確実に推定できない。
- 🔁 Bash 経路では従来通り cwd 基準（`git -C "."`）でブランチを判定する。

### 💥 影響

teammate（並列 ship の Agent）が worktree 内で **素の `git commit` を直接呼んだ場合**に発生する。

- 起動条件: `/vibecorp:ship --worktree <path>`。
- フックは main repo の cwd を見て `base_branch`（main 等）と判定する。
- → コミットを deny する可能性がある。

### 🔍 識別方法

deny メッセージで判別する。

- `permissionDecisionReason` に `tool=Bash` が含まれていれば、本制限による deny と判別できる。
- `check_dir=.` は cwd 基準判定であることの補助情報。

```text
main ブランチでは直接作業できません。フィーチャーブランチを作成してください。 [tool=Bash, check_dir=.]
```

`tool=Edit` / `tool=Write` の場合は対象外。

- 理由: `tool_input.file_path` から worktree を判定しているため。

### 🛠️ 回避策

worktree 内で git コマンドを実行する場合は **必ず cwd を worktree に切り替える**。

```bash
# OK: cd で worktree に入ってから commit
cd /path/to/worktree && git commit -m "..."

# NG: 素の git commit（cwd が main repo のままだと deny される）
git commit -m "..."

# NG: git -C <worktree> commit も同様に deny される
#     （Bash 経路では tool_input.command から worktree を推定できず、
#      CHECK_DIR="." のまま cwd 基準で判定されるため）
git -C /path/to/worktree commit -m "..."
```

`/vibecorp:commit` スキルは内部で `cd <path> && git commit` 形式を使う。

- ✅ スキル経由なら本制限の影響を受けない。
- 📚 `rules/use-skills.md` でスキル経由が推奨されている理由の一つ。

### 🔮 解消の方向性（将来）

`tool_input.command` から worktree を抽出するロジックを追加すれば本制限を解消できる。

抽出対象のパターン例:

- `git -C <path>` パターン。
- `cd <path> && ...` パターン。

> [!WARNING]
> ただし以下の課題があるため別 Issue として後続化する。
>
> - shell パースの複雑性（quote / escape / heredoc 等）。
> - 複数 cd を含む compound command の扱い。
> - 偽陽性・偽陰性のバランス。

### 🔗 関連

- Issue #296（本制限を生んだ修正）。
- Issue #258（teammate Bash compound command 制限）。
- 参照ファイル: `.claude/hooks/protect-branch.sh` ヘッダーコメント。
