#!/bin/bash
# test_install.sh — install.sh の統合テスト
# 使い方: bash tests/test_install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"
PASSED=0
FAILED=0
TOTAL=0
TMPDIR_ROOT=""

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

assert_exit_code() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (期待: exit $expected, 実際: exit $actual)"
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

assert_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc (ファイルが存在する: $path)"
  fi
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

assert_file_not_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if ! grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれている: $path)"
  fi
}

assert_file_executable() {
  local desc="$1"
  local path="$2"
  if [ -x "$path" ]; then
    pass "$desc"
  else
    fail "$desc (実行権限なし: $path)"
  fi
}

# --- セットアップ / クリーンアップ ---

create_test_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  cd "$TMPDIR_ROOT"
  git init -q
  git config user.name "vibecorp-test"
  git config user.email "vibecorp-test@example.com"
  git commit --allow-empty -m "initial" -q
}

run_install() {
  local exit_code=0
  bash "$INSTALL_SH" "$@" 2>/dev/null || exit_code=$?
  echo "$exit_code"
}

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
  cd "$SCRIPT_DIR"
}
trap cleanup EXIT

# ============================================
echo "=== A. 引数パース ==="
# ============================================

create_test_repo

# A1. --name のみで成功
EXIT_CODE=$(run_install --name test-proj)
assert_exit_code "--name のみで成功" "0" "$EXIT_CODE"
cleanup

# A2. --name 未指定でエラー
create_test_repo
EXIT_CODE=$(run_install 2>/dev/null || echo $?)
# run_install は exit code を echo するが、引数なしの場合はエラー
EXIT_CODE=0; bash "$INSTALL_SH" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--name 未指定でエラー" "1" "$EXIT_CODE"
cleanup

# A3. --name の値欠落でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--name の値欠落でエラー" "1" "$EXIT_CODE"
cleanup

# A4. --preset 指定で成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--preset 指定で成功" "0" "$EXIT_CODE"
cleanup

# A5. --language 指定で成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--language 指定で成功" "0" "$EXIT_CODE"
cleanup

# A6. 不明オプションでエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --unknown 2>/dev/null || EXIT_CODE=$?
assert_exit_code "不明オプションでエラー" "1" "$EXIT_CODE"
cleanup

# A7. --help でヘルプ表示・正常終了
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --help 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--help でヘルプ表示・正常終了" "0" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== B. プロジェクト名バリデーション ==="
# ============================================

# B1. 正常な名前(my-project) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name my-project 2>/dev/null || EXIT_CODE=$?
assert_exit_code "正常な名前(my-project) → 成功" "0" "$EXIT_CODE"
cleanup

# B2. 1文字(a) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name a 2>/dev/null || EXIT_CODE=$?
assert_exit_code "1文字(a) → 成功" "0" "$EXIT_CODE"
cleanup

# B3. 2文字(ab) → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name ab 2>/dev/null || EXIT_CODE=$?
assert_exit_code "2文字(ab) → 成功" "0" "$EXIT_CODE"
cleanup

# B4. 50文字 → 成功
create_test_repo
NAME50=$(printf 'a%.0s' $(seq 1 50))
EXIT_CODE=0; bash "$INSTALL_SH" --name "$NAME50" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "50文字 → 成功" "0" "$EXIT_CODE"
cleanup

# B5. 51文字 → エラー
create_test_repo
NAME51=$(printf 'a%.0s' $(seq 1 51))
EXIT_CODE=0; bash "$INSTALL_SH" --name "$NAME51" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "51文字 → エラー" "1" "$EXIT_CODE"
cleanup

# B6. ハイフン始まり → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "-bad" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ハイフン始まり → エラー" "1" "$EXIT_CODE"
cleanup

# B7. ハイフン終わり → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "bad-" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ハイフン終わり → エラー" "1" "$EXIT_CODE"
cleanup

# B8. アンダースコア含む → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name "bad_name" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "アンダースコア含む → エラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== C. プリセットバリデーション ==="
# ============================================

# C1. minimal → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null || EXIT_CODE=$?
assert_exit_code "minimal → 成功" "0" "$EXIT_CODE"
cleanup

# C2. full → エラー（現在未対応）
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null || EXIT_CODE=$?
assert_exit_code "full → エラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== D. 言語バリデーション ==="
# ============================================

# D1. ja → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language ja 2>/dev/null || EXIT_CODE=$?
assert_exit_code "ja → 成功" "0" "$EXIT_CODE"
cleanup

# D2. en → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null || EXIT_CODE=$?
assert_exit_code "en → 成功" "0" "$EXIT_CODE"
cleanup

# D3. 特殊文字含む → エラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --language 'ja;rm' 2>/dev/null || EXIT_CODE=$?
assert_exit_code "特殊文字含む → エラー" "1" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== E. ファイル生成（統合） ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# E1. hooks ディレクトリ存在
assert_dir_exists "hooks ディレクトリ存在" "$R/.claude/hooks"

# E2. protect-files.sh 存在
assert_file_exists "protect-files.sh 存在" "$R/.claude/hooks/protect-files.sh"

# E3. hooks に実行権限
assert_file_executable "hooks に実行権限" "$R/.claude/hooks/protect-files.sh"

# E4. skills ディレクトリ存在
assert_dir_exists "skills ディレクトリ存在" "$R/.claude/skills"

# E5. vibecorp.yml に name/preset/language
assert_file_contains "vibecorp.yml に name" "$R/.claude/vibecorp.yml" "name: test-proj"
assert_file_contains "vibecorp.yml に preset" "$R/.claude/vibecorp.yml" "preset: minimal"
assert_file_contains "vibecorp.yml に language" "$R/.claude/vibecorp.yml" "language: ja"

# E6. vibecorp.lock に version
assert_file_contains "vibecorp.lock に version" "$R/.claude/vibecorp.lock" "version: 0.1.0"

# E7. vibecorp.lock にマニフェスト
assert_file_contains "vibecorp.lock に hooks マニフェスト" "$R/.claude/vibecorp.lock" "protect-files.sh"
assert_file_contains "vibecorp.lock に skills マニフェスト" "$R/.claude/vibecorp.lock" "review"
assert_file_contains "vibecorp.lock に rules マニフェスト" "$R/.claude/vibecorp.lock" "comments.md"

# E8. settings.json に hooks 構造
assert_file_contains "settings.json に hooks 構造" "$R/.claude/settings.json" "PreToolUse"

# E9. settings.json のフックパスが .claude/hooks/ を参照
assert_file_contains "settings.json のフックパス" "$R/.claude/settings.json" '.claude/hooks/'
assert_file_not_contains "settings.json に旧パスなし" "$R/.claude/settings.json" '.claude/vibecorp/'

# E10. .claude/rules/ にファイル存在
RULES_COUNT=$(find "$R/.claude/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$RULES_COUNT" -gt 0 ]; then
  pass ".claude/rules/ にファイル存在 (${RULES_COUNT}件)"
else
  fail ".claude/rules/ にファイル存在 (0件)"
fi

# E11. CLAUDE.md 存在 + プレースホルダーなし
assert_file_exists "CLAUDE.md 存在" "$R/.claude/CLAUDE.md"
assert_file_not_contains "CLAUDE.md にプレースホルダーなし" "$R/.claude/CLAUDE.md" '{{.*}}'

# E12. MVV.md 存在 + プレースホルダーなし
assert_file_exists "MVV.md 存在" "$R/MVV.md"
assert_file_not_contains "MVV.md にプレースホルダーなし" "$R/MVV.md" '{{.*}}'

# E13. .claude/vibecorp/ ディレクトリが存在しない
if [ ! -d "$R/.claude/vibecorp" ]; then
  pass ".claude/vibecorp/ が存在しない"
else
  fail ".claude/vibecorp/ が存在しない (ディレクトリが残っている)"
fi

cleanup

# ============================================
echo ""
echo "=== F. minimal プリセット固有 ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# F1. review-to-rules-gate.sh が削除されている
assert_file_not_exists "review-to-rules-gate.sh が削除されている" "$R/.claude/hooks/review-to-rules-gate.sh"

# F2. review-to-rules スキルが削除されている
if [ ! -d "$R/.claude/skills/review-to-rules" ]; then
  pass "review-to-rules スキルが削除されている"
else
  fail "review-to-rules スキルが削除されている (ディレクトリが存在)"
fi

cleanup

# ============================================
echo ""
echo "=== G. 冪等性 ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# 1回目の内容を保存
YML_CONTENT_BEFORE=$(cat "$R/.claude/vibecorp.yml")
CLAUDE_MD_BEFORE=$(cat "$R/.claude/CLAUDE.md")
MVV_MD_BEFORE=$(cat "$R/MVV.md")

# 2回目実行
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?

# G1. 2回目実行でエラーにならない
assert_exit_code "2回目実行でエラーにならない" "0" "$EXIT_CODE"

# G2. vibecorp.yml スキップ（内容保持）
YML_CONTENT_AFTER=$(cat "$R/.claude/vibecorp.yml")
if [ "$YML_CONTENT_BEFORE" = "$YML_CONTENT_AFTER" ]; then
  pass "vibecorp.yml スキップ（内容保持）"
else
  fail "vibecorp.yml スキップ（内容が変わった）"
fi

# G3. CLAUDE.md スキップ（内容保持）
CLAUDE_MD_AFTER=$(cat "$R/.claude/CLAUDE.md")
if [ "$CLAUDE_MD_BEFORE" = "$CLAUDE_MD_AFTER" ]; then
  pass "CLAUDE.md スキップ（内容保持）"
else
  fail "CLAUDE.md スキップ（内容が変わった）"
fi

# G4. MVV.md スキップ（内容保持）
MVV_MD_AFTER=$(cat "$R/MVV.md")
if [ "$MVV_MD_BEFORE" = "$MVV_MD_AFTER" ]; then
  pass "MVV.md スキップ（内容保持）"
else
  fail "MVV.md スキップ（内容が変わった）"
fi

cleanup

# ============================================
echo ""
echo "=== H. settings.json マージ ==="
# ============================================

# H1. 既存あり → ユーザーフック保持 + vibecorp フック追加
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "my-custom-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# H2. ユーザー独自フックが残る
assert_file_contains "ユーザー独自フックが残る" "$R/.claude/settings.json" 'my-custom-hook.sh'

# vibecorp フックも追加されている
assert_file_contains "vibecorp フック追加" "$R/.claude/settings.json" 'protect-files.sh'

# H3. 再実行で vibecorp フック重複なし
bash "$INSTALL_SH" --name test-proj 2>/dev/null
PROTECT_COUNT=$(grep -c 'protect-files.sh' "$R/.claude/settings.json")
if [ "$PROTECT_COUNT" = "1" ]; then
  pass "再実行で vibecorp フック重複なし"
else
  fail "再実行で vibecorp フック重複なし (${PROTECT_COUNT}件)"
fi

# H4. 非vibecorpフックが不変であること（同名matcher内でも操作対象外）
CUSTOM_HOOK_COUNT=$(grep -c 'my-custom-hook.sh' "$R/.claude/settings.json")
if [ "$CUSTOM_HOOK_COUNT" = "1" ]; then
  pass "非vibecorpフックが不変"
else
  fail "非vibecorpフックが不変 (${CUSTOM_HOOK_COUNT}件)"
fi

cleanup

# ============================================
echo ""
echo "=== I. テンプレート置換 ==="
# ============================================

create_test_repo
bash "$INSTALL_SH" --name my-cool-app --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# I1. CLAUDE.md にプロジェクト名置換済み
assert_file_contains "CLAUDE.md にプロジェクト名置換済み" "$R/.claude/CLAUDE.md" 'my-cool-app'

# I2. CLAUDE.md に言語(日本語)置換済み
assert_file_contains "CLAUDE.md に言語(日本語)置換済み" "$R/.claude/CLAUDE.md" '日本語'

# I3. MVV.md にプロジェクト名置換済み
assert_file_contains "MVV.md にプロジェクト名置換済み" "$R/MVV.md" 'my-cool-app'

cleanup

# ============================================
echo ""
echo "=== J. rules コピー ==="
# ============================================

# J1. 既存同名ルールはスキップ
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/rules"
echo "# カスタムルール" > "$TMPDIR_ROOT/.claude/rules/comments.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
CONTENT=$(cat "$TMPDIR_ROOT/.claude/rules/comments.md")
if [ "$CONTENT" = "# カスタムルール" ]; then
  pass "既存同名ルールはスキップ"
else
  fail "既存同名ルールはスキップ (内容が上書きされた)"
fi

# J2. 新規ルールはコピーされる
assert_file_exists "新規ルールはコピーされる" "$TMPDIR_ROOT/.claude/rules/mvv.md"

cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
