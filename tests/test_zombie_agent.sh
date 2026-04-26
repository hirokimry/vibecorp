#!/bin/bash
# test_zombie_agent.sh — ゾンビエージェント検出ロジックの単体テスト
# 使い方: bash tests/test_zombie_agent.sh
#
# tmux 実コマンド (kill-pane) は副作用が大きいため検証しない。
# - list_zombies のフィルタリング条件
# - _extract_worktree_path の prompt パース
# - kill_zombies の tmux 未起動時挙動
# のみを対象とする。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
LIB_FILE="${REPO_ROOT}/templates/claude/lib/zombie_agent.sh"

# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

# --- セットアップ ---

if [[ ! -f "$LIB_FILE" ]]; then
  fail "zombie_agent.sh が存在しない: ${LIB_FILE}"
  exit 1
fi

TMPDIR_ROOT=$(mktemp -d)
TEAMS_DIR="${TMPDIR_ROOT}/teams"
EXISTING_WT="${TMPDIR_ROOT}/existing-worktree"
MISSING_WT="${TMPDIR_ROOT}/missing-worktree"
SPACED_WT="${TMPDIR_ROOT}/dir with spaces"

mkdir -p "$TEAMS_DIR" "$EXISTING_WT"

cleanup() {
  rm -rf "$TMPDIR_ROOT" || true
}
trap cleanup EXIT

# テスト対象の関数を読み込む（CLAUDE_TEAMS_DIR で TEAMS_DIR を上書き）
export CLAUDE_TEAMS_DIR="$TEAMS_DIR"
# shellcheck disable=SC1090
source "$LIB_FILE"

# テスト用の team config を生成する
make_team_config() {
  local team_name="$1"
  local config_path="${TEAMS_DIR}/${team_name}/config.json"
  mkdir -p "$(dirname "$config_path")"
  cat > "$config_path"
}

# ===== テスト =====

echo "=== zombie_agent.sh 単体テスト ==="
echo ""

# --- テスト1: teams ディレクトリが存在しない場合は空出力 ---

echo "--- テスト1: teams ディレクトリ不在時の挙動 ---"
# TEAMS_DIR は source 時に確定するため、関数内で参照される変数を直接差し替える
# （CLAUDE_TEAMS_DIR の代入では効かないため shell 変数 TEAMS_DIR を一時退避→上書き→復元）
_old_teams_dir="$TEAMS_DIR"
TEAMS_DIR="${TMPDIR_ROOT}/no-such-dir"
output=$(list_zombies)
TEAMS_DIR="$_old_teams_dir"
assert_eq "teams ディレクトリ不在 → 空出力" "" "$output"

echo ""

# --- テスト2: backendType が tmux でないメンバーは検出されない ---

echo "--- テスト2: backendType フィルタ ---"
make_team_config "team-non-tmux" <<JSON
{
  "name": "team-non-tmux",
  "members": [
    {
      "name": "lead",
      "backendType": "",
      "tmuxPaneId": "",
      "prompt": "worktree パス: ${MISSING_WT}"
    }
  ]
}
JSON

output=$(list_zombies)
assert_eq "backendType=空 → 検出されない" "" "$output"

rm -rf "${TEAMS_DIR}/team-non-tmux"
echo ""

# --- テスト3: tmuxPaneId が空のメンバーは検出されない ---

echo "--- テスト3: tmuxPaneId 空フィルタ ---"
make_team_config "team-no-pane" <<JSON
{
  "name": "team-no-pane",
  "members": [
    {
      "name": "ghost",
      "backendType": "tmux",
      "tmuxPaneId": "",
      "prompt": "worktree パス: ${MISSING_WT}"
    }
  ]
}
JSON

output=$(list_zombies)
assert_eq "tmuxPaneId 空 → 検出されない" "" "$output"

rm -rf "${TEAMS_DIR}/team-no-pane"
echo ""

# --- テスト4: worktree が存在するメンバーは検出されない ---

echo "--- テスト4: 生存 worktree はスキップ ---"
make_team_config "team-alive" <<JSON
{
  "name": "team-alive",
  "members": [
    {
      "name": "ship-100",
      "backendType": "tmux",
      "tmuxPaneId": "%100",
      "prompt": "worktree パス: ${EXISTING_WT}"
    }
  ]
}
JSON

output=$(list_zombies)
assert_eq "worktree 存在 → 検出されない" "" "$output"

rm -rf "${TEAMS_DIR}/team-alive"
echo ""

# --- テスト5: worktree 不在 + tmux backend → ゾンビとして検出される ---

echo "--- テスト5: ゾンビ検出 ---"
make_team_config "team-zombie" <<JSON
{
  "name": "team-zombie",
  "members": [
    {
      "name": "ship-200",
      "backendType": "tmux",
      "tmuxPaneId": "%200",
      "prompt": "あなたは Issue #200 の実装担当です。\n\n- worktree パス: ${MISSING_WT}\n- ベースブランチ: main"
    }
  ]
}
JSON

output=$(list_zombies)
expected=$(printf '%s\t%s\t%s\t%s' "team-zombie" "ship-200" "%200" "$MISSING_WT")
assert_eq "ゾンビ1件が tab 区切りで検出される" "$expected" "$output"

rm -rf "${TEAMS_DIR}/team-zombie"
echo ""

# --- テスト6: prompt に worktree パスがない場合はスキップ ---

echo "--- テスト6: prompt パース失敗時のスキップ ---"
make_team_config "team-no-path" <<JSON
{
  "name": "team-no-path",
  "members": [
    {
      "name": "ship-300",
      "backendType": "tmux",
      "tmuxPaneId": "%300",
      "prompt": "Issue #300 の実装担当です。詳細はチケット参照。"
    }
  ]
}
JSON

output=$(list_zombies)
assert_eq "prompt に worktree パスなし → 検出されない" "" "$output"

rm -rf "${TEAMS_DIR}/team-no-path"
echo ""

# --- テスト7: パスにスペースを含む worktree でも抽出できる ---

echo "--- テスト7: スペース入りパスのパース ---"
make_team_config "team-spaced" <<JSON
{
  "name": "team-spaced",
  "members": [
    {
      "name": "ship-400",
      "backendType": "tmux",
      "tmuxPaneId": "%400",
      "prompt": "- worktree パス: ${SPACED_WT}\n- ベースブランチ: main"
    }
  ]
}
JSON

output=$(list_zombies)
expected=$(printf '%s\t%s\t%s\t%s' "team-spaced" "ship-400" "%400" "$SPACED_WT")
assert_eq "スペース入り worktree パスが抽出される" "$expected" "$output"

rm -rf "${TEAMS_DIR}/team-spaced"
echo ""

# --- テスト8: 複数 team config を跨ぐ走査 ---

echo "--- テスト8: 複数 team の同時走査 ---"
make_team_config "team-multi-a" <<JSON
{
  "name": "team-multi-a",
  "members": [
    {
      "name": "ship-501",
      "backendType": "tmux",
      "tmuxPaneId": "%501",
      "prompt": "- worktree パス: ${MISSING_WT}-a"
    }
  ]
}
JSON

make_team_config "team-multi-b" <<JSON
{
  "name": "team-multi-b",
  "members": [
    {
      "name": "ship-502",
      "backendType": "tmux",
      "tmuxPaneId": "%502",
      "prompt": "- worktree パス: ${EXISTING_WT}"
    },
    {
      "name": "ship-503",
      "backendType": "tmux",
      "tmuxPaneId": "%503",
      "prompt": "- worktree パス: ${MISSING_WT}-c"
    }
  ]
}
JSON

output=$(list_zombies | sort)
expected=$(printf '%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s' \
  "team-multi-a" "ship-501" "%501" "${MISSING_WT}-a" \
  "team-multi-b" "ship-503" "%503" "${MISSING_WT}-c" | sort)
assert_eq "複数 team 跨ぎで2件のゾンビが検出される" "$expected" "$output"

rm -rf "${TEAMS_DIR}/team-multi-a" "${TEAMS_DIR}/team-multi-b"
echo ""

# --- テスト9: _extract_worktree_path の単体動作 ---

echo "--- テスト9: _extract_worktree_path の単体動作 ---"

actual=$(_extract_worktree_path $'前置きテキスト\n- worktree パス: /tmp/foo\n- ベースブランチ: main')
assert_eq "標準的な prompt から抽出" "/tmp/foo" "$actual"

actual=$(_extract_worktree_path "worktree パス: /tmp/bar")
assert_eq "単一行 prompt から抽出" "/tmp/bar" "$actual"

actual=$(_extract_worktree_path "Issue について")
assert_eq "ラベル不在 → 空文字" "" "$actual"

echo ""

# --- テスト10: kill_zombies の tmux 未起動時の挙動 ---
# tmux 実環境を仮想化できないため、tmux コマンドをスタブする

echo "--- テスト10: kill_zombies tmux 未起動時の挙動 ---"

STUB_DIR="${TMPDIR_ROOT}/stub-bin"
mkdir -p "$STUB_DIR"
cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/bash
# tmux スタブ: has-session で常に非ゼロ（サーバー未起動を模倣）
case "$1" in
  has-session) exit 1 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${STUB_DIR}/tmux"

make_team_config "team-stub" <<JSON
{
  "name": "team-stub",
  "members": [
    {
      "name": "ship-600",
      "backendType": "tmux",
      "tmuxPaneId": "%600",
      "prompt": "- worktree パス: ${MISSING_WT}"
    }
  ]
}
JSON

PATH="${STUB_DIR}:${PATH}" output=$(PATH="${STUB_DIR}:${PATH}" kill_zombies)

if echo "$output" | grep -q "tmux サーバーが起動していません"; then
  pass "tmux 未起動 → 通知メッセージが出力される"
else
  fail "tmux 未起動メッセージが出力されない"
fi

if echo "$output" | grep -q "Skipped: team-stub/ship-600"; then
  pass "tmux 未起動でも Skipped でカウントされる"
else
  fail "Skipped カウントが出力されない (output: $output)"
fi

if echo "$output" | grep -q "Killed: 0, Skipped: 1"; then
  pass "サマリ出力が正しい"
else
  fail "サマリ出力が正しくない (output: $output)"
fi

rm -rf "${TEAMS_DIR}/team-stub"
echo ""

# ===== 結果 =====

print_test_summary
