# Plugin 名前空間への移行ガイド

## 概要

vibecorp v0.2.0 より、全スキルが Claude Code 公式 Plugin 名前空間 `/vibecorp:xxx` で呼び出せるようになった。
v0.3.0 で `.claude/skills/` の互換スタブが廃止され、Plugin 形式に一本化された。

## 変更点

| 項目 | v0.1.x | v0.2.0（Phase 2） | v0.3.0（Phase 3） |
|------|--------|-------------------|-------------------|
| スキル呼び出し | `/ship` | `/vibecorp:ship` | `/vibecorp:ship` |
| スキル本体 | `.claude/skills/` | `skills/`（プラグインルート） | `skills/`（プラグインルート） |
| `.claude/skills/` | スキル本体 | 互換スタブ | **廃止** |
| プラグインメタデータ | なし | `.claude-plugin/plugin.json` | `.claude-plugin/plugin.json` |

## 移行手順

### 既存プロジェクトの場合

```bash
# install.sh --update で自動移行
bash /path/to/vibecorp/install.sh --update
```

`--update` を実行すると以下が自動で行われる:

1. `skills/` にプラグインスキルがコピーされる
2. `.claude-plugin/plugin.json` が配置される
3. `.claude/skills/` の旧スタブが自動クリーンアップされる（v0.3.0 以降）

### 旧コマンド名（`/ship` 等）について

v0.3.0 で互換スタブが廃止されたため、旧コマンド名（`/ship`、`/autopilot` 等）は使用できない。
`/vibecorp:ship`、`/vibecorp:autopilot` 等の Plugin 名前空間形式を使用すること。

## ディレクトリ構成

```text
project-root/
├── .claude-plugin/
│   └── plugin.json          # プラグインメタデータ
├── skills/                   # プラグインスキル本体（/vibecorp:xxx で呼び出し）
│   ├── ship/
│   │   └── SKILL.md
│   ├── review/
│   │   └── SKILL.md
│   └── ...
├── .claude/
│   ├── hooks/
│   ├── agents/
│   ├── rules/
│   └── ...
```

## `$CLAUDE_PROJECT_DIR` について

現時点では `$CLAUDE_PROJECT_DIR` を維持している。`claude plugin install` コマンドが安定した段階で `$CLAUDE_PLUGIN_ROOT` への移行を検討する。

## 関連

- Issue #352（Phase 1 実機検証）
- Issue #358（Phase 2 全面移行）
- Issue #359（Phase 3 互換レイヤ廃止）
- `.claude-plugin/plugin.json`
