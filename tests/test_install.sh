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
echo "=== O. .coderabbit.yaml スキップ動作 ==="
# ============================================

# O1. 既存 .coderabbit.yaml はスキップ（ユーザー版保持）
create_test_repo
echo "# ユーザーカスタム設定" > "$TMPDIR_ROOT/.coderabbit.yaml"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存 .coderabbit.yaml はスキップ（ユーザー版保持）" "$R/.coderabbit.yaml" "ユーザーカスタム設定"

# O2. --language en で language: en-US になる
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj --language en 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains ".coderabbit.yaml に language: en-US" "$R/.coderabbit.yaml" "language: en-US"

cleanup

# ============================================
echo ""
echo "=== P. Issue テンプレート・ラベル・/issue スキル ==="
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
assert_file_contains "lock に issue_templates セクション" "$R/.claude/vibecorp.lock" "issue_templates:"
assert_file_contains "lock に bug_report.md" "$R/.claude/vibecorp.lock" "bug_report.md"
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
echo "=== Q. CI ワークフロー生成 ==="
# ============================================

# Q1. .github/workflows/test.yml が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists ".github/workflows/test.yml 存在" "$R/.github/workflows/test.yml"

# Q2. name: test が含まれる
assert_file_contains "CI ワークフロー名が test" "$R/.github/workflows/test.yml" "name: test"

# Q3. 集約ジョブ test: が含まれる
assert_file_contains "集約ジョブ test 存在" "$R/.github/workflows/test.yml" "needs: test-matrix"

# Q4. concurrency 設定が含まれる
assert_file_contains "concurrency 設定" "$R/.github/workflows/test.yml" "cancel-in-progress: true"

# Q5. 既存ファイルがある場合はスキップ
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
echo "=== R. リポジトリ設定（gh 未インストール時フォールバック） ==="
# ============================================

# R1. gh が利用できない環境でもインストール成功
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

# R2. gh 利用可能だが repo view 失敗時もインストール成功
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

# R3. 既存 contexts が保持される（マージ動作）
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
  # required_status_checks GET → 既存 contexts を返す
  if echo "\$*" | grep -q "required_status_checks"; then
    echo '["test","custom-ci"]'
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
if [[ -f "$PUT_LOG" ]] && jq -e '.required_status_checks.contexts | index("custom-ci")' "$PUT_LOG" >/dev/null 2>&1; then
  pass "R3: 既存 contexts (custom-ci) がマージされて保持される"
else
  fail "R3: 既存 contexts (custom-ci) がマージされて保持される"
fi

cleanup

# R4. 既存 Branch Protection なし（GET 404）でも正常動作
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

# R5. Branch Protection PUT 失敗時にフォールバック（推奨設定表示）
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
  # required_status_checks GET → 未設定
  if echo "$*" | grep -q "required_status_checks"; then
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
echo "=== S. PR テンプレート・ワークフロー ==="
# ============================================

# S1. PR テンプレートが生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_exists "PR テンプレートが生成される" "$R/.github/pull_request_template.md"

# S2. PR テンプレートに Issue リンクセクションが含まれる
assert_file_contains "PR テンプレートに関連 Issue セクション" "$R/.github/pull_request_template.md" "関連 Issue"
assert_file_contains "PR テンプレートに close/ref の説明" "$R/.github/pull_request_template.md" "close"

# S3. auto-assign ワークフローが生成される
assert_file_exists "auto-assign ワークフローが生成される" "$R/.github/workflows/auto-assign.yml"
assert_file_contains "auto-assign に pull_request トリガー" "$R/.github/workflows/auto-assign.yml" "pull_request"
assert_file_contains "auto-assign に add-assignee" "$R/.github/workflows/auto-assign.yml" "add-assignee"

# S4. 既存 PR テンプレートはスキップ（冪等性）
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github"
echo "# カスタム PR テンプレート" > "$TMPDIR_ROOT/.github/pull_request_template.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存 PR テンプレートはスキップ" "$R/.github/pull_request_template.md" "カスタム PR テンプレート"

# S5. 既存ワークフローはスキップ（冪等性）
cleanup
create_test_repo
mkdir -p "$TMPDIR_ROOT/.github/workflows"
echo "# カスタム auto-assign" > "$TMPDIR_ROOT/.github/workflows/auto-assign.yml"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

assert_file_contains "既存ワークフローはスキップ" "$R/.github/workflows/auto-assign.yml" "カスタム auto-assign"

# S6. 再実行時に上書きされない
cleanup
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
echo "# ユーザー編集済み" > "$R/.github/pull_request_template.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null

assert_file_contains "再実行時に PR テンプレートが上書きされない" "$R/.github/pull_request_template.md" "ユーザー編集済み"

cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
