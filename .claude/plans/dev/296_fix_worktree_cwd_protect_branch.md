---
issue: 296
branch: dev/296_fix_worktree_cwd_protect_branch
title: protect-branch.sh の worktree 誤検知修正（teammate cwd 問題の根本対応）
---

# 実装計画: protect-branch.sh の worktree 誤検知修正

## 概要

`/ship --worktree <path>` で起動した teammate が Write/Edit を呼ぶと、`protect-branch.sh` が cwd（main repo）の `git branch --show-current` を見て main と判定し、worktree 内の編集を deny してしまう。

CTO 設計レビュー（option 1 採用）に基づき、**Edit/Write は対象ファイルパスから worktree を判定**、**Bash は file_path がないため判定不能 → cwd 基準維持（既知制限として明記）**する形で根本対応する。

## ガードレール変更に関する承認

`.claude/hooks/protect-branch.sh` および `templates/claude/hooks/protect-branch.sh` は `autonomous-restrictions.md` セクション4「ガードレール」に該当する自律実行不可領域。本計画は **CEO（ユーザー）からの明示的な指示で `/ship` 経由で人間主導実装** されるため、同ファイル末尾「人間承認ルート」に該当し、自律実行禁止の制約には抵触しない。

## 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `.claude/hooks/protect-branch.sh` | file_path から worktree を引いて `git -C` で判定、サニタイズ・上限ガード・deny メッセージ拡張 |
| `templates/claude/hooks/protect-branch.sh` | 同上（公開テンプレート同期） |
| `tests/test_protect_branch.sh` | worktree シナリオのテスト追加、`run_hook` ヘルパー拡張、両ファイル diff チェック |
| `docs/known-limitations.md`（新規） | Bash 検出の cwd 依存を既知制限として明記 |

## 設計方針

### 採用案: Option 1（CTO 承認済）

- **Edit/Write**: `tool_input.file_path` を取り、その親ディレクトリを `git -C` の対象にしてブランチを取得する
- **Bash**: `tool_input.command` には対象ファイルパスがないため、worktree を確実に推定できない
  - 既存の cwd 基準の判定を維持（main repo の cwd を見るため、worktree 内 git commit は deny されるが、`/commit` スキルが `cd <path> && git commit` 形式で実行する想定）
  - `tool_input.command` 内の `git -C <path>` パターンを抽出する拡張は将来課題（本 Issue では対象外）

### 入力サニタイズ・パストラバーサル対策

`file_path` には任意のパス（`../../../etc/passwd`、`~/foo`、相対パス、repo 外絶対パス、空文字、null 等）が渡され得る。以下のルールで安全に処理する:

1. 空文字、`null`、`~` 始まり → `CHECK_DIR="."` フォールバック（安全側 deny）
2. `realpath` で正規化し、`CLAUDE_PROJECT_DIR` および既知 worktree ルート配下に収まらない場合は `CHECK_DIR="."` フォールバック（安全側 deny）
3. 親ディレクトリ遡及ループは **最大 10 階層** で打ち切る（深さ制限）
4. ループ終了時に実在ディレクトリが見つからなければ `CHECK_DIR="."` フォールバック（安全側 deny）
5. **`ALLOWED_ROOT` が `/` または空の場合**（`realpath` 失敗または `CLAUDE_PROJECT_DIR` がルート直下のとき）→ サニタイズ機能無効化を避けるため `CHECK_DIR="."` 強制フォールバック（安全側 deny）

「既知 worktree ルート」は以下のいずれかで判定:
- `git rev-parse --show-toplevel` を `CLAUDE_PROJECT_DIR` 上で実行 → main repo の root
- `git -C "$CLAUDE_PROJECT_DIR" worktree list --porcelain` の出力から各 worktree path を抽出

ただし `git worktree list` は I/O が増えるため、簡略化として **「`realpath` 後のパスが `realpath $CLAUDE_PROJECT_DIR/..` の配下にある」場合のみ許可** する方針を採用（worktree は通常 `<project>.worktrees/...` のように親ディレクトリの兄弟として作られるため）。これで誤検知を許容範囲に保ちつつ、`/etc/passwd` 等の完全な repo 外参照を弾ける。

### 判定ロジック疑似コード

```bash
# 既知ルートの上限（main repo の親ディレクトリ）
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
ALLOWED_ROOT=$(realpath "$CLAUDE_PROJECT_DIR/.." 2>/dev/null || echo "")

CHECK_DIR="."
# ALLOWED_ROOT が空 or "/" の場合はサニタイズ無効化を避けて常時フォールバック
if [ -n "$ALLOWED_ROOT" ] && [ "$ALLOWED_ROOT" != "/" ]; then
  if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
    TARGET_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

    # 空文字 / ~ 始まり / null は安全側にフォールバック
    if [ -n "$TARGET_PATH" ] && [ "${TARGET_PATH#\~}" = "$TARGET_PATH" ]; then
      # 親ディレクトリを遡る（最大 10 階層）
      PARENT_DIR=$(dirname "$TARGET_PATH")
      DEPTH=0
      while [ ! -d "$PARENT_DIR" ] && [ "$PARENT_DIR" != "/" ] && [ "$PARENT_DIR" != "." ] && [ "$DEPTH" -lt 10 ]; do
        PARENT_DIR=$(dirname "$PARENT_DIR")
        DEPTH=$((DEPTH + 1))
      done

      if [ -d "$PARENT_DIR" ]; then
        # realpath で正規化し、ALLOWED_ROOT 配下にあることを検証
        RESOLVED=$(realpath "$PARENT_DIR" 2>/dev/null || echo "")
        case "$RESOLVED/" in
          "$ALLOWED_ROOT"/*) CHECK_DIR="$RESOLVED" ;;
          *) CHECK_DIR="." ;;  # repo 外 → 安全側 deny
        esac
      fi
    fi
  fi
fi

CURRENT_BRANCH=$(git -C "$CHECK_DIR" branch --show-current 2>/dev/null || echo "")
```

### deny メッセージ拡張

既存の `deny()` は `permissionDecisionReason` にブランチ名のみを含む。これを拡張して以下を含める:

- 判定対象 tool (`Edit` / `Write` / `Bash`)
- 判定に使った `CHECK_DIR`
- 判定されたブランチ名

```bash
deny() {
  local tool="${TOOL_NAME:-unknown}"
  local check_dir="${CHECK_DIR:-.}"
  jq -n \
    --arg branch "$BASE_BRANCH" \
    --arg tool "$tool" \
    --arg check_dir "$check_dir" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ($branch + " ブランチでは直接作業できません。フィーチャーブランチを作成してください。 [tool=" + $tool + ", check_dir=" + $check_dir + "]")
      }
    }'
  exit 0
}
```

これにより teammate が deny を受けた際、worktree 判定の失敗（`check_dir=.`）か正当な main 判定かが識別できる。

### 副作用評価

- **正常系（main session, main repo の Edit）**: file_path は repo 内の絶対/相対パス → realpath で `ALLOWED_ROOT` 配下と確認 → `git -C` で同 repo を見る → 既存挙動と同一
- **worktree teammate（worktree 内ファイル Edit）**: file_path は worktree 内 → realpath で `ALLOWED_ROOT` 配下と確認 → `git -C` で worktree のブランチ（`dev/...`）を取得 → allow
- **存在しないファイル新規作成**: 親ディレクトリを最大 10 階層遡って実在ディレクトリを見つけて判定
- **repo 外パス・パストラバーサル**: `ALLOWED_ROOT` 配下に収まらない → `CHECK_DIR="."` でフォールバック → 安全側で deny
- **vibecorp.yml 不在 worktree**: `CLAUDE_PROJECT_DIR` ベースで base_branch 取得は変更しない（main repo の vibecorp.yml を信頼）

## Phase 分け

### Phase 1: `.claude/hooks/protect-branch.sh` を修正

**タスク:**
- 21行目の `git branch --show-current` 呼び出し直前に、上記疑似コードのロジック（サニタイズ・遡及・realpath 検証・上限ガード）を挿入
- `CURRENT_BRANCH=$(git -C "$CHECK_DIR" branch --show-current ...)` に変更
- `deny()` 関数を拡張し、tool 名と check_dir を `permissionDecisionReason` に含める
- ヘッダーコメントに既知制限（Bash の cwd 依存）を1〜2行で追記
- `realpath` の可搬性確認: macOS 標準環境（`/bin/bash` 3.2）で `realpath` コマンドが利用可能かを `which realpath` で確認。利用不可なら `cd "$dir" && pwd -P` の代替実装に切り替える

**テスト項目:**
- `bash tests/test_protect_branch.sh` を実行し、既存 22 ケースが全 PASS すること
- worktree 新規ケース（Phase 3 で追加）も PASS すること
- macOS bash 3.2 環境（`bash --version` で 3.2.x を確認）で全テストが PASS すること

### Phase 2: `templates/claude/hooks/protect-branch.sh` を同期

**タスク:**
- Phase 1 と同一の修正を `templates/claude/hooks/protect-branch.sh` にも適用
- `diff .claude/hooks/protect-branch.sh templates/claude/hooks/protect-branch.sh` が exit 0（同一）になることを確認

**テスト項目:**
- `tests/test_protect_branch.sh` の `HOOKS_DIR` は templates/ を参照しているため、Phase 1 のテストでカバーされる
- `.claude/hooks/` 版も独立検証するため、Phase 3 で diff チェックテストを追加

### Phase 3: worktree シナリオのテスト追加

**`run_hook` ヘルパーの修正:**

既存の `run_hook` は `GIT_DIR="${TMPDIR_ROOT}/.git"` を環境変数で渡している。`GIT_DIR` は `git -C` より優先されるため、worktree テストでは `git -C` が無視されてしまう。

→ **既存 `run_hook` の `GIT_DIR` 指定を削除し、代わりに `cd "$TMPDIR_ROOT" && bash "$HOOKS_DIR/protect-branch.sh"` 形式に変更する。**worktree 用の追加 helper は不要（cd 方式で main repo・worktree 両方が同じ仕組みで動く）。

```bash
run_hook() {
  ( cd "$TMPDIR_ROOT" && bash "$HOOKS_DIR/protect-branch.sh" )
}
```

**テスト22（CLAUDE_PROJECT_DIR 未設定時）の修正:**

既存テスト22は `cd "$EMPTY_DIR" && GIT_DIR=... bash hook` で起動していた。`GIT_DIR` 削除に伴い、以下のように書き換える:

```bash
# 22. CLAUDE_PROJECT_DIR 未設定 → デフォルト "." で動作
unset CLAUDE_PROJECT_DIR
EMPTY_DIR=$(mktemp -d)
git init "$EMPTY_DIR" >/dev/null 2>&1
git -C "$EMPTY_DIR" config user.name "Test" >/dev/null 2>&1
git -C "$EMPTY_DIR" config user.email "test@example.com" >/dev/null 2>&1
git -C "$EMPTY_DIR" commit --allow-empty -m "init" >/dev/null 2>&1
set +e
OUTPUT=$(cd "$EMPTY_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | bash "$HOOKS_DIR/protect-branch.sh" 2>/dev/null)
EXIT_CODE=$?
set -e
rm -rf "$EMPTY_DIR"
# CLAUDE_PROJECT_DIR が未設定でも異常終了しないことだけを確認
if [ "$EXIT_CODE" = "0" ]; then
  pass "CLAUDE_PROJECT_DIR 未設定時に異常終了しない"
else
  fail "CLAUDE_PROJECT_DIR 未設定時に異常終了しない (exit $EXIT_CODE)"
fi
export CLAUDE_PROJECT_DIR="$TMPDIR_ROOT"
```

`EMPTY_DIR` を git 初期化することで、フックが `git -C` を呼んだ際にエラーにならない（`git rev-parse` 失敗で hook が異常終了するのを防ぐ）。

**追加テストケース（疑似コード付き）:**

WT-2 は「worktree が base_branch にいるときに deny される」を実証するため、`vibecorp.yml` に `base_branch: develop` を設定し、main repo は `dev/test` ブランチ、worktree は `develop` ブランチで作成する。これにより「worktree のブランチが base_branch と一致 → deny」を直接検証できる。

```bash
setup_worktree() {
  local worktree_path="$1"
  local branch="$2"
  if ! git -C "$TMPDIR_ROOT" worktree add -B "$branch" "$worktree_path" >/dev/null 2>&1; then
    echo "  ERROR: worktree セットアップ失敗 (branch=$branch, path=$worktree_path)" >&2
    exit 1
  fi
}

# --- worktree シナリオ専用セットアップ ---
# main repo を dev/test ブランチに、別 worktree を develop ブランチで作成
write_vibecorp_yml_with_base() {
  local base="$1"
  cat > "${TMPDIR_ROOT}/.claude/vibecorp.yml" <<YAML
name: test-project
base_branch: ${base}
YAML
}

WORKTREE_DEV="${TMPDIR_ROOT}.wt/dev_test"
WORKTREE_BASE="${TMPDIR_ROOT}.wt/base_test"

# --- 全 worktree テストの開始時に main repo を main ブランチ・base_branch=main にリセット ---
write_vibecorp_yml  # base_branch: main
switch_to_branch main

# WT-1: worktree が dev ブランチ → 内部ファイル Edit → allow
setup_worktree "$WORKTREE_DEV" "dev/test_branch"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_DEV/src/app.ts\"}}" | run_hook)
assert_allowed "worktree dev ブランチ内 Edit → allow（main repo は main）" "$OUTPUT"

# WT-2: worktree が base_branch（develop）→ 内部ファイル Edit → deny
write_vibecorp_yml_with_base develop
switch_to_branch dev/main_test  # main repo は dev/main_test
setup_worktree "$WORKTREE_BASE" "develop"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_BASE/src/app.ts\"}}" | run_hook)
assert_blocked "worktree が base_branch(develop) → 内部 Edit → deny" "$OUTPUT"
write_vibecorp_yml  # base_branch を main に戻す
switch_to_branch main

# WT-3: 存在しないファイル新規作成（親ディレクトリ遡及）→ worktree なら allow
# 注意: WORKTREE_DEV は WT-1 で setup_worktree 済みのため実在する。
# new/dir/ サブディレクトリは存在しないため遡及ロジックで WORKTREE_DEV まで戻る → dev/test_branch と判定 → allow
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$WORKTREE_DEV/new/dir/file.ts\"}}" | run_hook)
assert_allowed "worktree 内の新規パス Edit（遡及）→ allow" "$OUTPUT"

# WT-4: repo 外絶対パス → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/etc/passwd"}}' | run_hook)
assert_blocked "repo 外絶対パス Edit → 安全側 deny" "$OUTPUT"

# WT-5: ~ 始まりパス → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"~/foo/bar.ts"}}' | run_hook)
assert_blocked "~ 始まり file_path → 安全側 deny" "$OUTPUT"

# WT-6: 深いパストラバーサル → 安全側 deny
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR_ROOT/../../../etc/passwd\"}}" | run_hook)
assert_blocked "パストラバーサル Edit → 安全側 deny" "$OUTPUT"

# WT-7: 空文字 file_path → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":""}}' | run_hook)
assert_blocked "空文字 file_path → 安全側 deny" "$OUTPUT"

# WT-8: file_path キー欠落 → 安全側 deny
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{}}' | run_hook)
assert_blocked "file_path キー欠落 → 安全側 deny" "$OUTPUT"

# WT-9: deny 出力に tool=Edit / check_dir が含まれる（main session で Edit）
# main repo が main ブランチ（base_branch=main と一致）なので Edit は deny される。
# その deny メッセージに tool=Edit と check_dir= が含まれることを検証する。
switch_to_branch main
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' | run_hook)
if echo "$OUTPUT" | grep -q 'tool=Edit' && echo "$OUTPUT" | grep -q 'check_dir='; then
  pass "deny メッセージに tool=Edit / check_dir= が含まれる"
else
  fail "deny メッセージに tool / check_dir が含まれない"
fi

# WT-10: Bash 経由 git commit の deny メッセージに tool=Bash が含まれる
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | run_hook)
if echo "$OUTPUT" | grep -q 'tool=Bash'; then
  pass "Bash deny メッセージに tool=Bash が含まれる"
else
  fail "Bash deny メッセージに tool=Bash が含まれない"
fi

# WT-11: ALLOWED_ROOT が "/" になるエッジケース → 安全側 deny
# CLAUDE_PROJECT_DIR=/ では realpath /.. が "/" を返す
SAVED_CLAUDE_DIR="$CLAUDE_PROJECT_DIR"
export CLAUDE_PROJECT_DIR="/"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR_ROOT/src/app.ts\"}}" | run_hook)
assert_blocked "ALLOWED_ROOT=/ のエッジケース → 安全側 deny" "$OUTPUT"
export CLAUDE_PROJECT_DIR="$SAVED_CLAUDE_DIR"
```

**diff チェックテスト:**

実行ディレクトリへの依存を排除するため `REPO_ROOT` を絶対パスで導出する:

```bash
# DIFF-1: .claude/hooks/ と templates/claude/hooks/ が同期されていること
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if diff -q "$REPO_ROOT/.claude/hooks/protect-branch.sh" "$REPO_ROOT/templates/claude/hooks/protect-branch.sh" >/dev/null 2>&1; then
  pass ".claude/hooks/ と templates/claude/hooks/ の protect-branch.sh が同期"
else
  fail ".claude/hooks/ と templates/claude/hooks/ の protect-branch.sh が差分あり"
fi
```

**cleanup 拡張:**

`git worktree remove` と `rm -rf` の二重処理は冗長。`rm -rf` だけで worktree のファイルツリーは削除でき、main repo 側の `.git/worktrees/<name>` メタデータは git の prune で自然に消える（次回 `git worktree list` 時にチェック・削除）。テスト用の使い捨て repo なので prune 対応は不要。

```bash
cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT" "${TMPDIR_ROOT}.wt" || true
  fi
}
```

**テスト項目:**
- 既存 22 ケース + worktree 11 ケース + diff 1 ケース = 計 34 ケースが全 PASS
- `run_hook` ヘルパー変更後も既存 22 ケースが non-regression（特に GIT_DIR 削除と cd 方式変更による影響を確認）
- macOS bash 3.2 環境（`/bin/bash --version` で確認）で `bash tests/test_protect_branch.sh` が全 PASS すること

### Phase 4: 既知制限のドキュメント化

**タスク:**
- `docs/known-limitations.md`（新規）に以下のセクションを追加:
  - 「protect-branch.sh の Bash 検出は cwd 依存」
  - 説明: teammate が `/commit` スキルを使わず素の `git commit` を実行した場合、worktree であっても main repo の cwd を見るため deny される可能性がある
  - 識別方法: deny メッセージの `[tool=Bash, check_dir=.]` で判別
  - 回避策: `cd <worktree> && git commit ...` または `git -C <worktree> commit ...`
- `protect-branch.sh` のヘッダーコメントにも上記制限を1〜2行で記載

**テスト項目:**
- `grep -q "protect-branch.sh の Bash 検出は cwd 依存" docs/known-limitations.md` が成功すること

## 完了条件

- [ ] `.claude/hooks/protect-branch.sh` が file_path 基準で worktree を判定（サニタイズ・上限ガード・deny 拡張済）
- [ ] `templates/claude/hooks/protect-branch.sh` も同一修正（diff 0）
- [ ] `tests/test_protect_branch.sh` に worktree テスト 11 ケース（WT-1〜WT-11）+ diff 1 ケース追加・全 PASS
- [ ] Bash の cwd 依存を `docs/known-limitations.md` に既知制限として明記
- [ ] 既存 22 ケースが non-regression（合計 34 ケース全 PASS）
- [ ] macOS bash 3.2 環境で全テストが PASS

## 懸念事項

1. **vibecorp.yml の base_branch が worktree と main repo で異なるケース**
   - 通常 worktree は同 repo から派生するため `.claude/vibecorp.yml` は同一内容（rsync 済）
   - `CLAUDE_PROJECT_DIR` を main repo 側に固定したまま `git -C` を worktree に向けるため、base_branch 設定は main repo のものを使う → 整合性 OK

2. **シンボリックリンク・特殊パス**
   - file_path がシンボリックリンクの場合 `realpath` で正規化される → `ALLOWED_ROOT` 配下判定は実体ベースで行う
   - macOS の `/private/tmp` ↔ `/tmp` 等のシンボリックリンク差異も `realpath` で吸収される

3. **Bash 検出制限の運用影響**
   - teammate は `/commit` スキル経由で `cd <path> && git commit` を呼ぶ前提
   - 素の `git commit` を直叩きするケースは想定しない（スキル使用ルール `rules/use-skills.md` で担保）
   - deny メッセージで `tool=Bash` が確認できるため、誤判定時の調査が可能

4. **複数 worktree の同時 Edit（並列実行）**
   - 各 Edit ごとに `git -C` で個別判定する
   - `git branch --show-current` は read-only 操作（`HEAD` ファイルの読み込みのみ）で write lock を取得しないため、並列 worktree でも競合しない
   - `git -C` 自体のオーバーヘッドは < 10ms 程度で、teammate 体感レイテンシに影響しない

5. **`realpath` の可搬性**
   - macOS 標準には `realpath` がない場合がある（GNU coreutils が必要）
   - 代替として `python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))"` または `cd "$dir" && pwd -P` を使う
   - 実装時に macOS bash 3.2 環境で動作確認する

6. **既存 Bash sed 分割バイパス（範囲外）**
   - security-analyst の指摘 (`sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g'` が quote 内区切りを無視しない問題) は既存問題であり本 Issue 範囲外
   - 別 Issue として後続化する（本実装後にフォローアップ Issue を起票）

## 関連

- Issue #296（本 Issue）
- Issue #258（teammate Bash compound command 制限）
- PR #292（発覚契機）
- CTO レビュー: option 1 採用、Bash の cwd 依存は既知制限として残す
- 計画レビュー（plan-review-loop）: 7 専門家エージェントの指摘を反映済（パストラバーサル対策・上限ガード・deny 拡張・テスト整合性）
