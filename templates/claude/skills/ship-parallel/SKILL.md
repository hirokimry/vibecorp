---
name: ship-parallel
description: "複数Issueを並列shipするオーケストレーションスキル。COOエージェントで並列判定し、TeamCreate + 手動worktree + Agentで同時実行する。「/ship-parallel」「並列シップ」「まとめてship」と言った時に使用。"
---

**ultrathink**

# 並列 ship オーケストレーション

複数の Issue を並列に `/ship` 実行する。**COO エージェントが Issue 群の依存関係を分析**し、その結果に基づいてスキル実行者が TeamCreate + 手動 worktree + Agent で同時進行する。

**full プリセット専用**。COO エージェントによる並列判定が必要なため、standard 以下では利用不可。

## 使用方法

```bash
/ship-parallel <Issue URL 1> <Issue URL 2> [...]
/ship-parallel --all
```

- Issue URL を複数指定: 指定された Issue のみ対象
- `--all`: open な Issue を全て取得し、COO が選別

## 前提条件

- **full プリセット** であること（COO エージェントが必要）
- ベースブランチ（Issue 本文で指定されたブランチ、未指定時は現在のブランチ）を特定できること
- GitHub CLI (`gh`) が認証済みであること
- ベースブランチが最新であること
- **Docker** がインストール・起動済みであること
- **`vibecorp/claude-sandbox:dev` イメージ** がビルド済みであること
- **`secrets/anthropic_api_key` ファイル** と **`secrets/github_token` ファイル** が準備されていること

## アーキテクチャ

**手動 worktree + docker run コンテナ** 方式を採用する。
COO は分析専任、オーケストレーションはスキル実行者が直接実行する。
各 Issue の実行はコンテナ内のヘッドレス Claude に委任し、ホスト側はコンテナの監視・クリーンアップに徹する。

```text
スキル実行者（オーケストレーター・ホスト側）
  ├─ 1. Agent(COO) で Issue 群の並列判定を取得
  │     └─ COO が依存関係を分析し、並列グループ・直列チェーン・保留を返す
  ├─ 2. 実行計画をユーザーに提示・確認
  ├─ 3. 各 Issue の worktree を事前作成（git worktree add + rsync .claude/）
  ├─ 4. 各 worktree に対して docker run でコンテナ起動（1 Issue = 1 コンテナ）
  │     └─ コンテナ内: claude -p "/ship --worktree /workspace <Issue URL>"
  ├─ 5. docker logs --since で各コンテナの stuck 監視
  │     ├─ stuck 検出 → 診断スナップショット → 強制停止
  │     └─ 正常終了 → PR 作成状況を確認
  ├─ 6. 並列 PR 間のコンフリクト検知
  └─ 7. 結果統合、レポート出力、コンテナクリーンアップ
```

### 方式選定理由

- `Agent(isolation: "worktree")` は TeamCreate 下で機能しない（#127 検証1で確定）
- 手動 worktree（`git worktree add` + `rsync .claude/`）で skills/hooks 同期が確実（#127 検証2で確定）
- `/ship --worktree <path>` でスキルチェーン全体が worktree 内で動作（#128 で実装済み）
- COO は分析専任とし、`/sync-check` 等と同じ「分析エージェント→メイン実行」パターンに統一
- **Phase 2-2 コンテナ統合**: TeamCreate + Agent + SendMessage を docker run + docker logs に置き換え。コンテナ隔離により各 Issue の実行がホストから物理的に分離される（#269）

## ワークフロー

### 1. プリセット確認

`vibecorp.yml` の `preset` を確認する。

```bash
awk '/^preset:[[:space:]]*/ { sub(/^preset:[[:space:]]*/, ""); print; exit }' .claude/vibecorp.yml
```

`full` 以外の場合は「/ship-parallel は full プリセット専用です」と報告して終了する。

### 2. コンテナ前提条件チェック

```bash
command -v docker
```

```bash
docker info
```

```bash
docker image inspect vibecorp/claude-sandbox:dev
```

いずれかが失敗した場合は「コンテナモードが必須です。`docker build -t vibecorp/claude-sandbox:dev docker/claude-sandbox/` でビルドしてから再実行してください」と報告して終了。

```bash
ls "$CLAUDE_PROJECT_DIR/secrets/anthropic_api_key"
```

```bash
ls "$CLAUDE_PROJECT_DIR/secrets/github_token"
```

いずれかが存在しない場合は「secrets ファイルが不足しています。`docker/claude-sandbox/README.md` を参照してください」と報告して終了。

### 3. Issue 一覧の取得

**URL 直接指定の場合:**

各 URL から Issue 情報を取得する。

```bash
gh issue view <Issue URL> --json number,title,body --jq '{number, title, body}'
```

**`--all` の場合:**

open な Issue を一括取得する。

```bash
gh issue list --state open --json number,title,body,labels --limit 500
```

Issue が1件以下の場合は「並列実行の対象がありません。単一 Issue には `/ship` を使用してください」と報告して終了する。

### 4. COO エージェントによる並列判定

COO エージェントを Agent ツールで起動し、Issue 群の並列実行可否を判定させる。
COO は分析結果のみを返し、オーケストレーションには関与しない。

COO エージェントが Agent ツールの利用可能タイプにない場合は、general-purpose エージェントに COO エージェント定義（`.claude/agents/coo.md`）の内容を渡して代用する。

COO に渡すプロンプト:

```text
以下の Issue 群の並列実行可否を分析してください。

## Issue 一覧
{Issue 情報のリスト}

## 分析観点
- 各 Issue の影響範囲（変更対象ファイル・モジュール）
- Issue 間の依存関係（同一ファイル変更、機能的依存）
- コンフリクトリスク

## 出力フォーマット
以下の分類で結果を返してください:
- 並列グループ: 同時実行可能な Issue の集合（複数グループ可）
- 直列チェーン: 順序制約のある Issue のリスト（依存理由付き）
- 保留: 情報不足で判定できない Issue（理由付き）
- コンフリクトリスク: 並列実行時に衝突する可能性のあるファイル
```

### 5. 実行計画の提示・ユーザー確認

COO の分析結果に基づき、スキル実行者が実行計画をユーザーに提示し、承認を求める。

```text
## 並列 ship 実行計画

### 並列グループ 1
| Issue | タイトル | 影響範囲 |
|-------|---------|---------|
| #10 | xxx | .claude/skills/foo/ |
| #11 | yyy | tests/test_bar.sh |

### 直列チェーン
| 順序 | Issue | タイトル | 依存理由 |
|------|-------|---------|---------|
| 1 | #12 | zzz | - |
| 2 | #13 | www | #12 と同一ファイル変更 |

### 保留（実行対象外）
| Issue | 理由 |
|-------|------|
| #14 | 影響範囲が不明 |

実行しますか？ (y/n)
```

ユーザーが承認しない場合は終了する。

### 6. worktree 作成・コンテナ起動

承認後、スキル実行者が worktree を事前作成し、各 Issue に対して docker run でコンテナを起動する。

#### 5a. SESSION_ID の準備

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel"
```

```bash
ls "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel/.current-session"
```

ファイルが存在しない場合のみ:

```bash
date +%s > "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel/.current-session"
```

```bash
cat "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel/.current-session"
```

取得した値を `SESSION_ID` として記録する。

#### 5b. ベースブランチの決定

Issue 本文にベースブランチの指定がある場合はそれを使用する。ない場合は現在のブランチを使用する。

#### 5c. worktree の事前作成

各 Issue に対して、オーケストレーター自身が worktree を作成する。

```bash
project=$(basename "$(pwd)")
```

```bash
git worktree add "../${project}.worktrees/dev_${Issue番号}_${要約}" -b "dev/${Issue番号}_${要約}"
```

```bash
rsync -a --exclude=state/ .claude/ "../${project}.worktrees/dev_${Issue番号}_${要約}/.claude/"
```

worktree 作成の確認:

```bash
git worktree list
```

- 期待する worktree 数（メイン + 各 Issue）と一致すること
- worktree 作成が失敗した場合は該当 Issue をスキップし、他の Issue の処理は継続する

#### 5d. 並列グループのコンテナ起動

並列グループ内の各 Issue に対して、docker run でコンテナを起動する。
**同一グループの全コンテナを順次起動する**（docker run -d はバックグラウンド実行）。

各 Issue のコンテナ起動:

```bash
docker run -d --name "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>" --init --read-only --tmpfs /tmp:rw,size=256m --tmpfs /home/claude/.cache:rw,size=256m --tmpfs /home/claude/.claude:rw,size=256m,uid=1000,gid=1000 --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --security-opt "seccomp=$CLAUDE_PROJECT_DIR/docker/claude-sandbox/seccomp.json" --security-opt no-new-privileges --memory 2g --cpus 2 --pids-limit 512 --network bridge -e GIT_DIR=/repo-git/worktrees/dev_<ISSUE_NUMBER>_<要約> -e GIT_WORK_TREE=/workspace -e VIBECORP_IN_CONTAINER=1 -v "<WORKTREE_PATH>:/workspace:rw" -v "$CLAUDE_PROJECT_DIR/.git:/repo-git:ro" --mount type=bind,source="$HOME/.gitconfig",target=/home/claude/.gitconfig,readonly --mount type=bind,source="$CLAUDE_PROJECT_DIR/secrets/anthropic_api_key",target=/run/secrets/anthropic_api_key,readonly --mount type=bind,source="$CLAUDE_PROJECT_DIR/secrets/github_token",target=/run/secrets/github_token,readonly vibecorp/claude-sandbox:dev claude -p --permission-mode dontAsk --verbose "/ship <Issue URL> --worktree /workspace"
```

- `--init`: tini を PID 1 にして孤児プロセスを reap
- `--read-only`: rootfs を read-only にして書き込みを `/tmp` / `/home/claude/.cache` / `/home/claude/.claude` の tmpfs と `/workspace` bind mount のみに制限
- `--cap-drop ALL` + 最小 capability: entrypoint.sh が iptables を設定するために `NET_ADMIN` / `SETUID` / `SETGID` のみ付与
- `GIT_DIR` / `GIT_WORK_TREE`: #268 設計に基づく 2 マウント方式で worktree を正しく解決
- `VIBECORP_IN_CONTAINER=1`: コンテナ内の `/ship` がさらにコンテナを起動しないようスキップフラグ
- `-v "<WORKTREE_PATH>:/workspace:rw"`: worktree ディレクトリを RW マウント
- `-v "$CLAUDE_PROJECT_DIR/.git:/repo-git:ro"`: git メタデータを RO マウント
- `--rm` を付けない: stuck 検出後に `docker logs` / `docker inspect` を取得する必要があるため

#### 5e. 直列チェーンの順序実行

直列チェーンがある場合、前の Issue のコンテナが完了してから次の Issue のコンテナを起動する。
`docker inspect --format '{{.State.Status}}'` で前のコンテナの完了を確認し、成功していれば次を起動する。

### 7. stuck 監視・結果収集

`docker logs --since=30s` で直近 30 秒間の出力行数を数え、0 行が続けば無音時間としてカウントする。10 分（600 秒）連続無音で stuck と判定する。

各コンテナに対して以下を繰り返す:

```bash
docker inspect --format '{{.State.Status}}' "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>"
```

`running` 以外の場合はコンテナ終了済みなので、結果確認へ。

```bash
docker logs --since=30s "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>"
```

行数を数え、0 なら無音カウンタに 30 秒加算、それ以外なら 0 にリセット。

```bash
sleep 30
```

無音カウンタが 600 以上で stuck 確定。

#### stuck 時の対応

```bash
docker logs "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>" > "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel/<ISSUE_NUMBER>/container-logs.txt"
```

```bash
docker stop -t 10 "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>"
```

```bash
docker rm "vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>"
```

#### 成功判定

各 Issue URL から Issue 番号を抽出し、`dev/{番号}` パターンのブランチで PR が存在するか確認する。

```bash
gh pr list --state open --head "dev/{番号}" --json number --jq '.[0].number'
```

### 8. 並列 PR コンフリクト検知

並列グループの全 Agent が完了した後、PR 間のコンフリクトを検知する。

```bash
# 各 PR のブランチを順にマージして衝突を検出（ドライラン）
git merge-tree $(git merge-base HEAD <branch_a>) HEAD <branch_a>
```

- コンフリクトが検出された場合、対象 PR とファイルをユーザーに報告する
- 解消方法の提案（どちらを先にマージすべきか等）を提示する
- **自動解消は行わない** — ユーザーの判断を待つ

### 9. コンテナクリーンアップ

全コンテナの処理完了後、SESSION_ID ベースで孤立コンテナを検出・削除する。

```bash
docker ps -aq --filter "name=vibecorp-ship-" --filter "name=<SESSION_ID>"
```

返ってきた ID を 1 件ずつ削除する:

```bash
docker rm -f <id>
```

SESSION_ID ファイルを削除する:

```bash
rm "$CLAUDE_PROJECT_DIR/.claude/state/ship-parallel/.current-session"
```

### 10. 結果報告

```text
## /ship-parallel 完了

### 成功
| Issue | PR | ブランチ | コンテナ |
|-------|-----|---------|---------|
| #10 | #20 | dev/10_xxx | vibecorp-ship-10-<SESSION> |
| #11 | #21 | dev/11_yyy | vibecorp-ship-11-<SESSION> |

### 失敗
| Issue | 理由 | コンテナ |
|-------|------|---------|
| #12 | テスト失敗 | vibecorp-ship-12-<SESSION> |

### stuck
| Issue | 無音時間 | スナップショット |
|-------|---------|----------------|
| #13 | 10分 | .claude/state/ship-parallel/13/ |

### 保留（未実行）
| Issue | 理由 |
|-------|------|
| #14 | 影響範囲が不明 |

### 後始末
完了した worktree は `/worktree clean` で自動削除できます。
```

## 介入ポイント

以下の状況ではユーザーに報告して判断を委ねる:

| 状況 | タイミング |
|------|-----------|
| full プリセットでない | ステップ 1 |
| Docker 未導入 | ステップ 2 |
| Issue が1件以下 | ステップ 3 |
| COO が全 Issue を保留に分類 | ステップ 4 |
| ユーザーが実行計画を承認しない | ステップ 5 |
| コンテナ内の /ship が介入ポイントに到達 | ステップ 6 |
| コンテナが stuck | ステップ 7 |
| 並列 PR 間でコンフリクト検出 | ステップ 8 |

## 制約

- **worktree 作成（`git worktree add`）が失敗した場合は該当 Issue をスキップ**し、他の Issue の処理は継続する
- `--force`、`--hard`、`--no-verify` は使用しない
- ユーザーの明示的な指示なしに force push しない
- **jq では string interpolation `\(...)` を使わない** — Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
- 介入ポイントではユーザーの指示を待つ（自動でスキップしない）
- 1つの Issue の失敗で他の並列実行を中断しない
