# vibecorp ポリシー

> このドキュメントはプロジェクト全体のポリシーを定義する Source of Truth です。

## 開発ポリシー

### ブランチ戦略

（ブランチ命名規則・マージ戦略を記載）

### コードレビュー

（レビューの必須条件・承認基準を記載）

### デプロイ

（デプロイフロー・承認プロセスを記載）

## コミュニケーションポリシー

（Issue・PR・ドキュメントの運用方針を記載）

## コンテナ隔離ポリシー（full プリセット）

full プリセットの自律実行スキル（spike-loop, ship-parallel, autopilot）に適用される。

### MUST

- 自律実行スキルはコンテナ内で実行しなければならない
- コンテナ設定は SECURITY.md の「コンテナ隔離の最低条件」を全て満たさなければならない
- secrets は `/run/secrets/` への read-only bind mount で注入しなければならない
- コンテナイメージは `install.sh` でビルドされた `vibecorp/claude-sandbox:dev` を使用しなければならない

### MUST NOT

- `/var/run/docker.sock` をコンテナにマウントしてはならない
- `docker run -e` で secrets を環境変数として渡してはならない
- `--privileged` フラグを使用してはならない
- `--cap-add ALL` を使用してはならない

### 適用範囲

minimal / standard プリセットにはこのポリシーは適用されない。これらのプリセットは Docker なしで動作する。

## 品質ポリシー

### テスト

（テスト戦略・カバレッジ基準を記載）

### ドキュメント

（ドキュメント管理方針を記載）
