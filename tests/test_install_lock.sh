#!/bin/bash
# test_install_lock.sh — install.sh の lock ファイル生成・整合性テスト
# 使い方: bash tests/test_install_lock.sh
# 元ファイル: tests/test_install.sh を Issue #340 で 4 シャードに分割した

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

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

# AK9. 別ディレクトリから source した際に SCRIPT_DIR が install.sh 自身のディレクトリを指す
# （${BASH_SOURCE[0]} 使用の退行検知。$0 に戻ると、source 呼び出し側のパスを指してしまう）
TMPDIR_ROOT=$(mktemp -d)
RESOLVED_SCRIPT_DIR=$(cd "$TMPDIR_ROOT" && bash -c 'source "$1"; printf "%s" "$SCRIPT_DIR"' _ "$INSTALL_SH")
EXPECTED_SCRIPT_DIR="$SCRIPT_DIR"
if [ "$RESOLVED_SCRIPT_DIR" = "$EXPECTED_SCRIPT_DIR" ]; then
  pass "AK9: source 時に SCRIPT_DIR が install.sh 自身のディレクトリを指す"
else
  fail "AK9: source 時 SCRIPT_DIR が誤った場所を指す（resolved=${RESOLVED_SCRIPT_DIR}, expected=${EXPECTED_SCRIPT_DIR}）"
fi
cleanup

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


print_test_summary
