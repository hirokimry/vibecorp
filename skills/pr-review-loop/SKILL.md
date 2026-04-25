---
name: pr-review-loop
description: "PRの未解決コメントをマージされるまで定期的に修正し続ける。内部で /loop 5m /pr-review-fix を実行する。「/pr-review-loop」「レビュー対応して」「PRレビュー修正して」と言った時に使用。"
---

# PRレビュー修正ループ

`/vibecorp:pr-review-fix` を5分間隔で定期実行し、PRがマージされるまで指摘対応を繰り返す。
ユーザーは1回指示するだけで、あとは放置できる。

## 使用方法

```bash
/vibecorp:pr-review-loop                    # 現在のブランチのPRを対象に開始
```

## 動作

以下を内部で実行する:

```bash
/loop 5m /vibecorp:pr-review-fix
```

- 5分間隔で `/vibecorp:pr-review-fix` が起動される
- 各回は PR の現在の状態を取得し、未解決コメントまたは CI 失敗があれば修正→push→終了
- PR がマージ済みなら「マージ完了」で終了
- `/vibecorp:pr-review-fix` が「未解決 0 件 かつ CI green」を達成した時点で GitHub auto-merge が自動マージ
- `/vibecorp:pr-review-fix` が外部要因 CI 失敗を検知した場合は CEO にエスカレーション
- セッションが続く限り自動で繰り返す

## 制約

- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する（[根拠](docs/design-philosophy.md#jq-string-interpolation-の禁止)）
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
