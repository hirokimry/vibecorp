# フック設計パターン

vibecorp のフックに共通する設計パターンと注意点を記録する。

## コマンド正規化の統一パターン

ゲート系フック（sync-gate, review-to-rules-gate, session-harvest-gate）は以下の正規化処理を共有する:

1. 先頭空白の除去
2. 環境変数プレフィックス（`KEY=VALUE ...`）の除去（sed）
3. ラッパーコマンド（`env`, `command`）のループ除去
4. 絶対パス / 相対パスの `basename` 正規化
5. 先頭 N トークンの抽出・比較

この処理を省略すると `ENV_VAR=val git push` や `/usr/bin/git push` でバイパスされる。

### 注意: block-api-bypass.sh との実装差異

`block-api-bypass.sh` は Bash の正規表現（`=~`）でプレフィックス除去を行い、`env`/`command` の除去は `${var#pattern}` で行っている。他のフックとは正規化手法が異なるが、検出対象が `gh api` のサブ文字列マッチ（grep -qE）であるため、実質的に問題は発生していない。

新しいフックを追加する場合は、ゲート系フックの正規化パターン（sed + awk 方式）に統一すること。

## スタンプファイルの設計

ゲート系フックはスタンプファイル（`/tmp/.{project}-{gate名}-ok`）で状態管理する:

- スタンプの生成元: 対応するスキル（例: `/sync-check` が `/tmp/.{project}-sync-ok` を生成）
- スタンプの消費: ゲートフックがスタンプの存在を確認し、確認後に `rm -f` で即座に削除する
- **ワンタイム性**: 1回の push / merge につき1回のスキル実行を強制する設計。スタンプを使い回せない

### プロジェクト名のサニタイズ

スタンプファイル名にプロジェクト名を含めるため、`vibecorp.yml` の `name` を `tr -cs 'A-Za-z0-9._-' '_'` でサニタイズする。未設定時のフォールバック値は `vibecorp-project`。

## team-auto-approve.sh の判定ロジック

Claude Code の Agent Teams でチームメイトの承認プロンプトを抑制するフック。ホワイトリスト方式で安全なツールコールのみ `permissionDecision: "allow"` を返す。

重要な注意点:

- `"allow"` を使うこと。`"approve"` は deprecated で Write/Edit に効かない
- allow は「入口を開ける」だけであり、他のフックの deny が優先される
- 未知のコマンド・ツールには何も返さない（通常の承認プロンプトに委ねる）
