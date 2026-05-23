.claude/knowledge/{role}/decisions/ や {role}/audit-log/ は knowledge/buffer worktree 経由で更新してください。

復旧手順:
1. . .claude/lib/knowledge_buffer.sh
2. knowledge_buffer_ensure
3. BUFFER_DIR=$(knowledge_buffer_worktree_dir)
4. ファイルパスを ${BUFFER_DIR}/.claude/knowledge/... に置き換えて再実行

スキル経由の場合: /vibecorp:session-harvest, /vibecorp:sync-edit, /vibecorp:audit-cost, /vibecorp:audit-security のいずれかを使用
詳細: docs/specification.md の「自動反映フロー」節