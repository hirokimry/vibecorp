# install.sh の仕様上の注意点

install.sh を変更する際に踏みやすいトラップを記録する。

## lock ベースの管理ファイル判定

`settings.json` のマージ時に vibecorp 管理フックかどうかを判定する際、以前はフックの `.command` パスに `.claude/hooks/` が含まれるかで判定していた。現在は **lock ファイルのフック名リストで判定** する方式に変更されている。

- lock に記載されたフック名を JSON 配列に変換し、jq の `is_managed_hook` 関数で判定する
- パス文字列に依存しないため、ディレクトリ構造を変更しても判定が壊れない

## プリセットの引き算方式

テンプレートは全プリセット分をフル装備で含む。`install.sh` が `copy_managed_files` でまず全ファイルをコピーした後、`case "$PRESET"` で不要なファイルを `rm` する。

- テンプレートに条件分岐を持たせず、`install.sh` だけが選別ロジックを持つ
- 新しいフック/スキルを追加したら、minimal/standard での削除リストに追記が必要

## --update 時のユーザーファイル保護

- hooks / skills: `--update` 時は上書きする（テンプレートが source of truth）
- agents: 既存ファイルがあればスキップする（`--update` でも上書きしない）
- knowledge: 削除しない（ユーザーが蓄積したデータ）
- docs: 既存ファイルはスキップする（ユーザーがカスタマイズ済みの前提）
- rules: `--update` 時は上書きする

## COPIED_* 変数による lock 精度

lock にファイル名を記録する際、hooks/skills/agents はテンプレートの存在 + 配置先の存在で判定する。一方、rules/docs/knowledge/issue_templates は `COPIED_*` 変数に「実際にコピーしたファイル名」を追記し、lock 生成時にこの変数を参照する。

これにより、既存ファイルのスキップによりコピーが行われなかった場合に lock に誤登録されることを防いでいる。

## vibecorp.yml 設定の読み取り順序

`--update` モードでは:

1. `parse_args` でコマンドライン引数をパース（デフォルト値を設定）
2. `read_vibecorp_yml` で yml から既存設定を読み取る
3. コマンドラインで `--preset` / `--language` が明示指定されていればそちらを優先
4. `update_vibecorp_yml` で yml の preset を更新（`--preset` 指定時のみ）

## coderabbit.enabled の判定

`vibecorp.yml` の `coderabbit:` ブロック内の `enabled:` フィールドは、`awk` でネストを追跡して抽出する。トップレベルに `enabled:` という別のキーがあった場合に誤読しないよう注意が必要。
