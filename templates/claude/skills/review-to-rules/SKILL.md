---
name: review-to-rules
description: "PRレビュー指摘から規約・ナレッジ・仕様への反映を自動化。修正した指摘を分析し、CTO/CPOエージェントが管轄の rules/ / knowledge/ / docs/ に反映すべきか判断・実行する。「/review-to-rules」「指摘を規約化して」と言った時に使用。"
---

# レビュー指摘 → 規約・ナレッジ自動反映

PRレビュー（CodeRabbit / 人間）で修正した指摘を分析し、再発防止のために CTO/CPO エージェントが各自の管轄で rules/ / knowledge/ / docs/ に反映する。

## 使用方法

```bash
/review-to-rules                    # 現在のブランチのPRから指摘を取得
/review-to-rules <PR URL>           # PR URLを直接指定
/review-to-rules --worktree <path>  # worktree 内で実行
```

## worktree モード

`--worktree <path>` が指定された場合、全操作を指定パス内で実行する。

- **Bash**: 全コマンドを `cd <path> && command` で実行する
- **Read/Write/Edit**: `<path>/` を基準とした絶対パスを使用する
- **サブスキル呼び出し**: `--worktree <path>` を引き継ぐ
- 未指定時は従来通り CWD で実行する（後方互換）
- **`.claude/knowledge/`**: worktree モードでは `<path>/.claude/knowledge/` を使用する

## ワークフロー

### 1. 修正済み指摘の収集

PRのレビューコメントから、返信済み（＝修正済み）の指摘を収集する。
「返信済み」の判定は、指摘コメントに対して `in_reply_to_id` で紐づく返信が存在するかで行う。

```bash
# 全トップレベルコメントのID
ALL_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.in_reply_to_id == null) | .id]')

# 返信済みID一覧
REPLY_TO_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.in_reply_to_id != null) | .in_reply_to_id] | unique')

# CodeRabbitの返信済み指摘を抽出
CR_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.in_reply_to_id == null) | .id]')
echo "$CR_IDS" | jq --argjson replied "$REPLY_TO_IDS" \
  '[.[] | select(. as $id | $replied | index($id))]'

# 人間レビュアーの返信済み指摘を抽出
HUMAN_IDS=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --paginate \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i") | not) | select(.in_reply_to_id == null) | .id]')
echo "$HUMAN_IDS" | jq --argjson replied "$REPLY_TO_IDS" \
  '[.[] | select(. as $id | $replied | index($id))]'
```

返信済みの指摘IDを取得したら、そのIDで指摘本文を取得する。

### 2. 指摘の分類

収集した指摘を以下の観点で分類する:

| 分類 | 反映先 | 判断する専門職 |
|------|--------|---------------|
| 全員が守るべきコーディング規約 | `.claude/rules/` | CTO |
| 技術的ノウハウ・パターン | `.claude/knowledge/cto/` | CTO |
| プロダクト仕様・設計パターン | `docs/specification.md` or `.claude/knowledge/cpo/` | CPO |
| 一過性の指摘（反映不要） | なし | — |

**分類基準:**
- 同じ指摘が今後も繰り返し発生しうるか？ → Yes なら反映対象
- 一度きりのバグ修正・タイポ修正 → 反映不要

### 3. 専門職エージェントに委任

分類結果に基づき、該当する専門職エージェントを **順次起動** する（ファイル競合防止）。

該当する指摘がないエージェントは起動しない。

各エージェントに以下を渡す:

````text
あなたは {役職名} として、レビュー指摘を管轄の規約・ナレッジに反映してください。

## 最初にやること（必須）

管轄の knowledge ディレクトリが存在しない場合は作成する:

```bash
mkdir -p .claude/knowledge/{role}/
```

## あなたの管轄
- rules/: {CTO の場合のみ — 全エージェントが守るべきコーディング規約}
- docs/: {管轄ファイル}
- knowledge/{role}/: 自分のナレッジディレクトリ

## 反映すべき指摘
{指摘内容のリスト}

## 判断基準
各指摘について、以下の4つから判断すること:

1. **rules/ に追加**: 全エージェントが守るべきルール（CTO のみ）
   - 例: 「テストではモックを使わない」「コードブロックに言語指定を付ける」
2. **docs/ に追加**: MUST/MUST NOT 制約
   - 例: 「APIキーをクライアントに含めてはならない」
3. **knowledge/{role}/ に記事として蓄積**: 自分の判断ノウハウ
   - 例: 「deprecation 対応パターン」「設計指針」
4. **反映不要**: 一過性のバグ修正、タイポ、文脈依存の指摘

## 制約
- 管轄ファイルのみ編集すること
- 既存の記述スタイル・フォーマットを維持する
- 過剰な加筆をしない

## 出力
- 反映したファイルと内容の要約
- 反映不要と判断した指摘とその理由
````

### 4. 結果報告

全エージェントの結果を統合して報告する:

```text
## review-to-rules 結果

### 反映内容

#### CTO
- .claude/rules/testing.md: 「コードブロックに言語指定を付ける」を追加
- .claude/knowledge/cto/patterns.md: deprecation 対応パターンを記事化

#### CPO
- （該当指摘なし）

### 反映不要と判断した指摘
- [タイポ修正] — 一過性の修正のため
```

### 5. スタンプ発行

全エージェントの処理が完了したら、必ずスタンプを発行する（反映の有無に関わらず）。スタンプは `~/.cache/vibecorp/state/<repo-id>/` 配下に作成される:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/common.sh"
STAMP_DIR="$(vibecorp_stamp_mkdir)"
touch "${STAMP_DIR}/review-to-rules-ok"
```

このスタンプがないと review-to-rules-gate フックにより `gh pr merge` がブロックされる。

## 制約

- `git add` / `git commit` / `git push` はこのスキル内では実行しない（呼び出し元に委ねる）
- knowledge/ の記事は、既存の記事がある場合は追記する（新規ファイル乱立を防ぐ）
- rules/ への追加は慎重に。全エージェントに影響するため、本当に全員が守るべきルールかを確認する
