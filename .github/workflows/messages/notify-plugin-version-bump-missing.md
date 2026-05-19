⚠️ プラグインの `version` bump 漏れを検知しました

## 🎯 検知内容

- `.claude-plugin/marketplace.json` の `plugins[0].skills` が変更されました
- `.claude-plugin/plugin.json` の `version` は据え置かれています
- このままでは利用者が新しいスキルを取得できなくなります

## 🛠️ 必要な対応

マージ前に `.claude-plugin/plugin.json` の `version` を bump してください。

| 操作 | 内容 |
|------|------|
| 編集 | `.claude-plugin/plugin.json` の `version` を SemVer で 1 段上げる |
| 再 push | 同一ブランチに force push 不要、通常 push で本チェックが再実行される |

## 📍 根拠

- 取りこぼし防止の経緯: PR #459
- 本チェックの位置づけ: 警告のみ・非ブロック（マージ自体は阻害しません）
