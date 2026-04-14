# ヘッドレス Claude の起動・管理パターン

vibecorp では Claude Code CLI をコンテナ化されたヘッドレスプロセスとして起動し、スキルから外部制御するパターンを採用している（spike-loop スキルが初例）。

## 起動コマンド

```bash
claude -p --permission-mode dontAsk --verbose
```

| オプション | 意味 |
|-----------|------|
| `-p` | print mode（非対話・標準出力に結果を出力） |
| `--permission-mode dontAsk` | ツール呼び出しの permission をフック（hook）に委譲する。`bypassPermissions` と異なりフックが引き続き動作する |
| `--verbose` | デバッグ情報を stderr に出力。stuck 診断時に有用 |

## コンテナ版起動パターン（Phase 1-2 以降）

`vibecorp/claude-sandbox:dev` コンテナで起動し、SESSION_ID + container.id ファイルで管理する。

```bash
docker run -d \
    --name "vibecorp-spike-loop-${SESSION_ID}-${RUN_N}" \
    --init --read-only \
    --tmpfs /tmp:rw,size=256m \
    --tmpfs /home/claude/.cache:rw,size=256m \
    --tmpfs /home/claude/.claude:rw,size=256m,uid=1000,gid=1000 \
    --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID \
    --security-opt "seccomp=docker/claude-sandbox/seccomp.json" \
    --security-opt no-new-privileges \
    --memory 2g --cpus 2 --pids-limit 512 \
    -v "$RUN_DIR:/state/run:rw" \
    vibecorp/claude-sandbox:dev \
    claude -p --permission-mode dontAsk --verbose "/ship-parallel ..."
```

### SESSION_ID ファイル永続化

Bash ツールは呼び出しごとに shell を再生成するため、`$$` ベースの prefix は使えない。セッション開始時に `.current-session` ファイルに epoch を保存し、全 run_N で共有する。

```bash
SPIKE_STATE_DIR="$CLAUDE_PROJECT_DIR/.claude/state/spike-loop"
SESSION_FILE="$SPIKE_STATE_DIR/.current-session"
test -f "$SESSION_FILE" || date +%s > "$SESSION_FILE"
SESSION_ID=$(cat "$SESSION_FILE")
```

container 名は `vibecorp-spike-loop-${SESSION_ID}-${RUN_N}` で一意化。

### container.id ファイルからの参照

stuck 検出・kill 等の後続コマンドは必ず `cat "$RUN_DIR/container.id"` で container 名を取得する。

## stuck 検出パターン（`docker logs --since` 無音カウンタ方式）

`docker logs --since=30s` で直近 30 秒間の stdout 行数を数え、0 行が続けば無音としてカウントする。

- ポーリング間隔: 30 秒
- stuck 判定閾値: 10 分（600 秒）連続無音
- Monitor ツールによるイベント駆動監視は通知過多でコンテキストを圧迫するため採用しない

```bash
docker logs --since=30s "$CONTAINER_NAME" | wc -l
```

**設計判断**: タイムスタンプ parse が不要で、BSD `date` / GNU `date` の互換性問題を回避できる。起動直後にログがまだ無い場合も自然に処理できる（最初の 600 秒は待機扱い）。

### 強制停止

```bash
docker stop -t 10 "$CONTAINER_NAME"
docker rm "$CONTAINER_NAME"
```

SIGTERM → 10 秒猶予 → SIGKILL。孤立コンテナは SESSION_ID ベースの filter で検出・削除する。

## 注意事項

- `--permission-mode dontAsk` は `bypassPermissions` とは異なり、hook が permit/deny を制御し続ける
- `-p` モードは非対話前提。スキルのプロンプトは stdin または引数で渡す必要がある
- `--verbose` の出力は stderr に出るため、stdout と分離してキャプチャできる
- spike-loop 制約（`2>/dev/null`・`|| echo` 等のフォールバック禁止、Bash 1 コマンド 1 呼び出し）はこのスキルのサンプルコードにも適用される
- `/home/claude/.claude` tmpfs は `claude -p` 実行時に必要（session state 書き込み先）

## 関連する decisions.md エントリ

- 2026-04-12: spike-loop container integration（PID → container ID、docker logs --since 無音カウンタ、SESSION_ID 設計、host 直接実行モード削除）
- 2026-04-11: ヘッドレス Claude を子プロセスとして起動し PID 管理するアーキテクチャパターンの採用（spike-loop）— Phase 1-2 でコンテナ版に置換
- 2026-04-11: command-log ベースの stuck 検出（10分閾値）と 30 秒間隔ポーリングの採用（spike-loop）— Phase 1-2 で docker logs --since 方式に置換
- 2026-04-10: ship-parallel の Agent 起動に mode: "dontAsk" を指定（Issue #260）

## コンテナ環境での認証アーキテクチャ

### Claude Code CLI の認証方式

Claude Code CLI には2種類の認証方式がある。

| 方式 | 保存場所 | `--bare` / `-p` モードで利用可能 |
|------|---------|-------------------------------|
| OAuth トークン | macOS: `~/Library/Application Support/Claude/config.json` の `oauth:tokenCache` キー | 不可 |
| API キー | `ANTHROPIC_API_KEY` 環境変数または `apiKeyHelper` スクリプト | 可 |

### `--bare` モード・非対話モードの制約

`-p`（print mode）や `--permission-mode dontAsk` などの非対話モードでは OAuth フローが動作しない。そのため：

- OAuth トークンや keychain は読まれない
- `ANTHROPIC_API_KEY` 環境変数または `apiKeyHelper` の設定が必須

### Linux コンテナでの認証

Linux コンテナ環境では `~/Library/Application Support/` パスが存在しない。XDG 規約（`~/.config/`）に従うとしても、Claude Code CLI がそのパスを認識する保証はない。

**結論**: コンテナ環境での唯一の公式手段は `ANTHROPIC_API_KEY` のファイル注入。

```bash
# 推奨: シークレットファイルを tmpfs にマウントし、コンテナ起動時に環境変数として渡す
docker run \
    --tmpfs /run/secrets:rw,mode=0700 \
    -e ANTHROPIC_API_KEY="$(cat /path/to/secret)" \
    ...
```

OAuth トークンの mount による共有は CLI アップストリームの対応待ち。現時点では採用しない。

### `gh auth token` 自動取得 revert の経緯（2026-04-14）

install.sh に `gh auth token` で GitHub トークンを自動取得する処理を追加したが、以下の理由で revert した：

- コンテナ内で `gh auth login` が完了している前提を置いてしまう（install.sh の責務外）
- install.sh は環境セットアップ手順を明示的に記述する場であり、暗黙の依存を持ち込むべきでない
- 認証トークンの自動取得はセキュリティ上の懸念がある（CISO 評価待ち）
