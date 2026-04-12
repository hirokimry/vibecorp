# CISO 判断記録

## 2026-04-11: `--dangerously-skip-permissions` のコンテナ隔離構想 評価

### 判断内容

`claude --dangerously-skip-permissions` をコンテナ内で実行する構想に対するリスク評価。

### 検出リスクと軽減可否

#### コンテナ隔離で軽減できるリスク

- ホスト FS への直接書き込み（read-only mount / overlay で防御可能）
- ホストプロセスへの干渉（PID namespace 分離）
- ネットワーク横断攻撃（egress 制御で大幅軽減）
- リソース枯渇（cgroup limits で防御可能）

#### コンテナ隔離では軽減できないリスク

- マウントされた secrets（GitHub token, Anthropic API key, .ssh, .gnupg）の流出: コンテナ内からは読み取り可能であり、egress が開いていれば外部送信できる
- プロンプトインジェクション経由の任意コマンド実行: `--dangerously-skip-permissions` が前提である以上、コンテナ内でも任意コマンドは実行される
- docker.sock マウント時のコンテナエスケープ: docker.sock があればホスト root 相当の権限を取得可能
- 共有ボリュームを経由したホスト側データ汚染: 書き込み権限のある共有ボリュームは攻撃経路になる
- 環境変数経由の credential 流出: コンテナ環境変数に渡した secrets は `env` コマンド一発で読める

### 必須防御層（最低条件）

1. docker.sock をコンテナにマウントしない（絶対禁止）
2. egress を allowlist 制御する（Anthropic API, GitHub API のみ許可、その他全遮断）
3. secrets をコンテナ環境変数に渡さない（Docker secrets または実行直前の一時ファイルマウントに限定）
4. .ssh / .gnupg をマウントしない（必要なら操作専用の使い捨てキーペアを発行）
5. GitHub token のスコープを最小化する（対象リポジトリ・対象操作のみ）
6. read-only FS + 必要最小限の書き込み可能 overlay のみ
7. non-root user での実行（user namespace または `--user` 指定）
8. seccomp / AppArmor プロファイルで危険な syscall を制限
9. resource limit（CPU/memory/PID）を必ず設定
10. コンテナイメージを定期更新・脆弱性スキャンする

### 最終判断

**条件付き承認**。上記 10 項目を全て満たした上で、egress 制御の実装と secrets 管理方式の設計をオーナーが確認してから実行すること。docker.sock マウントと egress 全開放は即時 NO-GO。

### 攻撃チェーン（最悪シナリオ）

プロンプトインジェクション → 任意コマンド実行（skip-permissions により確実） → 環境変数 or マウントファイルから GitHub token 取得 → egress 経由で外部 C2 へ token 送信 → リポジトリへの不正 push / secrets 破壊

## 2026-04-12: Issue #267（spike-loop のコンテナ統合）防御層実装確認

### 判断内容

spike-loop スキルにおけるコンテナ統合実装（Issue #267）の防御層設計を評価。前回判断（2026-04-11）で定義した必須防御層 10 項目との整合性を検証した。

### 評価対象の実装

1. `--cap-add SETUID / SETGID` を entrypoint 降格前提で条件付き承認
2. `ESTABLISHED,RELATED` ルールによる CDN IP ローテーション対応
3. `entrypoint.sh` の `load_secrets` による env 拒否検査

### 各実装の評価

#### `--cap-add SETUID / SETGID`（entrypoint 降格前提）

- **評価**: 条件付き承認
- **根拠**: entrypoint.sh がコンテナ起動直後に非 root ユーザーへ降格する前提であれば、SETUID / SETGID ケーパビリティは降格処理のためにのみ使用され、通常操作中の権限昇格リスクは限定的となる。ただし降格処理が失敗した場合（entrypoint.sh のバグ等）に root のまま処理が継続するリスクは残存する。
- **必要条件**: entrypoint.sh の降格処理が必ず成功するか、失敗時にコンテナを即時終了させること。降格確認の assert を entrypoint.sh に実装すること。

#### `ESTABLISHED,RELATED` ルールによる CDN IP ローテーション対応

- **評価**: 承認
- **根拠**: Anthropic API・GitHub API は CDN を経由するため静的 IP allowlist が機能しない問題への現実的な対応策。`ESTABLISHED,RELATED` ルールはコンテナ側から開始した接続の応答パケットのみを許可し、外部からの新規接続は拒否する。egress allowlist（ドメイン名ベース）と組み合わせることで、CDN IP ローテーションに対応しつつ egress 制御を維持できる。
- **攻撃チェーンへの影響**: 外部からの新規接続開始は引き続き拒否されるため、リモートコード実行による C2 サーバーへのビーコン送信が容易になるリスクは増加しない。

#### `load_secrets` による env 拒否検査

- **評価**: 承認（重要な多層防御として評価）
- **根拠**: `ANTHROPIC_API_KEY` が環境変数経由でコンテナに渡されている場合にコンテナ起動を即時拒否する検査は、前回判断（2026-04-11）の必須防御層 3「secrets をコンテナ環境変数に渡さない」を実装レベルで強制する。設定ミスによる credential の環境変数混入を運用に依存せずコードで防ぐ。
- **防御層としての位置づけ**: `docker run` 側の設定ミスに対するフェイルセーフ。docker-compose や CI 設定で誤って `env:` に API キーを書いた場合でもコンテナが起動拒否することで漏洩リスクを低減する。

### 残存リスク

- entrypoint.sh の降格失敗時に SETUID / SETGID ケーパビリティを持ったまま root で動作継続するリスク
- `load_secrets` の拒否検査をバイパスする手段（entrypoint.sh を差し替えたカスタムイメージ等）が存在する場合はホスト側の制御に委ねる必要がある

### 最終判断

**条件付き承認**。entrypoint.sh の降格処理に失敗時即時終了の assert を追加することを条件とする。その他 2 項目は承認。前回判断（2026-04-11）の必須防御層 10 項目との整合性を確認した。

### 攻撃チェーン（最悪シナリオ）

プロンプトインジェクション → 任意コマンド実行 → `load_secrets` を回避するため entrypoint.sh 外から env を読もうとするが、env 拒否検査によりコンテナ起動前に検出 → entrypoint 降格が失敗した場合のみ root で動作継続 → ただし egress 制御（ESTABLISHED,RELATED + ドメイン allowlist）により外部 C2 への通信は限定的

