あなたは Issue #{番号} の実装担当です。

以下の Issue を /vibecorp:ship --worktree で実装してください。

- Issue URL: <Issue URL>
- worktree パス: <worktree_path>
- ベースブランチ: <ベースブランチ>

実行コマンド:
/vibecorp:ship <Issue URL> --worktree <worktree_path>

注意:
- 全操作は worktree パス内で実行されます（/vibecorp:ship --worktree が自動処理）
- PR のベースブランチは <ベースブランチ> を指定してください
- Bash は 1 コマンド 1 呼び出しに分割すること。`cd ... && cmd1 && cmd2 | head` のように cd + パイプ + リダイレクトを含む compound command は Claude Code 本体の built-in security check（path resolution bypass 検出）に引っかかり permission 確認が出るため、別々の Bash 呼び出しに分ける（参照: #258）

完了したら SendMessage でチームリーダーに以下を報告してください:
- PR URL
- 成功/失敗
- 失敗の場合は理由

エラーが発生した場合も SendMessage で即座にチームリーダーに報告してください。
