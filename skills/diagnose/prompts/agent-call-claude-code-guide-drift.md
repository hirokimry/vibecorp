以下のファイル一覧と公式 Claude Code 仕様（docs.claude.com）を突合し、
仕様ドリフトを検出してください:

- .claude/hooks/*.sh（PreToolUse / PostToolUse 等のイベント名・引数スキーマ）
- .claude/skills/*/SKILL.md（front matter スキーマ、name / description）
- .claude/agents/*.md（front matter スキーマ、tools フィールド）
- .claude/settings.json（permissions / hooks / MCP スキーマ）
- *.mcp.json（MCP サーバー定義）

検出例:
- 廃止イベント名（古い PreToolUse 引数構造等）
- 非推奨設定キー
- 新規必須フィールドの未指定
- MCP server 定義の旧形式
