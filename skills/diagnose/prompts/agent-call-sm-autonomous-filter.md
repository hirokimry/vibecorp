以下の改善候補について、rules/autonomous-restrictions.md に定義された不可領域に該当するものをチェックしてください:

不可領域:
1. 認証（hooks/*auth*, hooks/*permission*, settings.json の permissions, gh auth, ANTHROPIC_API_KEY 扱い）
2. 暗号（encrypt/decrypt/secret/credential/token を扱うコード）
3. 課金構造（docs/cost-analysis.md, max_issues_per_day 等のコスト上限, claude -p / npx / bunx で LLM を呼ぶ箇所、**モデル指定の変更（Opus → Sonnet 等）**）
4. ガードレール（protect-files.sh, diagnose-guard.sh, forbidden_targets, diagnose-active スタンプの制御、**エージェント削減・合議制回数削減・並列度自体の削減**）
5. MVV（MVV.md 自体の変更）
6. CI エージェント（GitHub Actions）（`.github/workflows/claude*.{yml,yaml}` / `.github/workflows/ai-review.{yml,yaml}` の `permissions` / `secrets` 参照変更、トリガーを `pull_request_target` に変更する候補、`CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` の参照方式変更、Fork PR 除外条件（`if: github.event.pull_request.head.repo.full_name == github.repository`）の削除・緩和、GitHub App に与える権限スコープの変更（特に `administration: write` / `secrets: write` / `workflows: write` の追加））

該当する候補には「除外」と判定し、理由として該当領域名を付記してください。
