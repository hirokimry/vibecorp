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

## auto-resolve 動作（#466 確定）

push 毎の再レビューでは以下の方針に従ってください:

- **dismiss 対象**: claude-action 自身が過去に出したインラインコメントのみ。CodeRabbit / 人間レビュアーのコメントは絶対に触らない（越権行為禁止）
- **dismiss タイミング**: 該当行が修正されたと判定したコメントだけを dismiss する。push 時に古いコメントを一括 dismiss しない
- **インクリメンタルレビュー**: 前回レビュー以降の差分だけを対象とする。PR 全体の再レビューはコスト節約のため行わない
- 既に出したコメントは「修正済みなら dismiss」「未修正なら維持」を判定する

## approve / request_changes 発行ルール（#467 確定）

レビュー完了時、以下の判定に従って `gh pr review --approve` または `gh pr review --request-changes` を発行してください:

### 1. 修正対象判定

`.claude/rules/review-handling.md` の捌き基準に従って「修正対象」を判定する:

- **Critical / Major** — intent 問わず必ず修正対象
- **Minor / Trivial / Info** — PR の intent ラベルに該当する重視軸の指摘のみ修正対象（重視軸外は管轄外）

### 2. approve / request_changes の発行

| 修正対象の件数 | 発行コマンド |
|---|---|
| 1 件以上あり | `gh pr review --request-changes` |
| 0 件（修正対象なし） | `gh pr review --approve` |

### 3. 認証エラー時の挙動

`gh pr review` が Bot 認証エラー（PAT / GitHub App token が無効・期限切れ等）で失敗した場合:

- `approve` / `request_changes` は **発行しない**
- PR に「⚠️ Bot 認証エラーで `gh pr review` が発行できませんでした。人間 approve が必要です。詳細は `docs/ai-review-auth.md` を参照してください。」と警告コメントだけ投稿
- マージ可否の判定は GitHub Branch Protection（`required_approvals`）に委ねる

### 4. 挙動不変性確認で誤分類検出時の挙動

`intent/refactor` / `intent/infra` / `intent/docs`（影響を与えない系）の PR で **挙動が変わる変更** を検出した場合（公開 API リネーム、ランタイム挙動変更、サンプルコードへの依存等、`review-observations.md` の「挙動不変性の確認」観点参照）:

- `request_changes` を発行
- コメント: 「⚠️ これは現在の `intent/<label>` ラベルではなく、`intent/feature` または `intent/bugfix` で扱うべき変更です。intent ラベルを再分類してから再 push してください。詳細は `.claude/rules/intent-labels.md` と `.claude/rules/review-observations.md` を参照。」

PR 作成者がラベルを付け替えて push し直すと、再レビューで適切な severity 判定が行われる。

## 関連設定

- 認証経路: `docs/ai-review-auth.md`
- ワークフロー: `.github/workflows/ai-review.yml`
- vibecorp.yml: `claude_action.enabled` / `claude_action.skip_paths`
- 捌き基準: `.claude/rules/review-handling.md`
- 観点定義: `.claude/rules/review-observations.md`
- intent ラベル: `.claude/rules/intent-labels.md`
