#!/bin/bash
# test_install_update.sh — install.sh の --update 系差分検証テスト
# 使い方: bash tests/test_install_update.sh
# 元ファイル: tests/test_install.sh を Issue #340 で 4 シャードに分割した

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/tests/lib/install_test_helpers.sh"

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

# O5. --update でテンプレートが更新されると CLAUDE.md が新テンプレートに追従する
# （カスタマイズなし・ベーススナップショット ⇒ 3-way マージで新内容が反映される）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# 初回インストールで CLAUDE.md のベーススナップショットが作成される
assert_file_exists "O5: CLAUDE.md のベーススナップショットが保存される" "$R/.claude/vibecorp-base/CLAUDE.md"

# ベーススナップショットを旧テンプレート相当の内容に差し替えて「テンプレート更新」を模擬
echo "# 旧テンプレート" > "$R/.claude/vibecorp-base/CLAUDE.md"
OLD_HASH=$(shasum -a 256 "$R/.claude/vibecorp-base/CLAUDE.md" | awk '{print $1}')
# 現行 CLAUDE.md も旧テンプレート相当に揃える（= カスタマイズなし）
cp "$R/.claude/vibecorp-base/CLAUDE.md" "$R/.claude/CLAUDE.md"
# lock の base_hash も旧ハッシュに差し替え（他エントリのインデントを壊さないため
# マッチ行でのみ print を差し替える）
awk -v path="CLAUDE.md" -v newhash="$OLD_HASH" '
  /^  base_hashes:/ { in_hashes = 1; print; next }
  in_hashes && /^  [a-z]/ { in_hashes = 0 }
  in_hashes && /^[^ ]/ { in_hashes = 0 }
  in_hashes {
    line = $0
    stripped = line
    sub(/^[ \t]+/, "", stripped)
    idx = index(stripped, ":")
    if (idx > 0 && substr(stripped, 1, idx - 1) == path) {
      print "    " path ": " newhash
      next
    }
  }
  { print }
' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

bash "$INSTALL_SH" --update 2>/dev/null
# 新テンプレート（= 最新の templates/CLAUDE.md.tpl 相当）で上書きされる
assert_file_contains "O5: --update でテンプレート更新が CLAUDE.md に反映" "$R/.claude/CLAUDE.md" "test-proj"
cleanup

# O6. --update でカスタマイズ済み CLAUDE.md はベーススナップショット無しならスキップされる
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

# ユーザーが CLAUDE.md を大幅にカスタマイズ
echo "# My customized CLAUDE.md" > "$R/.claude/CLAUDE.md"
echo "user-specific-marker-xyz" >> "$R/.claude/CLAUDE.md"

# ベーススナップショット・lock から CLAUDE.md のエントリを削除して旧バージョン移行を模擬
rm -f "$R/.claude/vibecorp-base/CLAUDE.md"
awk '!/^    CLAUDE\.md:/' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

bash "$INSTALL_SH" --update 2>/dev/null

# カスタマイズ内容は保持される（上書きされない）
assert_file_contains "O6: カスタマイズ済み CLAUDE.md が保持される" "$R/.claude/CLAUDE.md" "user-specific-marker-xyz"
# 次回以降の 3-way マージのためベーススナップショットが記録されている
assert_file_exists "O6: 次回マージ用にベーススナップショットが作成される" "$R/.claude/vibecorp-base/CLAUDE.md"
cleanup

# O7. --update で MVV.md も同じ挙動（カスタマイズ保護）
create_test_repo
bash "$INSTALL_SH" --name test-proj 2>/dev/null
R="$TMPDIR_ROOT"

echo "# Custom MVV" > "$R/MVV.md"
echo "mvv-marker-abc" >> "$R/MVV.md"
rm -f "$R/.claude/vibecorp-base/MVV.md"
awk '!/^    MVV\.md:/' "$R/.claude/vibecorp.lock" > "$R/.claude/vibecorp.lock.tmp" && mv "$R/.claude/vibecorp.lock.tmp" "$R/.claude/vibecorp.lock"

bash "$INSTALL_SH" --update 2>/dev/null

assert_file_contains "O7: カスタマイズ済み MVV.md が保持される" "$R/MVV.md" "mvv-marker-abc"
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


print_test_summary
