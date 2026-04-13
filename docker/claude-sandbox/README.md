# claude-sandbox

> **通常はスキル（`/ship`, `/ship-parallel`, `/autopilot`）が自動でコンテナを起動するため、手動での `docker run` は不要です。** 本ドキュメントはイメージの内部設計とデバッグ用の手動実行手順を記載しています。

`claude` CLI を `--dangerously-skip-permissions` 付きで安全に実行するためのコンテナイメージ定義。

- 親 Issue: [#265](https://github.com/hirokimry/vibecorp/issues/265)
- 本 Issue: [#266](https://github.com/hirokimry/vibecorp/issues/266)（Phase 1-1）
- 設計判断: `.claude/knowledge/cto/decisions.md`
- セキュリティ最低条件: `docs/SECURITY.md` の「コンテナ隔離の最低条件」セクション

## 目的

`--dangerously-skip-permissions` を伴う無人実行（`full` プリセットの spike-loop / ship-parallel / autopilot 等）をホスト環境から隔離された条件で実行する。CISO 最低条件 10 項目（docker.sock 非マウント / egress allowlist / secrets ファイル注入 / `.ssh` `.gnupg` 非マウント / GitHub token 最小スコープ / read-only FS / non-root / seccomp / resource limit / 定期更新）を全て満たすイメージとランタイム設定を提供する。

本 Phase 1-1 ではスタンドアロンで動作するベースイメージとテストスイートのみを提供する。spike-loop / ship-parallel への統合は Phase 1-2（#267）以降で行う。

## ビルド

```bash
docker build -t vibecorp/claude-sandbox:dev docker/claude-sandbox/
```

初回ビルドは 5 分以内に完了することを受け入れ基準としている（`tests/test_container_sandbox.sh` で計測）。

## 推奨起動コマンド

CISO 最低条件 1〜9 を全て満たす `docker run` の最小形。Phase 1-1 では claude CLI 起動の確認のみを目的とし、worktree / spike-loop との統合は Phase 1-2 以降で扱う。

```bash
docker run --rm \
    --init \
    --read-only \
    --tmpfs /tmp:rw,size=256m \
    --tmpfs /state:rw,size=256m,uid=1000,gid=1000 \
    --tmpfs /home/claude/.cache:rw,size=256m \
    --cap-drop ALL \
    --cap-add NET_ADMIN \
    --cap-add SETUID \
    --cap-add SETGID \
    --security-opt seccomp=./seccomp.json \
    --security-opt no-new-privileges \
    --memory 2g --cpus 2 --pids-limit 512 \
    --network bridge \
    -v "$(pwd)/workspace:/workspace:rw" \
    --mount type=bind,source="$HOME/.gitconfig",target=/home/claude/.gitconfig,readonly \
    --mount type=bind,source="$PWD/secrets/anthropic_api_key",target=/run/secrets/anthropic_api_key,readonly \
    --mount type=bind,source="$PWD/secrets/github_token",target=/run/secrets/github_token,readonly \
    vibecorp/claude-sandbox:dev \
    claude -p --permission-mode dontAsk --verbose "$@"
```

### 補足

- `--user` は指定しない。entrypoint.sh が root で iptables 設定後、`setpriv --reuid=1000 --regid=1000 --clear-groups --inh-caps=-all --bounding-set=-all` で降格する。事前に `--user 1000:1000` を指定すると iptables の OUTPUT 書き換えが行えなくなり egress allowlist が機能しないため禁止
- `CLAUDE_PROJECT_DIR` は Dockerfile の `ENV` で `/workspace` に設定済み
- `docker run` には `--secret` フラグが存在しないため、`--mount type=bind ... target=/run/secrets/...,readonly` でシークレットを注入する。`docker compose` 利用時は `secrets:` セクションを使用する（後述）
- `--network bridge` を前提とする。`--network=host` や `--network=none` では Docker 内部 DNS（`127.0.0.11:53`）前提が崩れる

### docker compose での例

`docker compose` を利用する場合のシークレット注入例:

```yaml
services:
  claude-sandbox:
    image: vibecorp/claude-sandbox:dev
    init: true
    read_only: true
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - SETUID
      - SETGID
    security_opt:
      - "seccomp=./seccomp.json"
      - "no-new-privileges"
    mem_limit: 2g
    cpus: 2
    pids_limit: 512
    tmpfs:
      - /tmp:size=256m
      - /state:size=256m,uid=1000,gid=1000
      - /home/claude/.cache:size=256m
    volumes:
      - ./workspace:/workspace:rw
      - ${HOME}/.gitconfig:/home/claude/.gitconfig:ro
    secrets:
      - anthropic_api_key
      - github_token

secrets:
  anthropic_api_key:
    file: ./secrets/anthropic_api_key
  github_token:
    file: ./secrets/github_token
```

## 禁止事項

以下の操作は CISO 最低条件に抵触する。絶対に行わないこと。

| 禁止操作 | 理由 |
|----------|------|
| `-v /var/run/docker.sock:/var/run/docker.sock` | docker.sock はコンテナエスケープの直接経路 |
| `-v $HOME/.ssh:/home/claude/.ssh` | SSH 秘密鍵の流出経路。Phase 2-1 で deploy key 方式を設計 |
| `-v $HOME/.gnupg:/home/claude/.gnupg` | GPG 秘密鍵の流出経路 |
| `-e ANTHROPIC_API_KEY=...` | env 経由は `env` コマンド 1 発で露出。必ず `/run/secrets/` ファイル注入 |
| `-e GH_TOKEN=...` | 同上 |
| `--user 1000:1000`（事前降格） | iptables 設定ができず egress allowlist が機能しない |
| `--privileged` | seccomp / capability drop を全て無効化する |
| `--network host` | ホストネットワーク名前空間に侵入、isolation 崩壊 |

## CISO 最低条件チェックリスト対応表

| # | 最低条件 | 実装 |
|---|----------|------|
| 1 | docker.sock 非マウント | 本 README で禁止を明記、テストで触らない |
| 2 | egress allowlist（`api.anthropic.com` / `api.github.com` / `github.com` のみ許可） | `entrypoint.sh` が `iptables -P OUTPUT DROP` → DNS / allowlist ホストのみ ACCEPT |
| 3 | secrets を環境変数で渡さない | `/run/secrets/anthropic_api_key` / `/run/secrets/github_token` を `--mount type=bind` で ro 注入 |
| 4 | `.ssh` / `.gnupg` 非マウント | 本 README で禁止を明記。Phase 2-1 で deploy key 方式を設計 |
| 5 | GitHub token 最小スコープ | fine-grained token で対象リポジトリ・対象操作のみに制限（運用ガイド） |
| 6 | read-only FS + 最小 overlay | `--read-only` + 必要な tmpfs（`/tmp` / `/state` / `/home/claude/.cache`）のみ |
| 7 | non-root 実行 | UID/GID 1000 の `claude` ユーザー + `setpriv` による bounding set drop |
| 8 | seccomp プロファイル | `seccomp.json` で `ptrace` / `mount` / `pivot_root` / `bpf` / `unshare` / `setns` / `reboot` / `kexec_load` / `swapon` / `swapoff` / `init_module` / `perf_event_open` を拒否 |
| 9 | resource limit | `--memory` / `--cpus` / `--pids-limit` を必須化 |
| 10 | 定期更新・脆弱性スキャン | 運用セクション参照（本 Issue スコープ外） |

## 運用

- ベースイメージ（`node:20-slim`）は定期的に `docker pull` して再ビルドする
- `@anthropic-ai/claude-code` は `@latest` で再ビルドすることで自動更新される（再現性が必要な運用ではイメージタグを固定する）
- 脆弱性スキャンは `trivy image vibecorp/claude-sandbox:dev` 等を利用（自動化は別 Issue）

## spike-loop 統合（Phase 1-2 / #267）

spike-loop スキルは Phase 1-2 でコンテナベースに移行した。

- 起動: `docker run -d --name vibecorp-spike-loop-<SESSION_ID>-<RUN_N>` でヘッドレス Claude をコンテナ起動
- stuck 検出: `docker logs --since=30s` の無音カウンタ方式（10 分間 stdout 出力なしで stuck 判定）
- 強制停止: `docker stop -t 10` + `docker rm`。孤立コンテナは SESSION_ID ベースの filter で検出・削除
- RW bind mount は `/state/run`（`.claude/state/spike-loop/run_N/`）のみ。それ以外は read-only
- 詳細は `templates/claude/skills/spike-loop/SKILL.md` を参照

## TODO

- ~~spike-loop 統合（Phase 1-2 / #267）~~ ✅ 完了
- ~~worktree ↔ コンテナマウント設計と deploy key 方式による GitHub push（Phase 2-1 / #268）~~ ✅ 完了 → `docs/design/container-worktree.md`
- 全ヘッドレス実行のコンテナ統合（Phase 2-2 / #269）
- `install.sh` 統合と `full` プリセット条件付き必須化（Phase 2-3 / #270）
- 脆弱性スキャンの自動化（別 Issue）
- Docker default seccomp profile をベースにしたより厳格なプロファイルへの移行
- CDN IP ローテーション対策としての HTTPS フォワードプロキシ（tinyproxy / squid）sidecar 方式の評価
