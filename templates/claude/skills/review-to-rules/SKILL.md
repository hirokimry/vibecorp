---
name: review-to-rules
description: "PRレビュー指摘から規約・ナレッジへの反映を自動化。修正した指摘を分析し、rules/ / knowledge/ に反映すべきか判断・実行する。「/review-to-rules」「指摘を規約化して」と言った時に使用。"
---

# レビュー指摘 → 規約・ナレッジ自動反映

PRレビュー（CodeRabbit / 人間）で修正した指摘を分析し、再発防止のために `.claude/rules/` または `.claude/knowledge/` に反映する。

## 使用方法

```bash
/review-to-rules                    # 現在のブランチのPRから指摘を取得
/review-to-rules <PR URL>           # PR URLを直接指定
```

## ワークフロー

### 1. 修正済み指摘の収集

PRのレビューコメントから、返信済み（＝修正済み）の指摘を収集する。
「返信済み」の判定は、指摘コメントに対して `in_reply_to_id` で紐づく返信が存在するかで行う。

```bash
# 全トップレベルコメントのID
ALL_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.in_reply_to_id == null) | .id]')

# 返信済みID一覧
REPLY_TO_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.in_reply_to_id != null) | .in_reply_to_id] | unique')

# CodeRabbitの返信済み指摘を抽出
CR_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.in_reply_to_id == null) | .id]')
echo "$CR_IDS" | jq --argjson replied "$REPLY_TO_IDS" \
  '[.[] | select(. as $id | $replied | index($id))]'

# 人間レビュアーの返信済み指摘を抽出
HUMAN_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i") | not) | select(.in_reply_to_id == null) | .id]')
echo "$HUMAN_IDS" | jq --argjson replied "$REPLY_TO_IDS" \
  '[.[] | select(. as $id | $replied | index($id))]'
```

返信済みの指摘IDを取得したら、そのIDで指摘本文を取得する。

### 2. 指摘の分類

収集した指摘を以下の観点で分類する:

| 判断 | 反映先 | 基準 |
|------|--------|------|
| rules/ に追加 | `.claude/rules/` | 全エージェントが守るべきコーディング規約 |
| knowledge/ に蓄積 | `.claude/knowledge/` | ドメイン固有のノウハウ・パターン |
| 反映不要 | なし | 一過性のバグ修正、タイポ、文脈依存の指摘 |

**判断基準:** 同じ指摘が今後も繰り返し発生しうるか？ → Yes なら反映対象

### 3. 反映実行

- **rules/**: テーマが近い既存ルールファイルに追記する。新しいテーマなら新規ファイルを作成。簡潔で実行可能な記述にする
- **knowledge/**: 既存の記事に追記する。小さなファイルの乱立を避ける
- 各ファイルの既存のフォーマット・スタイルを維持する

### 4. 結果報告

```text
## review-to-rules 結果

### 反映内容
- .claude/rules/testing.md: 「コードブロックに言語指定を付ける」を追加
- .claude/knowledge/patterns.md: deprecation 対応パターンを記事化

### 反映不要と判断した指摘
- [変数名タイポ] — 一過性の修正のため
```

### 5. スタンプ発行

処理完了時に必ずスタンプを発行する（反映の有無に関わらず）:

```bash
touch /tmp/.{{PROJECT_NAME}}-review-to-rules-ok
```

このスタンプがないと review-to-rules-gate フックにより `gh pr merge` がブロックされる。

## 制約

- `git add` / `git commit` / `git push` はこのスキル内では実行しない（呼び出し元に委ねる）
- knowledge/ の記事は既存記事に追記する（新規ファイル乱立を防ぐ）
- rules/ への追加は慎重に — 全エージェントに影響するため
