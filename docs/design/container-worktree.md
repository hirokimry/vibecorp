# worktree ↔ コンテナマウント設計

> Phase 2-1 / Issue [#268](https://github.com/hirokimry/vibecorp/issues/268) ・ Phase 2-2 / Issue [#269](https://github.com/hirokimry/vibecorp/issues/269)
> 親 Issue: [#265](https://github.com/hirokimry/vibecorp/issues/265)

## 概要

ship-parallel は `git worktree add` でリポジトリ外にディレクトリを展開する。コンテナ内でこの worktree を正しく動作させるためのマウント設計を定義する。

Phase 2-2（#269）では全ヘッドレス実行のコンテナ統合を実施する。ship-parallel に加えて、ship 単体実行時のコンテナモードと autopilot のコンテナ化の設計も本ドキュメントに含める。

## 前提

- コンテナベースイメージ: `vibecorp/claude-sandbox:dev`（Phase 1-1 / #266）
- spike-loop のコンテナ統合済み（Phase 1-2 / #267）
- CISO 最低条件 10 項目を全て満たすこと（`docs/SECURITY.md`）
- read-only rootfs + tmpfs overlay（Phase 1-1 の既存パターン）

## 1. worktree のマウント戦略

### 問題

ホスト側の worktree 構造:

```text
/path/to/vibecorp/                          # リポジトリルート
  .git/                                     # git 本体
    worktrees/
      dev_123_feature/                      # worktree メタデータ
        HEAD, index, commondir, gitdir, ...
/path/to/vibecorp.worktrees/
  dev_123_feature/                          # worktree 作業ディレクトリ
    .git                                    # テキストファイル: "gitdir: /path/to/vibecorp/.git/worktrees/dev_123_feature"
    src/, docs/, ...
```

worktree 内の `.git` はテキストファイルで、`gitdir: <絶対パス>` でリポジトリ本体の `.git/worktrees/<name>/` を指す。この `.git/worktrees/<name>/commondir` は `../..` で `.git/` 本体を逆参照する。

コンテナに worktree だけをマウントしても、この絶対パスチェーンが切れて `git` コマンドが動作しない。

### 採用方式: 2 マウント方式

worktree 作業ディレクトリと、リポジトリの `.git/` を別々にマウントし、環境変数で git メタデータの場所を指定する。

```text
ホスト側                                    コンテナ側
─────────────────────────────────          ──────────────────────
vibecorp.worktrees/dev_123/     ──bind──→  /workspace/           (RW)
vibecorp/.git/                  ──bind──→  /repo-git/            (RO)
```

**コンテナ起動前の準備（オーケストレーター側）:**

worktree の `.git` ポインタをコンテナ内パスに書き換えるのではなく、コンテナ側で git の `GIT_DIR` / `GIT_WORK_TREE` 環境変数を設定する方式を採用する。これによりホスト側のファイルを変更せずにコンテナ内で git が正しく動作する。`GIT_DIR` が worktree メタデータディレクトリを指すと、その中の `commondir` ファイル（`../..`）により `.git/` 本体が自動解決される。

```bash
# コンテナ起動時に環境変数で git メタデータの場所を指定
docker run ... \
    -e GIT_DIR=/repo-git/worktrees/<worktree_name> \
    -e GIT_WORK_TREE=/workspace \
    -v "<worktree_path>:/workspace:rw" \
    -v "<repo_root>/.git:/repo-git:ro" \
    ...
```

ただし `GIT_DIR` を設定すると一部の git コマンド（`git worktree list` 等）の挙動が変わるため、代替として worktree 内の `.git` ファイルをコンテナ側で上書きする方式も検討した結果、**環境変数方式を採用**する。理由:

1. ホスト側ファイルの書き換えが不要（並列実行時の競合なし）
2. コンテナ終了後のクリーンアップが不要
3. `git worktree list` はコンテナ内で使用しない（ship-parallel のオーケストレーションはホスト側で行う）

### 却下した案

| 案 | 理由 |
|----|------|
| worktree だけマウント + `.git` ポインタ書き換え | ホスト側ファイルの変更が必要。並列実行で競合する |
| リポジトリルート全体をマウント | worktree がリポジトリ外にあるため解決しない |
| `git clone --shared` でコンテナ内に再作成 | 余分な I/O、ブランチ状態の同期が複雑 |

## 2. 並列 worktree の割り当て（1 Agent = 1 コンテナ）

### 方式

ship-parallel のオーケストレーターがホスト側で以下を実行する:

1. Issue ごとに worktree を作成（既存の手動 worktree + rsync 方式を踏襲）
2. 各 worktree に対して 1 コンテナを起動
3. 各コンテナ内で `/ship --worktree /workspace` を実行

```text
ホスト側オーケストレーター
├── worktree: vibecorp.worktrees/dev_101_auth/
│   └── コンテナ: vibecorp-ship-101-<SESSION>
│       └── /workspace (RW) + /repo-git (RO)
├── worktree: vibecorp.worktrees/dev_102_api/
│   └── コンテナ: vibecorp-ship-102-<SESSION>
│       └── /workspace (RW) + /repo-git (RO)
└── worktree: vibecorp.worktrees/dev_103_ui/
    └── コンテナ: vibecorp-ship-103-<SESSION>
        └── /workspace (RW) + /repo-git (RO)
```

### コンテナ命名規則

```text
vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>
```

spike-loop の `vibecorp-spike-loop-<SESSION_ID>-<RUN_N>` と同じパターンを踏襲。Issue 番号をコンテナ名に含めることで `docker ps` での識別が容易。

### 並列書き込みの安全性

- 各コンテナは独立した worktree（= 独立したファイルシステム）にマウントされるため、書き込みの競合は発生しない
- `/repo-git` は read-only マウントのため、複数コンテナからの同時参照は安全
- `git push` は HTTPS プロトコルで認証するため、ファイルレベルのロック競合なし

### 却下した案

| 案 | 理由 |
|----|------|
| 1 コンテナ内で複数 worktree | UID 1000 で全 worktree が書き込み可能になり、Agent 間の隔離が崩れる |
| コンテナ内で `git worktree add` | read-only rootfs 制約、および `.git/worktrees/` への書き込みが必要 |

## 3. `.claude/state/` の共有範囲

### 方式: worktree ローカル state

各 worktree は独立した `.claude/state/` を持つ。gate stamp ファイル（`review-ok`, `sync-ok`, `session-harvest-ok`, `review-to-rules-ok`）は worktree ごとにスコープされる。

```text
vibecorp.worktrees/dev_101_auth/.claude/state/
├── review-ok           # この worktree のレビュー完了スタンプ
├── sync-ok
├── session-harvest-ok
└── review-to-rules-ok

vibecorp.worktrees/dev_102_api/.claude/state/
├── review-ok           # 別の worktree の独立したスタンプ
└── ...
```

### rsync による初期化

worktree 作成後の rsync で `.claude/` をコピーする際、`.claude/state/` は**除外する**。各 worktree はクリーンな state から開始する。

```bash
rsync -a --exclude='state/' .claude/ "<worktree_path>/.claude/"
```

### コンテナ内でのマウント

`.claude/state/` は worktree ディレクトリの一部として `/workspace/.claude/state/` にマウントされる（worktree 全体を `/workspace` にマウントするため、追加のマウント設定は不要）。

## 4. git push の認証方式

### 採用方式: gh CLI の HTTPS token 認証（案C）

deploy key を使わず、gh CLI の fine-grained personal access token で HTTPS push する。

```bash
# コンテナ内での git push（gh CLI が credential helper として動作）
git push origin HEAD
```

gh CLI は `git` の credential helper として登録されており（`gh auth setup-git` で設定済み）、`git push` 時に自動で token を使って HTTPS 認証する。

### token scope（最小権限）

fine-grained personal access token で以下のみ許可:

| スコープ | 用途 |
|---------|------|
| Contents: Read and Write | `git push`、ファイル読み取り |
| Pull Requests: Read and Write | `gh pr create`、`gh pr merge --auto` |
| Issues: Read and Write | `gh issue view`、`gh issue edit` |

### token の注入方法

既存の CISO 最低条件に従い、`/run/secrets/github_token` への read-only bind mount で注入する（Phase 1-1 で確立済み）。

```bash
--mount type=bind,source="$PWD/secrets/github_token",target=/run/secrets/github_token,readonly
```

`entrypoint.sh` の `load_secrets()` が `/run/secrets/github_token` から `GH_TOKEN` 環境変数に展開する。

### 却下した案

| 案 | 理由 |
|----|------|
| 案A: 使い捨て deploy key | コンテナ起動ごとの鍵生成→GitHub API で登録→終了時削除の運用が複雑。GitHub API の rate limit リスクもある |
| 案B: 永続 deploy key | `/run/secrets/deploy_key` で注入可能だが、SSH agent forwarding が必要で `.ssh` マウント禁止（CISO #4）と矛盾。`GIT_SSH_COMMAND` で鍵ファイルを直接指定する方法はあるが、gh CLI の HTTPS 方式より複雑 |

### deploy key が不要な理由

gh CLI の `git credential helper` 統合により、`git push` は内部的に HTTPS + token で認証される。SSH プロトコルを使わないため deploy key 自体が不要。

## 5. gh CLI の認証引き継ぎ

### 方式: GH_TOKEN 環境変数のみ

```bash
# token は /run/secrets/ から entrypoint.sh が GH_TOKEN に展開
--mount type=bind,source="$PWD/secrets/github_token",target=/run/secrets/github_token,readonly
```

`$HOME/.config/gh` のマウントは不要。`GH_TOKEN` 環境変数のみで gh CLI は動作する（後述）。

### token refresh の問題

gh CLI は OAuth token の場合、期限切れ時に自動で refresh を試みる。read-only マウントでは `hosts.yml` への書き込みが失敗する。

**対策**: fine-grained personal access token（PAT）を使用する。PAT は有効期限内であれば refresh 不要。有効期限は最大 1 年に設定し、定期的に手動更新する。

### `GH_TOKEN` と `hosts.yml` の優先順位

gh CLI は `GH_TOKEN` 環境変数が設定されている場合、`hosts.yml` より優先する。`entrypoint.sh` が `/run/secrets/github_token` から `GH_TOKEN` を設定するため、`hosts.yml` の内容に依存しない。

したがって、`$HOME/.config/gh` のマウントは不要。`/run/secrets/github_token` からの `GH_TOKEN` 展開のみで運用する。

## ship-parallel 用 docker run コマンド例

Phase 2-2 の実装で参照する具体的な起動コマンド:

```bash
# オーケストレーターが各 worktree に対して実行
docker run -d \
    --name "vibecorp-ship-${ISSUE_NUMBER}-${SESSION_ID}" \
    --init \
    --read-only \
    --tmpfs /tmp:rw,size=256m \
    --tmpfs /home/claude/.cache:rw,size=256m \
    --tmpfs /home/claude/.claude:rw,size=256m,uid=1000,gid=1000 \
    --cap-drop ALL \
    --cap-add NET_ADMIN \
    --cap-add SETUID \
    --cap-add SETGID \
    --security-opt "seccomp=${REPO_ROOT}/docker/claude-sandbox/seccomp.json" \
    --security-opt no-new-privileges \
    --memory 2g --cpus 2 --pids-limit 512 \
    --network bridge \
    -e GIT_DIR=/repo-git/worktrees/${WORKTREE_NAME} \
    -e GIT_WORK_TREE=/workspace \
    -v "${WORKTREE_PATH}:/workspace:rw" \
    -v "${REPO_ROOT}/.git:/repo-git:ro" \
    --mount type=bind,source="${REPO_ROOT}/secrets/anthropic_api_key",target=/run/secrets/anthropic_api_key,readonly \
    --mount type=bind,source="${REPO_ROOT}/secrets/github_token",target=/run/secrets/github_token,readonly \
    vibecorp/claude-sandbox:dev \
    claude -p --permission-mode dontAsk --verbose "/ship --worktree /workspace <Issue URL>"
```

### spike-loop との差分

| 項目 | spike-loop | ship-parallel |
|------|-----------|---------------|
| コンテナ名 | `vibecorp-spike-loop-<SESSION>-<RUN>` | `vibecorp-ship-<ISSUE>-<SESSION>` |
| `/workspace` マウント元 | リポジトリルート | worktree ディレクトリ |
| `/repo-git` マウント | なし（リポジトリ直接マウント） | `.git/` を RO マウント |
| `GIT_DIR` / `GIT_WORK_TREE` | 不要（リポジトリ直接） | 必要（worktree ポインタ解決） |
| `.config/gh` マウント | 不要（`GH_TOKEN` のみ） | 不要（`GH_TOKEN` のみ） |
| 並列数 | 1（直列ループ） | N（Issue 数） |

## CISO 最低条件との整合確認

| # | 最低条件 | 本設計での対応 |
|---|---------|--------------|
| 1 | docker.sock 非マウント | マウントしない |
| 2 | egress allowlist | entrypoint.sh で設定（Phase 1-1 と同一） |
| 3 | secrets の env 渡し禁止 | `/run/secrets/` bind mount（Phase 1-1 と同一） |
| 4 | `.ssh` / `.gnupg` 非マウント | マウントしない。HTTPS + token 方式で SSH 不要 |
| 5 | GitHub token 最小スコープ | fine-grained PAT: Contents RW / PRs RW / Issues RW のみ |
| 6 | read-only rootfs | `--read-only` + 最小 tmpfs + worktree RW mount |
| 7 | non-root 実行 | entrypoint.sh の setpriv 降格（Phase 1-1 と同一） |
| 8 | seccomp | seccomp.json（Phase 1-1 と同一） |
| 9 | resource limit | `--memory 2g --cpus 2 --pids-limit 512` |
| 10 | 定期更新 | 運用ガイドに従う |

## 参考

- `docker/claude-sandbox/README.md` — ベースイメージの使用方法
- `docker/claude-sandbox/entrypoint.sh` — egress allowlist + secrets 読み込み + non-root 降格
- `docs/worktree-patterns.md` — worktree モードの設計パターン
- `docs/SECURITY.md` — CISO 最低条件
- `.claude/knowledge/cto/decisions.md` — 設計判断記録

## Phase 2-2: 全ヘッドレス実行のコンテナ統合（#269）

### ship 単体のコンテナモード

単体 `/ship` を直接呼んだ場合も、コンテナ内で実行する。

**ネスト防止設計**: `VIBECORP_IN_CONTAINER=1` 環境変数で二重起動を防ぐ。

| 条件 | 動作 |
|------|------|
| `VIBECORP_IN_CONTAINER=1` が設定済み | コンテナ起動をスキップし、通常のワークフローを実行 |
| worktree モード（`--worktree`）あり | コンテナ起動をスキップ（ship-parallel がコンテナを管理） |
| 上記以外（通常の単体 `/ship`） | ブランチ作成後、docker run でコンテナを起動して自身を再実行 |

worktree モードでない通常起動時は、リポジトリルート（`$CLAUDE_PROJECT_DIR`）を `/workspace:rw` にマウントし、`VIBECORP_IN_CONTAINER=1` を渡してコンテナを起動する。コンテナ内の `/ship` が同じフラグを検出してスキップするため、再帰的なコンテナ起動は発生しない。

コンテナ命名規則: `vibecorp-ship-<ISSUE_NUMBER>-<SESSION_ID>`（ship-parallel と同じパターン）

### autopilot のコンテナ化設計

autopilot のメインループ自体をコンテナ内で実行する。ship と同じ `VIBECORP_IN_CONTAINER=1` によるネスト防止パターンを踏襲する。

コンテナ命名規則: `vibecorp-autopilot-<SESSION_ID>`

`/workspace:rw` にリポジトリルートをマウントし、コンテナ内でそのまま `/autopilot --auto` を再実行する。コンテナ内では `VIBECORP_IN_CONTAINER=1` が設定済みのため、コンテナ起動ステップをスキップして診断・ship フローに進む。

### 各スキルのコンテナ起動方式まとめ

| スキル | コンテナ名パターン | `/workspace` マウント元 | `GIT_DIR` / `GIT_WORK_TREE` | ネスト防止 |
|--------|-----------------|------------------------|-------------------------------|----------|
| spike-loop | `vibecorp-spike-loop-<SESSION>-<RUN>` | リポジトリルート | 不要 | なし（直列ループ） |
| ship（単体） | `vibecorp-ship-<ISSUE>-<SESSION>` | リポジトリルート | 不要 | `VIBECORP_IN_CONTAINER=1` |
| ship-parallel | `vibecorp-ship-<ISSUE>-<SESSION>` | worktree ディレクトリ | 必要（2マウント方式） | `VIBECORP_IN_CONTAINER=1` |
| autopilot | `vibecorp-autopilot-<SESSION>` | リポジトリルート | 不要 | `VIBECORP_IN_CONTAINER=1` |
