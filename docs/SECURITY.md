# vibecorp セキュリティポリシー

> このドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth です。

## セキュリティ方針

（セキュリティに関する基本方針を記載）

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

（認証方式・認可モデルの概要を記載）

## データ保護

### 機密情報の取り扱い

- シークレット・APIキー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する
- コンテナ環境では `/run/secrets/` への read-only bind mount 方式でシークレットを注入する。`docker run -e` による環境変数渡しは禁止する（`docker run --mount type=bind,source=./secrets/anthropic_api_key,target=/run/secrets/anthropic_api_key,readonly` を使用する）
- `install.sh --preset full` を実行すると、`secrets/anthropic_api_key` と `secrets/github_token` が自動生成される。優先順位は「環境変数（`ANTHROPIC_API_KEY` / `GH_TOKEN` / `GITHUB_TOKEN`）→ 対話入力 → エラー終了」。ファイルが既存の場合はスキップされる。生成されたファイルには `chmod 600` が適用される

### 個人情報

（個人情報の取り扱い方針を記載）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）

## コンテナ隔離の最低条件

`--dangerously-skip-permissions` を伴う無人実行（`full` プリセットの spike-loop / ship-parallel / autopilot 等）は以下の最低条件を全て満たしたコンテナ環境で実行しなければならない（MUST）。1 項目でも欠ける場合は NO-GO とする。

1. **docker.sock を非マウント**: `/var/run/docker.sock` のマウントは絶対禁止（コンテナエスケープの直接経路になる）
2. **egress allowlist**: `api.anthropic.com` / `api.github.com` / `github.com` のみ許可し、それ以外への外部通信を遮断する
3. **secrets の環境変数渡し禁止**: GitHub token / Anthropic API key は Docker secrets または `/run/secrets/` への読み取り専用 bind mount で注入する。`docker run -e ANTHROPIC_API_KEY=...` のような host 側からの env 渡しは禁止
4. **.ssh / .gnupg の非マウント**: `~/.ssh` および `~/.gnupg` はマウントしない。必要な場合は操作専用の使い捨て deploy key を用いる
5. **GitHub token の最小スコープ**: fine-grained token で対象リポジトリ・対象操作のみに制限する
6. **read-only rootfs**: `--read-only` を有効化し、書き込み可能領域は `/workspace`（bind mount）/ `/state`（tmpfs）/ `/tmp`（tmpfs）/ `/home/$USER/.cache`（tmpfs）に限定する
7. **非 root 実行**: init 完了後のワークロードプロセスは UID 0 で実行しない。entrypoint は起動直後に root で iptables allowlist 設定等の特権セットアップを行った上で、`setpriv --reuid=1000 --regid=1000 --clear-groups --inh-caps=-all --bounding-set=-all` により UID 1000 へ降格し、capability bounding set 全体を drop する（降格後の NET_ADMIN / SETUID / SETGID 等の再取得を物理的に不可能にする）。`--user 1000:1000` による事前降格は iptables 設定不可となり egress allowlist が機能しないため禁止する
   - **最小 capability セット**: `--cap-drop ALL` を基本とし、起動時の特権セットアップに必要な `NET_ADMIN`（iptables egress allowlist 設定）/ `SETUID` / `SETGID`（`setpriv` によるユーザー降格）のみを `--cap-add` で追加する。それ以外の capability は追加しない
8. **seccomp プロファイル**: `ptrace` / `mount` / `umount2` / `pivot_root` / `chroot` / `bpf` / `unshare(CLONE_NEW*)` / `setns` / `reboot` / `kexec_load` / `swapon` / `swapoff` / `init_module` / `perf_event_open` を拒否する
9. **resource limit**: `--memory` / `--cpus` / `--pids-limit` を必ず指定する
10. **イメージの定期更新と脆弱性スキャン**: ベースイメージ・依存パッケージを定期的に更新し、`trivy` 等で CVE スキャンを実施する

参考実装: `docker/claude-sandbox/` — コンテナ隔離を使用する場合は当該ディレクトリの `README.md` に記載された推奨 `docker run` コマンドを出発点とし、利用プロジェクトの要件に合わせてマウント・secrets 注入を調整すること。entrypoint 実装は `docker/claude-sandbox/entrypoint.sh` を参照。spike-loop のコンテナライフサイクル統合（container ID 管理・docker logs stuck 検出・SESSION_ID 孤立コンテナ検出）は実装済み。`install.sh` の `setup_secrets()` による secrets 自動生成と `prepare_docker_image()` による Docker イメージビルドも実装済み。`tests/test_container_sandbox.sh` で CISO 最低条件のテストを提供（Docker 未導入環境ではテスト 8-9 がスキップされる）
参考判断記録: `.claude/knowledge/cto/decisions.md` の `2026-04-11: docker/claude-sandbox/ のリポジトリトップレベル配置判断` および `2026-04-11: seccomp プロファイルを ALLOW デフォルト + 特定 syscall denial 構成で実装`
