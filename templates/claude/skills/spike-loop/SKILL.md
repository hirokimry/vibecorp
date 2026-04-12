---
name: spike-loop
description: "ship-parallel の E2E 検証を自動化する。コンテナ化されたヘッドレス Claude で ship-parallel を起動し、docker logs --since の無音カウンタで stuck 検出 → 診断 → 強制停止 → 再起動をループする。「/spike-loop」「並列検証」と言った時に使用。"
---

**ultrathink**

# spike-loop: ship-parallel 自動 E2E 検証

`vibecorp/claude-sandbox:dev` コンテナでヘッドレス Claude を起動して `/ship-parallel` を実行し、`docker logs --since` の無音カウンタで stuck 検出 → 診断スナップショット → 強制停止 → 分析レポートを自律的にループする。

**full プリセット専用**。ship-parallel と同じく COO エージェントが必要なため。

## 使用方法

```bash
/spike-loop <Issue URL 1> <Issue URL 2> [...]
/spike-loop --max-runs 5    # 最大5回ループ（デフォルト: 3）
```

## 前提条件

- **full プリセット** であること
- main ブランチにいること
- GitHub CLI (`gh`) が認証済みであること
- **Docker** がインストール・起動済みであること
- **`vibecorp/claude-sandbox:dev` イメージ** がビルド済みであること
  ```bash
  docker build -t vibecorp/claude-sandbox:dev docker/claude-sandbox/
  ```
- **`secrets/anthropic_api_key` ファイル** が準備されていること（詳細は `docker/claude-sandbox/README.md` 参照）

## ワークフロー

### 1. 事前チェック

```bash
awk '/^preset:[[:space:]]*/ { sub(/^preset:[[:space:]]*/, ""); print; exit }' "$CLAUDE_PROJECT_DIR/.claude/vibecorp.yml"
```

`full` 以外の場合は「full プリセット専用です」と報告して終了。

```bash
git branch --show-current
```

main でない場合は「main ブランチに切り替えてください」と報告して終了。

**コンテナ前提条件チェック**（Phase 1-2 から必須）:

```bash
command -v docker
```

```bash
docker info
```

```bash
docker image inspect vibecorp/claude-sandbox:dev
```

いずれかが失敗した場合は「Phase 1-2 ではコンテナモードが必須です。`docker build -t vibecorp/claude-sandbox:dev docker/claude-sandbox/` でビルドしてから再実行してください」と報告して終了。

### 2. ヘッドレス Claude の起動（コンテナモード）

セッション開始時に一度だけ `SESSION_ID` を生成し、`.current-session` ファイルに保存して全 run_N で共有する。Bash ツールは呼び出しごとに shell を再生成するため、`$$` ベースの prefix は使えない。

**2-1. SESSION_ID の準備**

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop"
```

```bash
ls "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/.current-session"
```

ファイルが存在しない場合のみ、次のコマンドで作成する:

```bash
date +%s > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/.current-session"
```

```bash
cat "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/.current-session"
```

取得した値を `SESSION_ID` として記録する。

**2-2. run_N ディレクトリ準備**

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1"
```

container 名は `vibecorp-spike-loop-${SESSION_ID}-${RUN_N}` 形式で組み立て、`run_N/container.id` に保存する。

```bash
date -u +%s > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/started_at"
```

```bash
echo "vibecorp-spike-loop-<SESSION_ID>-1" > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/container.id"
```

**2-3. コンテナ起動**

```bash
docker run -d --name "vibecorp-spike-loop-<SESSION_ID>-1" --init --read-only --tmpfs /tmp:rw,size=256m --tmpfs /home/claude/.cache:rw,size=256m --tmpfs /home/claude/.claude:rw,size=256m,uid=1000,gid=1000 --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --security-opt "seccomp=$CLAUDE_PROJECT_DIR/docker/claude-sandbox/seccomp.json" --security-opt no-new-privileges --memory 2g --cpus 2 --pids-limit 512 --network bridge -v "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1:/state/run:rw" --mount type=bind,source="$HOME/.gitconfig",target=/home/claude/.gitconfig,readonly --mount type=bind,source="$HOME/.config/gh",target=/home/claude/.config/gh,readonly --mount type=bind,source="$CLAUDE_PROJECT_DIR/secrets/anthropic_api_key",target=/run/secrets/anthropic_api_key,readonly vibecorp/claude-sandbox:dev claude -p --permission-mode dontAsk --verbose "/ship-parallel <Issue URL 1> <Issue URL 2>"
```

- `--init`: tini を PID 1 にして孤児プロセスを reap
- `--read-only`: rootfs を read-only にして書き込みを `/tmp` / `/state` / `/home/claude/.cache` / `/home/claude/.claude` の tmpfs と `/state/run` bind mount のみに制限
- `--tmpfs /home/claude/.claude`: claude CLI が session state を `~/.claude/` に書く可能性があるため必須
- `--cap-drop ALL` + 最小 capability: entrypoint.sh が iptables を設定するために `NET_ADMIN` / `SETUID` / `SETGID` のみ付与し、降格後は `--bounding-set=-all` で全 capability を drop
- `seccomp.json`: `ptrace` / `mount` / `unshare` / `setns` 等を deny
- `--memory 2g --cpus 2 --pids-limit 512`: resource limit
- `-v "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1:/state/run:rw"`: run_N のみ host と RW 共有
- `--mount type=bind ... readonly`: ホスト側の `.gitconfig` / `gh` 設定 / API キーを read-only 注入
- `claude -p --permission-mode dontAsk --verbose`: ヘッドレスモード、結果は stdout に出る

**`--rm` を付けない理由**: stuck 検出後に `docker logs` / `docker inspect` を取得する必要があるため。明示的に `docker rm` する。

### 3. stuck 監視ループ（`docker logs --since` 無音カウンタ方式）

`docker logs --since=30s` で直近 30 秒間の出力行数を数え、0 行が続けば無音時間としてカウントする。10 分（600 秒）連続無音で stuck と判定する。

```bash
cat "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/container.id"
```

```bash
docker inspect --format '{{.State.Status}}' "vibecorp-spike-loop-<SESSION_ID>-1"
```

`running` 以外の場合はコンテナ終了済みなので、ステップ 6（結果確認）へ。

```bash
docker logs --since=30s "vibecorp-spike-loop-<SESSION_ID>-1"
```

行数を `wc -l` で取得し、0 なら `STUCK_SECONDS` に 30 を加算、それ以外なら 0 にリセット。

```bash
sleep 30
```

`STUCK_SECONDS` が 600 以上で stuck 確定。ステップ 4 へ進む。

#### 判定ロジック

| 条件 | 判定 | アクション |
|------|------|-----------|
| 10 分間 `docker logs --since=30s` が 0 行 | stuck | ステップ 4 へ |
| `docker inspect` が `running` 以外 | 完了（成功 or 失敗） | ステップ 6 へ |

**設計判断**:

- **無音カウンタを採用した理由**: タイムスタンプ parse が不要で、BSD `date` / GNU `date` の互換性問題を回避できる。起動直後にログがまだ無い場合も自然に処理できる（最初の 600 秒は待機扱い）
- **stderr は監視対象外**: リダイレクト禁止ルールにより `2>&1` が使えない。stdout のみで判定するが、`claude -p` は結果を stdout に出すため stuck 検出には十分

#### 成功判定

各 Issue URL から Issue 番号を抽出し、`dev/{番号}` パターンのブランチで PR が存在するか確認する。

```bash
gh pr list --state open --head "dev/{番号}" --json number --jq '.[0].number'
```

全 Issue の PR が存在すれば成功。

### 4. stuck 時の診断スナップショット

stuck を検出したら、container 固有の情報を `run_N/` に保存する。

```bash
docker logs "vibecorp-spike-loop-<SESSION_ID>-1" > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/container-logs.txt"
```

```bash
docker inspect "vibecorp-spike-loop-<SESSION_ID>-1" > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/container-inspect.json"
```

```bash
docker ps -a --filter "name=vibecorp-spike-loop-<SESSION_ID>" > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/container-list.txt"
```

```bash
git worktree list --porcelain > "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/run_1/worktrees.txt"
```

### 5. 強制停止・クリーンアップ

stuck したコンテナを安全に停止し、孤立コンテナがあればまとめて削除する。**各コマンドは 1 呼び出し単位で実行し、パイプで連結しない。**

**5-1. SIGTERM → 10 秒猶予 → SIGKILL**

```bash
docker stop -t 10 "vibecorp-spike-loop-<SESSION_ID>-1"
```

**5-2. 削除（`--rm` を付けていないため明示的に）**

```bash
docker rm "vibecorp-spike-loop-<SESSION_ID>-1"
```

**5-3. 同一 SESSION_ID の孤立コンテナを検出**

```bash
docker ps -aq --filter "name=vibecorp-spike-loop-<SESSION_ID>"
```

返ってきた ID を 1 件ずつ削除する:

```bash
docker rm -f <id>
```

**設計判断**:

- **`docker stop -t 10`**: SIGTERM → 10 秒猶予 → SIGKILL。claude CLI が graceful shutdown できるチャンスを与える。`-t 0` で即 SIGKILL は避ける（tmp 書き込み中のファイルが中途半端な状態で残る可能性）
- **`-f` は孤立時のみ**: 正常フローでは stop → rm の 2 段階。`-f` は SIGKILL 相当なので、正常フローでは使わない
- **SESSION_ID ベースの filter**: 並列 spike-loop 実行時も安全。他セッションの container を誤削除しない
- **PID ベースの host 側プロセス停止は不要**: コンテナ内プロセスは `docker stop` で一括終了する。host 側の直接プロセス操作や worktree / branch 削除は spike-loop の責務外（Phase 2-1 以降で扱う）

### 6. 結果確認

コンテナが正常終了した場合（`docker inspect` が `exited` を返した場合）、成功判定を行う。

- 全 PR が作成済み → 成功（ステップ 7 へ）
- 一部の PR が未作成 → 失敗（スナップショットを取得してステップ 7 へ）

ステップ 4 と同じ手順でログ・inspect を `run_N/` に保存してから次に進む。

### 7. 分析・レポート

収集した findings を分析し、レポートを出力する。

```text
## /spike-loop 結果

### ループ {N}
- 状態: {成功 / stuck / 失敗}
- 経過時間: {分}
- container 名: {vibecorp-spike-loop-<SESSION_ID>-{N}}
- container 終了状態: {Status}
- PR 作成状況:
  - #{番号}: {作成済み / 未作成}
  - #{番号}: {作成済み / 未作成}

### stuck 分析（stuck の場合のみ）
- 無音時間: {分}
- 推定原因: {分析結果}
- スナップショット: .claude/state/spike-loop/run_{N}/

### 総合
- 実行回数: {N}/{最大}
- 成功: {回}
- stuck: {回}
- 失敗: {回}
```

成功の場合は、作成された PR の URL を一覧表示する。

### 8. 次のループ

stuck または失敗の場合、最大ループ回数に達していなければステップ 2 に戻る（`RUN_N` をインクリメントし、新しい `run_N/` ディレクトリと新しい container 名で再起動する）。

**修正の自動適用は行わない**（Phase 2 で対応予定）。分析レポートを出力し、ユーザーの判断を待つ。

### 9. 終了時のクリーンアップ

全ループ完了時（成功・最大ループ到達のいずれも）、`.current-session` を削除して次回 spike-loop 呼び出し時に新しい SESSION_ID を発行できるようにする。

```bash
rm "$CLAUDE_PROJECT_DIR/.claude/state/spike-loop/.current-session"
```

## run_N ディレクトリの成果物

| ファイル | 生成タイミング | 内容 |
|---|---|---|
| `container.id` | 起動時 | container 名 |
| `started_at` | 起動時 | Unix 秒 |
| `container-logs.txt` | stuck 時 / 終了時 | `docker logs` の全量 |
| `container-inspect.json` | stuck 時 / 終了時 | `docker inspect` の全量 |
| `container-list.txt` | stuck 時 | 同一 SESSION_ID の container 一覧 |
| `worktrees.txt` | stuck 時 | `git worktree list --porcelain`（host 側） |

spike-loop 親ディレクトリの成果物:

| ファイル | 生成タイミング | 内容 |
|---|---|---|
| `.current-session` | 初回起動時 | SESSION_ID（Unix 秒）。全 run_N で共有。loop 完了時に削除 |

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- 修正の自動適用は行わない（分析レポートの出力まで）
- 最大ループ回数のデフォルトは 3 回
- findings は `.claude/state/spike-loop/` に保存する（gitignored）
- **コンテナモード必須**: Docker 未導入環境ではホスト直接実行のフォールバックは行わない（Phase 2-3 / #270 の install.sh での Docker 必須化と整合）
- **`/state/run` 以外への書き込みは物理的に不可能**: read-only rootfs と必要最小限の tmpfs / bind mount により、コンテナ内から host の `.claude/` / `docker/` / `docs/` 等は書き換えられない
- **jq では string interpolation `\(...)` を使わない** — Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
- **Bash は 1 コマンド 1 呼び出しに分割する** — compound command は Claude Code 本体の built-in security check で止められるため（参照: #258）
