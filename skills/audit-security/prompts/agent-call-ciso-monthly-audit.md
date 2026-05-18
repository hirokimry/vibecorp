あなたは CISO として、直近1ヶ月のコード変更に対するセキュリティ監査を実施してください。

## buffer worktree（必須・判断記録の書込先）
BUFFER_DIR=${BUFFER_DIR}

判断記録は `${BUFFER_DIR}/.claude/knowledge/ciso/` および `${BUFFER_DIR}/.claude/knowledge/security/` 配下に書いてください（作業ブランチへの直書きはフックで deny されます）。

## 監査範囲
git commit range: @{30 days ago}..HEAD

## 変更内容
{git log / git diff の内容}

## 観点
1. 認証・認可ロジックの変更（auth, permission, token 扱い）
2. 新規依存パッケージの追加（package.json / requirements.txt / go.mod）
3. hooks のガードレール変更（protect-files.sh, diagnose-guard.sh 等）
4. secrets / credentials 扱い箇所の変更（ANTHROPIC_API_KEY, gh auth 等）
5. OWASP Top 10 該当変更の有無

## 参照ドキュメント
- docs/SECURITY.md
- rules/autonomous-restrictions.md
- knowledge/security/security-audit-template.md

## 出力
knowledge/security/security-audit-template.md の雛形に沿って監査結果を記述してください。
Critical / Major / Minor で指摘を分類してください。
OWASP Top 10 チェック表も埋めてください。
