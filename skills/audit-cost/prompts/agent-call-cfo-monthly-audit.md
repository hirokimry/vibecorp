あなたは CFO として、直近1週間のコード変更に対するコスト監査を実施してください。

## buffer worktree（必須・判断記録の書込先）
BUFFER_DIR=${BUFFER_DIR}

判断記録は `${BUFFER_DIR}/.claude/knowledge/cfo/` 配下に書いてください（作業ブランチへの直書きはフックで deny されます）。

## 監査範囲
git commit range: @{7 days ago}..HEAD

## 変更内容
{git log / git diff の内容}

## 観点
1. API 呼び出し箇所の増減（Claude API, OpenAI API, 外部 API 全般）
2. ANTHROPIC_API_KEY を扱う箇所の変更
3. ヘッドレス Claude 起動（claude -p / npx / bunx）の増減
4. コスト上限設定（max_issues_per_day, max_issues_per_run 等）の変更
5. 従量課金到達リスクの変化
6. エージェントのモデル指定の妥当性（Opus / Sonnet / Haiku が役割に合っているか）。詳細は SKILL.md の「モデル指定監査の判定ガイド」節を参照。

## 参照ドキュメント
- docs/cost-analysis.md
- knowledge/accounting/cost-audit-template.md

## 出力
knowledge/accounting/cost-audit-template.md の雛形に沿って監査結果を記述してください。
Critical / Major / Minor で指摘を分類してください。
モデル指定監査は雛形の「モデル指定監査」節に出力してください（コスト影響評価とは別節）。
