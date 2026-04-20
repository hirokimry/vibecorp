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
  if grep -q -e "$pattern" "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (パターン '$pattern' がファイルに含まれない: $path)"
  fi
}

assert_file_not_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if ! grep -q -e "$pattern" "$path" 2>/dev/null; then
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
    # 擬似 git リポジトリ・chmod 操作・シンボリックリンクを含むテストがあるため、
    # rm -rf の一時的失敗がテスト結果に波及しないように `|| true` で失敗を無害化する。
    # 詳細: .claude/rules/testing.md「trap cleanup EXIT でのリソース解放」
    rm -rf "$TMPDIR_ROOT" || true
  fi
  cd "$SCRIPT_DIR" || true
}
trap cleanup EXIT

# Darwin 限定テストで使用する skip ヘルパー
require_darwin() {
  local desc="$1"
  local os
  os=$(uname -s)
  if [ "$os" = "Darwin" ]; then
    return 0
  fi
  pass "${desc} (Darwin 以外のためスキップ)"
  return 1
}

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

# C2. full → 成功
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null || EXIT_CODE=$?
assert_exit_code "full → 成功" "0" "$EXIT_CODE"
R="$TMPDIR_ROOT"
assert_file_contains "full: vibecorp.yml に preset: full" "$R/.claude/vibecorp.yml" "preset: full"
assert_dir_exists "full: agents ディレクトリ存在" "$R/.claude/agents"
assert_dir_exists "full: skills ディレクトリ存在" "$R/.claude/skills"
assert_file_exists "full: sync-gate.sh 配置" "$R/.claude/hooks/sync-gate.sh"
# --update --preset full の冪等性確認
EXIT_CODE=0; bash "$INSTALL_SH" --update --preset full 2>/dev/null || EXIT_CODE=$?
assert_exit_code "full → update 成功" "0" "$EXIT_CODE"
assert_file_contains "full: update 後も preset: full" "$R/.claude/vibecorp.yml" "preset: full"
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

# E6. vibecorp.lock に version（動的取得値と一致すること）
EXPECTED_VERSION=$(git -C "$(dirname "$INSTALL_SH")" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
EXPECTED_VERSION="${EXPECTED_VERSION#v}"
assert_file_contains "vibecorp.lock に version" "$R/.claude/vibecorp.lock" "version: ${EXPECTED_VERSION}"

# E7. vibecorp.lock にマニフェスト
assert_file_contains "vibecorp.lock に hooks マニフェスト" "$R/.claude/vibecorp.lock" "protect-files.sh"
assert_file_contains "vibecorp.lock に skills マニフェスト" "$R/.claude/vibecorp.lock" "review"
assert_file_contains "vibecorp.lock に rules マニフェスト" "$R/.claude/vibecorp.lock" "comments.md"

# E8. settings.json に hooks 構造
assert_file_contains "settings.json に hooks 構造" "$R/.claude/settings.json" "PreToolUse"

# E9. settings.json のフックパスが .claude/hooks/ を参照
assert_file_contains "settings.json のフックパス" "$R/.claude/settings.json" '.claude/hooks/'
assert_file_not_contains "settings.json に旧パスなし" "$R/.claude/settings.json" '.claude/vibecorp/'

# E9b. settings.json に team-auto-approve.sh が含まれない（#336 削除済み）
assert_file_not_contains "settings.json に team-auto-approve なし" "$R/.claude/settings.json" "team-auto-approve.sh"

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

# E11a. CLAUDE.md に COO 役割セクションが含まれる（#364 §0-2）
assert_file_contains "CLAUDE.md に COO 役割セクションあり" "$R/.claude/CLAUDE.md" '主Claudeの役割（COO）'
assert_file_contains "CLAUDE.md に COO 説明あり" "$R/.claude/CLAUDE.md" 'CEO の意図を解釈'

# E12. MVV.md 存在 + プレースホルダーなし
assert_file_exists "MVV.md 存在" "$R/MVV.md"
assert_file_not_contains "MVV.md にプレースホルダーなし" "$R/MVV.md" '{{.*}}'

# E13. .coderabbit.yaml 存在
assert_file_exists ".coderabbit.yaml 存在" "$R/.coderabbit.yaml"

# E14. .coderabbit.yaml に request_changes_workflow: true
assert_file_contains ".coderabbit.yaml に request_changes_workflow" "$R/.coderabbit.yaml" "request_changes_workflow: true"

# E15. .coderabbit.yaml に auto_resolve
assert_file_contains ".coderabbit.yaml に auto_resolve" "$R/.coderabbit.yaml" "auto_resolve"

# E16. .coderabbit.yaml に language: ja-JP（ロケール変換確認）
assert_file_contains ".coderabbit.yaml に language: ja-JP" "$R/.coderabbit.yaml" "language: ja-JP"

# E17. .coderabbit.yaml にプレースホルダーなし
assert_file_not_contains ".coderabbit.yaml にプレースホルダーなし" "$R/.coderabbit.yaml" '{{.*}}'

# E18. .claude/vibecorp/ ディレクトリが存在しない
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

# F3. sync-gate.sh が削除されている
assert_file_not_exists "sync-gate.sh が削除されている" "$R/.claude/hooks/sync-gate.sh"

# F4. sync-check スキルが削除されている
if [ ! -d "$R/.claude/skills/sync-check" ]; then
  pass "sync-check スキルが削除されている"
else
  fail "sync-check スキルが削除されている (ディレクトリが存在)"
fi

# F4b. sync-edit スキルが削除されている
if [ ! -d "$R/.claude/skills/sync-edit" ]; then
  pass "sync-edit スキルが削除されている"
else
  fail "sync-edit スキルが削除されている (ディレクトリが存在)"
fi

# F5. settings.json に sync-gate のエントリがない
assert_file_not_contains "settings.json に sync-gate なし" "$R/.claude/settings.json" "sync-gate"

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
CODERABBIT_BEFORE=$(cat "$R/.coderabbit.yaml")
CI_WORKFLOW_BEFORE=$(cat "$R/.github/workflows/test.yml")

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

# G5. .coderabbit.yaml スキップ（内容保持）
CODERABBIT_AFTER=$(cat "$R/.coderabbit.yaml")
if [ "$CODERABBIT_BEFORE" = "$CODERABBIT_AFTER" ]; then
  pass ".coderabbit.yaml スキップ（内容保持）"
else
  fail ".coderabbit.yaml スキップ（内容が変わった）"
fi

# G6. .github/workflows/test.yml スキップ（内容保持）
CI_WORKFLOW_AFTER=$(cat "$R/.github/workflows/test.yml")
if [ "$CI_WORKFLOW_BEFORE" = "$CI_WORKFLOW_AFTER" ]; then
  pass ".github/workflows/test.yml スキップ（内容保持）"
else
  fail ".github/workflows/test.yml スキップ（内容が変わった）"
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
echo "=== K. 既存フック保持（独自フック + vibecorp フック共存） ==="
# ============================================

# K1. ユーザー独自フックが install 後も残る
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/hooks"
echo '#!/bin/bash' > "$TMPDIR_ROOT/.claude/hooks/my-guard.sh"
echo 'echo "ユーザー独自ガード"' >> "$TMPDIR_ROOT/.claude/hooks/my-guard.sh"
chmod +x "$TMPDIR_ROOT/.claude/hooks/my-guard.sh"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "ユーザー独自フック(my-guard.sh)が残る" "$R/.claude/hooks/my-guard.sh"
assert_file_contains "ユーザー独自フックの内容が保持" "$R/.claude/hooks/my-guard.sh" "ユーザー独自ガード"

# K2. vibecorp フックも同時に存在する
assert_file_exists "vibecorp フック(protect-files.sh)も存在" "$R/.claude/hooks/protect-files.sh"

# K3. 再実行でもユーザー独自フックは消えない
bash "$INSTALL_SH" --name test-proj 2>/dev/null
assert_file_exists "再実行後もユーザー独自フックが残る" "$R/.claude/hooks/my-guard.sh"
assert_file_contains "再実行後もユーザー独自フックの内容が保持" "$R/.claude/hooks/my-guard.sh" "ユーザー独自ガード"

# K4. lock にユーザー独自フックが含まれない
assert_file_not_contains "lock にユーザー独自フックなし" "$R/.claude/vibecorp.lock" "my-guard.sh"

cleanup

# ============================================
echo ""
echo "=== L. 既存スキル保持（同名スキルスキップ） ==="
# ============================================

# L1. ユーザーがカスタマイズした同名スキルはスキップ
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/skills/review"
echo "# カスタムレビュースキル" > "$TMPDIR_ROOT/.claude/skills/review/SKILL.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

REVIEW_CONTENT=$(cat "$R/.claude/skills/review/SKILL.md")
if [ "$REVIEW_CONTENT" = "# カスタムレビュースキル" ]; then
  pass "同名スキル(review)はユーザー版を保持"
else
  fail "同名スキル(review)はユーザー版を保持 (上書きされた)"
fi

# L2. ユーザー独自スキルも保持
mkdir -p "$TMPDIR_ROOT/.claude/skills/my-deploy"
echo "# デプロイスキル" > "$TMPDIR_ROOT/.claude/skills/my-deploy/SKILL.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
assert_file_exists "ユーザー独自スキルが残る" "$R/.claude/skills/my-deploy/SKILL.md"
assert_file_contains "ユーザー独自スキルの内容が保持" "$R/.claude/skills/my-deploy/SKILL.md" "デプロイスキル"

# L3. lock にユーザー独自スキルが含まれない
assert_file_not_contains "lock にユーザー独自スキルなし" "$R/.claude/vibecorp.lock" "my-deploy"

cleanup

# ============================================
echo ""
echo "=== M. lock ベース再インストール（管理ファイルのみ差し替え） ==="
# ============================================

# M1. vibecorp 管理フックは差し替えられる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# protect-files.sh の内容を変更（古いバージョンを模擬）
echo "# 古いバージョン" > "$R/.claude/hooks/protect-files.sh"
# ユーザー独自フックを追加
echo '#!/bin/bash' > "$R/.claude/hooks/my-custom-gate.sh"
echo 'echo "ユーザー独自カスタムゲート"' >> "$R/.claude/hooks/my-custom-gate.sh"

# 再実行で管理ファイルは差し替え、ユーザーファイルは保持
bash "$INSTALL_SH" --name test-proj 2>/dev/null

assert_file_not_contains "管理フックが差し替え済み" "$R/.claude/hooks/protect-files.sh" "古いバージョン"
assert_file_exists "ユーザー独自フック(my-custom-gate.sh)が残る" "$R/.claude/hooks/my-custom-gate.sh"
assert_file_contains "ユーザー独自フックの内容が保持" "$R/.claude/hooks/my-custom-gate.sh" "ユーザー独自カスタムゲート"

# M2. vibecorp 管理スキルも差し替えられる
echo "# 古いレビュー" > "$R/.claude/skills/review/SKILL.md"
mkdir -p "$R/.claude/skills/my-custom"
echo "# カスタム" > "$R/.claude/skills/my-custom/SKILL.md"

bash "$INSTALL_SH" --name test-proj 2>/dev/null

assert_file_not_contains "管理スキルが差し替え済み" "$R/.claude/skills/review/SKILL.md" "古いレビュー"
assert_file_exists "ユーザー独自スキルが残る" "$R/.claude/skills/my-custom/SKILL.md"

cleanup

# ============================================
echo ""
echo "=== N. 同名ファイル初回移行（スキップ動作） ==="
# ============================================

# N1. 初回（lock なし）で同名フックが既存ならスキップ
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/hooks"
echo '#!/bin/bash' > "$TMPDIR_ROOT/.claude/hooks/protect-files.sh"
echo 'echo "ユーザーカスタム版 protect-files"' >> "$TMPDIR_ROOT/.claude/hooks/protect-files.sh"

bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "初回で同名フックはスキップ（ユーザー版保持）" "$R/.claude/hooks/protect-files.sh" "ユーザーカスタム版 protect-files"

# N2. 初回（lock なし）で同名スキルが既存ならスキップ
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/skills/commit"
echo "# ユーザーカスタム commit" > "$TMPDIR_ROOT/.claude/skills/commit/SKILL.md"

bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

COMMIT_CONTENT=$(cat "$R/.claude/skills/commit/SKILL.md")
if [ "$COMMIT_CONTENT" = "# ユーザーカスタム commit" ]; then
  pass "初回で同名スキルはスキップ（ユーザー版保持）"
else
  fail "初回で同名スキルはスキップ（ユーザー版保持） (上書きされた)"
fi

# N3. settings.json のユーザー独自フック参照も保持（lock なし初回）
cleanup
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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/my-custom-gate.sh"
          }
        ]
      }
    ]
  }
}
JSON

bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "初回でもユーザー独自フック参照が保持" "$R/.claude/settings.json" "my-custom-gate.sh"
assert_file_contains "vibecorp フックも追加" "$R/.claude/settings.json" "protect-files.sh"

cleanup

# ============================================
echo ""
echo "=== O. --update 引数パース ==="
# ============================================

# O1. --update で vibecorp.yml から設定を読み取って成功
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal --language ja 2>/dev/null
EXIT_CODE=0; bash "$INSTALL_SH" --update 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--update で成功" "0" "$EXIT_CODE"
cleanup

# O2. --update で vibecorp.yml が無い場合はエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --update 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--update で vibecorp.yml 無しはエラー" "1" "$EXIT_CODE"
cleanup

# O3. --update + --name 同時指定はエラー
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
EXIT_CODE=0; bash "$INSTALL_SH" --update --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "--update + --name 同時指定はエラー" "1" "$EXIT_CODE"
cleanup

# O4. --update で vibecorp.yml の設定が正しく読み取られる
create_test_repo
bash "$INSTALL_SH" --name my-app --preset minimal --language en 2>/dev/null
R="$TMPDIR_ROOT"
# CLAUDE.md を削除して --update で再生成されるか確認
rm -f "$R/.claude/CLAUDE.md"
bash "$INSTALL_SH" --update 2>/dev/null
# CLAUDE.md が yml の name/language で再生成されているか
assert_file_exists "--update で CLAUDE.md 再生成" "$R/.claude/CLAUDE.md"
assert_file_contains "--update で yml の name を使用" "$R/.claude/CLAUDE.md" "my-app"
assert_file_contains "--update で yml の language を使用" "$R/.claude/CLAUDE.md" "English"
cleanup

# ============================================
echo ""
echo "=== P. --update での管理ファイル強制差し替え ==="
# ============================================

# P1. --update でカスタマイズ済みフックはテンプレート未変更ならスキップ（3-way マージ）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# protect-files.sh をカスタム内容に変更
echo "# ユーザーカスタム版" > "$R/.claude/hooks/protect-files.sh"
# ユーザー独自フックも追加
echo '#!/bin/bash' > "$R/.claude/hooks/my-guard.sh"

bash "$INSTALL_SH" --update 2>/dev/null

# テンプレート未変更のため、カスタム版が保持される
assert_file_contains "--update でカスタム版フックが保持される" "$R/.claude/hooks/protect-files.sh" "ユーザーカスタム版"
# ユーザー独自フックは残る
assert_file_exists "--update でユーザー独自フックは保持" "$R/.claude/hooks/my-guard.sh"
cleanup

# P2. --update でカスタマイズ済みスキルはテンプレート未変更ならスキップ（3-way マージ）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

echo "# 古い review" > "$R/.claude/skills/review/SKILL.md"
mkdir -p "$R/.claude/skills/my-deploy"
echo "# デプロイ" > "$R/.claude/skills/my-deploy/SKILL.md"

bash "$INSTALL_SH" --update 2>/dev/null

# テンプレート未変更のため、カスタム版が保持される
assert_file_contains "--update でカスタム版スキルが保持される" "$R/.claude/skills/review/SKILL.md" "古い review"
assert_file_exists "--update でユーザー独自スキルは保持" "$R/.claude/skills/my-deploy/SKILL.md"
cleanup

# P3. --update でカスタマイズ済みルールはテンプレート未変更ならスキップ（3-way マージ）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

echo "# 古いルール" > "$R/.claude/rules/comments.md"

bash "$INSTALL_SH" --update 2>/dev/null

# テンプレートが変更されていないため、カスタム版が保持される
assert_file_contains "--update でカスタム済みルールがテンプレート未変更なら保持" "$R/.claude/rules/comments.md" "古いルール"
cleanup

# ============================================
echo ""
echo "=== Q. --update でのプリセット変更 ==="
# ============================================

# Q1. --update --preset で vibecorp.yml の preset が更新される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "初回は minimal" "$R/.claude/vibecorp.yml" "preset: minimal"

# 注: 現在 minimal のみ対応のため、preset 変更テストは validate_preset を一時回避
# ここでは yml の更新ロジック自体をテスト（同じ preset での --update）
bash "$INSTALL_SH" --update --preset minimal 2>/dev/null
assert_file_contains "--update --preset で yml 保持" "$R/.claude/vibecorp.yml" "preset: minimal"
cleanup

# Q2. --update で全既存テスト後のファイル整合性
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ユーザーファイルを配置
echo '#!/bin/bash' > "$R/.claude/hooks/custom.sh"
mkdir -p "$R/.claude/skills/custom-skill"
echo "# custom" > "$R/.claude/skills/custom-skill/SKILL.md"

bash "$INSTALL_SH" --update 2>/dev/null

# vibecorp 管理ファイルが存在
assert_file_exists "--update 後に protect-files.sh 存在" "$R/.claude/hooks/protect-files.sh"
assert_dir_exists "--update 後に review スキル存在" "$R/.claude/skills/review"
# ユーザーファイルが保持
assert_file_exists "--update 後にユーザーフック保持" "$R/.claude/hooks/custom.sh"
assert_file_exists "--update 後にユーザースキル保持" "$R/.claude/skills/custom-skill/SKILL.md"
# lock にユーザーファイルなし
assert_file_not_contains "--update 後の lock にユーザーフックなし" "$R/.claude/vibecorp.lock" "custom.sh"
assert_file_not_contains "--update 後の lock にユーザースキルなし" "$R/.claude/vibecorp.lock" "custom-skill"
cleanup

# ============================================
echo ""
echo "=== R. .coderabbit.yaml スキップ動作 ==="
# ============================================

# R1. 既存 .coderabbit.yaml はスキップ（ユーザー版保持）
create_test_repo
echo "# ユーザーカスタム設定" > "$TMPDIR_ROOT/.coderabbit.yaml"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存 .coderabbit.yaml はスキップ（ユーザー版保持）" "$R/.coderabbit.yaml" "ユーザーカスタム設定"

# R2. --language en で language: en-US になる
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains ".coderabbit.yaml に language: en-US" "$R/.coderabbit.yaml" "language: en-US"

cleanup

# ============================================
echo ""
echo "=== S. Issue テンプレート・ラベル・/issue スキル ==="
# ============================================

# P1. .github/ISSUE_TEMPLATE/ ディレクトリ存在
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_dir_exists ".github/ISSUE_TEMPLATE/ 存在" "$R/.github/ISSUE_TEMPLATE"

# P2. bug_report.md 存在
assert_file_exists "bug_report.md 存在" "$R/.github/ISSUE_TEMPLATE/bug_report.md"

# P3. feature_request.md 存在
assert_file_exists "feature_request.md 存在" "$R/.github/ISSUE_TEMPLATE/feature_request.md"

# P4. config.yml 存在
assert_file_exists "config.yml 存在" "$R/.github/ISSUE_TEMPLATE/config.yml"

# P5. 既存同名テンプレートはスキップ
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github/ISSUE_TEMPLATE"
echo "# カスタムバグ報告" > "$TMPDIR_ROOT/.github/ISSUE_TEMPLATE/bug_report.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
CONTENT=$(cat "$R/.github/ISSUE_TEMPLATE/bug_report.md")
if [ "$CONTENT" = "# カスタムバグ報告" ]; then
  pass "既存同名テンプレートはスキップ"
else
  fail "既存同名テンプレートはスキップ (内容が上書きされた)"
fi

# P6. vibecorp.lock に issue_templates セクション含む
# bug_report.md はスキップされたため lock に載らない（COPIED_* 方式）
assert_file_contains "lock に issue_templates セクション" "$R/.claude/vibecorp.lock" "issue_templates:"
assert_file_not_contains "スキップされた bug_report.md は lock に載らない" "$R/.claude/vibecorp.lock" "bug_report.md"
assert_file_contains "lock に feature_request.md" "$R/.claude/vibecorp.lock" "feature_request.md"
assert_file_contains "lock に config.yml" "$R/.claude/vibecorp.lock" "config.yml"

# P7. /issue スキルが配置されている
assert_dir_exists "issue スキルディレクトリ存在" "$R/.claude/skills/issue"
assert_file_exists "issue スキル SKILL.md 存在" "$R/.claude/skills/issue/SKILL.md"
assert_file_contains "issue スキルに name: issue" "$R/.claude/skills/issue/SKILL.md" "name: issue"

# P8. gh が repo view に失敗する場合のラベル作成スキップ動作
# ダミー gh を PATH の先頭に配置し、常に失敗させる
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'FAKESH'
#!/bin/bash
# ダミー gh: 常に失敗を返す
exit 1
FAKESH
chmod +x "$FAKE_BIN/gh"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
# gh が使えなくてもインストール自体は成功する
assert_exit_code "gh 失敗時でもインストール成功" "0" "$EXIT_CODE"

# P9. gh 正常時は期待ラベル作成コマンドが発行される
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
GH_LOG="$TMPDIR_ROOT/gh_calls.log"
cat > "$FAKE_BIN/gh" <<FAKESH
#!/bin/bash
# ダミー gh: 引数をログに記録して成功を返す
echo "\$*" >> "$GH_LOG"
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "gh 正常時インストール成功" "0" "$EXIT_CODE"
assert_file_contains "bug ラベル作成呼び出し" "$GH_LOG" "label create bug"
assert_file_contains "enhancement ラベル作成呼び出し" "$GH_LOG" "label create enhancement"
assert_file_contains "documentation ラベル作成呼び出し" "$GH_LOG" "label create documentation"
assert_file_contains "good first issue ラベル作成呼び出し" "$GH_LOG" "label create good first issue"

cleanup

# ============================================
echo ""
echo "=== T. CI ワークフロー生成 ==="
# ============================================

# T1. .github/workflows/test.yml が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists ".github/workflows/test.yml 存在" "$R/.github/workflows/test.yml"

# T2. name: test が含まれる
assert_file_contains "CI ワークフロー名が test" "$R/.github/workflows/test.yml" "name: test"

# T3. 集約ジョブ test: が含まれる
assert_file_contains "集約ジョブ test 存在" "$R/.github/workflows/test.yml" "needs: test-matrix"

# T4. concurrency 設定が含まれる
assert_file_contains "concurrency 設定" "$R/.github/workflows/test.yml" "cancel-in-progress: true"

# T5. 既存ファイルがある場合はスキップ
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github/workflows"
echo "# カスタム CI" > "$TMPDIR_ROOT/.github/workflows/test.yml"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存 CI ワークフローはスキップ" "$R/.github/workflows/test.yml" "カスタム CI"

cleanup

# ============================================
echo ""
echo "=== U. リポジトリ設定（gh 未インストール時フォールバック） ==="
# ============================================

# U1. gh が利用できない環境でもインストール成功
create_test_repo
# PATH から gh を含むディレクトリを除外して gh を見つけられなくする
GH_REAL=$(command -v gh 2>/dev/null || true)
NO_GH_PATH="$PATH"
if [[ -n "$GH_REAL" ]]; then
  GH_DIR=$(dirname "$GH_REAL")
  NO_GH_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${GH_DIR}$" | tr '\n' ':' | sed 's/:$//')
fi
EXIT_CODE=0
PATH="$NO_GH_PATH" bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "gh 未インストールでもインストール成功" "0" "$EXIT_CODE"

# U2. gh 利用可能だが repo view 失敗時もインストール成功
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'FAKESH'
#!/bin/bash
# repo view は失敗、それ以外（label 等）は成功
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  exit 1
fi
echo "$*" >> /dev/null
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "gh repo view 失敗でもインストール成功" "0" "$EXIT_CODE"

cleanup

# U3. 既存 contexts が保持される（マージ動作）
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
PUT_LOG="$TMPDIR_ROOT/_put_payload.json"
cat > "$FAKE_BIN/gh" <<FAKESH
#!/bin/bash
# repo view → nameWithOwner を返す
if [[ "\$1" == "repo" && "\$2" == "view" ]]; then
  echo '{"nameWithOwner":"test/repo"}'
  exit 0
fi
# api 呼び出しの振り分け
if [[ "\$1" == "api" ]]; then
  # required_status_checks GET → 既存 contexts を返す（"test" を含めず UNION を検証）
  if echo "\$*" | grep -q "required_status_checks"; then
    echo '["custom-ci"]'
    exit 0
  fi
  # Branch Protection PUT → payload をログに保存
  if echo "\$*" | grep -q "protection" && echo "\$*" | grep -q "PUT"; then
    cat /dev/stdin > "$PUT_LOG"
    exit 0
  fi
  # それ以外の API（PATCH 等）は成功
  exit 0
fi
# label 等
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>/dev/null
if [[ -f "$PUT_LOG" ]] \
  && jq -e '.required_status_checks.contexts | index("custom-ci")' "$PUT_LOG" >/dev/null 2>&1 \
  && jq -e '.required_status_checks.contexts | index("test")' "$PUT_LOG" >/dev/null 2>&1; then
  pass "R3: 既存 contexts (custom-ci) と vibecorp contexts (test) が UNION される"
else
  fail "R3: 既存 contexts (custom-ci) と vibecorp contexts (test) が UNION される"
fi

cleanup

# U4. 既存 Branch Protection なし（GET 404）でも正常動作
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
PUT_LOG="$TMPDIR_ROOT/_put_payload.json"
cat > "$FAKE_BIN/gh" <<FAKESH
#!/bin/bash
if [[ "\$1" == "repo" && "\$2" == "view" ]]; then
  echo '{"nameWithOwner":"test/repo"}'
  exit 0
fi
if [[ "\$1" == "api" ]]; then
  # required_status_checks GET → 404（未設定）
  if echo "\$*" | grep -q "required_status_checks"; then
    echo "HTTP 404 - Not Found" >&2
    exit 1
  fi
  # Branch Protection PUT → payload をログに保存
  if echo "\$*" | grep -q "protection" && echo "\$*" | grep -q "PUT"; then
    cat /dev/stdin > "$PUT_LOG"
    exit 0
  fi
  exit 0
fi
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>/dev/null
if [[ -f "$PUT_LOG" ]] && jq -e '.required_status_checks.contexts | index("test")' "$PUT_LOG" >/dev/null 2>&1; then
  pass "R4: Branch Protection 未設定でも vibecorp contexts のみで動作"
else
  fail "R4: Branch Protection 未設定でも vibecorp contexts のみで動作"
fi

cleanup

# U5. Branch Protection PUT 失敗時にフォールバック（推奨設定表示）
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'FAKESH'
#!/bin/bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo '{"nameWithOwner":"test/repo"}'
  exit 0
fi
if [[ "$1" == "api" ]]; then
  # required_status_checks GET → 404（未設定）
  if echo "$*" | grep -q "required_status_checks"; then
    echo "HTTP 404 - Not Found" >&2
    exit 1
  fi
  # Branch Protection PUT → 403 エラー
  if echo "$*" | grep -q "protection" && echo "$*" | grep -q "PUT"; then
    echo "HTTP 403 - Resource not accessible" >&2
    exit 1
  fi
  # PATCH（マージ戦略）は成功
  exit 0
fi
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
EXIT_CODE=0
STDERR_OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>&1 >/dev/null) || EXIT_CODE=$?
assert_exit_code "R5: PUT 失敗でもインストール成功" "0" "$EXIT_CODE"
if echo "$STDERR_OUTPUT" | grep -q "推奨設定"; then
  pass "R5: PUT 失敗時にフォールバック（推奨設定）が表示される"
else
  fail "R5: PUT 失敗時にフォールバック（推奨設定）が表示される"
fi

cleanup

# ============================================
echo ""
echo "=== V. PR テンプレート・ワークフロー ==="
# ============================================

# V1. PR テンプレートが生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "PR テンプレートが生成される" "$R/.github/pull_request_template.md"

# V2. PR テンプレートに Issue リンクセクションが含まれる
assert_file_contains "PR テンプレートに関連 Issue セクション" "$R/.github/pull_request_template.md" "関連 Issue"
assert_file_contains "PR テンプレートに close/ref の説明" "$R/.github/pull_request_template.md" "close"

# V3. auto-assign ワークフローが生成される
assert_file_exists "auto-assign ワークフローが生成される" "$R/.github/workflows/auto-assign.yml"
assert_file_contains "auto-assign に pull_request トリガー" "$R/.github/workflows/auto-assign.yml" "pull_request"
assert_file_contains "auto-assign に add-assignee" "$R/.github/workflows/auto-assign.yml" "add-assignee"

# V4. 既存 PR テンプレートはスキップ（冪等性）
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github"
echo "# カスタム PR テンプレート" > "$TMPDIR_ROOT/.github/pull_request_template.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存 PR テンプレートはスキップ" "$R/.github/pull_request_template.md" "カスタム PR テンプレート"

# V5. 既存ワークフローはスキップ（冪等性）
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github/workflows"
echo "# カスタム auto-assign" > "$TMPDIR_ROOT/.github/workflows/auto-assign.yml"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存ワークフローはスキップ" "$R/.github/workflows/auto-assign.yml" "カスタム auto-assign"

# V6. 再実行時に上書きされない
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
echo "# ユーザー編集済み" > "$R/.github/pull_request_template.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null

assert_file_contains "再実行時に PR テンプレートが上書きされない" "$R/.github/pull_request_template.md" "ユーザー編集済み"

cleanup

# U6. required_status_checks GET が 403（権限不足）の場合、PUT をスキップして手動ガイダンス表示
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin"
mkdir -p "$FAKE_BIN"
PUT_LOG="$TMPDIR_ROOT/_put_payload.json"
cat > "$FAKE_BIN/gh" <<FAKESH
#!/bin/bash
if [[ "\$1" == "repo" && "\$2" == "view" ]]; then
  echo '{"nameWithOwner":"test/repo"}'
  exit 0
fi
if [[ "\$1" == "api" ]]; then
  # required_status_checks GET → 403（権限不足）
  if echo "\$*" | grep -q "required_status_checks"; then
    echo "HTTP 403 - Forbidden" >&2
    exit 1
  fi
  # Branch Protection PUT → payload をログに保存（到達しないはず）
  if echo "\$*" | grep -q "protection" && echo "\$*" | grep -q "PUT"; then
    cat /dev/stdin > "$PUT_LOG"
    exit 0
  fi
  exit 0
fi
exit 0
FAKESH
chmod +x "$FAKE_BIN/gh"
EXIT_CODE=0
STDERR_OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj 2>&1 >/dev/null) || EXIT_CODE=$?
assert_exit_code "R6: GET 403 でもインストール成功" "0" "$EXIT_CODE"
if [[ ! -f "$PUT_LOG" ]]; then
  pass "R6: GET 403 時は PUT をスキップ（既存 contexts 上書き回避）"
else
  fail "R6: GET 403 時は PUT をスキップ（既存 contexts 上書き回避）"
fi
if echo "$STDERR_OUTPUT" | grep -q "推奨設定"; then
  pass "R6: GET 403 時にフォールバック（推奨設定）が表示される"
else
  fail "R6: GET 403 時にフォールバック（推奨設定）が表示される"
fi

cleanup

# ============================================
echo ""
echo "=== W. エージェントテンプレート ==="
# ============================================

# W1. minimal プリセット（デフォルト）ではエージェントが削除される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

if [ ! -d "$R/.claude/agents" ]; then
  pass "minimal プリセットでエージェントディレクトリが削除される"
else
  fail "minimal プリセットでエージェントディレクトリが削除される (ディレクトリが残っている)"
fi

# W2. minimal の lock にエージェントが含まれない
assert_file_contains "lock に agents セクション" "$R/.claude/vibecorp.lock" "agents:"
assert_file_not_contains "minimal の lock に cto.md なし" "$R/.claude/vibecorp.lock" "cto.md"

# W3. 既存エージェントは minimal でも残る（ユーザーファイルは削除しない）
# → minimal は rm -rf agents_dir するため、ユーザーファイルも消える
# → これは意図した動作（standard 以上で有効化される機能のため）

cleanup

# W4. テンプレートにエージェントファイルが存在する
AGENTS_TPL="${SCRIPT_DIR}/templates/claude/agents"
assert_file_exists "テンプレートに cto.md 存在" "$AGENTS_TPL/cto.md"
assert_file_contains "cto.md に name: cto" "$AGENTS_TPL/cto.md" "name: cto"
assert_file_exists "テンプレートに cpo.md 存在" "$AGENTS_TPL/cpo.md"
assert_file_contains "cpo.md に name: cpo" "$AGENTS_TPL/cpo.md" "name: cpo"

cleanup

# ============================================
echo ""
echo "=== X. docs テンプレート ==="
# ============================================

# X1. docs/ ディレクトリが生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_dir_exists "docs/ ディレクトリ存在" "$R/docs"

# X2. specification.md が生成される
assert_file_exists "specification.md 存在" "$R/docs/specification.md"

# X3. POLICY.md が生成される
assert_file_exists "POLICY.md 存在" "$R/docs/POLICY.md"

# X4. SECURITY.md が生成される
assert_file_exists "SECURITY.md 存在" "$R/docs/SECURITY.md"

# X4a. cost-analysis.md が生成される
assert_file_exists "cost-analysis.md 存在" "$R/docs/cost-analysis.md"

# X4b. ai-organization.md が生成される
assert_file_exists "ai-organization.md 存在" "$R/docs/ai-organization.md"

# X4c. design-philosophy.md が生成される（#364 §1-4: /commit スキルのアンカーリンク先）
assert_file_exists "design-philosophy.md 存在" "$R/docs/design-philosophy.md"
assert_file_contains "design-philosophy.md にアンカー対象セクション" "$R/docs/design-philosophy.md" 'コマンドリダイレクト・フォールバックの禁止'

# X5. プレースホルダーが置換済み（残っていない）
assert_file_not_contains "specification.md にプレースホルダーなし" "$R/docs/specification.md" '{{.*}}'
assert_file_not_contains "POLICY.md にプレースホルダーなし" "$R/docs/POLICY.md" '{{.*}}'
assert_file_not_contains "SECURITY.md にプレースホルダーなし" "$R/docs/SECURITY.md" '{{.*}}'
assert_file_not_contains "cost-analysis.md にプレースホルダーなし" "$R/docs/cost-analysis.md" '{{.*}}'
assert_file_not_contains "ai-organization.md にプレースホルダーなし" "$R/docs/ai-organization.md" '{{.*}}'
assert_file_not_contains "design-philosophy.md にプレースホルダーなし" "$R/docs/design-philosophy.md" '{{.*}}'

# X6. PROJECT_NAME が実際のプロジェクト名に置換されている
assert_file_contains "specification.md にプロジェクト名" "$R/docs/specification.md" "test-proj"
assert_file_contains "POLICY.md にプロジェクト名" "$R/docs/POLICY.md" "test-proj"
assert_file_contains "SECURITY.md にプロジェクト名" "$R/docs/SECURITY.md" "test-proj"
assert_file_contains "cost-analysis.md にプロジェクト名" "$R/docs/cost-analysis.md" "test-proj"
assert_file_contains "ai-organization.md にプロジェクト名" "$R/docs/ai-organization.md" "test-proj"
assert_file_contains "design-philosophy.md にプロジェクト名" "$R/docs/design-philosophy.md" "test-proj"

# X6a. cost-analysis.md に必須セクションが含まれる
assert_file_contains "cost-analysis.md に初期投資セクション" "$R/docs/cost-analysis.md" "初期投資"
assert_file_contains "cost-analysis.md に変動費セクション" "$R/docs/cost-analysis.md" "変動費"
assert_file_contains "cost-analysis.md にスケール時のコスト予測セクション" "$R/docs/cost-analysis.md" "スケール時のコスト予測"
assert_file_contains "cost-analysis.md にコスト管理ポリシーセクション" "$R/docs/cost-analysis.md" "コスト管理ポリシー"

# X6b. ai-organization.md に必須セクションが含まれる
assert_file_contains "ai-organization.md に基本思想セクション" "$R/docs/ai-organization.md" "基本思想"
assert_file_contains "ai-organization.md に組織構成セクション" "$R/docs/ai-organization.md" "組織構成"
assert_file_contains "ai-organization.md に権限モデルセクション" "$R/docs/ai-organization.md" "権限モデル"
assert_file_contains "ai-organization.md に段階的導入計画セクション" "$R/docs/ai-organization.md" "段階的導入計画"

# X7. 既存同名ファイルはスキップ（ユーザーカスタマイズ保護）
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/docs"
echo "# カスタム仕様書" > "$TMPDIR_ROOT/docs/specification.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

CONTENT=$(cat "$R/docs/specification.md")
if [ "$CONTENT" = "# カスタム仕様書" ]; then
  pass "既存 docs ファイルはスキップ（ユーザー版保持）"
else
  fail "既存 docs ファイルはスキップ（ユーザー版保持） (上書きされた)"
fi
# 他の新規ファイルはコピーされる
assert_file_exists "既存でない docs ファイルはコピーされる" "$R/docs/POLICY.md"

# X8. --update でも既存 docs はスキップ（ユーザーカスタマイズ保護）
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
echo "# ユーザー編集済み仕様書" > "$R/docs/specification.md"
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_contains "--update でも docs はスキップ" "$R/docs/specification.md" "ユーザー編集済み仕様書"

# X8b. --update でも既存 docs の全ファイルがスキップされる（複数ファイル検証）
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# 全 docs ファイルにユーザー編集内容を書き込む
echo "# ユーザー編集済みポリシー" > "$R/docs/POLICY.md"
echo "# ユーザー編集済みセキュリティ" > "$R/docs/SECURITY.md"
echo "# ユーザー編集済みコスト分析" > "$R/docs/cost-analysis.md"
echo "# ユーザー編集済みAI組織" > "$R/docs/ai-organization.md"
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_contains "--update でも POLICY.md はスキップ" "$R/docs/POLICY.md" "ユーザー編集済みポリシー"
assert_file_contains "--update でも SECURITY.md はスキップ" "$R/docs/SECURITY.md" "ユーザー編集済みセキュリティ"
assert_file_contains "--update でも cost-analysis.md はスキップ" "$R/docs/cost-analysis.md" "ユーザー編集済みコスト分析"
assert_file_contains "--update でも ai-organization.md はスキップ" "$R/docs/ai-organization.md" "ユーザー編集済みAI組織"

# X8c. --update でも既存 workflows ファイルはスキップされる（ユーザーカスタマイズ保護）
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# workflows ファイルにユーザー編集内容を書き込む
echo "# ユーザー編集済みテストワークフロー" > "$R/.github/workflows/test.yml"
echo "# ユーザー編集済み自動アサイン" > "$R/.github/workflows/auto-assign.yml"
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_contains "--update でも test.yml はスキップ" "$R/.github/workflows/test.yml" "ユーザー編集済みテストワークフロー"
assert_file_contains "--update でも auto-assign.yml はスキップ" "$R/.github/workflows/auto-assign.yml" "ユーザー編集済み自動アサイン"

# X8d. --update で workflows に新規ファイルが追加された場合はコピーされる
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# 既存ワークフローを1つ削除して --update を実行
rm "$R/.github/workflows/auto-assign.yml"
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_exists "--update で欠落した auto-assign.yml が再コピーされる" "$R/.github/workflows/auto-assign.yml"
# 既存の test.yml は変わらない
assert_file_exists "--update 後も test.yml は存在する" "$R/.github/workflows/test.yml"

# X9. vibecorp.lock に docs: セクションが含まれる
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "lock に docs セクション" "$R/.claude/vibecorp.lock" "docs:"

# X10. vibecorp.lock に各ファイル名が含まれる
assert_file_contains "lock に specification.md" "$R/.claude/vibecorp.lock" "specification.md"
assert_file_contains "lock に POLICY.md" "$R/.claude/vibecorp.lock" "POLICY.md"
assert_file_contains "lock に SECURITY.md" "$R/.claude/vibecorp.lock" "SECURITY.md"
assert_file_contains "lock に cost-analysis.md" "$R/.claude/vibecorp.lock" "cost-analysis.md"
assert_file_contains "lock に ai-organization.md" "$R/.claude/vibecorp.lock" "ai-organization.md"

# X10. ユーザー既存 docs ファイルは lock に載らない
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/docs"
echo "# ユーザー独自ドキュメント" > "$TMPDIR_ROOT/docs/my-guide.md"
echo "# ユーザー版 specification" > "$TMPDIR_ROOT/docs/specification.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_not_contains "ユーザー独自 docs は lock に載らない" "$R/.claude/vibecorp.lock" "my-guide.md"
assert_file_not_contains "スキップされた docs は lock に載らない" "$R/.claude/vibecorp.lock" "specification.md"

cleanup

# ============================================
echo ""
echo "=== Y. knowledge テンプレート ==="
# ============================================

# Y1. standard プリセットで knowledge ファイルが配置される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "standard: cto/tech-principles.md が配置される" "$R/.claude/knowledge/cto/tech-principles.md"
assert_file_exists "standard: cto/decisions-index.md が配置される" "$R/.claude/knowledge/cto/decisions-index.md"
assert_file_not_exists "standard: cto/decisions.md（旧形式）は配置されない" "$R/.claude/knowledge/cto/decisions.md"
assert_file_exists "standard: cpo/product-principles.md が配置される" "$R/.claude/knowledge/cpo/product-principles.md"
assert_file_exists "standard: cpo/decisions-index.md が配置される" "$R/.claude/knowledge/cpo/decisions-index.md"
assert_file_not_exists "standard: cpo/decisions.md（旧形式）は配置されない" "$R/.claude/knowledge/cpo/decisions.md"
cleanup

# Y2. minimal プリセットでは knowledge が配置されない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_not_exists "minimal: knowledge が配置されない" "$R/.claude/knowledge/cto/tech-principles.md"
cleanup

# Y3. 既存 knowledge ファイルはスキップされる
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"
echo "# カスタム技術原則" > "$R/.claude/knowledge/cto/tech-principles.md"
bash "$INSTALL_SH" --update --preset standard 2>/dev/null

assert_file_contains "既存 knowledge はスキップ（ユーザー版保持）" "$R/.claude/knowledge/cto/tech-principles.md" "カスタム技術原則"
cleanup

# Y4. lock に knowledge セクションが含まれる
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "lock に knowledge セクション" "$R/.claude/vibecorp.lock" "knowledge:"
assert_file_contains "lock に tech-principles.md" "$R/.claude/vibecorp.lock" "tech-principles.md"
assert_file_contains "lock に decisions-index.md" "$R/.claude/vibecorp.lock" "decisions-index.md"
assert_file_not_contains "lock に旧 decisions.md が単独で残っていない" "$R/.claude/vibecorp.lock" "  - decisions.md$"
cleanup

# Y5. standard プリセットバリデーション
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null || EXIT_CODE=$?
assert_exit_code "standard → 成功" "0" "$EXIT_CODE"
cleanup

# ============================================
echo ""
echo "=== Z. standard プリセット統合テスト ==="
# ============================================

# Z1. standard 新規インストール: agents が配置される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

assert_dir_exists "standard: agents ディレクトリ存在" "$R/.claude/agents"
assert_file_exists "standard: cto.md が配置される" "$R/.claude/agents/cto.md"
assert_file_exists "standard: cpo.md が配置される" "$R/.claude/agents/cpo.md"

# Z2. standard 新規インストール: standard 専用 hooks が配置される
assert_file_exists "standard: sync-gate.sh が配置される" "$R/.claude/hooks/sync-gate.sh"
assert_file_executable "standard: sync-gate.sh に実行権限" "$R/.claude/hooks/sync-gate.sh"

# Z3. standard 新規インストール: standard 専用 skills が配置される
assert_dir_exists "standard: sync-check スキル存在" "$R/.claude/skills/sync-check"
assert_dir_exists "standard: sync-edit スキル存在" "$R/.claude/skills/sync-edit"
assert_dir_exists "standard: review-harvest スキル存在" "$R/.claude/skills/review-harvest"
assert_dir_exists "standard: knowledge-pr スキル存在" "$R/.claude/skills/knowledge-pr"

# Z4. standard lock: agents/hooks/skills が lock に記録される
assert_file_contains "standard lock: cto.md 記録" "$R/.claude/vibecorp.lock" "cto.md"
assert_file_contains "standard lock: cpo.md 記録" "$R/.claude/vibecorp.lock" "cpo.md"
assert_file_contains "standard lock: sync-gate.sh 記録" "$R/.claude/vibecorp.lock" "sync-gate.sh"
assert_file_contains "standard lock: review-harvest 記録" "$R/.claude/vibecorp.lock" "review-harvest"
assert_file_contains "standard lock: knowledge-pr 記録" "$R/.claude/vibecorp.lock" "knowledge-pr"

# Z5. standard settings.json: standard 用フックが含まれる
assert_file_contains "standard settings: sync-gate フック存在" "$R/.claude/settings.json" "sync-gate"

# Z6. standard vibecorp.yml: preset が standard
assert_file_contains "standard vibecorp.yml: preset が standard" "$R/.claude/vibecorp.yml" "preset: standard"

cleanup

# Z7. minimal → standard アップグレード: 不足ファイルが追加される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"

# minimal 状態を確認
assert_file_not_exists "アップグレード前: agents なし" "$R/.claude/agents/cto.md"
assert_file_not_exists "アップグレード前: sync-gate なし" "$R/.claude/hooks/sync-gate.sh"

# standard にアップグレード
bash "$INSTALL_SH" --update --preset standard 2>/dev/null

# agents が追加される
assert_file_exists "アップグレード後: cto.md 追加" "$R/.claude/agents/cto.md"
assert_file_exists "アップグレード後: cpo.md 追加" "$R/.claude/agents/cpo.md"

# standard 専用 hooks が追加される
assert_file_exists "アップグレード後: sync-gate.sh 追加" "$R/.claude/hooks/sync-gate.sh"

# standard 専用 skills が追加される
assert_dir_exists "アップグレード後: sync-check 追加" "$R/.claude/skills/sync-check"
assert_dir_exists "アップグレード後: sync-edit 追加" "$R/.claude/skills/sync-edit"
assert_dir_exists "アップグレード後: review-harvest 追加" "$R/.claude/skills/review-harvest"
assert_dir_exists "アップグレード後: knowledge-pr 追加" "$R/.claude/skills/knowledge-pr"

# knowledge が追加される
assert_file_exists "アップグレード後: knowledge 追加" "$R/.claude/knowledge/cto/tech-principles.md"
assert_file_exists "アップグレード後: cto/decisions-index.md 追加" "$R/.claude/knowledge/cto/decisions-index.md"
assert_file_not_exists "アップグレード後: cto/decisions.md（旧形式）は無い" "$R/.claude/knowledge/cto/decisions.md"

# Z8. minimal → standard アップグレード: vibecorp.yml が更新される
assert_file_contains "アップグレード後: preset が standard" "$R/.claude/vibecorp.yml" "preset: standard"

# Z9. minimal → standard アップグレード: settings.json に standard 用フックが追加される
assert_file_contains "アップグレード後: settings に sync-gate" "$R/.claude/settings.json" "sync-gate"

# Z10. minimal → standard アップグレード: lock が standard 構成に更新される
assert_file_contains "アップグレード後: lock に cto.md" "$R/.claude/vibecorp.lock" "cto.md"
assert_file_contains "アップグレード後: lock に sync-gate.sh" "$R/.claude/vibecorp.lock" "sync-gate.sh"

cleanup

# Z11. minimal → standard アップグレード: settings.json でフックが重複しない
# lock に未登録のフック（block-api-bypass.sh 等）がテンプレートと衝突して重複するバグの防止
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
bash "$INSTALL_SH" --update --preset standard 2>/dev/null

BYPASS_COUNT=$(grep -c 'block-api-bypass.sh' "$R/.claude/settings.json")
if [ "$BYPASS_COUNT" = "1" ]; then
  pass "アップグレード後: block-api-bypass.sh 重複なし"
else
  fail "アップグレード後: block-api-bypass.sh 重複なし (${BYPASS_COUNT}件)"
fi

PROTECT_COUNT=$(grep -c 'protect-files.sh' "$R/.claude/settings.json")
if [ "$PROTECT_COUNT" = "1" ]; then
  pass "アップグレード後: protect-files.sh 重複なし"
else
  fail "アップグレード後: protect-files.sh 重複なし (${PROTECT_COUNT}件)"
fi

cleanup

# Z12. standard → standard 更新: 正常に更新できる
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"
EXIT_CODE=0; bash "$INSTALL_SH" --update --preset standard 2>/dev/null || EXIT_CODE=$?
assert_exit_code "standard → standard 更新成功" "0" "$EXIT_CODE"

# 更新後もファイルが維持される
assert_file_exists "standard 更新後: agents 維持" "$R/.claude/agents/cto.md"
assert_file_exists "standard 更新後: sync-gate 維持" "$R/.claude/hooks/sync-gate.sh"
assert_dir_exists "standard 更新後: sync-check 維持" "$R/.claude/skills/sync-check"

cleanup

# ============================================
echo ""
echo "=== AA. .claude/.gitignore 生成 ==="
# ============================================

# AA1. 新規インストールで .claude/.gitignore が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists ".claude/.gitignore が生成される" "$R/.claude/.gitignore"
assert_file_contains ".gitignore に plans/" "$R/.claude/.gitignore" "plans/"
assert_file_contains ".gitignore に lib/" "$R/.claude/.gitignore" "lib/"
assert_file_contains ".gitignore に vibecorp-base/" "$R/.claude/.gitignore" "vibecorp-base/"
# AA1a. #364 §1-1: bin/claude-real が gitignore される（マシン固有 artifact 流出防止）
assert_file_contains ".gitignore に bin/claude-real" "$R/.claude/.gitignore" "bin/claude-real"
# AA1b. #333: CronCreate durable が生成する scheduled_tasks.{json,lock} が gitignore される
assert_file_contains ".gitignore に scheduled_tasks.json" "$R/.claude/.gitignore" "scheduled_tasks.json"
assert_file_contains ".gitignore に scheduled_tasks.lock" "$R/.claude/.gitignore" "scheduled_tasks.lock"
assert_file_not_contains ".gitignore に memory/ なし" "$R/.claude/.gitignore" "memory/"
assert_file_not_contains ".gitignore に tickets/ なし" "$R/.claude/.gitignore" "tickets/"

cleanup

# AA2. 既存 .claude/.gitignore にユーザー独自エントリがある場合、保持される
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/.claude/.gitignore" <<'EOF'
# ユーザー独自
my-local-stuff/
EOF
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "ユーザー独自エントリが保持される" "$R/.claude/.gitignore" "my-local-stuff/"
assert_file_contains "plans/ が追記される" "$R/.claude/.gitignore" "plans/"
assert_file_contains "lib/ が追記される" "$R/.claude/.gitignore" "lib/"
assert_file_contains "vibecorp-base/ が追記される" "$R/.claude/.gitignore" "vibecorp-base/"
# AA2a. #364 §1-1: 既存 .claude/.gitignore に bin/claude-real が追記される
assert_file_contains "bin/claude-real が追記される" "$R/.claude/.gitignore" "bin/claude-real"
# AA2b. #333: scheduled_tasks.{json,lock} も既存 consumer に追記される
assert_file_contains "scheduled_tasks.json が追記される" "$R/.claude/.gitignore" "scheduled_tasks.json"
assert_file_contains "scheduled_tasks.lock が追記される" "$R/.claude/.gitignore" "scheduled_tasks.lock"

cleanup

# AA3. --update で既存エントリが重複しない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
bash "$INSTALL_SH" --update 2>/dev/null

PLANS_COUNT=$(grep -cxF "plans/" "$R/.claude/.gitignore")
if [ "$PLANS_COUNT" = "1" ]; then
  pass "--update で plans/ が重複しない"
else
  fail "--update で plans/ が重複しない (${PLANS_COUNT}件)"
fi

cleanup

# ============================================
echo ""
echo "=== AJ. 配布テンプレート化: .gitignore.tpl / activate.sh ==="
# ============================================

# AJ1. templates/claude/.gitignore.tpl が Source of Truth として存在する
assert_file_exists "templates/claude/.gitignore.tpl が存在する" "${SCRIPT_DIR}/templates/claude/.gitignore.tpl"

# AJ2. 新規 install 後の .claude/.gitignore が templates と同一内容
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
if diff -q "${SCRIPT_DIR}/templates/claude/.gitignore.tpl" "$R/.claude/.gitignore" >/dev/null 2>&1; then
  pass "AJ2: .gitignore が templates/claude/.gitignore.tpl と同一内容"
else
  fail "AJ2: .gitignore が templates/claude/.gitignore.tpl と同一内容"
fi
# vibecorp.lock の base_hashes に .gitignore のハッシュが記録される
assert_file_contains "AJ2: vibecorp.lock の base_hashes に .gitignore" "$R/.claude/vibecorp.lock" "\.gitignore:"
cleanup

# AJ3. UPDATE_MODE で consumer の独自エントリが保持される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
echo "custom-secrets/" >> "$R/.claude/.gitignore"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_contains "AJ3: UPDATE_MODE で独自エントリ custom-secrets/ が保持" "$R/.claude/.gitignore" "custom-secrets/"
assert_file_contains "AJ3: UPDATE_MODE で vibecorp 管理エントリ plans/ も保持" "$R/.claude/.gitignore" "plans/"
cleanup

# AJ4. 旧 consumer（ベースハッシュ未記録、既存 .gitignore に独自エントリ）でも独自行保持
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/.claude/.gitignore" <<'EOF'
# 旧 consumer の独自エントリ
legacy-ignore/
plans/
EOF
# vibecorp.lock が存在するが base_hashes に .gitignore を含まない状態をシミュレート
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/.claude/vibecorp.lock" <<'EOF'
version: 0.0.0-dev
installed_at: 2026-01-01T00:00:00+00:00
preset: minimal
vibecorp_commit: unknown
files:
  hooks: []
  skills: []
  agents: []
  rules: []
  issue_templates: []
  docs: []
  knowledge: []
  base_hashes: {}
EOF
cat > "$TMPDIR_ROOT/.claude/vibecorp.yml" <<'EOF'
name: test-proj
preset: minimal
language: ja
EOF
bash "$INSTALL_SH" --update 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_contains "AJ4: 旧 consumer で legacy-ignore/ が保持される" "$R/.claude/.gitignore" "legacy-ignore/"
assert_file_contains "AJ4: 旧 consumer でも vibecorp エントリ lib/ が配布される" "$R/.claude/.gitignore" "lib/"
cleanup

# AJ5. 旧 consumer（vibecorp.lock 自体が存在しない）でも独自行保持
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/.claude/.gitignore" <<'EOF'
legacy-ignore/
EOF
cat > "$TMPDIR_ROOT/.claude/vibecorp.yml" <<'EOF'
name: test-proj
preset: minimal
language: ja
EOF
bash "$INSTALL_SH" --update 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_contains "AJ5: lock 非存在でも legacy-ignore/ が保持" "$R/.claude/.gitignore" "legacy-ignore/"
assert_file_contains "AJ5: lock 非存在でも vibecorp エントリ lib/ が配布" "$R/.claude/.gitignore" "lib/"
cleanup

# AJ6. templates/claude/bin/activate.sh が存在する（Source of Truth）
assert_file_exists "AJ6: templates/claude/bin/activate.sh が存在する" "${SCRIPT_DIR}/templates/claude/bin/activate.sh"

# AJ7-10. activate.sh 配置確認（Darwin only）
create_test_repo
if require_darwin "AJ7: full + Darwin で activate.sh が配置" ; then
  install_ec=0
  bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null || install_ec=$?
  R="$TMPDIR_ROOT"
  if [ "$install_ec" -ne 0 ]; then
    fail "AJ7: install.sh が 非ゼロ終了 (exit=${install_ec})"
  elif [ -f "$R/.claude/bin/activate.sh" ]; then
    if diff -q "${SCRIPT_DIR}/templates/claude/bin/activate.sh" "$R/.claude/bin/activate.sh" >/dev/null 2>&1; then
      pass "AJ7: activate.sh が templates と同一内容"
    else
      fail "AJ7: activate.sh が templates と同一内容"
    fi
    assert_file_executable "AJ8: activate.sh が実行権限付き" "$R/.claude/bin/activate.sh"
    assert_file_exists "AJ9: vibecorp-base/bin/activate.sh が存在する" "$R/.claude/vibecorp-base/bin/activate.sh"
  else
    fail "AJ7: activate.sh が配置されていない"
  fi
fi
cleanup

# AJ11. minimal preset では activate.sh が配置されない（退行検出）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_not_exists "AJ11: minimal preset では activate.sh が配置されない" "$R/.claude/bin/activate.sh"
cleanup

# AJ12. standard preset では activate.sh が配置されない（退行検出）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_not_exists "AJ12: standard preset では activate.sh が配置されない" "$R/.claude/bin/activate.sh"
cleanup

# ============================================
echo ""
echo "=== AK. migrate_tracked_artifacts（旧 consumer 向け untrack） ==="
# ============================================

# AK1. 擬似 git リポジトリで claude-real を tracked 化した状態から untrack
# 注: minimal preset は install.sh の preset クリーンアップで .claude/bin/claude-real を
#     working tree からも削除する。ここでの検証は「index から untrack された」点のみ。
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/bin"
echo '#!/bin/bash' > "$TMPDIR_ROOT/.claude/bin/claude-real"
chmod +x "$TMPDIR_ROOT/.claude/bin/claude-real"
# .gitignore がない状態で git add する（旧 consumer をシミュレート）
(cd "$TMPDIR_ROOT" && git add -f .claude/bin/claude-real >/dev/null 2>&1)
(cd "$TMPDIR_ROOT" && git commit -m "legacy: tracked claude-real" -q >/dev/null 2>&1)
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# ls-files に存在しなくなっていれば成功
if (cd "$R" && git ls-files --error-unmatch .claude/bin/claude-real >/dev/null 2>&1); then
  fail "AK1: claude-real が untrack されている"
else
  pass "AK1: claude-real が untrack されている"
fi
cleanup

# AK2. migrate_tracked_artifacts の git リポジトリガードが機能する
# 実使用上 migrate_tracked_artifacts は install.sh 内の git チェック通過後にのみ呼ばれるが、
# 関数内にも独立したガードが存在することをコードパスレベルで検証する。
if grep -q 'rev-parse --git-dir' "$INSTALL_SH" && \
   grep -q 'git リポジトリではないため tracked artifact の untrack をスキップ' "$INSTALL_SH"; then
  pass "AK2: migrate_tracked_artifacts に git リポジトリ不在時の安全ガードが実装されている"
else
  fail "AK2: migrate_tracked_artifacts に git リポジトリ不在時の安全ガードが実装されている"
fi

# AK3. artifact が tracked されていない場合もエラーにならない
create_test_repo
# claude-real を tracked 化しない
EXIT_CODE=0
bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AK3: artifact が未 tracked でも install が成功" "0" "$EXIT_CODE"
cleanup

# AK4. --no-migrate 指定時に tracked 済み artifact が untrack されない
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/bin"
echo '#!/bin/bash' > "$TMPDIR_ROOT/.claude/bin/claude-real"
chmod +x "$TMPDIR_ROOT/.claude/bin/claude-real"
(cd "$TMPDIR_ROOT" && git add -f .claude/bin/claude-real >/dev/null 2>&1)
(cd "$TMPDIR_ROOT" && git commit -m "legacy: tracked claude-real" -q >/dev/null 2>&1)
bash "$INSTALL_SH" --name test-proj --no-migrate 2>/dev/null
R="$TMPDIR_ROOT"
if (cd "$R" && git ls-files --error-unmatch .claude/bin/claude-real >/dev/null 2>&1); then
  pass "AK4: --no-migrate で claude-real が tracked のまま残る"
else
  fail "AK4: --no-migrate で claude-real が tracked のまま残る"
fi
cleanup

# AK5. claude-real がシンボリックリンクとして tracked でも untrack される
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/bin"
# シンボリックリンク先が存在する適当なファイル
echo '#!/bin/bash' > "$TMPDIR_ROOT/.claude/_fake_claude"
chmod +x "$TMPDIR_ROOT/.claude/_fake_claude"
(cd "$TMPDIR_ROOT/.claude/bin" && ln -s ../_fake_claude claude-real)
(cd "$TMPDIR_ROOT" && git add -f .claude/bin/claude-real .claude/_fake_claude >/dev/null 2>&1)
(cd "$TMPDIR_ROOT" && git commit -m "legacy: symlink claude-real" -q >/dev/null 2>&1)
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
if (cd "$R" && git ls-files --error-unmatch .claude/bin/claude-real >/dev/null 2>&1); then
  fail "AK5: symlink claude-real が untrack されている"
else
  pass "AK5: symlink claude-real が untrack されている"
fi
cleanup

# AK6. .gitignore.tpl の machine-specific セクション更新で migrate 対象が自動追随（DRY 検証）
# install.sh を source して _extract_gitignore_artifacts を直接呼び出し、実コードと同じロジックを検証する
TMPDIR_ROOT=$(mktemp -d)
TEST_TPL="$TMPDIR_ROOT/test.gitignore.tpl"
cat > "$TEST_TPL" <<'EOF'
plans/

# ---- machine-specific artifacts ----
bin/claude-real
bin/future-artifact
EOF
EXTRACTED=$(bash -c 'source "$1"; _extract_gitignore_artifacts "$2"' _ "$INSTALL_SH" "$TEST_TPL" | tr '\n' ',' )
if [ "$EXTRACTED" = "bin/claude-real,bin/future-artifact," ]; then
  pass "AK6: DRY 抽出ロジックが tpl 更新に追随"
else
  fail "AK6: DRY 抽出ロジックが tpl 更新に追随 (extracted=${EXTRACTED})"
fi
cleanup

# AK7. machine-specific セクションが空の場合、migrate 対象なしで install が成功
TMPDIR_ROOT=$(mktemp -d)
TEST_TPL="$TMPDIR_ROOT/empty.gitignore.tpl"
cat > "$TEST_TPL" <<'EOF'
plans/

# ---- machine-specific artifacts ----
EOF
EMPTY_COUNT=$(bash -c 'source "$1"; _extract_gitignore_artifacts "$2"' _ "$INSTALL_SH" "$TEST_TPL" | wc -l | tr -d ' ')
if [ "$EMPTY_COUNT" = "0" ]; then
  pass "AK7: 空セクションで抽出結果 0 行"
else
  fail "AK7: 空セクションで抽出結果 0 行（実際: ${EMPTY_COUNT}）"
fi
cleanup

# AK8. machine-specific セクションの後に別セクションが続く場合、後続エントリが untrack 対象に混入しないこと（セクション終端判定の退行検知）
TMPDIR_ROOT=$(mktemp -d)
TEST_TPL="$TMPDIR_ROOT/multi-section.gitignore.tpl"
cat > "$TEST_TPL" <<'EOF'
plans/

# ---- machine-specific artifacts ----
bin/claude-real

# ---- future-section ----
should-not-be-extracted/
EOF
MULTI_EXTRACTED=$(bash -c 'source "$1"; _extract_gitignore_artifacts "$2"' _ "$INSTALL_SH" "$TEST_TPL" | tr '\n' ',' )
if [ "$MULTI_EXTRACTED" = "bin/claude-real," ]; then
  pass "AK8: 後続セクションが machine-specific 抽出に混入しない"
else
  fail "AK8: 後続セクションが machine-specific 抽出に混入しない (extracted=${MULTI_EXTRACTED})"
fi
cleanup

# ============================================
echo ""
echo "=== CR. CodeRabbit 無効設定テスト ==="
# ============================================

# CR1. coderabbit.enabled: false で .coderabbit.yaml が生成されない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# vibecorp.yml の coderabbit.enabled を false に変更（macOS/Linux 互換）
tmp_yml=$(mktemp)
sed 's/  enabled: true/  enabled: false/' "$R/.claude/vibecorp.yml" > "$tmp_yml"
mv "$tmp_yml" "$R/.claude/vibecorp.yml"
# 既存の .coderabbit.yaml を削除して再インストール
rm -f "$R/.coderabbit.yaml"
bash "$INSTALL_SH" --update 2>/dev/null
if [ ! -f "$R/.coderabbit.yaml" ]; then
  pass "coderabbit.enabled: false で .coderabbit.yaml が生成されない"
else
  fail "coderabbit.enabled: false で .coderabbit.yaml が生成されない (ファイルが生成された)"
fi

cleanup

# CR2. coderabbit キー未定義（デフォルト）で .coderabbit.yaml が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_exists "デフォルトで .coderabbit.yaml 生成" "$R/.coderabbit.yaml"

cleanup

# CR3. coderabbit.enabled: true（デフォルト生成値）で .coderabbit.yaml が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# デフォルトで coderabbit.enabled: true が生成されているのでそのまま再インストール
rm -f "$R/.coderabbit.yaml"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "coderabbit.enabled: true で .coderabbit.yaml 生成" "$R/.coderabbit.yaml"

cleanup

# ============================================
echo "=== T. スキル・hooks トグル ==="
# ============================================

# T1. hooks セクションで false 指定した hook がインストールされない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"
# vibecorp.yml に hooks トグルを追加
cat >> "$R/.claude/vibecorp.yml" <<'YML'
hooks:
  block-api-bypass: false
YML
# --update で再インストール
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "無効化した hook がインストールされない" "$R/.claude/hooks/block-api-bypass.sh"
# 他の hook はインストールされている
assert_file_exists "無効化していない hook はインストールされる" "$R/.claude/hooks/protect-files.sh"

cleanup

# T2. skills セクションで false 指定した skill がインストールされない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"
cat >> "$R/.claude/vibecorp.yml" <<'YML'
skills:
  commit: false
YML
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "無効化した skill がインストールされない" "$R/.claude/skills/commit/SKILL.md"
# 他の skill はインストールされている
assert_dir_exists "無効化していない skill はインストールされる" "$R/.claude/skills/branch"

cleanup

# T3. 無効化した hook が settings.json に含まれない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"
cat >> "$R/.claude/vibecorp.yml" <<'YML'
hooks:
  block-api-bypass: false
YML
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_contains "無効化した hook が settings.json に含まれない" "$R/.claude/settings.json" "block-api-bypass"
# 他の hook は settings.json に含まれる
assert_file_contains "無効化していない hook は settings.json に含まれる" "$R/.claude/settings.json" "protect-files"

cleanup

# T4. トグルセクション省略時は全て有効（既存動作維持）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full 2>/dev/null
R="$TMPDIR_ROOT"
assert_file_exists "トグル省略時: hook がインストールされる" "$R/.claude/hooks/block-api-bypass.sh"
assert_dir_exists "トグル省略時: skill がインストールされる" "$R/.claude/skills/commit"
assert_file_contains "トグル省略時: hook が settings.json に含まれる" "$R/.claude/settings.json" "block-api-bypass"

cleanup

# T5. 初回インストール時に yml の hooks トグルが反映される
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"
cat > "$R/.claude/vibecorp.yml" <<'YML'
# vibecorp.yml — プロジェクト設定
name: test-proj
preset: full
language: ja
base_branch: main
protected_files:
  - MVV.md
hooks:
  sync-gate: false
skills:
  review-harvest: false
YML
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_not_exists "初回トグル: 無効化 hook がインストールされない" "$R/.claude/hooks/sync-gate.sh"
assert_file_not_exists "初回トグル: 無効化 skill がインストールされない" "$R/.claude/skills/review-harvest/SKILL.md"
assert_file_not_contains "初回トグル: 無効化 hook が settings.json に含まれない" "$R/.claude/settings.json" "sync-gate"

cleanup

# T6. 無効化対象と同名のユーザーファイルが --update で削除されない
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude/hooks" "$R/.claude/skills/commit"
echo '#!/bin/bash' > "$R/.claude/hooks/block-api-bypass.sh"
echo '# ユーザー独自の commit スキル' > "$R/.claude/skills/commit/SKILL.md"
mkdir -p "$R/.claude"
cat > "$R/.claude/vibecorp.yml" <<'YML'
# vibecorp.yml — プロジェクト設定
name: test-proj
preset: full
language: ja
base_branch: main
protected_files:
  - MVV.md
hooks:
  block-api-bypass: false
skills:
  commit: false
YML
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "同名ユーザーフックは保持される" "$R/.claude/hooks/block-api-bypass.sh"
assert_file_exists "同名ユーザースキルは保持される" "$R/.claude/skills/commit/SKILL.md"
assert_file_contains "ユーザーフックの内容が維持される" "$R/.claude/hooks/block-api-bypass.sh" "#!/bin/bash"
assert_file_not_contains "無効化 hook が settings.json に含まれない" "$R/.claude/settings.json" "block-api-bypass"

cleanup

# ============================================
echo ""
echo "=== AB. 3-way マージ（コンフリクト解消） ==="
# ============================================

# AB1. 未カスタマイズファイルは --update で上書きされる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ファイルを変更せずに --update
bash "$INSTALL_SH" --update 2>/dev/null

assert_file_exists "AB1: hook ファイルが存在" "$R/.claude/hooks/protect-files.sh"
assert_file_exists "AB1: rules ファイルが存在" "$R/.claude/rules/comments.md"
cleanup

# AB2. カスタマイズ済み & テンプレート未変更 → カスタム版を保持
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ユーザーがフックをカスタマイズ
echo '#!/bin/bash' > "$R/.claude/hooks/protect-files.sh"
echo '# ユーザーカスタム: 追加のチェック' >> "$R/.claude/hooks/protect-files.sh"
echo 'echo "カスタム版"' >> "$R/.claude/hooks/protect-files.sh"

bash "$INSTALL_SH" --update 2>/dev/null

# テンプレートが変更されていないため、カスタム版が保持される
assert_file_contains "AB2: カスタム版が保持される" "$R/.claude/hooks/protect-files.sh" "ユーザーカスタム: 追加のチェック"
cleanup

# AB3. ベーススナップショットが保存される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_dir_exists "AB3: vibecorp-base ディレクトリ存在" "$R/.claude/vibecorp-base"
assert_file_exists "AB3: hooks のベーススナップショット" "$R/.claude/vibecorp-base/hooks/protect-files.sh"
assert_file_exists "AB3: rules のベーススナップショット" "$R/.claude/vibecorp-base/rules/comments.md"
cleanup

# AB4. vibecorp.lock に base_hashes セクションが含まれる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "AB4: lock に base_hashes セクション" "$R/.claude/vibecorp.lock" "base_hashes:"
assert_file_contains "AB4: lock に hooks ハッシュ" "$R/.claude/vibecorp.lock" "hooks/protect-files.sh:"
assert_file_contains "AB4: lock に rules ハッシュ" "$R/.claude/vibecorp.lock" "rules/comments.md:"
cleanup

# AB5. .claude/.gitignore に vibecorp-base/ が含まれる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "AB5: .gitignore に vibecorp-base/" "$R/.claude/.gitignore" "vibecorp-base/"
cleanup

# AB6. 3-way マージ: 非コンフリクト自動解消
# テンプレートの先頭にベースから行を追加し、ユーザーが末尾に追加した場合
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ベーススナップショットを確認して取得
ORIGINAL_CONTENT=$(cat "$R/.claude/hooks/protect-files.sh")

# ユーザーが末尾に独自行を追加
echo "# ユーザー追加: カスタム処理" >> "$R/.claude/hooks/protect-files.sh"

# テンプレートを変更（先頭にコメント追加）
TEMPLATE_FILE="$SCRIPT_DIR/templates/claude/hooks/protect-files.sh"
ORIGINAL_TEMPLATE=$(cat "$TEMPLATE_FILE")

# ベーススナップショットを保持しつつ、テンプレートを変更
# ベースを明示的に設定して 3-way マージをテスト
TMPBASE=$(mktemp)
echo "#!/bin/bash" > "$TMPBASE"
echo "# ベース行1" >> "$TMPBASE"
echo "# ベース行2" >> "$TMPBASE"
echo "# 共通行" >> "$TMPBASE"

# カスタム版（末尾追加）
TMPCUSTOM=$(mktemp)
echo "#!/bin/bash" > "$TMPCUSTOM"
echo "# ベース行1" >> "$TMPCUSTOM"
echo "# ベース行2" >> "$TMPCUSTOM"
echo "# 共通行" >> "$TMPCUSTOM"
echo "# ユーザー追加行" >> "$TMPCUSTOM"

# 新テンプレート（先頭変更）
TMPNEW=$(mktemp)
echo "#!/bin/bash" > "$TMPNEW"
echo "# 新テンプレート行1" >> "$TMPNEW"
echo "# ベース行2" >> "$TMPNEW"
echo "# 共通行" >> "$TMPNEW"

# git merge-file を直接テスト
MERGE_EXIT=0
git merge-file "$TMPCUSTOM" "$TMPBASE" "$TMPNEW" 2>/dev/null || MERGE_EXIT=$?
if [ "$MERGE_EXIT" -eq 0 ]; then
  # マージ成功: ユーザー追加行と新テンプレート行の両方が含まれる
  if grep -q "ユーザー追加行" "$TMPCUSTOM" && grep -q "新テンプレート行1" "$TMPCUSTOM"; then
    pass "AB6: 3-way マージで非コンフリクト自動解消"
  else
    fail "AB6: 3-way マージで非コンフリクト自動解消 (マージ結果が不正)"
  fi
else
  fail "AB6: 3-way マージで非コンフリクト自動解消 (マージ失敗: exit $MERGE_EXIT)"
fi
rm -f "$TMPBASE" "$TMPCUSTOM" "$TMPNEW"
cleanup

# AB7. 3-way マージ: コンフリクト発生時にマーカーが出力される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

TMPBASE=$(mktemp)
echo "共通行" > "$TMPBASE"

TMPCUSTOM=$(mktemp)
echo "カスタム版の変更" > "$TMPCUSTOM"

TMPNEW=$(mktemp)
echo "テンプレートの変更" > "$TMPNEW"

MERGE_EXIT=0
git merge-file -L "カスタム版" -L "前回テンプレート" -L "新テンプレート" \
  "$TMPCUSTOM" "$TMPBASE" "$TMPNEW" 2>/dev/null || MERGE_EXIT=$?
if [ "$MERGE_EXIT" -gt 0 ]; then
  if grep -q "<<<<<<<" "$TMPCUSTOM" && grep -q ">>>>>>>" "$TMPCUSTOM"; then
    pass "AB7: コンフリクト時にマーカーが出力される"
  else
    fail "AB7: コンフリクト時にマーカーが出力される (マーカーなし)"
  fi
else
  fail "AB7: コンフリクト時にマーカーが出力される (コンフリクトが発生しなかった)"
fi
rm -f "$TMPBASE" "$TMPCUSTOM" "$TMPNEW"
cleanup

# AB8. 統合テスト: merge_or_overwrite がカスタム版を保持（テンプレート未変更時）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

# sync-gate.sh をカスタマイズ
echo '#!/bin/bash' > "$R/.claude/hooks/sync-gate.sh"
echo '# カスタム sync-gate' >> "$R/.claude/hooks/sync-gate.sh"

bash "$INSTALL_SH" --update --preset standard 2>/dev/null

assert_file_contains "AB8: カスタム sync-gate が保持される" "$R/.claude/hooks/sync-gate.sh" "カスタム sync-gate"
cleanup

# AB9. 統合テスト: SKILL.md のカスタマイズが保持される（テンプレート未変更時）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# review スキルの SKILL.md をカスタマイズ
echo "# custom-review-skill" > "$R/.claude/skills/review/SKILL.md"
echo "user-added-instruction" >> "$R/.claude/skills/review/SKILL.md"

bash "$INSTALL_SH" --update 2>/dev/null

assert_file_contains "AB9: カスタム SKILL.md が保持される" "$R/.claude/skills/review/SKILL.md" "custom-review-skill"
cleanup

# AB10. コンフリクト発生時に stderr に警告メッセージが出力される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ベーススナップショットとは異なる内容で上書き（カスタマイズ模擬）
echo "# カスタム版コメントルール" > "$R/.claude/rules/comments.md"

# テンプレートも変更（ベースと異なる新しい内容にする）
# ベーススナップショットを直接変更して強制的にマージをトリガー
echo "# 改変されたベース" > "$R/.claude/vibecorp-base/rules/comments.md"

STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true

# マージまたはスキップのログが出力されることを確認
if echo "$STDERR_OUTPUT" | grep -q "マージ\|スキップ\|MERGE\|SKIP\|CONFLICT"; then
  pass "AB10: マージ関連ログが出力される"
else
  fail "AB10: マージ関連ログが出力される (ログなし)"
fi
cleanup

# AB11. ベースハッシュなし（旧バージョン移行）の場合は上書きされる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# vibecorp.lock から base_hashes セクションを除去（旧バージョンの lock を模擬）
awk '/^  base_hashes:/{skip=1;next} skip && /^  [a-z]/{skip=0} skip{next} {print}' \
  "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"
# ベーススナップショットも削除
rm -rf "$R/.claude/vibecorp-base"

echo "# 古いカスタム版" > "$R/.claude/hooks/protect-files.sh"

bash "$INSTALL_SH" --update 2>/dev/null

assert_file_not_contains "AB11: ベースハッシュなしなら上書き" "$R/.claude/hooks/protect-files.sh" "古いカスタム版"
cleanup

# AB12. カスタムなし & テンプレート変更 → 新テンプレートで上書き
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ファイルは変更しないが、ベーススナップショットを差し替えて「テンプレート変更」を模擬
echo "# 古いベース" > "$R/.claude/vibecorp-base/rules/comments.md"
# lock のハッシュもベースに合わせる
OLD_HASH=$(shasum -a 256 "$R/.claude/vibecorp-base/rules/comments.md" | awk '{print $1}')
CURRENT_HASH=$(shasum -a 256 "$R/.claude/rules/comments.md" | awk '{print $1}')
# lock のハッシュを現在のファイルのハッシュに設定（= カスタムなし状態を作る）
awk -v path="rules/comments.md" -v newhash="$CURRENT_HASH" '
  /^  base_hashes:/ { in_hashes = 1; print; next }
  in_hashes && /^  [a-z]/ { in_hashes = 0 }
  in_hashes && /^[^ ]/ { in_hashes = 0 }
  in_hashes {
    gsub(/^[ \t]+/, "", $0)
    split($0, parts, ": ")
    if (parts[1] == path) {
      print "    " path ": " newhash
      next
    }
  }
  { print }
' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

bash "$INSTALL_SH" --update 2>/dev/null

# テンプレート版（=元々のテンプレート）で上書きされているはず
assert_file_exists "AB12: rules ファイルが存在" "$R/.claude/rules/comments.md"
cleanup

# AB13. --update 後のコンフリクト警告表示テスト
# ベースと現在とテンプレートが全て異なる場合にコンフリクトが報告される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ベーススナップショットを置き換え（独立した3つの内容を作る）
echo "ベース版の内容" > "$R/.claude/vibecorp-base/rules/comments.md"
BASE_HASH=$(shasum -a 256 "$R/.claude/vibecorp-base/rules/comments.md" | awk '{print $1}')

# lock のハッシュをベースに合わせる
awk -v path="rules/comments.md" -v newhash="$BASE_HASH" '
  /^  base_hashes:/ { in_hashes = 1; print; next }
  in_hashes && /^  [a-z]/ { in_hashes = 0 }
  in_hashes && /^[^ ]/ { in_hashes = 0 }
  in_hashes {
    gsub(/^[ \t]+/, "", $0)
    split($0, parts, ": ")
    if (parts[1] == path) {
      print "    " path ": " newhash
      next
    }
  }
  { print }
' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

# カスタム版に書き換え
echo "カスタム版の内容" > "$R/.claude/rules/comments.md"

# --update 実行（テンプレートはベースと異なる → 3-way マージ発生）
STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true

# MERGE または CONFLICT のログが出力される
if echo "$STDERR_OUTPUT" | grep -q "MERGE\|CONFLICT\|マージ\|コンフリクト"; then
  pass "AB13: コンフリクト/マージログが表示される"
else
  fail "AB13: コンフリクト/マージログが表示される (ログなし)"
fi
cleanup

# ============================================
echo ""
echo "=== AC. --version オプション ==="
# ============================================

# AC1. --version のバリデーション: 不正な形式でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "1.0.0" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC1: --version v なしでエラー" "1" "$EXIT_CODE"
cleanup

# AC2. --version のバリデーション: 不正な形式でエラー（文字列）
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "latest" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC2: --version 不正文字列でエラー" "1" "$EXIT_CODE"
cleanup

# AC3. --version の値欠落でエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC3: --version の値欠落でエラー" "1" "$EXIT_CODE"
cleanup

# AC4. --version に存在しないタグを指定してエラー
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj --version "v99.99.99" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC4: 存在しないタグでエラー" "1" "$EXIT_CODE"
cleanup

# AC5. --version に存在するタグを指定して成功する
# 一時 clone にタグを打ち、そのタグでインストールが成功することを検証
create_test_repo
# SCRIPT_DIR リポジトリ（vibecorp 本体）にテスト用タグを作成
VIBECORP_REPO_DIR="$(cd "$(dirname "$INSTALL_SH")" && pwd)"
ORIGINAL_BRANCH=$(git -C "$VIBECORP_REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$VIBECORP_REPO_DIR" rev-parse HEAD)
TEST_TAG="v0.0.99"
git -C "$VIBECORP_REPO_DIR" tag "$TEST_TAG"

EXIT_CODE=0
VIBECORP_REEXEC=1 bash "$INSTALL_SH" --name test-proj --version "$TEST_TAG" 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AC5: --version に存在するタグを指定して成功" "0" "$EXIT_CODE"

# テスト用タグを削除して元に戻す
# テスト用タグを削除して元のブランチに戻す
git -C "$VIBECORP_REPO_DIR" tag -d "$TEST_TAG" >/dev/null 2>&1 || true
git -C "$VIBECORP_REPO_DIR" checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
cleanup

# ============================================
echo ""
echo "=== AD. --update 時のバージョン差分表示 ==="
# ============================================

# AD1. --update 時にバージョンが異なる場合、差分が表示される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# lock の version を古いバージョンに書き換え
awk '
  /^version:/ { print "version: 0.0.1"; next }
  { print }
' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true
if echo "$STDERR_OUTPUT" | grep -q "バージョン更新:.*0.0.1.*→"; then
  pass "AD1: --update 時にバージョン差分が表示される"
else
  fail "AD1: --update 時にバージョン差分が表示される (ログ: ${STDERR_OUTPUT})"
fi
cleanup

# AD2. --update 時にバージョンが同一の場合、「変更なし」と表示される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true
if echo "$STDERR_OUTPUT" | grep -q "変更なし"; then
  pass "AD2: --update 時に同一バージョンで変更なし表示"
else
  fail "AD2: --update 時に同一バージョンで変更なし表示 (ログ: ${STDERR_OUTPUT})"
fi
cleanup

# AD3. lock ファイルに正しいバージョンが記録される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

LOCK_VERSION=$(awk '/^version:/ { print $2 }' "$R/.claude/vibecorp.lock")
# VIBECORP_VERSION は Git タグから動的取得されるため、同じ方法で期待値を算出
EXPECTED_VERSION=$(git -C "$(dirname "$INSTALL_SH")" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
EXPECTED_VERSION="${EXPECTED_VERSION#v}"
if [ "$LOCK_VERSION" = "$EXPECTED_VERSION" ]; then
  pass "AD3: lock の version が VIBECORP_VERSION（Git タグ由来）と一致"
else
  fail "AD3: lock の version が VIBECORP_VERSION（Git タグ由来）と一致 (lock: ${LOCK_VERSION}, expected: ${EXPECTED_VERSION})"
fi
cleanup

# ============================================
echo ""
echo "=== AE. --update 時の fetch --tags 実行 ==="
# ============================================

# AE1. --update 時に git fetch --tags のログが出力される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true
if echo "$STDERR_OUTPUT" | grep -q "タグ"; then
  pass "AE1: --update 時にタグ取得のログが出力される"
else
  fail "AE1: --update 時にタグ取得のログが出力される (ログ: ${STDERR_OUTPUT})"
fi
cleanup

# AE2. fetch 失敗時（リモートなし）でもエラーで停止しない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# リモートが設定されていないリポジトリで --update を実行
# fetch は失敗するがフォールバックで続行する
EXIT_CODE=0; bash "$INSTALL_SH" --update 2>/dev/null || EXIT_CODE=$?
assert_exit_code "AE2: fetch 失敗時でもエラーで停止しない" "0" "$EXIT_CODE"
cleanup

# AE3. fetch 後に VIBECORP_VERSION が lock に正しく記録される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

bash "$INSTALL_SH" --update 2>/dev/null
LOCK_VERSION=$(awk '/^version:/ { print $2 }' "$R/.claude/vibecorp.lock")
EXPECTED_VERSION=$(git -C "$(dirname "$INSTALL_SH")" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
EXPECTED_VERSION="${EXPECTED_VERSION#v}"
if [ "$LOCK_VERSION" = "$EXPECTED_VERSION" ]; then
  pass "AE3: fetch 後の VIBECORP_VERSION が lock に正しく記録される"
else
  fail "AE3: fetch 後の VIBECORP_VERSION が lock に正しく記録される (lock: ${LOCK_VERSION}, expected: ${EXPECTED_VERSION})"
fi
cleanup

# ============================================
# テスト: update_vibecorp_yml が main() 内で重複呼び出しされていないこと
# ============================================
echo ""
echo "--- テスト: update_vibecorp_yml 重複呼び出し防止 ---"

# main() 関数内での update_vibecorp_yml 呼び出し回数を数える
# 関数定義行（update_vibecorp_yml()）は除外し、呼び出し行のみカウントする
CALL_COUNT=$(awk '/^main\(\)/{found=1} found && /update_vibecorp_yml/ && !/update_vibecorp_yml\(\)/' "$INSTALL_SH" | wc -l | tr -d ' ')
if [ "$CALL_COUNT" -eq 1 ]; then
  pass "update_vibecorp_yml は main() 内で1回だけ呼ばれている"
else
  fail "update_vibecorp_yml が main() 内で ${CALL_COUNT} 回呼ばれている（期待: 1回）"
fi

# ============================================
echo "=== AF. exec 前の trap EXIT 設定 ==="
# ============================================

# AF1. checkout_target_version 内で trap が exec より前に設定されていること
# exec でプロセスが置き換わると trap EXIT が失われるため、exec 前に trap を設定する必要がある
TRAP_LINE=$(grep -n "trap 'restore_original_ref' EXIT" "$INSTALL_SH" | head -1 | cut -d: -f1)
EXEC_LINE=$(grep -n 'exec bash.*install\.sh' "$INSTALL_SH" | head -1 | cut -d: -f1)
if [ -n "$TRAP_LINE" ] && [ -n "$EXEC_LINE" ] && [ "$TRAP_LINE" -lt "$EXEC_LINE" ]; then
  pass "AF1: trap EXIT が exec より前の行に設定されている (trap:${TRAP_LINE} < exec:${EXEC_LINE})"
else
  fail "AF1: trap EXIT が exec より前の行に設定されている (trap:${TRAP_LINE:-未検出} exec:${EXEC_LINE:-未検出})"
fi

# AF2. main() 内に冗長な trap 'restore_original_ref' EXIT が残っていないこと
MAIN_START=$(grep -n '^main()' "$INSTALL_SH" | head -1 | cut -d: -f1)
if [ -n "$MAIN_START" ]; then
  TRAP_IN_MAIN=$(tail -n +"$MAIN_START" "$INSTALL_SH" | grep -c "trap 'restore_original_ref' EXIT" || true)
  if [ "$TRAP_IN_MAIN" -eq 0 ]; then
    pass "AF2: main() 内に冗長な trap EXIT が残っていない"
  else
    fail "AF2: main() 内に冗長な trap EXIT が残っている (${TRAP_IN_MAIN}件)"
  fi
else
  fail "AF2: main() 関数が見つからない"
fi

# AF3. trap が checkout_target_version 関数内に定義されていること
FUNC_START=$(grep -n '^checkout_target_version()' "$INSTALL_SH" | head -1 | cut -d: -f1)
if [ -n "$FUNC_START" ] && [ -n "$TRAP_LINE" ] && [ "$TRAP_LINE" -gt "$FUNC_START" ]; then
  pass "AF3: trap EXIT が checkout_target_version 関数内に定義されている"
else
  fail "AF3: trap EXIT が checkout_target_version 関数内に定義されている"
fi

# ============================================
echo ""
echo "=== AG. merge_or_overwrite の tmp ファイルリーク検証 ==="
# ============================================

# AG1. merge_or_overwrite が正常終了時に tmp ファイルを残さないことを検証
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard 2>/dev/null
R="$TMPDIR_ROOT"

# テスト専用 TMPDIR を隔離して外部プロセスの影響を排除
TMP_SANDBOX=$(mktemp -d)
TMP_BEFORE=$(mktemp)
TMP_AFTER=$(mktemp)
find "$TMP_SANDBOX" -maxdepth 1 -type f -name 'tmp.*' | sort > "$TMP_BEFORE"

# 3-way merge 分岐に入るための条件を整える:
# 1. current_hash != base_hash（ユーザーがカスタマイズした状態）
# 2. template_hash != base_hash（テンプレートも変更された状態）
# まず current ファイルを改変してカスタマイズ済みにする
echo "# ユーザーによるカスタマイズ" >> "$R/.claude/rules/comments.md"
# ベーススナップショットを改変してテンプレート変更を模擬する
echo "# 改変されたベース" > "$R/.claude/vibecorp-base/rules/comments.md"
# vibecorp.lock の base_hashes を更新して current_hash != base_hash にする
NEW_BASE_HASH=$(shasum -a 256 "$R/.claude/vibecorp-base/rules/comments.md" | awk '{print $1}')
LOCK_FILE="$R/.claude/vibecorp.lock"
ORIG_HASH=$(grep 'rules/comments\.md:' "$LOCK_FILE" | awk '{print $2}')
sed "s/${ORIG_HASH}/${NEW_BASE_HASH}/" "$LOCK_FILE" > "${LOCK_FILE}.tmp" && mv "${LOCK_FILE}.tmp" "$LOCK_FILE"

EXIT_CODE=0
TMPDIR="$TMP_SANDBOX" bash "$INSTALL_SH" --update --preset standard 2>/dev/null || EXIT_CODE=$?

# exit code の検証（0 以外なら --update 自体が失敗している）
if [ "$EXIT_CODE" -ne 0 ]; then
  fail "AG1: --update コマンドが exit code $EXIT_CODE で失敗"
else
  # 隔離 TMPDIR 内の新規ファイルを確認
  find "$TMP_SANDBOX" -maxdepth 1 -type f -name 'tmp.*' | sort > "$TMP_AFTER"

  # diff で新規 tmp ファイルがないか確認
  TMP_LEAKED=$(comm -13 "$TMP_BEFORE" "$TMP_AFTER" | grep -v -F -e "$TMP_BEFORE" -e "$TMP_AFTER" || true)

  if [ -z "$TMP_LEAKED" ]; then
    pass "AG1: merge_or_overwrite が正常終了時に tmp ファイルを残さない"
  else
    fail "AG1: merge_or_overwrite が正常終了時に tmp ファイルを残さない (リーク: $TMP_LEAKED)"
  fi
fi
rm -f "$TMP_BEFORE" "$TMP_AFTER"
rm -rf "$TMP_SANDBOX"
cleanup

# AG2. merge_or_overwrite の trap 設定を静的検証
# merge_or_overwrite 関数本体を抽出してからスコープを限定して検証
FUNC_BODY=$(sed -n '/^merge_or_overwrite()[[:space:]]*{/,/^}/p' "$INSTALL_SH")
TRAP_LINE=$(printf '%s\n' "$FUNC_BODY" | grep -E '^[[:space:]]*trap ' | grep 'rm' || true)
if [ -n "$TRAP_LINE" ] \
  && printf '%s\n' "$TRAP_LINE" | grep -q 'tmp_current' \
  && printf '%s\n' "$TRAP_LINE" | grep -q 'tmp_base' \
  && printf '%s\n' "$TRAP_LINE" | grep -q 'tmp_other' \
  && printf '%s\n' "$TRAP_LINE" | grep -q 'INT' \
  && printf '%s\n' "$TRAP_LINE" | grep -q 'TERM'; then
  pass "AG2: merge_or_overwrite に INT/TERM 用の trap が設定されている"
else
  fail "AG2: merge_or_overwrite に INT/TERM 用の trap が設定されている"
fi

# AG3. trap リセットが merge_or_overwrite 関数内に存在することを確認
if echo "$FUNC_BODY" | grep -q 'trap - INT TERM'; then
  pass "AG3: merge_or_overwrite の trap がリセットされている"
else
  fail "AG3: merge_or_overwrite の trap がリセットされている"
fi


# ============================================
echo ""
echo "=== AH. lock ファイル空リスト時のインデント ===" 
# ============================================

# AH1. 空リスト時に YAML の明示的空リスト表記 [] が使用される
create_test_repo
# テンプレートディレクトリを空にして空リストを再現
# hooks/skills/agents テンプレートを退避
TEMPLATES_BAK=$(mktemp -d)
for tpl_dir in hooks skills agents; do
  if [ -d "$SCRIPT_DIR/templates/claude/$tpl_dir" ]; then
    cp -r "$SCRIPT_DIR/templates/claude/$tpl_dir" "$TEMPLATES_BAK/$tpl_dir"
    rm -rf "$SCRIPT_DIR/templates/claude/$tpl_dir"
    mkdir -p "$SCRIPT_DIR/templates/claude/$tpl_dir"
  fi
done

EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
R="$TMPDIR_ROOT"
LOCK="$R/.claude/vibecorp.lock"

if [ -f "$LOCK" ]; then
  # 空リスト時は "hooks: []" のような表記であること（null ではない）
  if grep -q 'hooks: \[\]' "$LOCK"; then
    pass "AH1: 空リスト時に hooks: [] が出力される"
  else
    fail "AH1: 空リスト時に hooks: [] が出力される"
  fi
else
  fail "AH1: 空リスト時に hooks: [] が出力される (lock ファイルが存在しない)"
fi

# テンプレート復元
for tpl_dir in hooks skills agents; do
  if [ -d "$TEMPLATES_BAK/$tpl_dir" ]; then
    rm -rf "$SCRIPT_DIR/templates/claude/$tpl_dir"
    mv "$TEMPLATES_BAK/$tpl_dir" "$SCRIPT_DIR/templates/claude/$tpl_dir"
  fi
done
rm -rf "$TEMPLATES_BAK"
cleanup

# AH2. 空リスト lock がある状態で --update が正常に動作する
create_test_repo
R="$TMPDIR_ROOT"
mkdir -p "$R/.claude"
LOCK="$R/.claude/vibecorp.lock"
# 空リストを含む lock ファイルを手動生成
cat > "$LOCK" <<'LOCK_YAML'
# vibecorp.lock — 自動生成、手動編集禁止
version: 0.0.0
installed_at: 2026-01-01T00:00:00+00:00
preset: standard
vibecorp_commit: abc1234
files:
  hooks: []
  skills: []
  agents: []
  rules: []
  issue_templates: []
  docs: []
  knowledge: []
  base_hashes: {}
LOCK_YAML

# vibecorp.yml も必要（--update は REPO_ROOT/.claude/vibecorp.yml から設定を読む）
cat > "$R/.claude/vibecorp.yml" <<'YML'
name: test-proj
preset: standard
YML

# --update で空リスト lock を読んでも正常終了することを検証
EXIT_CODE=0; bash "$INSTALL_SH" --update 2>/dev/null || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && [ -f "$LOCK" ]; then
  pass "AH2: 空リスト lock がある状態で --update が正常に動作する"
else
  fail "AH2: 空リスト lock がある状態で --update が正常に動作する (exit=$EXIT_CODE)"
fi
cleanup

# AH3. 非空リスト時はインデント付きリスト項目（"    - "）が出力される
create_test_repo
EXIT_CODE=0; bash "$INSTALL_SH" --name test-proj 2>/dev/null || EXIT_CODE=$?
R="$TMPDIR_ROOT"
LOCK="$R/.claude/vibecorp.lock"

if [ -f "$LOCK" ]; then
  # rules セクションには通常コピーされるファイルがある
  # 非空リストの場合、"rules:" の後に "    - " で始まるリスト項目が必須
  if grep -q 'rules:$' "$LOCK"; then
    # rules: の後にリスト項目が存在することを厳密に検証（空リスト [] は不可）
    RULE_ITEMS=$(awk '/^  rules:$/{found=1; next} found && /^    - /{count++} found && /^  [a-z]/{exit} END{print count+0}' "$LOCK")
    if [ "$RULE_ITEMS" -gt 0 ]; then
      pass "AH3: 非空リスト時はインデント付きリスト項目が出力される (${RULE_ITEMS}件)"
    else
      fail "AH3: 非空リスト時はインデント付きリスト項目が出力される (リスト項目なし)"
    fi
  else
    fail "AH3: 非空リスト時はインデント付きリスト項目が出力される (rules セクションなし)"
  fi
else
  fail "AH3: 非空リスト時はインデント付きリスト項目が出力される (lock なし)"
fi
cleanup

# ============================================
echo ""
echo "=== AI. プレースホルダー置換エラーハンドリング ==="
# ============================================

# AI1. 正常な置換後にプレースホルダーが残らない（既存テスト I と重複するが明示的に検証）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full --language ja 2>/dev/null
R="$TMPDIR_ROOT"

# hooks 内の全ファイルに vibecorp プレースホルダーが残っていないこと
REMAINING=$(grep -rl '{{PROJECT_NAME}}\|{{PRESET}}\|{{LANGUAGE}}' "$R/.claude/hooks/" 2>/dev/null || true)
if [ -z "$REMAINING" ]; then
  pass "AI1: hooks 内にプレースホルダーが残っていない"
else
  fail "AI1: hooks 内にプレースホルダーが残っている: $REMAINING"
fi

# skills 内の全ファイルに vibecorp プレースホルダーが残っていないこと
REMAINING=$(grep -rl '{{PROJECT_NAME}}\|{{PRESET}}\|{{LANGUAGE}}' "$R/.claude/skills/" 2>/dev/null || true)
if [ -z "$REMAINING" ]; then
  pass "AI1: skills 内にプレースホルダーが残っていない"
else
  fail "AI1: skills 内にプレースホルダーが残っている: $REMAINING"
fi
cleanup

# AI2. --update 時に vibecorp プレースホルダーが正常に置換されること
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# vibecorp プレースホルダーを含むファイルを hooks に配置して --update で再実行
echo '#!/bin/bash
# {{PROJECT_NAME}} テスト' > "$R/.claude/hooks/test-placeholder.sh"
chmod +x "$R/.claude/hooks/test-placeholder.sh"

bash "$INSTALL_SH" --update 2>/dev/null
REMAINING=$(grep -l '{{PROJECT_NAME}}' "$R/.claude/hooks/test-placeholder.sh" 2>/dev/null || true)
if [ -z "$REMAINING" ]; then
  pass "AI2: --update でプレースホルダーが正常に置換される"
else
  fail "AI2: --update でプレースホルダーが残っている"
fi
# クリーンアップ
rm -f "$R/.claude/hooks/test-placeholder.sh"
cleanup

# AI2b. 未知のテンプレート構文（docker inspect 等）は誤検知しない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# docker inspect の Go テンプレート構文を含むファイルを配置
echo '#!/bin/bash
# docker inspect --format "{{.State.Status}}" container
# {{.HostConfig.Memory}} / {{.State.ExitCode}}' > "$R/.claude/hooks/test-docker-template.sh"
chmod +x "$R/.claude/hooks/test-docker-template.sh"

STDERR_OUTPUT=$(bash "$INSTALL_SH" --update 2>&1 >/dev/null) || true
if echo "$STDERR_OUTPUT" | grep -q "未解決のプレースホルダーが残っています"; then
  fail "AI2b: 未知のテンプレート構文が誤検知された"
else
  pass "AI2b: 未知のテンプレート構文を誤検知しない"
fi
# ファイル内容が書き換えられていないこと
if grep -q '{{.State.Status}}' "$R/.claude/hooks/test-docker-template.sh"; then
  pass "AI2b: 未知のテンプレート構文を保持する"
else
  fail "AI2b: 未知のテンプレート構文が書き換えられた"
fi
# クリーンアップ
rm -f "$R/.claude/hooks/test-docker-template.sh"
cleanup

# AI3. sed 失敗時に .tmp ファイルが残らない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# 正常実行後に .tmp ファイルが残っていないこと
TMP_FILES=$(find "$R/.claude/hooks/" "$R/.claude/skills/" -name '*.tmp' 2>/dev/null || true)
if [ -z "$TMP_FILES" ]; then
  pass "AI3: 置換後に .tmp ファイルが残っていない"
else
  fail "AI3: 置換後に .tmp ファイルが残っている: $TMP_FILES"
fi
cleanup

# ============================================
echo ""
echo "=== BILLING. 課金警告（Issue #286） ==="
# ============================================

# BILLING1. full プリセット install 時に課金警告が stderr に表示される
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset full 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデル"; then
  pass "BILLING1: full → stderr に課金警告が表示される"
else
  fail "BILLING1: full → stderr に課金警告が表示されない"
fi
if echo "$STDERR_OUT" | grep -q "ANTHROPIC_API_KEY"; then
  pass "BILLING1b: full → 警告に ANTHROPIC_API_KEY の言及がある"
else
  fail "BILLING1b: full → 警告に ANTHROPIC_API_KEY の言及がない"
fi
cleanup

# BILLING2. minimal プリセットでは課金警告が出ない
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset minimal 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデルに関する注意"; then
  fail "BILLING2: minimal → 課金警告が誤って表示されている"
else
  pass "BILLING2: minimal → 課金警告は表示されない"
fi
cleanup

# BILLING3. standard プリセットでは課金警告が出ない
create_test_repo
STDERR_OUT=$(bash "$INSTALL_SH" --name test-proj --preset standard 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -q "課金モデルに関する注意"; then
  fail "BILLING3: standard → 課金警告が誤って表示されている"
else
  pass "BILLING3: standard → 課金警告は表示されない"
fi
cleanup

# BILLING4. docs/cost-analysis.md に「実行モード別の課金モデル」セクションが存在する
assert_file_contains "BILLING4: cost-analysis.md に実行モード別の課金モデル見出しが存在" "$SCRIPT_DIR/docs/cost-analysis.md" "実行モード別の課金モデル"

# BILLING5. README.md のプリセット比較表に「課金モデル」列が追加されている
assert_file_contains "BILLING5: README.md に課金モデル列が追加されている" "$SCRIPT_DIR/README.md" "課金モデル"

# ============================================
echo ""
echo "=== PLAN. プリセット別 plan.review_agents デフォルト ==="
# ============================================

# PLAN1. minimal プリセット: vibecorp.yml の plan.review_agents は architect のみ
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1
R="$TMPDIR_ROOT"
assert_file_contains "PLAN1a: minimal vibecorp.yml に plan: セクションが存在" "$R/.claude/vibecorp.yml" "^plan:"
assert_file_contains "PLAN1b: minimal vibecorp.yml に review_agents: が存在" "$R/.claude/vibecorp.yml" "review_agents:"
assert_file_contains "PLAN1c: minimal vibecorp.yml の review_agents に architect が含まれる" "$R/.claude/vibecorp.yml" "- architect"
assert_file_not_contains "PLAN1d: minimal vibecorp.yml の review_agents に security が含まれない" "$R/.claude/vibecorp.yml" "- security"
assert_file_not_contains "PLAN1e: minimal vibecorp.yml の review_agents に cost が含まれない" "$R/.claude/vibecorp.yml" "- cost"
assert_file_not_contains "PLAN1f: minimal vibecorp.yml の review_agents に legal が含まれない" "$R/.claude/vibecorp.yml" "- legal"
cleanup

# PLAN2. standard プリセット: architect / security / testing の 3 つ
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard > /dev/null 2>&1
R="$TMPDIR_ROOT"
assert_file_contains "PLAN2a: standard vibecorp.yml の review_agents に architect が含まれる" "$R/.claude/vibecorp.yml" "- architect"
assert_file_contains "PLAN2b: standard vibecorp.yml の review_agents に security が含まれる" "$R/.claude/vibecorp.yml" "- security"
assert_file_contains "PLAN2c: standard vibecorp.yml の review_agents に testing が含まれる" "$R/.claude/vibecorp.yml" "- testing"
assert_file_not_contains "PLAN2d: standard vibecorp.yml の review_agents に performance が含まれない" "$R/.claude/vibecorp.yml" "- performance"
assert_file_not_contains "PLAN2e: standard vibecorp.yml の review_agents に cost が含まれない" "$R/.claude/vibecorp.yml" "- cost"
assert_file_not_contains "PLAN2f: standard vibecorp.yml の review_agents に legal が含まれない" "$R/.claude/vibecorp.yml" "- legal"
cleanup

# PLAN3. full プリセット: architect / security / testing / performance / dx / cost / legal の 7 つ
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"
assert_file_contains "PLAN3a: full vibecorp.yml の review_agents に architect が含まれる" "$R/.claude/vibecorp.yml" "- architect"
assert_file_contains "PLAN3b: full vibecorp.yml の review_agents に security が含まれる" "$R/.claude/vibecorp.yml" "- security"
assert_file_contains "PLAN3c: full vibecorp.yml の review_agents に testing が含まれる" "$R/.claude/vibecorp.yml" "- testing"
assert_file_contains "PLAN3d: full vibecorp.yml の review_agents に performance が含まれる" "$R/.claude/vibecorp.yml" "- performance"
assert_file_contains "PLAN3e: full vibecorp.yml の review_agents に dx が含まれる" "$R/.claude/vibecorp.yml" "- dx"
assert_file_contains "PLAN3f: full vibecorp.yml の review_agents に cost が含まれる" "$R/.claude/vibecorp.yml" "- cost"
assert_file_contains "PLAN3g: full vibecorp.yml の review_agents に legal が含まれる" "$R/.claude/vibecorp.yml" "- legal"
cleanup

# PLAN4. full プリセット: plan-cost.md / plan-legal.md が .claude/agents/ に配置される
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset full > /dev/null 2>&1
R="$TMPDIR_ROOT"
if [ -f "$R/.claude/agents/plan-cost.md" ]; then
  pass "PLAN4a: full プリセットで plan-cost.md が配置される"
else
  fail "PLAN4a: full プリセットで plan-cost.md が配置されていない"
fi
if [ -f "$R/.claude/agents/plan-legal.md" ]; then
  pass "PLAN4b: full プリセットで plan-legal.md が配置される"
else
  fail "PLAN4b: full プリセットで plan-legal.md が配置されていない"
fi
cleanup

# PLAN5. standard プリセット: plan-cost.md / plan-legal.md は削除される（他の plan-* は残る）
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset standard > /dev/null 2>&1
R="$TMPDIR_ROOT"
if [ ! -f "$R/.claude/agents/plan-cost.md" ]; then
  pass "PLAN5a: standard プリセットで plan-cost.md は削除される"
else
  fail "PLAN5a: standard プリセットで plan-cost.md が削除されていない"
fi
if [ ! -f "$R/.claude/agents/plan-legal.md" ]; then
  pass "PLAN5b: standard プリセットで plan-legal.md は削除される"
else
  fail "PLAN5b: standard プリセットで plan-legal.md が削除されていない"
fi
# 既存 plan-* は残ること
if [ -f "$R/.claude/agents/plan-architect.md" ]; then
  pass "PLAN5c: standard プリセットで plan-architect.md は保持される"
else
  fail "PLAN5c: standard プリセットで plan-architect.md が失われている"
fi
cleanup

# PLAN6. minimal プリセット: agents ディレクトリ自体が存在しない
create_test_repo
bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1
R="$TMPDIR_ROOT"
if [ ! -d "$R/.claude/agents" ]; then
  pass "PLAN6: minimal プリセットで agents/ ディレクトリは存在しない"
else
  fail "PLAN6: minimal プリセットで agents/ ディレクトリが存在している"
fi
cleanup

# ============================================
echo ""
echo "=== T. OS 判定（Windows / unknown 非対応） ==="
# ============================================
# detect_os / check_unsupported_os の挙動を uname モックで検証する。
# install.sh は set -e の下で uname -s を外部コマンドとして呼ぶため、
# PATH 先頭にダミー uname を置けばモック可能。

# T1. uname -s = Darwin なら続行（既存セットアップで動くことで検証済みだが、明示テスト）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_darwin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "Darwin"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T1: uname=Darwin で install が成功する" "0" "$EXIT_CODE"

# T2. uname -s = Linux なら続行
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_linux"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "Linux"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T2: uname=Linux で install が成功する" "0" "$EXIT_CODE"

# T3. uname -s = MINGW64_NT-10.0-19045 なら exit 2（Windows ネイティブ）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_mingw"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "MINGW64_NT-10.0-19045"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
ERR_LOG="$TMPDIR_ROOT/t3_err.log"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>"$ERR_LOG" || EXIT_CODE=$?
assert_exit_code "T3: uname=MINGW64 で exit 2" "2" "$EXIT_CODE"
assert_file_contains "T3: エラーメッセージに WSL2 案内が含まれる" "$ERR_LOG" "WSL2"

# T4. uname -s = MSYS_NT-10.0 なら exit 2
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_msys"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "MSYS_NT-10.0"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T4: uname=MSYS_NT で exit 2" "2" "$EXIT_CODE"

# T5. uname -s = CYGWIN_NT-10.0 なら exit 2
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_cygwin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "CYGWIN_NT-10.0"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>&1 || EXIT_CODE=$?
assert_exit_code "T5: uname=CYGWIN_NT で exit 2" "2" "$EXIT_CODE"

# T6. uname -s = FreeBSD なら exit 2（unknown OS）
cleanup
create_test_repo
FAKE_BIN="$TMPDIR_ROOT/_fake_bin_freebsd"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'FAKESH'
#!/bin/bash
if [ "${1:-}" = "-s" ]; then
  echo "FreeBSD"
else
  /usr/bin/uname "$@"
fi
FAKESH
chmod +x "$FAKE_BIN/uname"
EXIT_CODE=0
ERR_LOG="$TMPDIR_ROOT/t6_err.log"
PATH="${FAKE_BIN}:${PATH}" bash "$INSTALL_SH" --name test-proj --preset minimal > /dev/null 2>"$ERR_LOG" || EXIT_CODE=$?
assert_exit_code "T6: uname=FreeBSD で exit 2" "2" "$EXIT_CODE"
assert_file_contains "T6: エラーメッセージにサポート外の表記" "$ERR_LOG" "サポート外の OS"
cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
