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

