---
name: audit-security
description: >
  CISO による月次セキュリティ監査。直近30日間の変更から脆弱性・認証変更を分析し、
  `knowledge/security/audit-log/YYYY-QN.md` に追記 + `audit-log-index.md` に 1 行サマリ追記する。full プリセット限定。
  「/vibecorp:audit-security」「セキュリティ監査」と言った時に使用。
---

**ultrathink**

# /vibecorp:audit-security: 月次セキュリティ監査

CISO エージェントによる月次セキュリティ監査を自動化する。直近1ヶ月の変更から脆弱性・認証変更を分析し、監査レポートを `knowledge/security/` に保存する。脆弱性検出時は Issue を起票する。

## 前提条件

- **full プリセット専用**（CISO エージェントが必要）
- CISO エージェント定義（`.claude/agents/ciso.md`）が配置済み
- `knowledge/security/security-audit-template.md` が存在

## ワークフロー

### 1. プリセット確認

```bash
awk '/^preset:[[:space:]]*/ { sub(/^preset:[[:space:]]*/, ""); print; exit }' .claude/vibecorp.yml
```

`full` 以外の場合は「/vibecorp:audit-security は full プリセット専用です」と報告して終了する。

### 1.5. buffer worktree の準備

監査レポートは `knowledge/buffer` worktree 経由で main に反映する（`docs/specification.md` の「自動反映フロー」原則）。作業ブランチへの直書きは `protect-knowledge-direct-writes.sh` フックで deny される。

```bash
. "$CLAUDE_PROJECT_DIR/.claude/lib/knowledge_buffer.sh"
knowledge_buffer_ensure || { echo "[audit-security] buffer 準備失敗。作業ブランチへの直書きはフックで deny されるため処理を中止" >&2; exit 1; }
knowledge_buffer_lock_acquire || { echo "[audit-security] ロック取得失敗（${VIBECORP_LOCK_TIMEOUT:-60}s）" >&2; exit 2; }
trap knowledge_buffer_lock_release EXIT
BUFFER_DIR="$(knowledge_buffer_worktree_dir)"
```

### 2. 監査範囲取得

直近30日間の変更を取得する:

```bash
git log --since="30 days ago" --oneline
git diff "@{30 days ago}"..HEAD --stat
```

コミット数が0件の場合は「監査対象期間に変更なし」とレポートし、空の監査ファイルを生成して終了する。

### 3. CISO エージェント起動

CISO エージェントに以下を渡して起動する（Agent ツール）:

```text
あなたは CISO として、直近1ヶ月のコード変更に対するセキュリティ監査を実施してください。

## buffer worktree（必須・判断記録の書込先）
BUFFER_DIR=${BUFFER_DIR}

判断記録は `${BUFFER_DIR}/.claude/knowledge/ciso/` および `${BUFFER_DIR}/.claude/knowledge/security/` 配下に書いてください（作業ブランチへの直書きはフックで deny されます）。

## 監査範囲
git commit range: @{30 days ago}..HEAD

## 変更内容
{git log / git diff の内容}

## 観点
1. 認証・認可ロジックの変更（auth, permission, token 扱い）
2. 新規依存パッケージの追加（package.json / requirements.txt / go.mod）
3. hooks のガードレール変更（protect-files.sh, diagnose-guard.sh 等）
4. secrets / credentials 扱い箇所の変更（ANTHROPIC_API_KEY, gh auth 等）
5. OWASP Top 10 該当変更の有無

## 参照ドキュメント
- docs/SECURITY.md
- rules/autonomous-restrictions.md
- knowledge/security/security-audit-template.md

## 出力
knowledge/security/security-audit-template.md の雛形に沿って監査結果を記述してください。
Critical / Major / Minor で指摘を分類してください。
OWASP Top 10 チェック表も埋めてください。
```

### 4. レポート保存（四半期集約 + index 追記）

CISO の出力を **buffer worktree 内** の `${BUFFER_DIR}/.claude/knowledge/security/audit-log/YYYY-QN.md` に **追記** する。さらに `audit-log-index.md` に 1 行サマリを追記する。

```bash
today=$(date -u +%Y-%m-%d)
year=$(date -u +%Y)
month=$(date -u +%m)
# 10#$month で 8 進数解釈を回避（08/09 が無効になる問題対策）
quarter=$(( (10#$month - 1) / 3 + 1 ))
target="${year}-Q${quarter}"

mkdir -p "${BUFFER_DIR}/.claude/knowledge/security/audit-log"
audit_file="${BUFFER_DIR}/.claude/knowledge/security/audit-log/${target}.md"
index_file="${BUFFER_DIR}/.claude/knowledge/security/audit-log/audit-log-index.md"

# 四半期ファイルがなければ初期化（初回作成時）
if [ ! -f "$audit_file" ]; then
  printf '# セキュリティ監査ログ — %s\n\n`/vibecorp:audit-security` および `security-analyst` 合議結果のアーカイブ。\n\n---\n\n' "$target" > "$audit_file"
fi

# index がなければ templates から初期化
if [ ! -f "$index_file" ]; then
  cp .claude/knowledge/security/audit-log/audit-log-index.md "$index_file" 2>/dev/null \
    || cp templates/claude/knowledge/security/audit-log/audit-log-index.md "$index_file"
fi
```

その後、CISO の出力内容を `${audit_file}` に統一書式（`## YYYY-MM-DD — Issue #N — /vibecorp:audit-security` 見出し）で追記し、`${index_file}` の `## 索引` セクション直後に 1 行サマリを追加する。

**追記書式**:

```markdown
## YYYY-MM-DD — Issue #N — /vibecorp:audit-security

### 監査範囲
（CISO 出力の本文）
```

**index 1 行サマリ書式**:

```markdown
- YYYY-MM-DD — Issue #N — `/vibecorp:audit-security` Critical N / Major N / Minor N
```

### 4.5. C*O フォールバック警告の検知

CISO の出力に `### 判断記録（記録先取得失敗）` セクションが含まれる場合、CISO の自前 buffer 取得が失敗している。判断内容を結果レポート末尾の「⚠️ 手動反映が必要な判断記録」ブロックに転記し、ユーザーに `docs/migration-knowledge-buffer.md` の手順での手動反映を促す。

```bash
# 現在実行分の CISO 出力のみを検査する。
# 四半期集約後は audit_file に過去 fallback エントリが残っている可能性があるため、
# audit_file 全体走査による誤検知を避ける。
if echo "$ciso_output" | grep -q '^### 判断記録（記録先取得失敗）$'; then
  fallback_warning=1
fi
```

### 4.6. buffer commit + push

`knowledge_buffer_commit` は差分なしを成功扱い（exit 0）するため `|| true` は不要。実際の git エラーを握り潰さないために、commit 失敗時は push を中止する。

```bash
push_status="success"
if ! knowledge_buffer_commit "chore(knowledge): audit-security ${today}"; then
  echo "[audit-security] commit 失敗。push は中止します。buffer 内容を確認してください: ${BUFFER_DIR}" >&2
  push_status="failed (commit 失敗)"
elif ! knowledge_buffer_push; then
  echo "[audit-security] push 失敗。commit は ${BUFFER_DIR} に保持。手動 push: git -C ${BUFFER_DIR} push origin knowledge/buffer" >&2
  push_status="failed (worktree に保持)"
fi
```

### 5. 脆弱性検出時の Issue 起票

Critical または Major 指摘がある場合、`/vibecorp:issue` スキルで Issue を起票する:

- ラベル: `audit`, `security`
- タイトルプレフィックス: `[audit-security]`
- 本文: 監査レポートのサマリ + レポートファイルへのリンク

Minor のみの場合は起票しない（レポート保存のみ）。

### 6. 結果レポート

```text
## /vibecorp:audit-security 完了

### 監査範囲
- 期間: YYYY-MM-DD 〜 YYYY-MM-DD
- コミット数: N
- 変更ファイル数: N

### 指摘サマリ
- Critical: N 件
- Major: N 件
- Minor: N 件

### OWASP Top 10 該当
- A01 / A02 / A03 / A07 / A08: あり / なし

### 出力
- レポート: ${BUFFER_DIR}/.claude/knowledge/security/audit-log/YYYY-QN.md（追記）
- index: ${BUFFER_DIR}/.claude/knowledge/security/audit-log/audit-log-index.md（1 行サマリ追記）
- 起票 Issue: {URL} / なし

### 出力ステータス
- レポート保存: 成功 / 失敗
- buffer commit: 成功 / 失敗（差分なしスキップ）
- buffer push: 成功 / 失敗（失敗時は ${BUFFER_DIR} に保持。手動 push 手順を出力）

### ⚠️ 手動反映が必要な判断記録（CISO フォールバック発動時のみ）
{CISO 出力の「### 判断記録（記録先取得失敗）」セクションをここに転記}
→ docs/migration-knowledge-buffer.md の手順で手動反映してください
```

## 定期実行

`/schedule` または cron で月次実行:

```bash
# 毎月1日 09:00 JST に実行
/schedule monthly "0 0 1 * *" /vibecorp:audit-security
```

## 制約

- **コード変更は一切行わない** — 監査レポートと Issue 起票のみ
- `git add` / `git commit` / `git push` は `knowledge_buffer_*` ヘルパー経由でのみ実行する（buffer worktree 内に限定）
- 作業ブランチには直書きしない（`protect-knowledge-direct-writes.sh` フックで deny される）
- `--force`、`--hard`、`--no-verify` は使用しない
- **jq では string interpolation `\(...)` を使わない** — 必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない
