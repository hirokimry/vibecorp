# CodeRabbit 依存マップ

vibecorp の一部スキルは CodeRabbit に依存する。未導入でも基本機能は動作するが、一部のスキル・ステップがスキップまたは制限される。

## スキル別依存度

| スキル | 依存度 | 未導入時の挙動 |
|--------|--------|----------------|
| `/pr-review-loop` | **高** | スキップ（「対応不要」で即終了 + 案内表示） |
| `/review` | 部分 | `cr review --plain` がスキップされる。カスタムレビュアーのみ実行 |
| `/review-loop` | 間接 | `/review` 経由。cr CLI 不可時はカスタムレビュアーのみ |
| `/review-to-rules` | 部分 | CodeRabbit 指摘なし → 人間レビュアー指摘のみ対象 |
| `/ship` | 間接 | ステップ9（`/pr-review-loop`）がスキップ |
| `/pr` | なし | 影響なし |
| `/commit` | なし | 影響なし |
| `/branch` | なし | 影響なし |
| `/issue` | なし | 影響なし |
| `/plan` | なし | 影響なし |
| `/plan-review-loop` | なし | 影響なし |

## フォールバック挙動の詳細

### `/pr-review-loop`（依存度: 高）

CodeRabbit 未導入時は以下の流れになる:

1. ステップ 2.1（レビュー待ち）でコメント数が0のまま10分経過
2. **CodeRabbit 未導入と判断し、修正ループをスキップ**
3. auto-merge 状態を確認・設定
4. 結果報告に「CodeRabbit 未検出。Require approvals が有効な場合、人間による approve が必要です」と案内

修正ループが一度も回らないため、PR上のレビュー指摘修正は人間が手動で対応する前提になる。

### `/review`（依存度: 部分）

`cr` コマンドが利用できない場合:

- CodeRabbit CLI のレビューステップをスキップ
- レポートに「CodeRabbit CLI: 利用不可のためスキップ」と記載
- カスタムレビュアー（`vibecorp.yml` の `review.custom_commands`）があればそれのみ実行
- **カスタムレビュアーも未設定の場合、レビュー結果が0件になる**

### `/review-to-rules`（依存度: 部分）

- CodeRabbit 指摘の抽出はスキップ（`user.login` が CodeRabbit にマッチするコメントがない）
- **人間レビュアーの指摘は正常に収集・分析される**
- 人間レビュアーの指摘もない場合、「反映対象なし」で終了しスタンプを発行する

## Branch Protection との関係

### vibecorp 推奨構成（CodeRabbit あり）

```text
PR作成 → CodeRabbit 自動レビュー → approve → auto-merge → マージ
```

- **Require approvals**: ON（CodeRabbit の approve をゲートにする）
- **Required status checks**: `test`（CI 集約ジョブ）
- **Allow auto-merge**: ON

### CodeRabbit 未導入時

```text
PR作成 → auto-merge 設定 → 人間レビュー → 人間 approve → auto-merge → マージ
```

- **Require approvals**: ON のまま維持（人間の approve が必要）
- approve を外すと CI パスだけでマージされる＝レビューなしマージになるため非推奨
- auto-merge は人間の approve + CI パスで発動する

## CodeRabbit なしの実用ワークフロー

```text
/plan              → 計画策定
/review-loop       → ローカルレビュー（カスタムレビュアー or セルフ）
/commit            → コミット
/pr                → PR作成 + auto-merge 設定
                   → 人間がレビュー・approve
                   → auto-merge でマージ
```

`/pr-review-loop` と `/ship` のステップ9は実質スキップされるため、PR作成後は人間のワークフローに委ねる形になる。

## install.sh の挙動

`install.sh` は CodeRabbit の有無に関わらず動作する:

- `.coderabbit.yaml` テンプレートは配置するが、既存ファイルがあればスキップ
- Branch Protection の Required status checks に CodeRabbit を含めるかは `resolve_github_checks()` で判定
- CodeRabbit がない環境でもインストールは成功する
