# Changelog

## [0.1.1] - 2026-03-31

### 🐛 バグ修正
- release.yml のタグ既存時・変更なし時のエラーハンドリング (#165) (d24b683)

## [0.1.0] - 2026-03-28

### 初期リリース

- install.sh による 3 プリセット対応（minimal, standard, full）
- hooks, skills, agents, rules, knowledge テンプレート
- vibecorp.yml / vibecorp.lock によるプロジェクト設定管理
- settings.json のマージ管理（vibecorp 由来フックのみ操作）
- 3-way マージによるアップデート時のコンフリクト解消
- CodeRabbit 連携設定
- GitHub Branch Protection 自動設定
