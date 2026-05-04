# REVIEW.md

このリポジトリでの AI レビュー指示。`anthropics/claude-code-action` がレビュー実行時に参照する。

## レビュー言語

レビューコメントは **{{LANGUAGE}}** で出力してください。

## 判定基準・観点

レビューの severity 判定と捌き方は以下の Source of Truth を参照してください:

- `.claude/rules/severity/claude-action.md` — vibecorp の severity 5 段階定義（Critical / Major / Minor / Trivial / Info）
- `.claude/rules/review-handling.md` — intent × severity の捌き基準
- `.claude/rules/review-observations.md` — 各 intent のレビュー観点（挙動不変性の確認等を含む）

REVIEW.md 自体には実体ルールを書きません（実体は `.claude/rules/` 配下が SoT）。

## skip rules

以下のパスは AI レビュー対象外とします（vibecorp.yml の `claude_action.skip_paths` から自動反映）:

{{SKIP_PATHS_BLOCK}}

これらのパスへの変更については指摘・コメントを行わないでください。

## 関連設定

- 認証経路: `docs/ai-review-auth.md`
- ワークフロー: `.github/workflows/ai-review.yml`
- vibecorp.yml: `claude_action.enabled` / `claude_action.skip_paths`
