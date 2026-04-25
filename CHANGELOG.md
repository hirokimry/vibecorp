# Changelog

## [0.3.0] - 2026-04-25

### ⚠️ 破壊的変更

- `.claude/skills/` の互換スタブが廃止された。旧コマンド名（`/ship`、`/autopilot` 等）は動作しなくなり、Plugin 名前空間（`/vibecorp:ship`、`/vibecorp:autopilot` 等）のみ使用可能になった
- `install.sh --update` を実行すると、既存プロジェクトの `.claude/skills/` 互換スタブが自動クリーンアップされる（ユーザーが独自に追加したスキルは残る）

### 削除

- `install.sh` から互換スタブ自動生成ロジックを削除

## [0.1.0] - 2026-03-28

### 初期リリース

- install.sh による 3 プリセット対応（minimal, standard, full）
- hooks, skills, agents, rules, knowledge テンプレート
- vibecorp.yml / vibecorp.lock によるプロジェクト設定管理
- settings.json のマージ管理（vibecorp 由来フックのみ操作）
- 3-way マージによるアップデート時のコンフリクト解消
- CodeRabbit 連携設定
- GitHub Branch Protection 自動設定
