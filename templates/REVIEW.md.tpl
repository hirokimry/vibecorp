この PR のコードレビューを実施してください。以下の手順に必ず順番で従ってください。途中で停止せず、最後の Step 7 まで実行してください。

**重要**: 修正対象が 0 件でも必ず `gh pr review --approve` を発行してください。何もせず終了することは禁止です。

## Step 1: PR 差分を取得する

`Bash` ツールで以下を実行してください:

```bash
gh pr diff "$PR_NUMBER" --repo "$GITHUB_REPOSITORY"
```

差分が大きい場合は変更ファイル一覧と主要変更点を把握してください。skip rules（後述）に該当するファイルは無視してください。

## Step 2: PR の intent ラベルを取得する

```bash
gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json labels --jq '[.labels[].name | select(startswith("intent/"))]'
```

このラベルは Step 4 の修正対象判定で使います。

## Step 3: 各変更箇所を severity 5 段階で判定する

`.claude/rules/severity/claude-action.md` の Critical / Major / Minor / Trivial / Info 定義に従って判定してください。

判定観点（intent 別）は `.claude/rules/review-observations.md` を参照してください。

## Step 4: 修正対象を確定する

`.claude/rules/review-handling.md` の捌き基準に従ってください:

- 🔴 Critical / 🟠 Major — intent 問わず必ず修正対象
- 🟡 Minor / 🔵 Trivial / ⚪ Info — PR の intent に該当する重視軸の指摘のみ修正対象（重視軸外は管轄外として除外）

## Step 5: 修正対象の各指摘を inline comment で投稿する

`mcp__github_inline_comment__create_inline_comment` ツールを使ってください。各コメントの本文先頭に severity を絵文字で示してください:

| 絵文字 | severity |
|--------|---------|
| 🔴 | Critical |
| 🟠 | Major |
| 🟡 | Minor |
| 🔵 | Trivial |
| ⚪ | Info |

修正対象が 0 件なら本ステップをスキップして Step 6 に進んでください。

## Step 6: 全体観察を top-level コメントで投稿する（任意）

PR 全体に対する観察やまとめを投稿したい場合のみ実行してください:

```bash
gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "..."
```

## Step 7: approve / request_changes を発行する（必須）

修正対象の件数で発行を分岐してください。**この Step は必須、スキップ禁止**:

| 修正対象の件数 | 発行コマンド |
|---|---|
| **0 件**（修正対象なし） | `gh pr review "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --approve --body "✅ 修正対象なし。AI レビュー approve します。"` |
| **1 件以上** | `gh pr review "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --request-changes --body "⚠️ 修正対象が N 件あります。インラインコメントを参照してください。"` |

## Step 8: 認証エラー時のフォールバック

`gh pr review` が Bot 認証エラーで失敗した場合（PAT / GitHub App token が無効・期限切れ等）:

```bash
gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "⚠️ Bot 認証エラーで gh pr review が発行できませんでした。人間 approve が必要です。詳細は docs/ai-review-auth.md を参照してください。"
```

approve / request_changes は発行しない（Branch Protection の required_approvals に委ねる）。

## Step 9: 挙動不変性確認で誤分類検出時

`intent/refactor` / `intent/infra` / `intent/docs`（影響を与えない系）の PR で **挙動が変わる変更** を検出した場合（公開 API リネーム、ランタイム挙動変更、サンプルコードへの依存等、`review-observations.md` の「挙動不変性の確認」観点参照）:

```bash
gh pr review "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --request-changes --body "⚠️ これは現在の intent/<label> ラベルではなく、intent/feature または intent/bugfix で扱うべき変更です。intent ラベルを再分類してから再 push してください。詳細は .claude/rules/intent-labels.md と .claude/rules/review-observations.md を参照。"
```

---

## レビュー言語

レビューコメント（インラインコメント / approve コメント / request_changes コメント / 一般コメント）は全て **{{LANGUAGE}}** で出力してください。

## skip rules

以下のパスは AI レビュー対象外です（vibecorp.yml の `claude_action.skip_paths` から自動反映）:

{{SKIP_PATHS_BLOCK}}

これらのパスへの変更については Step 5 / Step 6 でコメントを投稿しないでください。

## auto-resolve（インクリメンタルレビュー）

push 毎の再レビューでは:

- **dismiss 対象**: claude-action 自身が過去に出したインラインコメントのみ。CodeRabbit / 人間レビュアーのコメントは絶対に触らない（越権行為禁止）
- **dismiss タイミング**: 該当行が修正されたと判定したコメントだけを dismiss する。push 時の一括 dismiss はしない
- **インクリメンタルレビュー**: 前回レビュー以降の差分だけを対象とする。PR 全体の再レビューはコスト節約のため行わない

---

## このファイルの責務

このファイルは `anthropics/claude-code-action` が PR レビュー実行時に読み込むプロンプトです。`.github/workflows/ai-review.yml` の `prompt:` 入力としてそのまま渡されます。冒頭から命令文で開始することで、Claude が action item として認識して tool 呼び出しに進む構造になっています。

実体ルール（severity 定義、捌き基準、レビュー観点）は `.claude/rules/` 配下が Source of Truth であり、このファイルからは参照のみ行います。

## 関連設定

- 認証経路: `docs/ai-review-auth.md`
- ワークフロー: `.github/workflows/ai-review.yml`
- vibecorp.yml: `claude_action.enabled` / `claude_action.skip_paths`
- severity 定義: `.claude/rules/severity/claude-action.md`
- 捌き基準: `.claude/rules/review-handling.md`
- 観点定義: `.claude/rules/review-observations.md`
- intent ラベル: `.claude/rules/intent-labels.md`
