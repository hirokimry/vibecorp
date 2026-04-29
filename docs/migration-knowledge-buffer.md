# 作業ブランチに残された knowledge 差分の救済手順

Issue #439 のガードレール導入後、作業ブランチに残ってしまった `.claude/knowledge/{role}/decisions/` や `{role}/audit-log/` の差分を `knowledge/buffer` 経由で main に反映する手順。

> Issue #442 で監査ログ構造が `audit-*.md` フラット → `{role}/audit-log/YYYY-QN.md` 四半期集約に変更されました。新構造では `protect-knowledge-direct-writes.sh` が `.claude/knowledge/*/audit-log/*.md`（glob）を deny 対象に含みます。

## 状況

例: dev/247 などの作業ブランチで以下のような差分が放置されている。

```text
M .claude/knowledge/cfo/decisions-index.md
M .claude/knowledge/cfo/decisions/2026-Q2.md
M .claude/knowledge/sm/decisions-index.md
M .claude/knowledge/sm/decisions/2026-Q2.md
```

これらは Issue #439 のガードレール (`protect-knowledge-direct-writes.sh`) 導入前に作業ブランチへ直書きされた残置差分です。新規の編集は hook により deny されますが、既存の差分は救済が必要です。

## 救済手順

### ステップ 1: 差分を一時保存

```bash
git stash push -m "knowledge migration $(date +%Y-%m-%d)" -- '.claude/knowledge/'
```

### ステップ 2: 機密情報スキャン（必須）

stash 内に API キー・トークン・認証情報が誤って含まれていないか確認する。**`knowledge/buffer` ブランチは origin に push されるため、機密情報の混入は重大なインシデントになる**。

```bash
# 目視確認（人間の目）
git stash show -p stash@{0} -- .claude/knowledge/

# 推奨: gitleaks で自動検出
# brew install gitleaks
gitleaks detect --source <(git stash show -p stash@{0}) --no-git
```

機密情報が含まれていた場合は **buffer に流さず**、当該行を削除した patch を作り直すか、機密箇所のみ手動編集してから再 stash する。

### ステップ 3: buffer worktree を最新化

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_ensure
BUFFER_DIR="$(knowledge_buffer_worktree_dir)"
echo "BUFFER_DIR=$BUFFER_DIR"
```

### ステップ 4: stash 内容を buffer に展開

**優先順位**: まず方法 A（patch apply）を試し、コンフリクト等で失敗した場合のみ方法 B（個別 cp）にフォールバックする。

#### 方法 A: patch を抽出して buffer に apply（推奨・最初に試す）

```bash
# mktemp で予測不能な一時ファイル名を使う（/tmp 直書きで他プロセスに改ざんされないよう）
patch_file="$(mktemp -t vibecorp-knowledge-migration.XXXXXX.patch)"
trap 'rm -f "$patch_file"' EXIT
git stash show -p stash@{0} -- .claude/knowledge/ > "$patch_file"

# apply 直前の最終スキャン（必須・ステップ 2 とは独立した最終確認）
gitleaks detect --source "$patch_file" --no-git || {
  echo "[migration] apply 直前スキャンで機密情報を検出。手順を中止します" >&2
  exit 1
}

# apply
git -C "$BUFFER_DIR" apply --3way "$patch_file"
```

#### 方法 B: 個別ファイルを cp（方法 A が失敗した場合のみ）

```bash
# 影響ファイルの確認
git stash show stash@{0} --name-only -- .claude/knowledge/

# 個別に展開
git checkout stash@{0} -- .claude/knowledge/cfo/decisions/2026-Q2.md
mkdir -p "${BUFFER_DIR}/.claude/knowledge/cfo/decisions"
cp .claude/knowledge/cfo/decisions/2026-Q2.md "${BUFFER_DIR}/.claude/knowledge/cfo/decisions/"

# 作業ブランチ側を綺麗に戻す
git restore --staged --worktree -- .claude/knowledge/
```

### ステップ 5: buffer に commit + push

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_commit "chore(knowledge): migrate stash from dev/<branch>"
knowledge_buffer_push
```

### ステップ 6: stash を破棄

機密情報スキャン通過 + buffer 反映確認後に stash を破棄する。

```bash
git stash drop stash@{0}
```

### ステップ 7: knowledge-pr で main に反映

```bash
/vibecorp:knowledge-pr
```

これにより buffer の差分が Issue 起票 → PR 作成 → auto-merge で main に反映される。

## トラブルシューティング

### `apply --3way` がコンフリクトする

buffer worktree に既に同名ファイルが存在し、内容が衝突している場合に発生。
手動で内容を確認してマージするか、方法 B（個別 cp）で 1 ファイルずつ展開する。

### `knowledge_buffer_ensure` が失敗する

`origin/main` の fetch が失敗、または worktree のロックが残っている可能性。
以下を確認する。

```bash
git fetch origin main
git worktree prune
ls -la "$BUFFER_DIR/.buffer.lock.d"  # ロックディレクトリが残っていないか
```

ロックが残っている場合は手動削除（プロセスが既に終了していることを確認してから）:

```bash
rm -rf "$BUFFER_DIR/.buffer.lock.d"
```

### `decisions/` や `{role}/audit-log/` に直書きしようとして deny される

これは Issue #439 で導入した `protect-knowledge-direct-writes.sh` フックの正しい挙動です。
本ドキュメントの手順に従い、必ず buffer worktree 経由で書き込んでください。

スキル経由の場合は以下を使ってください。

- `/vibecorp:session-harvest`（セッション中の知見）
- `/vibecorp:review-harvest`（マージ済み PR のレビュー指摘）
- `/vibecorp:sync-edit`（sync-check で検出された不整合の修正）
- `/vibecorp:audit-cost` / `/vibecorp:audit-security`（CFO / CISO 監査）

## audit-log 構造移行（Issue #442）

旧構造 `accounting/audit-YYYY-MM-DD.md` フラット直置き → 新構造 `accounting/audit-log/YYYY-QN.md` 四半期集約。

### 旧 → 新の対応

| 旧パス | 新パス |
|---|---|
| `accounting/audit-2026-04-29.md` | `accounting/audit-log/2026-Q2.md`（追記） |
| `security/audit-log.md`（単一 append-only） | `security/audit-log/2026-Q2.md`（四半期で分割）|
| - | `accounting/audit-log/audit-log-index.md`（1 行サマリ索引） |
| - | `security/audit-log/audit-log-index.md` |
| - | `legal/audit-log/audit-log-index.md` |

四半期計算: `(10#$month - 1) / 3 + 1` で算出（`10#` プレフィックスで 8 進数解釈を回避）。

### 既存 `security/audit-log.md` の git mv（履歴保全）

```bash
mkdir -p .claude/knowledge/security/audit-log
git mv .claude/knowledge/security/audit-log.md .claude/knowledge/security/audit-log/2026-Q2.md
git log --follow .claude/knowledge/security/audit-log/2026-Q2.md  # 履歴確認
```

### 新規 audit-log-index.md 作成（buffer 経由）

新構造では hook deny 対象に `.claude/knowledge/*/audit-log/*.md`（glob）が含まれるため、作業ブランチでの直書きは不可。templates から buffer worktree にコピーする。

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_ensure
BUFFER_DIR="$(knowledge_buffer_worktree_dir)"

for role in accounting security legal; do
  mkdir -p "${BUFFER_DIR}/.claude/knowledge/${role}/audit-log"
  cp templates/claude/knowledge/${role}/audit-log/audit-log-index.md \
     "${BUFFER_DIR}/.claude/knowledge/${role}/audit-log/audit-log-index.md"
done

knowledge_buffer_commit "chore(knowledge): audit-log/ 配下に audit-log-index.md を配置"
knowledge_buffer_push
```

その後 `/vibecorp:knowledge-pr` で main に反映する。

## cycle-metrics 出力先移行（Issue #442）

旧パス `.claude/knowledge/accounting/cycle-metrics-YYYY-MM-DD.md`（git 管理下）→ 新パス `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/YYYY-MM-DD.md`（揮発・XDG_CACHE_HOME 配下）。

### 旧パス参照を探す

```bash
grep -rn 'cycle-metrics-' --include='*.sh' --include='*.md' --include='*.py'
```

### 「ファイルが見つからない」と気づいた開発者向け

旧パス `.claude/knowledge/accounting/cycle-metrics-*.md` は **削除されました**。新パスは `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/`（git 管理外）。

過去のメトリクスデータは git history から取得可能:

```bash
git log --all --oneline -- '.claude/knowledge/accounting/cycle-metrics-*.md'
```

新パスの場所を取得:

```bash
. .claude/lib/common.sh
echo "$(vibecorp_state_dir)/cycle-metrics/"
```
