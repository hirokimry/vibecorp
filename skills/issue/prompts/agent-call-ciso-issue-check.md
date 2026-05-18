以下の Issue が `.claude/rules/autonomous-restrictions.md` の自律実行不可領域に該当するかチェックしてください:

タイトル: <タイトル>
本文: <本文>

不可領域:
1. 認証（hooks/*auth*, hooks/*permission*, settings.json の permissions, gh auth, ANTHROPIC_API_KEY 扱い）
2. 暗号（encrypt/decrypt/secret/credential/token を扱うコード）
3. 課金構造（docs/cost-analysis.md, max_issues_per_day 等のコスト上限, claude -p / npx / bunx で LLM を呼ぶ箇所）
4. ガードレール（protect-files.sh, diagnose-guard.sh, forbidden_targets, diagnose-active スタンプの制御）
5. MVV（MVV.md 自体の変更）
6. CI エージェント（GitHub Actions）（`.github/workflows/claude*.{yml,yaml}` / `.github/workflows/ai-review.{yml,yaml}` の `permissions` / `secrets` 参照変更、`pull_request_target` への変更、`CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` の参照方式変更、Fork PR 除外条件削除・緩和、GitHub App 権限スコープ追加）

判定: OK または 除外（該当領域名を明記）
