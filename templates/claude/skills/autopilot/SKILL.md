---
name: autopilot
description: "diagnose→ship の自律改善ループを1回実行する。Issue がなければ diagnose で起票し、あれば ship-parallel で実装する。「/autopilot」「自律改善」と言った時に使用。"
---

**ultrathink**

# 自律改善

`/diagnose` → `/ship-parallel` のサイクルを1回実行する。
定期実行は `/loop 12h /autopilot` で行う。

## 使用方法

```bash
/autopilot              # ship 前にユーザー確認（デフォルト）
/autopilot --auto       # 確認なしで全自動
/loop 12h /autopilot    # 12時間ごとに定期実行（確認あり）
```

## 前提条件

- **full プリセット専用**（`/diagnose` と `/ship-parallel` が必要）
- main ブランチにいること
- **Docker** がインストール・起動済みであること
- **`vibecorp/claude-sandbox:dev` イメージ** がビルド済みであること
- **`secrets/anthropic_api_key` ファイル** と **`secrets/github_token` ファイル** が準備されていること

## ワークフロー

### 1. プリセット確認

```bash
awk '/^preset:[[:space:]]*/ { sub(/^preset:[[:space:]]*/, ""); print; exit }' .claude/vibecorp.yml
```

`full` 以外の場合は「/autopilot は full プリセット専用です」と報告して終了。

### 2. ブランチ確認

```bash
git branch --show-current
```

main でない場合は「main ブランチに切り替えてください」と報告して終了。

### 3. コンテナ前提条件チェック

```bash
command -v docker
```

```bash
docker info
```

```bash
docker image inspect vibecorp/claude-sandbox:dev
```

```bash
ls "$CLAUDE_PROJECT_DIR/secrets/anthropic_api_key"
```

```bash
ls "$CLAUDE_PROJECT_DIR/secrets/github_token"
```

いずれかが失敗した場合は「コンテナモードが必須です。`docker build -t vibecorp/claude-sandbox:dev docker/claude-sandbox/` でビルドしてから再実行してください」と報告して終了。

### 4. コンテナ起動

autopilot のメインループ自体をコンテナ内で実行する。`VIBECORP_IN_CONTAINER=1` が設定されている場合はコンテナ起動をスキップし、そのまま診断・ship フローに進む。

```bash
date +%s
```

取得した値を `SESSION_ID` として使用する。

```bash
docker run -d --name "vibecorp-autopilot-<SESSION_ID>" --init --read-only --tmpfs /tmp:rw,size=256m --tmpfs /home/claude/.cache:rw,size=256m --tmpfs /home/claude/.claude:rw,size=256m,uid=1000,gid=1000 --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --security-opt "seccomp=$CLAUDE_PROJECT_DIR/docker/claude-sandbox/seccomp.json" --security-opt no-new-privileges --memory 2g --cpus 2 --pids-limit 512 --network bridge -e VIBECORP_IN_CONTAINER=1 -v "$CLAUDE_PROJECT_DIR:/workspace:rw" --mount type=bind,source="$HOME/.gitconfig",target=/home/claude/.gitconfig,readonly --mount type=bind,source="$CLAUDE_PROJECT_DIR/secrets/anthropic_api_key",target=/run/secrets/anthropic_api_key,readonly --mount type=bind,source="$CLAUDE_PROJECT_DIR/secrets/github_token",target=/run/secrets/github_token,readonly vibecorp/claude-sandbox:dev claude -p --permission-mode dontAsk --verbose "/autopilot --auto"
```

コンテナ命名規則: `vibecorp-autopilot-<SESSION_ID>`

コンテナ起動後は `docker logs --since=30s` で監視し、完了またはstuck（10分無音）を検出する。stuck 時は `docker stop -t 10` + `docker rm` で停止し、ユーザーに報告する。正常完了時はコンテナを `docker rm` で削除する。

### 5. open な diagnose Issue を確認

```bash
gh issue list --label "diagnose" --state open --json number,title --jq '.[] | "#" + (.number | tostring) + ": " + .title'
```

### 6. Issue がない場合 → diagnose 実行

open な diagnose Issue が0件の場合、`/diagnose` を実行して Issue を起票する。
起票後、そのままステップ5に進む（起票した Issue を ship する）。

### 7. COO による並列判定

COO エージェントに Issue 群の並列実行可否を判定させる（`/ship-parallel` のステップ3と同じ）。

COO の分析結果に基づき、並列グループ・直列チェーン・保留に分類する。
保留と判定された Issue は候補から除外する。

### 8. ship 確認・実行

#### 6a. デフォルト（確認あり）

COO の分析結果と候補一覧をユーザーに提示する:

```text
## /autopilot 改善候補

| # | Issue | タイトル |
|---|-------|---------|
| 1 | #218 | block-api-bypass.sh の専用テスト |
| 2 | #219 | install.sh の lock ファイル空リスト |

ship する Issue の番号を指定してください（例: 1,2）。
全て ship: all / スキップ: skip
```

AskUserQuestion でユーザーの選択を取得する。

- `skip` → 「スキップしました」で終了
- 番号指定 or `all` → 選択された Issue を `/ship-parallel` で実行

#### 6b. `--auto` モード

ユーザー確認なしで、全 diagnose Issue を `/ship-parallel` に渡す。

### 9. 結果報告

```text
## /autopilot 完了

- diagnose Issue: {n}件
- ship 実行: {n}件
- スキップ: {n}件
```

## 制約

- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する（[根拠](docs/design-philosophy.md#jq-string-interpolation-の禁止)）
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
- デフォルトでは ship 前にユーザー確認を挟む（`--auto` で解除可能）
