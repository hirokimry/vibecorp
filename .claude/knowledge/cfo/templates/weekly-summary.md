# 週次サマリテンプレート（実機検証期間用）

Issue #475 の 2 週間並走検証中、毎週末に CFO が記録する週次サマリのテンプレート。
記録先: `.claude/knowledge/cfo/decisions/YYYY-QN.md`（既存ファイルに追記）

## 使い方

1. 検証期間中、毎週末（または週初め）に本テンプレを複製する
2. 該当週の数値・観察を記入する
3. 完成したサマリを `decisions/YYYY-QN.md` に追記する
4. `decisions-index.md` に 1 行サマリを追記する

## テンプレート本体

```markdown
## YYYY-MM-DD — Issue #475 実機検証 第N週サマリ

- **期間**: YYYY-MM-DD 〜 YYYY-MM-DD
- **判定**: ✅ 継続 / ⚠️ 要監視 / ❌ ロールバック検討

### 1. レート消費（A 契約）

| 指標 | 実測値 | 目安 | 達成度 |
|------|--------|------|--------|
| Claude Max トークン消費 | XXM token | 90M token/月（≒ 22.5M token/週） | XX% |
| ヘッドレス Claude 起動回数 | XX 回 | — | — |
| GitHub Actions minutes 消費 | XX 分 | — | — |

### 2. 4 契約動作確認（B 契約）

| 契約 | CodeRabbit | claude-action | 並走時挙動 |
|------|----------|--------------|-----------|
| ① auto-review | ✅ / ⚠️ / ❌ | ✅ / ⚠️ / ❌ | — |
| ② approve / request_changes 切替 | ✅ / ⚠️ / ❌ | ✅ / ⚠️ / ❌ | — |
| ③ auto-resolve | ✅ / ⚠️ / ❌ | ✅ / ⚠️ / ❌ | — |
| ④ 日本語レビュー | ✅ / ⚠️ / ❌ | ✅ / ⚠️ / ❌ | — |

### 3. 観察された事象

- 良かった点:
  - …
- 課題・違和感:
  - …

### 4. ロールバック判断

- **本週ロールバック発動**: なし / あり（理由: …）
- **次週への申し送り**: …

### 5. 数値データ

- レビュー件数: XX 件（CodeRabbit XX 件 / claude-action XX 件）
- 重複指摘率: XX%（同一行両方が指摘した件数 / 全指摘件数）
- 平均レビュー所要時間: CodeRabbit XX 秒 / claude-action XX 秒
- 月次予測 Claude Max トークン消費: XXM token（実測 × 4.33 週で月次換算）
```

## 集計コマンド例

レビューメトリクスは Issue #474（並走比較メトリクス）で `~/.cache/vibecorp/state/<repo-id>/review-metrics/` に蓄積される。週次集計時は以下のように参照する:

```bash
# 週次集計（過去 7 日）
ls ~/.cache/vibecorp/state/<repo-id>/review-metrics/*.jsonl

# 簡易集計（CodeRabbit / claude-action 別件数）
cat ~/.cache/vibecorp/state/<repo-id>/review-metrics/*.jsonl | jq -s 'group_by(.tool) | map({tool: .[0].tool, count: length})'
```

詳細は `scripts/collect-review-metrics.sh` および本 Issue #474 のドキュメントを参照。

## 検証完了判定基準（Issue #475 確定）

2 週間（2 サマリ）の合計で以下全てを満たせば検証完了。

1. **A 契約**: レート消費 90M token/月以内（または cadence 24h → 36h に伸長して達成）
2. **B 契約**: 4 契約全部が両ツールで機能している
3. **C*O 合議**: CFO + CISO + CTO + CPO の 4 役合議で OK 判定

C・D 契約（二重指摘ノイズ、利用者不満）は判定外（観測のみ）。

## 関連

- 親 Issue: [#475](https://github.com/hirokimry/vibecorp/issues/475)
- メトリクス収集: [#474](https://github.com/hirokimry/vibecorp/issues/474)
- ロールバック手順: `docs/ai-review-rollback.md`
- 合議基準: `docs/ai-review-dependency.md` の「実機検証完了判定」セクション
