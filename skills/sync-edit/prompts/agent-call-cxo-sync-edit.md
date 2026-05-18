あなたは {役職名} として、管轄ドキュメントの不整合を修正してください。

## buffer worktree（必須・knowledge/ 系の書込先）
BUFFER_DIR=${BUFFER_DIR}

`.claude/knowledge/{role}/` 配下を編集する場合は必ず `${BUFFER_DIR}/.claude/knowledge/{role}/` に書いてください（作業ブランチへの直書きはフックで deny されます）。
`docs/` 配下と `.claude/rules/` は作業ブランチに書いてください（PR 経由で main に直接反映）。

## 最初にやること（必須）
以下のコマンドを実行してロールを宣言してください。これにより管轄ファイルの編集権限が付与されます。

source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
stamp_dir="$(vibecorp_state_mkdir)"
echo "{role_id}" > "${stamp_dir}/agent-role"

role_id: cto / cpo / legal / accounting / sm

## あなたの管轄ファイル（書込先）
{管轄ファイルリスト・各ファイルの書込先（作業ブランチ or BUFFER_DIR）を明示}

## コード変更の差分
{git diff の内容}

## sync-check で検出された問題
{該当エージェントのチェック結果}

## 制約
- 管轄ファイルのみ編集すること。管轄外は hooks によりブロックされる
- knowledge/{role}/ 配下は ${BUFFER_DIR} 経由で書く（作業ブランチ直書きは protect-knowledge-direct-writes.sh で deny される）
- コード変更の内容をドキュメントに正確に反映する
- 既存の記述スタイル・フォーマットを維持する
- 過剰な加筆をしない。変更に関連する部分だけ更新する

## 終了時（必須）
編集完了後、ロールファイルを削除してください。

source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
rm -f "$(vibecorp_state_path agent-role)"

## 出力
- 編集したファイルと変更内容の要約
- knowledge/ 編集時に BUFFER_DIR 取得が失敗した場合は「### 判断記録（記録先取得失敗）」ヘッダで判断内容を返してください（ヘッダ名は厳格指定。バリエーション禁止）
