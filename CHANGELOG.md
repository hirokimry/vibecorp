# Changelog

> [!NOTE]
> 利用者（vibecorp を導入するプロジェクト）向けのリリース別変更点一覧。
> カテゴリ: **追加** / **変更** / **非推奨** / **削除** / **修正** / **セキュリティ**。
> [Keep a Changelog 1.1.0](https://keepachangelog.com/ja/1.1.0/) 準拠の 6 種。
> バージョンは `[X.Y.Z] - YYYY-MM-DD` 形式。

## [Unreleased]

### 修正

- 旧構造で作られた知見バッファが新構造へ自動移行されるようになった。([#543](https://github.com/hirokimry/vibecorp/issues/543))
  - `/sync-edit` / `/review-harvest` / `/knowledge-pr` の次回実行時に自動回復する。
  - 未プッシュのコミットは移行中に保全される。
- `install.sh --update` 実行でバージョンがダウングレードする問題を修正した。([Issue #540](https://github.com/hirokimry/vibecorp/issues/540), [PR #542](https://github.com/hirokimry/vibecorp/pull/542))
  - バージョン情報の参照元を 1 箇所に統一し、上書きされなくなった。

## [0.3.0] - 2026-04-25

### 変更

- ⚠️ スキルの旧コマンド名（`/ship`、`/autopilot` 等）が動作しなくなった。
  - Plugin 名前空間（`/vibecorp:ship`、`/vibecorp:autopilot` 等）のみ使用可能になった。
- `install.sh --update` 実行時に、既存プロジェクトの互換スタブが自動で削除されるようになった。
  - 利用者が独自に追加したスキルは残る。

### 削除

- `install.sh` から互換スタブ自動生成ロジックを削除した。

## [0.1.0] - 2026-03-28

### 追加

- `install.sh` による 3 プリセット対応（minimal / standard / full）
- hooks / skills / agents / rules / knowledge テンプレート
- `vibecorp.yml` / `vibecorp.lock` によるプロジェクト設定管理
- `settings.json` のマージ管理（vibecorp 由来フックのみ操作）
- 3-way マージによるアップデート時のコンフリクト解消
- CodeRabbit 連携設定
- GitHub Branch Protection 自動設定
