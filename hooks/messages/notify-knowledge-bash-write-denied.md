検出パス: {{DETECTED}}

.claude/knowledge/{role}/decisions/ や {role}/audit-log/ への Bash 経由直書きは禁止です（>, >>, tee, cp, mv, sed -i, awk -i inplace を含む）。

復旧手順:
1. . .claude/lib/knowledge_buffer.sh
2. knowledge_buffer_ensure
3. BUFFER_DIR={{BUFFER}}
4. コマンドの宛先を ${BUFFER_DIR}/.claude/knowledge/... に置き換えて再実行

書込みは Bash redirect ではなく Edit/Write/MultiEdit ツールを使うことを推奨します（hook が deny を確実に検出できます）。