# Golden Test Data

claude-code-action のレビュー出力に対するリグレッション検知用の「正解」データ。

## 目的

`REVIEW.md` / `.claude/rules/severity/*` / `review-handling.md` / `review-observations.md` などのプロンプト・SoT を修正した際に、claude-action のレビュー品質が劣化していないかを **既知の PR を再レビューさせて期待結果と一致するか** で検証する。

## ファイル構成

各 intent の代表 PR を 1 件ずつ選んで golden データとする（合計 7 件）:

| ファイル | intent | 概要 |
|---|---|---|
| `feature_pr_*.json` | `intent/feature` | 新機能追加 PR |
| `bugfix_pr_*.json` | `intent/bugfix` | バグ修正 PR |
| `performance_pr_*.json` | `intent/performance` | 性能改善 PR |
| `security_pr_*.json` | `intent/security` | 脆弱性修正 PR |
| `refactor_pr_*.json` | `intent/refactor` | リファクタ PR |
| `infra_pr_*.json` | `intent/infra` | 開発基盤 PR |
| `docs_pr_*.json` | `intent/docs` | ドキュメント PR |

## JSON スキーマ

```json
{
  "pr_number": 123,
  "pr_url": "https://github.com/hirokimry/vibecorp/pull/123",
  "intent": "feature",
  "description": "新機能 X を追加した PR",
  "expected_severity_counts": {
    "critical": 1,
    "major": 2,
    "minor": 0
  },
  "expected_keywords": ["仕様逸脱", "エッジケース", "セキュリティ基礎"],
  "expected_keyword_min_match": 2
}
```

| フィールド | 説明 |
|---|---|
| `pr_number` | 対象 PR の番号 |
| `pr_url` | PR の URL（人間確認用） |
| `intent` | 7 種の intent ラベル名 |
| `description` | この PR を選んだ理由 / レビュー観点 |
| `expected_severity_counts` | 期待される severity 別の指摘件数 |
| `expected_keywords` | レビューコメントに含まれることが期待されるキーワード |
| `expected_keyword_min_match` | `expected_keywords` のうち最低何個マッチすれば合格か |

## 判定方法

LLM の出力ブレを許容しつつリグレッションを検知するため、厳密一致ではなく **件数 + キーワードの最低マッチ数** で判定する:

1. claude-action が PR をレビューする
2. レビューコメントから severity 別の件数を集計
3. 件数が `expected_severity_counts` と一致するか確認
4. レビューコメント全体から `expected_keywords` のマッチ数をカウント
5. マッチ数が `expected_keyword_min_match` 以上なら合格

## 実行タイミング

`templates/.github/workflows/ai-review-golden-test.yml` が以下のファイル変更を検知して自動実行する:

- `REVIEW.md`
- `templates/REVIEW.md.tpl`
- `.claude/rules/severity/**`
- `.claude/rules/review-handling.md`
- `.claude/rules/review-observations.md`
- `tests/golden/**`

これら以外の変更では golden test は走らない（コスト節約）。

## 比較対象

claude-code-action のみ。CodeRabbit は外部 SaaS で vibecorp がチューニングできないため対象外。

## 関連

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#473](https://github.com/hirokimry/vibecorp/issues/473)
- 依存元: [#465](https://github.com/hirokimry/vibecorp/issues/465)（REVIEW.md）、[#466](https://github.com/hirokimry/vibecorp/issues/466)（auto-resolve）、[#467](https://github.com/hirokimry/vibecorp/issues/467)（approve 発行）

## golden データの選定（#475 実機検証期間で確定）

実機検証期間（#475）でリポジトリ上の過去マージ PR から各 intent 1 件ずつ選定し、本ディレクトリに JSON を配置する。本 PR ではフレームワーク（スキーマ + サンプル + ワークフロー + 実行スクリプト）を提供する。

サンプルファイル: `_example.json`
