#!/bin/bash
# test_worktree.sh — ワークツリー機能の統合テスト
# 使い方: bash tests/test_worktree.sh

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_dir_exists() {
  local desc="$1"
  local path="$2"
  if [ -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在しない: $path)"
  fi
}

assert_dir_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -d "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ディレクトリが存在する: $path)"
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在しない: $path)"
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
  fi
}

assert_command_output_contains() {
  local desc="$1"
  local pattern="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -q "$pattern"; then
    pass "$desc"
  else
    fail "$desc (出力にパターン '$pattern' が含まれない)"
  fi
}

# --- セットアップ / クリーンアップ ---

TMPDIR_ROOT=$(mktemp -d)
REPO_DIR="$TMPDIR_ROOT/test-project"
PROJECT_NAME="test-project"
WORKTREE_BASE="$TMPDIR_ROOT/${PROJECT_NAME}.worktrees"

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    # ワークツリーを全て削除してからディレクトリ削除
    if [ -d "$REPO_DIR/.git" ]; then
      git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null | grep "^worktree " | grep -v "$REPO_DIR\$" | sed 's/^worktree //' | while read -r wt; do
        git -C "$REPO_DIR" worktree remove --force "$wt" 2>/dev/null || true
      done || true
    fi
    rm -rf "$TMPDIR_ROOT"
  fi
}

trap cleanup EXIT

setup_test_repo() {
  mkdir -p "$REPO_DIR"

  git -C "$REPO_DIR" init -b main >/dev/null 2>&1
  git -C "$REPO_DIR" config user.email "test@example.com"
  git -C "$REPO_DIR" config user.name "Test User"

  # .claude/ ディレクトリ構成（追跡ファイル）
  mkdir -p "$REPO_DIR/.claude/rules"
  echo "# テスト CLAUDE.md" > "$REPO_DIR/.claude/CLAUDE.md"
  echo "# テストルール" > "$REPO_DIR/.claude/rules/test-rule.md"

  # vibecorp.yml
  cat > "$REPO_DIR/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: standard
language: ja
base_branch: main
YAML

  # .gitignore（vibecorp パターン: hooks, skills, settings.json を除外）
  cat > "$REPO_DIR/.claude/.gitignore" <<'GITIGNORE'
hooks/
skills/
settings.json
GITIGNORE

  git -C "$REPO_DIR" add .
  git -C "$REPO_DIR" commit -m "初期コミット" >/dev/null 2>&1

  # 未追跡ファイル（.gitignore で除外されるもの — コミット後に作成）
  mkdir -p "$REPO_DIR/.claude/hooks" "$REPO_DIR/.claude/skills/branch"
  echo '#!/bin/bash' > "$REPO_DIR/.claude/hooks/test-hook.sh"
  chmod +x "$REPO_DIR/.claude/hooks/test-hook.sh"
  echo '# テストスキル' > "$REPO_DIR/.claude/skills/branch/SKILL.md"
  echo '{"hooks":{}}' > "$REPO_DIR/.claude/settings.json"
}

# ===== テスト =====

echo "=== ワークツリー機能テスト ==="
echo ""

setup_test_repo

# --- テスト1: ワークツリーの作成 ---

echo "--- テスト1: ワークツリーの作成 ---"

BRANCH_NAME="dev/1_test_feature"
mkdir -p "$WORKTREE_BASE"
git -C "$REPO_DIR" worktree add "$WORKTREE_BASE/$BRANCH_NAME" -b "$BRANCH_NAME" >/dev/null 2>&1

assert_dir_exists "ワークツリーディレクトリが作成される" "$WORKTREE_BASE/$BRANCH_NAME"
assert_file_exists "追跡ファイル（CLAUDE.md）がワークツリーに存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/CLAUDE.md"
assert_file_exists "追跡ファイル（rules/）がワークツリーに存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/rules/test-rule.md"
assert_file_exists "追跡ファイル（vibecorp.yml）がワークツリーに存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/vibecorp.yml"

echo ""

# --- テスト2: rsync による .claude/ 同期 ---

echo "--- テスト2: rsync による .claude/ 同期 ---"

# 未追跡ファイルはワークツリーに存在しないことを確認
assert_dir_not_exists "同期前: hooks/ がワークツリーに存在しない" "$WORKTREE_BASE/$BRANCH_NAME/.claude/hooks"

# rsync で同期
rsync -a "$REPO_DIR/.claude/" "$WORKTREE_BASE/$BRANCH_NAME/.claude/"

assert_dir_exists "同期後: hooks/ がワークツリーに存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/hooks"
assert_file_exists "同期後: hooks/test-hook.sh が存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/hooks/test-hook.sh"
assert_file_exists "同期後: skills/branch/SKILL.md が存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/skills/branch/SKILL.md"
assert_file_exists "同期後: settings.json が存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/settings.json"
assert_file_exists "同期後: 追跡ファイル（CLAUDE.md）が引き続き存在する" "$WORKTREE_BASE/$BRANCH_NAME/.claude/CLAUDE.md"

echo ""

# --- テスト3: ワークツリー一覧 ---

echo "--- テスト3: ワークツリー一覧 ---"

assert_command_output_contains "git worktree list にワークツリーが表示される" "$BRANCH_NAME" git -C "$REPO_DIR" worktree list
assert_command_output_contains "git worktree list にメインも表示される" "main" git -C "$REPO_DIR" worktree list

echo ""

# --- テスト4: ワークツリーの削除 ---

echo "--- テスト4: ワークツリーの削除 ---"

git -C "$REPO_DIR" worktree remove "$WORKTREE_BASE/$BRANCH_NAME"
assert_dir_not_exists "ワークツリーディレクトリが削除される" "$WORKTREE_BASE/$BRANCH_NAME"

# ブランチ削除
git -C "$REPO_DIR" branch -d "$BRANCH_NAME" >/dev/null 2>&1
local_branches=$(git -C "$REPO_DIR" branch --list "$BRANCH_NAME")
if [ -z "$local_branches" ]; then
  pass "ローカルブランチが削除される"
else
  fail "ローカルブランチが残っている"
fi

echo ""

# --- テスト5: 全追跡プロジェクトでの rsync（Case A） ---

echo "--- テスト5: 全追跡プロジェクト（Case A）での rsync ---"

# .gitignore を削除して全追跡にする
rm -f "$REPO_DIR/.claude/.gitignore"
git -C "$REPO_DIR" add "$REPO_DIR/.claude/hooks" "$REPO_DIR/.claude/skills" "$REPO_DIR/.claude/settings.json"
git -C "$REPO_DIR" rm --cached "$REPO_DIR/.claude/.gitignore" >/dev/null 2>&1 || true
git -C "$REPO_DIR" commit -m "全ファイルを追跡に追加" >/dev/null 2>&1

BRANCH_NAME_2="dev/2_case_a_test"
git -C "$REPO_DIR" worktree add "$WORKTREE_BASE/$BRANCH_NAME_2" -b "$BRANCH_NAME_2" >/dev/null 2>&1

# Case A: 追跡ファイルは全てワークツリーに存在する
assert_file_exists "Case A: hooks がワークツリーに存在する" "$WORKTREE_BASE/$BRANCH_NAME_2/.claude/hooks/test-hook.sh"

# rsync を実行しても問題ない（no-op に近い）
rsync -a "$REPO_DIR/.claude/" "$WORKTREE_BASE/$BRANCH_NAME_2/.claude/"
assert_file_exists "Case A: rsync 後も hooks が存在する" "$WORKTREE_BASE/$BRANCH_NAME_2/.claude/hooks/test-hook.sh"
assert_file_exists "Case A: rsync 後も CLAUDE.md が存在する" "$WORKTREE_BASE/$BRANCH_NAME_2/.claude/CLAUDE.md"

# クリーンアップ
git -C "$REPO_DIR" worktree remove "$WORKTREE_BASE/$BRANCH_NAME_2"
git -C "$REPO_DIR" branch -d "$BRANCH_NAME_2" >/dev/null 2>&1

echo ""

# --- テスト6: ワークツリーのディレクトリ命名 ---

echo "--- テスト6: ディレクトリ命名パターン ---"

assert_dir_exists "ワークツリーベースが {project}.worktrees パターンに従う" "$WORKTREE_BASE"
assert_file_contains "vibecorp.yml からプロジェクト名を取得できる" "$REPO_DIR/.claude/vibecorp.yml" "name: test-project"

echo ""

# --- テスト7: メインワークツリーへの影響なし ---

echo "--- テスト7: メインワークツリーへの影響確認 ---"

BRANCH_NAME_3="dev/3_isolation_test"
git -C "$REPO_DIR" worktree add "$WORKTREE_BASE/$BRANCH_NAME_3" -b "$BRANCH_NAME_3" >/dev/null 2>&1

# ワークツリーにファイルを追加
echo "# ワークツリー専用ファイル" > "$WORKTREE_BASE/$BRANCH_NAME_3/worktree-only.txt"

# メインには存在しないことを確認
if [ ! -f "$REPO_DIR/worktree-only.txt" ]; then
  pass "ワークツリーの変更がメインに影響しない"
else
  fail "ワークツリーの変更がメインに影響している"
fi

# クリーンアップ
git -C "$REPO_DIR" worktree remove --force "$WORKTREE_BASE/$BRANCH_NAME_3"
git -C "$REPO_DIR" branch -D "$BRANCH_NAME_3" >/dev/null 2>&1

echo ""

# ===== 結果 =====

echo "==========================="
echo "結果: $PASSED/$TOTAL 成功, $FAILED 失敗"
echo "==========================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
