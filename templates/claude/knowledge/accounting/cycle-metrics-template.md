# Issue サイクル実測レポート雛形

`/cycle-metrics` による実測データの記録雛形。実施ごとに `cycle-metrics-YYYY-MM-DD.md` としてコピーして使用する。

判断（Critical/Major、Issue 起票要否）は CFO の `/audit-cost` 側で行う。本レポートは **データ生成専用**。

---

## 実施日

YYYY-MM-DD（生成スキル: `/vibecorp:cycle-metrics`）

## 集計範囲

- 対象 PR: 直近 N 件（マージ済み）
- 集計ブランチ: M 件（`dev/` プレフィックス付き）

## PR サマリ

| 指標 | 値 |
|---|---|
| PR 件数 | N |
| 平均サイクル時間 | X h |
| 最大サイクル時間 | X h |
| 中央値サイクル時間 | X h |
| 平均初回レビュー待ち時間 | X h |
| 平均 CI 所要時間 | X h |
| 総追加行数 | N |
| 総削除行数 | N |

## PR 別詳細

| PR | Issue | タイトル | 総時間 | 初回レビュー | CI | +行 | -行 |
|---|---|---|---|---|---|---|---|
| #N | #N | （PR タイトル） | Xh | Xh | Xh | N | N |

## エージェント・トークン消費（ブランチ別）

総トークン: input=N / output=N / cache_creation=N / cache_read=N
サブエージェント呼び出し合計（sidechain）: N

| ブランチ | Issue | セッション数 | input | output | cache_creation | cache_read | sidechain |
|---|---|---|---|---|---|---|---|
| dev/N_summary | #N | N | N | N | N | N | N |

## モデル別集計

| モデル | input | output | cache_creation | cache_read | message数 |
|---|---|---|---|---|---|
| claude-opus-4-7 | N | N | N | N | N |
| claude-sonnet-4-6 | N | N | N | N | N |
| claude-haiku-4-5 | N | N | N | N | N |

## サブエージェント別呼び出し回数

| subagent_type | 呼び出し回数 |
|---|---|
| general-purpose | N |
| Explore | N |
| cfo | N |

## ボトルネック

- 最長サイクル: PR #N (Xh)
  - 初回レビュー: Xh
  - CI: Xh

## 関連

- `docs/cost-analysis.md`（実測値で補正する前提データ）
- `/audit-cost`（本レポートを参照する CFO 監査スキル）
- Issue #353（本スキル新設の根拠）

## 生データ

実行スクリプトは `/cycle-metrics` スキル（vibecorp プラグイン同梱）が内部で呼び出す。配置先で個別に手動実行する想定はないため、本テンプレートは `/cycle-metrics` 実行時に生成された出力を貼り付ける用途で使用する。

- PR メトリクス JSON: vibecorp プラグインの `skills/cycle-metrics/fetch-pr-metrics.sh` 出力（`/cycle-metrics` 実行時に生成）
- Agent メトリクス JSON: vibecorp プラグインの `skills/cycle-metrics/fetch-agent-metrics.sh` 出力（同上）
