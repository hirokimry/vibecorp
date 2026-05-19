⚠️ PR 本文に対応 Issue への参照が見つかりませんでした

## 🎯 検知内容

- PR 本文を走査しましたが、Issue 参照キーワードが含まれていませんでした
- vibecorp は Issue 経由起票必須の運用です
- このままでは PR がマージできません

## 🛠️ 必要な対応

PR 本文に対応 Issue を参照するキーワードを 1 行以上追加し、再 push してください。

受理されるキーワードは以下のとおりです。

| キーワード | 例 | 動作 |
|------------|------|------|
| `Closes #N` | `Closes #123` | マージ時に Issue を auto-close する |
| `Fixes #N` / `Fixed #N` | `Fixes #123` | マージ時に Issue を auto-close する |
| `Resolves #N` / `Resolved #N` | `Resolves #123` | マージ時に Issue を auto-close する |
| `Refs #N` | `Refs #123` | 参照のみ（auto-close しない） |

GitHub Issue URL 形式（`Closes https://github.com/<owner>/<repo>/issues/N`）も受理されます。

## 📍 根拠

- 運用判断: Issue #469 残 #5（Issue 経由起票必須）
- intent ラベル定義: `.claude/rules/intent-labels.md`
- CC prefix 厳格定義: `docs/conventional-commits.md`
