#!/bin/bash
# test_install_preset.sh — install.sh の preset / language / ファイル生成テスト
# 使い方: bash tests/test_install_preset.sh
# 元ファイル: tests/test_install.sh を Issue #340 で 4 シャードに分割した

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

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

# L1. 同名スキルもスタブ自動生成で上書き（plugin 名前空間移行済み）
create_test_repo
mkdir -p "$TMPDIR_ROOT/.claude/skills/review"
echo "# カスタムレビュースキル" > "$TMPDIR_ROOT/.claude/skills/review/SKILL.md"
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

if grep -q "vibecorp:review" "$R/.claude/skills/review/SKILL.md"; then
  pass "同名スキル(review)もスタブで上書き（plugin リダイレクト）"
else
  fail "同名スキル(review)がスタブで上書きされていない"
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
echo "=== S. Issue テンプレート・ラベル・/vibecorp:issue スキル ==="
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

# P7. /vibecorp:issue スキルが配置されている
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

# X4c. design-philosophy.md が生成される（#364 §1-4: /vibecorp:commit スキルのアンカーリンク先）
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


print_test_summary
