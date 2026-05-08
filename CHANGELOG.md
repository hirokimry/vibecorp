# Changelog

## [Unreleased]

### 修正

- `knowledge_buffer.sh` の repo-id namespace 構造（PR #344）に旧構造で作られた buffer worktree が migration されない問題を修正 (#543)。`knowledge_buffer_ensure` 内で旧構造を自動検知し、未 push commit を保全しつつ新構造へ移行するようになった。利用者は次回 `/sync-edit` / `/review-harvest` / `/knowledge-pr` 実行時に自動回復する
- `install.sh --update` 実行で `.claude-plugin/plugin.json` の `version` がダウングレードする問題を修正 (#540, PR #542)。`templates/claude-plugin/plugin.json` を廃止し、リポジトリ直下の `.claude-plugin/plugin.json` を唯一の Source-of-Truth として直接コピーするようになった

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
