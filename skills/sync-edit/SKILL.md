---
name: sync-edit
description: >
  /sync-check で検出された不整合を、各職種エージェントに委任して修正する。
  各エージェントは自分の管轄ファイルのみ編集する。
  「/sync-edit」と言った時に使用。
---

# sync-edit: 整合性修正（各職種が管轄のみ編集）

`/vibecorp:sync-check` で検出された不整合を、**各職種エージェントに委任して** 修正する。
各エージェントは **自分の管轄ファイルだけ** を編集する。

## 前提条件

- `/vibecorp:sync-check` が先に実行されていること
- sync-check の結果に ⚠️ または ❌ が含まれていること

## ワークフロー

### 0. buffer worktree の準備

C*O 委任編集の `.claude/knowledge/{role}/` 配下への書き込みは `knowledge/buffer` worktree 経由で行う（`docs/specification.md` の「自動反映フロー」原則）。作業ブランチへの直書きは `protect-knowledge-direct-writes.sh` フックで deny される。

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_ensure || { echo "[sync-edit] buffer 準備失敗。作業ブランチへの直書きはフックで deny されるため処理を中止" >&2; exit 1; }
knowledge_buffer_lock_acquire || { echo "[sync-edit] ロック取得失敗（${VIBECORP_LOCK_TIMEOUT:-60}s）" >&2; exit 2; }
trap knowledge_buffer_lock_release EXIT
BUFFER_DIR="$(knowledge_buffer_worktree_dir)"
```

なお `docs/` 配下（specification.md / design-philosophy.md / POLICY.md / cost-analysis.md / ai-organization.md）は本スキルの管轄では作業ブランチに書く（ドキュメントは PR 経由で main に直接反映する仕様）。`.claude/knowledge/{role}/` のみ buffer worktree 経由とする。

### 1. sync-check 結果の確認

直前の `/vibecorp:sync-check` の結果を参照し、修正が必要なファイルと担当エージェントを特定する。

### 2. 担当エージェントの起動

修正が必要な管轄を持つエージェントを **Agent ツールで順次起動** する（ロールファイルの競合防止）。

#### エージェントと管轄の対応

**デフォルト（CTO / CPO）:**

| エージェント | 管轄ファイル（書込先） | 編集権限 |
|-------------|------------|---------|
| CTO | `docs/specification.md`（技術スタック部分・作業ブランチ）、`.claude/rules/`（作業ブランチ）、`${BUFFER_DIR}/.claude/knowledge/cto/`（buffer worktree） | 管轄のみ |
| CPO | `docs/specification.md`（プロダクト仕様部分・作業ブランチ）、`${BUFFER_DIR}/.claude/knowledge/cpo/`（buffer worktree） | 管轄のみ |

**拡張時（上記に加えて追加可能）:**

| エージェント | 管轄ファイル（書込先） | 編集権限 |
|-------------|------------|---------|
| 法務 | `docs/POLICY.md`（作業ブランチ）、`${BUFFER_DIR}/.claude/knowledge/legal/`（buffer worktree） | 管轄のみ |
| 経理 | `docs/cost-analysis.md`（作業ブランチ）、`${BUFFER_DIR}/.claude/knowledge/accounting/`（buffer worktree） | 管轄のみ |
| SM | `docs/ai-organization.md`（作業ブランチ）、`${BUFFER_DIR}/.claude/knowledge/sm/`（buffer worktree） | 管轄のみ |

**knowledge/ の記事** は、内容の領域に応じて該当する職種エージェントが編集する。書込先は必ず `${BUFFER_DIR}` 配下（作業ブランチ直書きはフックで deny される）。

#### 起動方法

各エージェントに以下を渡して Agent ツールで起動する。
**重要**: 各エージェントは hooks による権限チェックを受けるため、ロール宣言が必須。

```text
あなたは {役職名} として、管轄ドキュメントの不整合を修正してください。

## buffer worktree（必須・knowledge/ 系の書込先）
BUFFER_DIR=${BUFFER_DIR}

`.claude/knowledge/{role}/` 配下を編集する場合は必ず `${BUFFER_DIR}/.claude/knowledge/{role}/` に書いてください（作業ブランチへの直書きはフックで deny されます）。
`docs/` 配下と `.claude/rules/` は作業ブランチに書いてください（PR 経由で main に直接反映）。

## 最初にやること（必須）
以下のコマンドを実行してロールを宣言してください。これにより管轄ファイルの編集権限が付与されます。

source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
stamp_dir="$(vibecorp_state_mkdir)"
echo "{role_id}" > "${stamp_dir}/agent-role"

role_id: cto / cpo / legal / accounting / sm

## あなたの管轄ファイル（書込先）
{管轄ファイルリスト・各ファイルの書込先（作業ブランチ or BUFFER_DIR）を明示}

## コード変更の差分
{git diff の内容}

## sync-check で検出された問題
{該当エージェントのチェック結果}

## 制約
- 管轄ファイルのみ編集すること。管轄外は hooks によりブロックされる
- knowledge/{role}/ 配下は ${BUFFER_DIR} 経由で書く（作業ブランチ直書きは protect-knowledge-direct-writes.sh で deny される）
- コード変更の内容をドキュメントに正確に反映する
- 既存の記述スタイル・フォーマットを維持する
- 過剰な加筆をしない。変更に関連する部分だけ更新する

## 終了時（必須）
編集完了後、ロールファイルを削除してください。

source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
rm -f "$(vibecorp_state_path agent-role)"

## 出力
- 編集したファイルと変更内容の要約
- knowledge/ 編集時に BUFFER_DIR 取得が失敗した場合は「### 判断記録（記録先取得失敗）」ヘッダで判断内容を返してください（ヘッダ名は厳格指定。バリエーション禁止）
```

**注意**: エージェントは順次起動すること（並列だとロールファイルが競合する）。

### 2.5. C*O フォールバック警告の検知

各エージェントの出力に `### 判断記録（記録先取得失敗）` セクションが含まれる場合、当該エージェントの knowledge/ 書込みが buffer 取得失敗で失敗している。判断内容を結果レポート末尾の「⚠️ 手動反映が必要な判断記録」ブロックに転記し、ユーザーに `docs/migration-knowledge-buffer.md` の手順での手動反映を促す。

ヘッダー名は厳格指定（バリエーション禁止）。検知は **アンカー付き grep**（行頭 `^` + 行末 `$`）で行うこと:

```bash
if echo "$agent_output" | grep -q '^### 判断記録（記録先取得失敗）$'; then
  # 結果レポートに「⚠️ 手動反映が必要な判断記録」ブロックとして転記
fi
```

### 2.6. buffer commit + push（C*O 全員完了後 1 回のみ）

`knowledge_buffer_commit` は差分なしを成功扱い（exit 0）するため `|| true` は不要。実際の git エラーを握り潰さないために、commit 失敗時は push を中止する。

```bash
push_status="success"
if ! knowledge_buffer_commit "chore(knowledge): sync-edit fixes $(date +%Y-%m-%d)"; then
  echo "[sync-edit] commit 失敗。push は中止します。buffer 内容を確認してください: ${BUFFER_DIR}" >&2
  push_status="failed (commit 失敗)"
elif ! knowledge_buffer_push; then
  echo "[sync-edit] push 失敗。commit は ${BUFFER_DIR} に保持。手動 push: git -C ${BUFFER_DIR} push origin knowledge/buffer" >&2
  push_status="failed (worktree に保持)"
fi
```

### 3. 結果の統合・レポート出力

全エージェントの修正結果を統合し、以下のフォーマットで出力する:

```text
## sync-edit 結果

### 修正内容

#### CTO（技術設計）
- docs/design-philosophy.md: {変更の要約}（作業ブランチ）
- ${BUFFER_DIR}/.claude/knowledge/cto/decisions.md: {変更の要約}（buffer worktree）

#### CPO（プロダクト）
- docs/specification.md: {変更の要約}（作業ブランチ）

#### 法務（拡張時のみ）
- docs/POLICY.md: {変更の要約}（作業ブランチ）

### 出力ステータス
- buffer commit: 成功 / 失敗（差分なしスキップ）
- buffer push: 成功 / 失敗（失敗時は ${BUFFER_DIR} に保持）

### ⚠️ 手動反映が必要な判断記録（フォールバック発動時のみ）
{各エージェントの「### 判断記録（記録先取得失敗）」セクションをここに転記}
→ docs/migration-knowledge-buffer.md の手順で手動反映してください

### 次のステップ
→ `/vibecorp:sync-check` を再実行して整合性を確認してください
```

### 4. 再チェックの案内

修正完了後、必ず `/vibecorp:sync-check` の再実行を案内する。
sync-edit 自身はスタンプを発行しない（スタンプは sync-check のみが発行する）。

## 制約

- **knowledge/ への書込みは buffer worktree 経由限定** — 作業ブランチへの直書きは `protect-knowledge-direct-writes.sh` フックで deny される
- `git add` / `git commit` / `git push` は `knowledge_buffer_*` ヘルパー経由でのみ実行する
- **jq では string interpolation `\(...)` を使わない** — Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
