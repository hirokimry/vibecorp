# 実装計画: Issue #41 — mvv.md パス表記の不一致修正

## 概要

`rules/mvv.md` のパス表記 `/MVV.md`（先頭スラッシュ付き）が、`vibecorp.yml` の `protected_files` 等で使われている `MVV.md`（相対パス）と不一致。統一する。

## 影響範囲

| ファイル | 現状 | 修正後 |
|---------|------|--------|
| `.claude/rules/mvv.md` | `/MVV.md` | `MVV.md` |
| `templates/claude/rules/mvv.md` | `/MVV.md` | `MVV.md` |

## タスク

### Phase 1: パス表記の修正

1. `.claude/rules/mvv.md` の1行目 `/MVV.md` → `MVV.md` に変更
2. `templates/claude/rules/mvv.md` の1行目 `/MVV.md` → `MVV.md` に変更

### テスト項目

- 修正後のファイルに `/MVV.md` が残っていないこと
- `vibecorp.yml` の `protected_files` と表記が一致していること
- 他のファイルで `MVV.md` を参照している箇所に影響がないこと

## 懸念事項

- 特になし。単純な文字列置換で完結する修正
