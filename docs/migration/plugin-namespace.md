# Plugin 名前空間への移行ガイド

## 概要

vibecorp v0.2.0 より、全スキルが Claude Code 公式 Plugin 名前空間 `/vibecorp:xxx` で呼び出せるようになった。

## 変更点

| 項目 | Before | After |
|------|--------|-------|
| スキル呼び出し | `/ship` | `/vibecorp:ship` |
| スキル本体の配置先 | `.claude/skills/` | `skills/`（プラグインルート） |
| `.claude/skills/` の役割 | スキル本体 | 互換スタブ（リダイレクト） |
| プラグインメタデータ | なし | `.claude-plugin/plugin.json` |

## 移行手順

### 既存プロジェクトの場合

```bash
# install.sh --update で自動移行
source /path/to/vibecorp/install.sh --update
```

`--update` を実行すると以下が自動で行われる:

1. `skills/` にプラグインスキルがコピーされる
2. `.claude-plugin/plugin.json` が配置される
3. `.claude/skills/` のスタブが更新される（旧スキル本体 → リダイレクトスタブ）

### 互換性

- 旧名称 `/ship` は `.claude/skills/` のスタブが `/vibecorp:ship` へリダイレクトする
- 既存のカスタマイズ（SKILL.md の編集）は `--update` の 3-way マージで保持される
- `vibecorp.yml` の設定は変更不要

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
│   ├── skills/               # 互換スタブ（/xxx → /vibecorp:xxx へリダイレクト）
│   │   ├── ship/
│   │   │   └── SKILL.md     # "このスキルは /vibecorp:ship に移行しました"
│   │   └── ...
│   └── ...
```

## `$CLAUDE_PROJECT_DIR` について

現時点では `$CLAUDE_PROJECT_DIR` を維持している。`claude plugin install` コマンドが安定した段階で `$CLAUDE_PLUGIN_ROOT` への移行を検討する。

## 関連

- Issue #358
- `.claude-plugin/plugin.json`
