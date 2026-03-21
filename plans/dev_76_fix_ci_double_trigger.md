# 実装計画: CI push/pull_request 二重発火修正

## 概要

Issue #76: `.github/workflows/test.yml` の `push` トリガーが全ブランチで発火するため、PR ブランチへの push 時に `push` と `pull_request` の2つの run が同時起動する。`concurrency.cancel-in-progress: true` により古い方がキャンセルされ、PR 画面に常に ❌ が表示される問題を修正する。

## 影響範囲

- `.github/workflows/test.yml` （1ファイルのみ）

## タスク

### Phase 1: ワークフロー修正

- `push` トリガーに `branches: [main]` を追加
- `pull_request` トリガーはそのまま維持

**変更前:**

```yaml
on:
  push:
  pull_request:
```

**変更後:**

```yaml
on:
  push:
    branches: [main]
  pull_request:
```

**テスト項目:**
- YAML 構文が正しいこと（`yamllint` または手動確認）
- 既存テスト（`tests/test_*.sh`）が引き続きパスすること

## 懸念事項

- なし。Branch Protection で main への直接 push は禁止済みのため、main への push は PR マージ時のみ発火する
