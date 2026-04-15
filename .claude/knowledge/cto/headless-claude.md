# ヘッドレス Claude の起動・管理パターン

vibecorp では Claude Code CLI をヘッドレスプロセスとして起動し、スキルから外部制御するパターンを採用している（spike-loop スキルが初例）。

## 起動コマンド

```bash
claude -p --permission-mode dontAsk --verbose
```

| オプション | 意味 |
|-----------|------|
| `-p` | print mode（非対話・標準出力に結果を出力） |
| `--permission-mode dontAsk` | ツール呼び出しの permission をフック（hook）に委譲する。`bypassPermissions` と異なりフックが引き続き動作する |
| `--verbose` | デバッグ情報を stderr に出力。stuck 診断時に有用 |

## PID 管理パターン

`run_in_background: true` で起動した場合、Bash ツールが PID を返す。これを変数に保持して stuck 時の強制終了・クリーンアップに使う。

```bash
# 起動（バックグラウンド）
pid=$!  # run_in_background 時に利用可能

# stuck 判定後の強制終了
kill "$pid"
```

## stuck 検出パターン（command-log ベース）

command-log.sh が記録するログの最終タイムスタンプを定期ポーリングして stuck を検出する。

- ポーリング間隔: 30 秒
- stuck 判定閾値: 最終タイムスタンプから 10 分以上更新なし
- Monitor ツールによるイベント駆動監視は通知過多でコンテキストを圧迫するため採用しない

最終タイムスタンプを取得するには `awk 'END { print $1 }' "$COMMAND_LOG"` を使う（1コマンドで完結するため、パイプ連結不要）。10分（600秒）以上更新がなければ stuck と判定する。

## 注意事項

- `--permission-mode dontAsk` は `bypassPermissions` とは異なり、hook が permit/deny を制御し続ける
- `-p` モードは非対話前提。スキルのプロンプトは stdin または引数で渡す必要がある
- `--verbose` の出力は stderr に出るため、stdout と分離してキャプチャできる
- spike-loop 制約（`2>/dev/null`・`|| echo` 等のフォールバック禁止、Bash 1 コマンド 1 呼び出し）はこのスキルのサンプルコードにも適用される

## 認証方式

ヘッドレス Claude を起動する環境では、親プロセス（通常のインタラクティブ Claude Code）と同じ認証コンテキストを継承する。認証方式によって課金経路が異なるため、フルプリセット利用者には明示する必要がある。

| 認証方式 | 課金経路 | 用途 |
|---------|---------|------|
| Claude Max サブスクリプション | 月額定額 | 個人開発・通常利用 |
| `ANTHROPIC_API_KEY` | API 従量課金 | ヘッドレス大量起動・並列 spike |

- ヘッドレスプロセスは親の認証を継承するため、`ANTHROPIC_API_KEY` がセットされていれば API 経由で課金される
- spike-loop や ship-parallel のように複数のヘッドレス Claude を並列起動するスキルは、従量課金でコストが嵩む
- full プリセットを有効にする前に、利用者が想定している課金経路を把握しておくこと

## 関連する decisions.md エントリ

- 2026-04-11: ヘッドレス Claude を子プロセスとして起動し PID 管理するアーキテクチャパターンの採用（spike-loop）
- 2026-04-11: command-log ベースの stuck 検出（10分閾値）と 30 秒間隔ポーリングの採用（spike-loop）
- 2026-04-10: ship-parallel の Agent 起動に mode: "dontAsk" を指定（Issue #260）
