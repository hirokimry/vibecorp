---
description: 作業ブランチに残された knowledge 差分を knowledge/buffer 経由で main に救済する手順
---

> [!IMPORTANT]
> 本ガイドは **🛠️ vibecorp 導入リポジトリの管理者・運用者** が読者。
> Issue #439 のガードレール導入後に残った `.claude/knowledge/` 差分を救済できるようになる。
> 機密情報スキャン込みで安全に main へ反映する。
> 旧 buffer worktree 構造・audit-log 旧構造・cycle-metrics 旧パスからの移行も網羅する。

# 📦 作業ブランチに残された knowledge 差分の救済手順

Issue #439 のガードレール導入後に残った `.claude/knowledge/` 差分を救済する。

- 対象は `.claude/knowledge/{role}/decisions/` や `{role}/audit-log/` の差分。
- `knowledge/buffer` 経由で main に反映する手順を定める。

> [!NOTE]
> Issue #442 で監査ログ構造が変更された。
> 旧: `audit-*.md` フラット → 新: `{role}/audit-log/YYYY-QN.md` 四半期集約。
> 新構造では `protect-knowledge-direct-writes.sh` が `.claude/knowledge/*/audit-log/*.md` を deny する。

## 🧭 状況

例: `dev/247` などの作業ブランチで以下のような差分が放置されている。

```text
M .claude/knowledge/cfo/decisions-index.md
M .claude/knowledge/cfo/decisions/2026-Q2.md
M .claude/knowledge/sm/decisions-index.md
M .claude/knowledge/sm/decisions/2026-Q2.md
```

これらは Issue #439 のガードレール（`protect-knowledge-direct-writes.sh`）導入前に作業ブランチへ直書きされた残置差分である。

- 新規の編集は hook により deny されるようになった。
- 既存の差分は救済が必要である。

## 🚑 救済手順

> [!WARNING]
> 手順は ステップ 1 → 7 の順に実行する。
> 番号と順序を守らないと、機密情報の流出・差分の取りこぼし・データロストが起きる可能性がある。

### ステップ 1: 差分を一時保存

```bash
git stash push -m "knowledge migration $(date +%Y-%m-%d)" -- '.claude/knowledge/'
```

### ステップ 2: 機密情報スキャン（必須）

stash 内に API キー・トークン・認証情報が誤って含まれていないか確認する。

> [!WARNING]
> `knowledge/buffer` ブランチは origin に push される。
> 機密情報の混入は重大なインシデントになる。

```bash
# 目視確認（人間の目）
git stash show -p stash@{0} -- .claude/knowledge/

# 推奨: gitleaks で自動検出
# brew install gitleaks
gitleaks detect --source <(git stash show -p stash@{0}) --no-git
```

機密情報が含まれていた場合の対応:

- buffer に流さない。
- 当該行を削除した patch を作り直す、または機密箇所のみ手動編集してから再 stash する。

### ステップ 3: buffer worktree を最新化

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_ensure
BUFFER_DIR="$(knowledge_buffer_worktree_dir)"
echo "BUFFER_DIR=$BUFFER_DIR"
```

### ステップ 4: stash 内容を buffer に展開

| 優先度 | 方法 | 採用条件 |
|---|---|---|
| 1 | 方法 A: patch を抽出して buffer に apply | まず方法 A を試す |
| 2 | 方法 B: 個別ファイルを cp | 方法 A が失敗した場合のみ |

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

機密情報スキャン通過 + buffer 反映確認の **両方** が済んだ後に stash を破棄する。

```bash
git stash drop stash@{0}
```

### ステップ 7: knowledge-pr で main に反映

```bash
/vibecorp:knowledge-pr
```

`/vibecorp:knowledge-pr` が起動すると、buffer の差分が以下の流れで main に反映されるようになる。

- Issue を起票する。
- PR を作成する。
- auto-merge で main にマージする。

## 🛠️ トラブルシューティング

### `apply --3way` がコンフリクトする

buffer worktree に既に同名ファイルが存在し、内容が衝突している場合に発生する。

- 手動で内容を確認してマージする。
- または方法 B（個別 cp）で 1 ファイルずつ展開する。

### `knowledge_buffer_ensure` が失敗する

`origin/main` の fetch が失敗、または worktree のロックが残っている可能性がある。

以下を確認する。

```bash
git fetch origin main
git worktree prune
ls -la "$BUFFER_DIR/.buffer.lock.d"  # ロックディレクトリが残っていないか
```

ロックが残っている場合は手動削除する（プロセスが既に終了していることを確認してから）。

```bash
rm -rf "$BUFFER_DIR/.buffer.lock.d"
```

### `decisions/` や `{role}/audit-log/` に直書きしようとして deny される

> [!NOTE]
> これは Issue #439 で導入した `protect-knowledge-direct-writes.sh` フックの **正しい挙動** である。

本ドキュメントの手順に従い、必ず buffer worktree 経由で書き込むこと。

スキル経由の場合は以下を使う。

| スキル | 用途 |
|---|---|
| `/vibecorp:session-harvest` | セッション中の知見 |
| `/vibecorp:review-harvest` | マージ済み PR のレビュー指摘 |
| `/vibecorp:sync-edit` | sync-check で検出された不整合の修正 |
| `/vibecorp:audit-cost` | CFO 監査 |
| `/vibecorp:audit-security` | CISO 監査 |

## 🔄 buffer worktree 旧構造からの自動 migration（Issue #543）

PR #344（2026-04-18）で `knowledge_buffer.sh` が以下の構造変更を行った。

| 状態 | パス |
|---|---|
| 旧 | `~/.cache/vibecorp/buffer-worktree/`（直下に worktree） |
| 新 | `~/.cache/vibecorp/buffer-worktree/<repo-id>/`（repo-id namespace） |

それ以前に作成された buffer worktree は新コードと整合しなかった。

- 新コードが期待する場所と異なるパスに置かれていた。
- `/sync-edit` / `/review-harvest` / `/knowledge-pr` が無音失敗していた。
- Issue #543 で `knowledge_buffer_ensure` に **自動 migration ロジック** を追加した。
- 旧構造を検出したら自動的に新構造へ移行するようになった。

### 自動 migration の動作

利用者が `/vibecorp:sync-edit` 等のスキルを実行すると `knowledge_buffer_ensure` が呼ばれる。

その内部で以下が自動で行われる。

1. `git worktree list --porcelain` で旧構造（`buffer-worktree/` 直下が worktree）を検出する。
2. **未 push commit がない** 場合のみ migrate を続行する。
3. `git worktree remove --force` で旧 worktree を解除する。
4. 旧 path 自体を削除する。
5. 新構造（`buffer-worktree/<repo-id>/`）で worktree を再作成する。

利用者は何もしなくても次回 skill 実行時に自動回復するようになった。

### 未 push commit がある場合（手動復旧）

旧 worktree に未 push の harvest commit が残っている場合の動作:

- データ保全のため migration は **強制中断** される。

stderr に以下のメッセージが出るようになっている。

```text
[knowledge-buffer] 旧構造 worktree に N 件の未 push commit があります: ~/.cache/vibecorp/buffer-worktree
[knowledge-buffer] データ保全のため migration を停止します
[knowledge-buffer] 復旧手順:
[knowledge-buffer]   1. cd ~/.cache/vibecorp/buffer-worktree
[knowledge-buffer]   2. git push origin knowledge/buffer
[knowledge-buffer]   3. 元のスキルを再実行
```

メッセージに従って未 push commit を push してから skill を再実行する。

- 自動 migration が走って新構造に移行するようになる。

### 確認方法

migration が成功したかは `git worktree list` で確認できる。

```bash
git worktree list
```

- 新構造（`<repo-id>` を含むパス）に worktree が登録されている。
- 旧構造（`<repo-id>` を含まないパス）が登録されていない。

両方を満たせば migration 完了。

## 📚 audit-log 構造移行（Issue #442）

audit-log の配置構造を変更した。

- 旧: `accounting/audit-YYYY-MM-DD.md`（フラット直置き）。
- 新: `accounting/audit-log/YYYY-QN.md`（四半期集約）。

### 旧 → 新の対応

| 旧パス | 新パス |
|---|---|
| `accounting/audit-2026-04-29.md` | `accounting/audit-log/2026-Q2.md`（追記） |
| `security/audit-log.md`（単一 append-only） | `security/audit-log/2026-Q2.md`（四半期で分割）|
| - | `accounting/audit-log/audit-log-index.md`（1 行サマリ索引） |
| - | `security/audit-log/audit-log-index.md` |
| - | `legal/audit-log/audit-log-index.md` |

四半期計算式: `(10#$month - 1) / 3 + 1`

- `10#` プレフィックスで 8 進数解釈を回避する。

### 既存 `security/audit-log.md` の git mv（履歴保全）

```bash
mkdir -p .claude/knowledge/security/audit-log
git mv .claude/knowledge/security/audit-log.md .claude/knowledge/security/audit-log/2026-Q2.md
git log --follow .claude/knowledge/security/audit-log/2026-Q2.md  # 履歴確認
```

### 新規 `audit-log-index.md` 作成（buffer 経由）

> [!WARNING]
> 新構造では hook deny 対象に `.claude/knowledge/*/audit-log/*.md`（glob）が含まれる。
> 作業ブランチでの直書きは不可。
> templates から buffer worktree にコピーする。

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

## 📊 cycle-metrics 出力先移行（Issue #442）

| 状態 | パス | 管理 |
|---|---|---|
| 旧 | `.claude/knowledge/accounting/cycle-metrics-YYYY-MM-DD.md` | git 管理下 |
| 新 | `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/YYYY-MM-DD.md` | 揮発・`XDG_CACHE_HOME` 配下 |

### 旧パス参照を探す

```bash
grep -rn 'cycle-metrics-' --include='*.sh' --include='*.md' --include='*.py'
```

### 「ファイルが見つからない」と気づいた開発者向け

> [!NOTE]
> 旧パス `.claude/knowledge/accounting/cycle-metrics-*.md` は **削除された**。
> 新パスは `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/`（git 管理外）。

過去のメトリクスデータは git history から取得できる。

```bash
git log --all --oneline -- '.claude/knowledge/accounting/cycle-metrics-*.md'
```

新パスの場所は以下で取得する。

```bash
. .claude/lib/common.sh
echo "$(vibecorp_state_dir)/cycle-metrics/"
```

## 🆘 C\*O フォールバック判断記録の救済（Issue #439 設計判断 5）

C\*O / 分析員エージェントが `BUFFER_DIR` 取得に失敗した場合の挙動:

- 判断内容は **所定のヘッダー名で呼出元に返却される**。

呼出元スキルがこれを検知して結果レポートに転記し、ユーザーに手動反映を促す。

### ヘッダー名（厳格指定）

```text
### 判断記録（記録先取得失敗）
```

> [!WARNING]
> バリエーション禁止。
> 半角カッコ（`(`）や別語句（`フォールバック判断記録`）は検知漏れになる。
> 見出しレベル変更（`##`）等も全て検知漏れになる。
> エージェントは正確にこの文字列のみを出力する。

### 検知の仕組み

呼出元スキルは agent 出力に対して以下で検知する。

対象: `/vibecorp:audit-cost` / `/vibecorp:audit-security` / `/vibecorp:sync-edit`。

```bash
if echo "$agent_output" | grep -q '^### 判断記録（記録先取得失敗）$'; then
  # 結果レポートに「⚠️ 手動反映が必要な判断記録」ブロックとして転記
fi
```

### ユーザー側の手動反映手順

呼出元スキルから「⚠️ 手動反映が必要な判断記録」ブロックが返ってきた場合の対応:

- 本ドキュメント冒頭の「救済手順」（ステップ 1〜7）に従って判断記録を buffer 経由で main に反映する。
- stash の代わりに、エージェント出力の `### 判断記録（記録先取得失敗）` 配下のテキストを `~/.cache/vibecorp/buffer-worktree/<repo-id>/.claude/knowledge/{role}/decisions/{YYYY-QN}.md` に手動で追記する。
- index 更新後 `knowledge_buffer_commit` + `knowledge_buffer_push` + `/vibecorp:knowledge-pr` で main に反映する。

### 設計意図

| 観点 | 意図 |
|---|---|
| **無言データロスト回避** | BUFFER_DIR 取得失敗時に判断記録を捨てない。ヘッダー付きで返すことで人間が必ず気づける |
| **検知の機械化** | 呼出元スキルが grep で確実に検知できるよう、ヘッダー文字列を完全一致で固定している |
