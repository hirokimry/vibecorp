# Issue 駆動ワークフロー

Issue 対応は以下の順序で進める:

1. `develop` を pull して最新化
2. `dev/{Issue番号}_{要約}` ブランチを作成
3. plan mode で設計
4. Issue 本文を設計内容で更新（設計を本文に残す）
5. 実装
6. PR 作成

## ブランチ命名規約

| 種別 | パターン | 例 |
|------|---------|-----|
| 通常 Issue | `dev/{Issue番号}_{要約}` | `dev/123_add_login` |
| 親エピック（feature ブランチ） | `feature/epic-{Issue番号}_{要約}` | `feature/epic-345_plan_epic_skill` |
| エピック配下の子 Issue | `dev/{Issue番号}_{要約}` | `dev/346_ship_epic_child` |

- 親エピックの feature ブランチは `/plan-epic` が作成する（full プリセット専用）
- 子 Issue のブランチは通常の `dev/` 命名に従うが、PR の base は親 feature ブランチとなる（`/ship` が自動判定する）
- 要約は英語スネークケース 2〜4 語

## Issue の使い方

- Issue の本文は設計の記録場所。設計・仕様に関する内容は本文を編集する
- 実装完了報告やチェックリストをコメントに書かない
- 進捗報告的なコメントは書かない

## PR 本文の Issue リンク（auto-close キーワード）

PR 本文には GitHub の auto-close キーワードを **必ず `#N` 形式** で記載する。`.github/workflows/close-on-feature-merge.yml` が `(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+` のみを抽出対象とするため、URL 形式（例: `close https://github.com/.../issues/N`）では feature ブランチへのマージ時に Issue が auto-close されない。

| 用途 | 書式 | 動作 |
|------|------|------|
| 子 Issue / 通常 Issue を close する | `Closes #N` | PR が main にマージされると Issue が auto-close される（feature ブランチ運用では `close-on-feature-merge.yml` が代行する） |
| 親エピック Issue を参照するだけ | `Refs #N` | auto-close 対象外（暴発防止）。親エピックは `/vibecorp:release-epic` のリリース PR で `Closes #<親番号>` により最終的に close される |

### 運用ルール

- 子 Issue / 通常 Issue 用 PR（`/vibecorp:ship` で作成）→ PR 本文に `Closes #<Issue 番号>` を必ず記載する
- 親エピック用リリース PR（`/vibecorp:release-epic` で作成）→ PR 本文に `Closes #<親エピック番号>` を記載する
- 子 Issue 本文から親エピックを参照する場合 → `Refs #<親エピック番号>`（auto-close 対象外）
- 既存の `📍 関連` セクション（人間向けナビゲーション）は維持しつつ、必ず `Closes #N` または `Refs #N` 行を併記する
- `Fixes #N` / `Resolves #N` の同義キーワードは使わず、`Closes` に統一する（一貫性のため）

### 根拠

- `.github/workflows/close-on-feature-merge.yml` が `close[sd]?` / `fix(es|ed)?` / `resolve[sd]?` のみを抽出対象とし、`Refs` / `Related to` は意図的に除外している（暴発防止）
- GitHub 公式: <https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue>

## 言語

- 回答・コード内コメント・ログメッセージ・エラーメッセージは全て日本語で書く
- 変数名・関数名は英語のままでよい
- 仕様書が英語で書かれていても、実装は日本語で統一する
