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

# P1. --update で管理フックが強制上書きされる（スキップしない）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# protect-files.sh をカスタム内容に変更
echo "# ユーザーカスタム版" > "$R/.claude/hooks/protect-files.sh"
# ユーザー独自フックも追加
echo '#!/bin/bash' > "$R/.claude/hooks/my-guard.sh"

bash "$INSTALL_SH" --update 2>/dev/null

# 管理フックは強制上書き
assert_file_not_contains "--update で管理フックが上書き" "$R/.claude/hooks/protect-files.sh" "ユーザーカスタム版"
# ユーザー独自フックは残る
assert_file_exists "--update でユーザー独自フックは保持" "$R/.claude/hooks/my-guard.sh"
cleanup

# P2. --update で管理スキルが強制上書きされる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

echo "# 古い review" > "$R/.claude/skills/review/SKILL.md"
mkdir -p "$R/.claude/skills/my-deploy"
echo "# デプロイ" > "$R/.claude/skills/my-deploy/SKILL.md"

bash "$INSTALL_SH" --update 2>/dev/null

assert_file_not_contains "--update で管理スキルが上書き" "$R/.claude/skills/review/SKILL.md" "古い review"
assert_file_exists "--update でユーザー独自スキルは保持" "$R/.claude/skills/my-deploy/SKILL.md"
cleanup

# P3. --update で管理ルールが強制上書きされる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

echo "# 古いルール" > "$R/.claude/rules/comments.md"

bash "$INSTALL_SH" --update 2>/dev/null

assert_file_not_contains "--update で管理ルールが上書き" "$R/.claude/rules/comments.md" "古いルール"
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

# X5. プレースホルダーが置換済み（残っていない）
assert_file_not_contains "specification.md にプレースホルダーなし" "$R/docs/specification.md" '{{.*}}'
assert_file_not_contains "POLICY.md にプレースホルダーなし" "$R/docs/POLICY.md" '{{.*}}'
assert_file_not_contains "SECURITY.md にプレースホルダーなし" "$R/docs/SECURITY.md" '{{.*}}'

# X6. PROJECT_NAME が実際のプロジェクト名に置換されている
assert_file_contains "specification.md にプロジェクト名" "$R/docs/specification.md" "test-proj"
assert_file_contains "POLICY.md にプロジェクト名" "$R/docs/POLICY.md" "test-proj"
assert_file_contains "SECURITY.md にプロジェクト名" "$R/docs/SECURITY.md" "test-proj"

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
assert_file_exists "standard: cto/decisions.md が配置される" "$R/.claude/knowledge/cto/decisions.md"
assert_file_exists "standard: cpo/product-principles.md が配置される" "$R/.claude/knowledge/cpo/product-principles.md"
assert_file_exists "standard: cpo/decisions.md が配置される" "$R/.claude/knowledge/cpo/decisions.md"
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
assert_file_contains "lock に decisions.md" "$R/.claude/vibecorp.lock" "decisions.md"
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
assert_file_exists "standard: review-to-rules-gate.sh が配置される" "$R/.claude/hooks/review-to-rules-gate.sh"
assert_file_executable "standard: sync-gate.sh に実行権限" "$R/.claude/hooks/sync-gate.sh"
assert_file_executable "standard: review-to-rules-gate.sh に実行権限" "$R/.claude/hooks/review-to-rules-gate.sh"

# Z3. standard 新規インストール: standard 専用 skills が配置される
assert_dir_exists "standard: sync-check スキル存在" "$R/.claude/skills/sync-check"
assert_dir_exists "standard: sync-edit スキル存在" "$R/.claude/skills/sync-edit"
assert_dir_exists "standard: review-to-rules スキル存在" "$R/.claude/skills/review-to-rules"

# Z4. standard lock: agents/hooks/skills が lock に記録される
assert_file_contains "standard lock: cto.md 記録" "$R/.claude/vibecorp.lock" "cto.md"
assert_file_contains "standard lock: cpo.md 記録" "$R/.claude/vibecorp.lock" "cpo.md"
assert_file_contains "standard lock: sync-gate.sh 記録" "$R/.claude/vibecorp.lock" "sync-gate.sh"
assert_file_contains "standard lock: review-to-rules-gate.sh 記録" "$R/.claude/vibecorp.lock" "review-to-rules-gate.sh"

# Z5. standard settings.json: standard 用フックが含まれる
assert_file_contains "standard settings: sync-gate フック存在" "$R/.claude/settings.json" "sync-gate"
assert_file_contains "standard settings: review-to-rules-gate フック存在" "$R/.claude/settings.json" "review-to-rules-gate"

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
assert_file_exists "アップグレード後: review-to-rules-gate.sh 追加" "$R/.claude/hooks/review-to-rules-gate.sh"

# standard 専用 skills が追加される
assert_dir_exists "アップグレード後: sync-check 追加" "$R/.claude/skills/sync-check"
assert_dir_exists "アップグレード後: sync-edit 追加" "$R/.claude/skills/sync-edit"
assert_dir_exists "アップグレード後: review-to-rules 追加" "$R/.claude/skills/review-to-rules"

# knowledge が追加される
assert_file_exists "アップグレード後: knowledge 追加" "$R/.claude/knowledge/cto/tech-principles.md"

# Z8. minimal → standard アップグレード: vibecorp.yml が更新される
assert_file_contains "アップグレード後: preset が standard" "$R/.claude/vibecorp.yml" "preset: standard"

# Z9. minimal → standard アップグレード: settings.json に standard 用フックが追加される
assert_file_contains "アップグレード後: settings に sync-gate" "$R/.claude/settings.json" "sync-gate"
assert_file_contains "アップグレード後: settings に review-to-rules-gate" "$R/.claude/settings.json" "review-to-rules-gate"

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
echo "=== CR. CodeRabbit 無効設定テスト ==="
# ============================================

# CR1. coderabbit.enabled: false で .coderabbit.yaml が生成されない
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
# vibecorp.yml に coderabbit: enabled: false を追記
cat >> "$R/.claude/vibecorp.yml" <<'YML'
coderabbit:
  enabled: false
YML
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

# CR3. coderabbit.enabled: true で .coderabbit.yaml が生成される
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"
cat >> "$R/.claude/vibecorp.yml" <<'YML'
coderabbit:
  enabled: true
YML
rm -f "$R/.coderabbit.yaml"
bash "$INSTALL_SH" --update 2>/dev/null
assert_file_exists "coderabbit.enabled: true で .coderabbit.yaml 生成" "$R/.coderabbit.yaml"

cleanup

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
