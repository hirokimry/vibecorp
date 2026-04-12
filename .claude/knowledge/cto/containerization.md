# コンテナ化実装ノウハウ

docker/claude-sandbox/ の実装（Issue #266）で得られた知見。
`node:*-slim` / `node:*` ベースの non-root コンテナを立てる際に参照すること。

## node:*-slim の UID 1000 衝突

`node:20-slim`（および `node:*-slim` / `node:*` 全般）には UID/GID 1000 の `node` ユーザーが既に存在する。
`useradd -m -u 1000 claude` を直接実行すると `useradd: UID 1000 is not unique` で失敗する。

対策: 既存ユーザーを削除してから作成する。

```dockerfile
RUN userdel -r node && useradd -m -u 1000 -s /bin/bash claude
```

## setpriv によるユーザー降格に必要な capability

`setpriv --reuid=1000 --regid=1000` は `CAP_SETUID` / `CAP_SETGID` を必要とする。
`--cap-drop ALL` でこれらも落とすと `setpriv` がエラーになる。

対策: `--cap-add SETUID --cap-add SETGID` を追加する。

```bash
docker run \
  --cap-drop ALL \
  --cap-add NET_ADMIN \
  --cap-add SETUID \
  --cap-add SETGID \
  ...
```

降格後に全 capability を drop するには `setpriv --bounding-set=-all` を使う。
個別指定（`-cap_net_admin,-cap_sys_admin` 等）より安全で、将来の capability 追加にも対応できる。

## docker run には --secret フラグが存在しない

Docker secrets（`--secret`）は swarm / compose 専用機能。`docker run` では使えない。

代替: bind mount で readonly マウントする。

```bash
docker run \
  --mount type=bind,source=/path/to/anthropic_api_key,target=/run/secrets/anthropic_api_key,readonly \
  ...
```

`docker compose` を使う場合は `secrets:` セクションが利用できる。

## iptables egress allowlist の CDN IP ローテーション問題

起動時に `getent ahosts` で解決した IP を iptables の ACCEPT ルールに追加する方式は、
Anthropic / GitHub が CDN（Cloudflare 等）で IP をローテーションすると通信が失敗する。

現状の対策: `--ctstate ESTABLISHED,RELATED` ルールで一度確立したセッションをフォールバックとして維持する。

将来的な解決策: HTTPS フォワードプロキシ（tinyproxy / squid）を sidecar として立て、
コンテナのデフォルトルートをプロキシに向けることで IP ローテーションを吸収できる。
Phase 2 以降で要再評価。

## 関連する decisions.md エントリ

- 2026-04-11: docker/claude-sandbox/ のリポジトリトップレベル配置判断
- 2026-04-11: seccomp プロファイルを ALLOW デフォルト + 特定 syscall denial 構成で実装
- 2026-04-12: spike-loop container integration — PID 管理からコンテナ ID 管理への移行（Issue #267 / Phase 1-2）
- 2026-04-12: docker logs --since 無音カウンタ方式の採用（Issue #267 / Phase 1-2）
- 2026-04-12: SESSION_ID ファイル永続化による孤立コンテナ検出設計（Issue #267 / Phase 1-2）
