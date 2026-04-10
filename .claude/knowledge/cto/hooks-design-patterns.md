# フック設計パターン

vibecorp のフックに共通する設計パターンと注意点を記録する。

## コマンド正規化の統一パターン

ゲート系フック（sync-gate, review-to-rules-gate, session-harvest-gate）は以下の正規化処理を共有する:

1. 先頭空白の除去
2. 環境変数プレフィックス（`KEY=VALUE ...`）の除去（sed）
3. ラッパーコマンド（`env`, `command`）のループ除去
4. 絶対パス / 相対パスの `basename` 正規化
5. 先頭 N トークンの抽出・比較

この処理を省略すると `ENV_VAR=val git push` や `/usr/bin/git push` でバイパスされる。

### 注意: block-api-bypass.sh との実装差異

`block-api-bypass.sh` は Bash の正規表現（`=~`）でプレフィックス除去を行い、`env`/`command` の除去は `${var#pattern}` で行っている。他のフックとは正規化手法が異なるが、検出対象が `gh api` のサブ文字列マッチ（grep -qE）であるため、実質的に問題は発生していない。

新しいフックを追加する場合は、ゲート系フックの正規化パターン（sed + awk 方式）に統一すること。

## スタンプファイルの設計

ゲート系フックはステートファイル（`$CLAUDE_PROJECT_DIR/.claude/state/{gate名}-ok`）で状態管理する:

- ステートの生成元: 対応するスキル（例: `/sync-check` が `$CLAUDE_PROJECT_DIR/.claude/state/sync-ok` を生成）
- ステートの消費: ゲートフックがファイルの存在を確認し、確認後に `rm -f` で即座に削除する
- **ワンタイム性**: 1回の push / merge につき1回のスキル実行を強制する設計。ステートを使い回せない
- **worktree 分離**: `CLAUDE_PROJECT_DIR` が worktree ごとに異なるため、ブランチ単位で自動的に state が分離される
- **書き込み前の `mkdir -p`**: state ディレクトリが存在しない可能性があるため、生成側（スキル / `command-log.sh`）は `mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"` を必ず実施する
- **ship-parallel との連携**: worktree 作成時の `rsync` で `--exclude=state/` を指定し、main の state を持ち込まない

## team-auto-approve.sh の判定ロジック

Claude Code の Agent Teams でチームメイトの承認プロンプトを抑制するフック。ホワイトリスト方式で安全なツールコールのみ `permissionDecision: "allow"` を返す。

重要な注意点:

- `"allow"` を使うこと。`"approve"` は deprecated で Write/Edit に効かない
- allow は「入口を開ける」だけであり、他のフックの deny が優先される
- 未知のコマンド・ツールには何も返さない（通常の承認プロンプトに委ねる）

### Bash コマンドの多段検証（セグメント分割）

Bash コマンドは3段階で検証する:

1. **サブシェル/コマンド置換のブロック**: `$()` またはバッククォートを含む場合は即スキップ。ホワイトリスト外のコマンドを任意実行されるリスクを排除する
2. **パイプ/OR のブロック**: `|` または `||` を含む場合は即スキップ。パイプで安全リストのコマンドを迂回する攻撃パターンを防ぐ
3. **セグメント分割検証**: `&&` と `;` でコマンドを分割し、`is_safe_segment()` で全セグメントを個別検証する。1つでも安全でないセグメントがあれば全体をスキップする

`is_safe_segment()` 関数は各セグメントに対して環境変数プレフィックス除去・ラッパーコマンド除去・basename 正規化を行い、危険コマンド・危険フラグ・安全リストの順に判定する。

### 危険フラグの管理

危険フラグのリスト: `--force`, `--hard`, `-rf`, `-fr`, `--no-verify`, `--delete`, `--rsh`

`--rsh` は rsync の `--rsh=COMMAND` オプションで任意コマンドを実行できるため追加。新しいフラグを追加する際は `is_safe_segment()` の grep パターンを更新する。

## protect-branch.sh の設計

メインブランチでの直接作業をブロックする PreToolUse フック。

### 検出対象

- **Edit / Write**: ツール名で判定し即 deny
- **Bash**: `git commit` を含むコマンドを deny。`&&`, `||`, `;` で連結されたコマンドも各セグメントに分割して検査

### コマンド正規化

Bash コマンドの判定には sync-gate.sh と同じ正規化パターンを適用する:

1. 環境変数プレフィックスの除去
2. ラッパーコマンド（env, command）の除去
3. 絶対パス/相対パスを basename に正規化
4. 先頭2トークン（例: `git commit`）で比較

### ブランチ取得

`vibecorp.yml` の `base_branch` を awk で抽出する。未設定時は `main` にフォールバック。`git branch --show-current` が空（detached HEAD 等）の場合はブロックしない。

### settings.json 登録

Bash マッチャーと Edit|Write マッチャーの両方に登録する。マッチャーを分けることで Edit/Write フックの入力形式に依存せず確実に検出できる。

## command-log.sh の設計（判定不要型フック）

ゲート系フックと異なり、判定を返さず純粋にコマンドをログ記録するオブザーバブルフック。

### 早期リターンパターン

Bash ツール以外のマッチャーには対応不要なため、ツール種別を確認して即 exit 0 する:

```bash
tool_name=$(echo "$CLAUDE_TOOL_NAME" | tr '[:upper:]' '[:lower:]')
if [ "$tool_name" != "bash" ]; then
  exit 0
fi
```

判定（permissionDecision）を出力しないまま exit 0 すると、Claude Code はそのフックを「通過」として扱い、他のフックの判定に委ねる。

### ログファイルのパス命名規則

ログファイルは `$CLAUDE_PROJECT_DIR/.claude/state/command-log` に出力する:

- `$CLAUDE_PROJECT_DIR` 配下に置くことで worktree ごとに自動分離される（同じプロジェクトの別 worktree でログが混在しない）
- `.claude/state/` は `.gitignore` 対象なのでログがコミット対象にならない
- プロジェクト名をパスに含める必要がないため、命名規則のサニタイズも不要
- 書き込み前に `mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"` で state ディレクトリを確実に作成する

### /approve-audit スキルとの連携

`/approve-audit` スキルがログを読み取り、allow リストへの追加要否を棚卸しする。フック自体はログ記録のみを担い、allow リスト更新の判断をスキルに委譲することで責務を分離している。

## Claude Code built-in security check の限界

Claude Code 本体は hook とは独立した built-in security check を持つ。hook で `permissionDecision: "allow"` を返しても、built-in check が阻止するケースがある。

確認された例:

```text
Compound command contains cd with output redirection - manual approval required to prevent path resolution bypass
```

`cd ... && cmd > /dev/null` のような複合コマンド（cd + リダイレクト）に対して Claude Code が自動でダイアログを出す。この check は hook の後段で動いており、hook 側で override する方法は存在しない。

**対策**: hook でのカバーに限界があるケースは、teammate への指示（SKILL.md のプロンプト等）で「そのようなコマンドを生成しないよう」制約するのが唯一の実用的な対応。具体的には「`&&` で複数コマンドを繋ぐ場合は個別の Bash ツール呼び出しに分割する」旨を SKILL.md に明記する。

## hook デバッグ: fired.log による発火確認

「hook は登録されているが permission ダイアログが出続ける」問題の切り分けには、一時的なログ行を hook の冒頭に仕込む方法が有効。

```bash
{
  echo "$(date '+%Y-%m-%dT%H:%M:%S') TOOL=$TOOL_NAME PID=$$ PPID=$PPID CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-unset}"
} >> /tmp/team-auto-approve-fired.log 2>&1
```

このログが書き出されていれば「hook は発火しているが allow を返していない」。ログが書き出されていなければ「hook が発火していない（設定登録の問題 or マッチャーのミス）」と切り分けできる。デバッグ完了後は必ずログ行を削除すること。
