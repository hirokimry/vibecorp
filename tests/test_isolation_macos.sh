#!/bin/bash
# test_isolation_macos.sh — macOS sandbox-exec 隔離レイヤのテスト
#
# 対象:
#   - templates/claude/bin/claude           (PATH シム)
#   - templates/claude/bin/vibecorp-sandbox (OS ディスパッチャ)
#   - templates/claude/sandbox/claude.sb    (sandbox-exec プロファイル)
#
# 非 macOS では skip (exit 0)。
#
# 参照: #293 / #309

# 非 Darwin では早期 skip（Linux CI が赤くならないように）
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: tests/test_isolation_macos.sh は Darwin 以外では実行しない（現在: $(uname -s)）"
  exit 0
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="${SCRIPT_DIR}/templates/claude/bin/claude"
DISPATCHER="${SCRIPT_DIR}/templates/claude/bin/vibecorp-sandbox"
PROFILE="${SCRIPT_DIR}/templates/claude/sandbox/claude.sb"

PASSED=0
FAILED=0
TOTAL=0

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

# ----- 前提ファイル確認 -----

echo "=== 前提: ファイル存在と実行権限 ==="

prereq_ok=1
for f in "$SHIM" "$DISPATCHER" "$PROFILE"; do
  if [[ -f "$f" ]]; then
    pass "存在: $f"
  else
    fail "前提ファイル不在: $f"
    prereq_ok=0
  fi
done

for f in "$SHIM" "$DISPATCHER"; do
  if [[ -x "$f" ]]; then
    pass "実行権限: $f"
  else
    fail "実行権限が無い: $f"
    prereq_ok=0
  fi
done

if [[ "$prereq_ok" -ne 1 ]]; then
  # 前提ファイル不在 or 実行権限なしのときは後続テストに意味がない
  echo ""
  echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
  exit 1
fi

# ----- テスト環境構築 -----

TMPDIR_TEST=$(mktemp -d -t vibecorp-isolation-XXXXXX)
STDERR_LOG="${TMPDIR_TEST}/stderr.log"
STDOUT_LOG="${TMPDIR_TEST}/stdout.log"

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT

FAKE_HOME="${TMPDIR_TEST}/fake-home"
FAKE_WORKTREE="${TMPDIR_TEST}/fake-worktree"
FAKE_BIN="${TMPDIR_TEST}/fake-bin"

# fake-home: ~/.ssh ディレクトリを事前作成（書込失敗理由を ENOENT ではなく EPERM に限定するため）
mkdir -p "${FAKE_HOME}/.ssh"
# ~/.gitconfig を読取テスト用に書く
cat > "${FAKE_HOME}/.gitconfig" <<'GITCONFIG'
[user]
  name = isolation-test
  email = test@example.com
GITCONFIG

mkdir -p "$FAKE_WORKTREE"
mkdir -p "$FAKE_BIN"

# フェイク claude-real を PATH 先頭に配置
cat > "${FAKE_BIN}/claude-real" <<'CLAUDEREAL'
#!/bin/bash
# 隔離テスト用フェイク claude-real。コマンドで動作を切替える。
set -u
case "${1:-}" in
  write-ssh)
    # $HOME/.ssh/denied.txt への書込を試みる（sandbox で拒否されるべき）
    echo "wrote by claude-real" > "$HOME/.ssh/denied.txt"
    ;;
  write-wt)
    # $2 に渡された絶対パスへ書込（WORKTREE 配下を想定）
    echo "wrote by claude-real" > "$2"
    ;;
  read-config)
    # $HOME/.gitconfig を読み出す
    cat "$HOME/.gitconfig"
    ;;
  show-sandboxed)
    # VIBECORP_SANDBOXED の値を出力（未設定なら UNSET）
    printf '%s\n' "${VIBECORP_SANDBOXED:-UNSET}"
    ;;
  *)
    echo "unknown: $*" >&2
    exit 1
    ;;
esac
CLAUDEREAL
chmod +x "${FAKE_BIN}/claude-real"

# ----- shim 起動ヘルパー -----
#
# env -i でホスト環境を切り離し、テスト専用環境で shim を起動する。
# 使い方: run_shim VIBECORP_ISOLATION=1 VIBECORP_SANDBOXED=1 -- <claude-real arg> [args...]
#
# stdout / stderr はそれぞれ $STDOUT_LOG / $STDERR_LOG に保存する。
# 終了コードは関数の戻り値として返す。
run_shim() {
  local -a env_vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_vars+=("$1")
    shift
  done
  if [[ $# -eq 0 ]]; then
    echo "run_shim: '--' 区切りが必要" >&2
    return 64
  fi
  shift # 消費 --

  # bash 3.2 互換: 空配列を ${arr[@]} 展開すると nounset で落ちるため分岐
  local status=0
  if [[ ${#env_vars[@]} -gt 0 ]]; then
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="${TMPDIR:-/tmp}" \
      "${env_vars[@]}" \
      bash "$SHIM" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  else
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="${TMPDIR:-/tmp}" \
      bash "$SHIM" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  fi
  return "$status"
}

# ============================================
echo ""
echo "=== [1] VIBECORP_ISOLATION=0 で shim passthrough ==="
# ============================================
# passthrough なら fake claude-real が ~/.ssh/denied.txt を書けるはず
rm -f "${FAKE_HOME}/.ssh/denied.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=0 -- write-ssh) || status=$?
if [[ "$status" -eq 0 && -f "${FAKE_HOME}/.ssh/denied.txt" ]]; then
  pass "VIBECORP_ISOLATION=0: ~/.ssh に書けた（passthrough 動作）"
else
  fail "VIBECORP_ISOLATION=0: passthrough せず書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [2] VIBECORP_ISOLATION 未設定で shim passthrough ==="
# ============================================
# opt-in 設計なので未設定時は passthrough
rm -f "${FAKE_HOME}/.ssh/denied.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim -- write-ssh) || status=$?
if [[ "$status" -eq 0 && -f "${FAKE_HOME}/.ssh/denied.txt" ]]; then
  pass "未設定: ~/.ssh に書けた（既定が opt-in である）"
else
  fail "未設定: passthrough せず書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [3] 外部からの VIBECORP_SANDBOXED=1 注入で sandbox はバイパスされない（ネガティブ） ==="
# ============================================
# 祖先プロセスに sandbox-exec がいない状態で VIBECORP_SANDBOXED=1 だけを外部から注入しても、
# claude シムの PPID 検証により passthrough しない。
# 結果として VIBECORP_ISOLATION=1 経路に落ち、sandbox-exec 経由で起動され、
# ~/.ssh への書込は sandbox が拒否するため denied.txt は生成されない。
# 参照: audit-log.md S-005/S-009/T-001（外部注入バイパスの修正）
rm -f "${FAKE_HOME}/.ssh/denied.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 VIBECORP_SANDBOXED=1 -- write-ssh) || status=$?
if [[ "${status}" -ne 0 && ! -f "${FAKE_HOME}/.ssh/denied.txt" ]]; then
  pass "外部からの VIBECORP_SANDBOXED=1 注入では sandbox をバイパスできない (status=${status})"
else
  fail "外部からの VIBECORP_SANDBOXED=1 注入で sandbox がバイパスされた (status=${status}, file_exists=$([[ -f "${FAKE_HOME}/.ssh/denied.txt" ]] && echo yes || echo no))"
fi

# ============================================
echo ""
echo "=== [4] VIBECORP_ISOLATION=1 で sandbox 経由（VIBECORP_SANDBOXED=1 伝播） ==="
# ============================================
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- show-sandboxed) || status=$?
observed=$(cat "$STDOUT_LOG")
if [[ "$status" -eq 0 && "$observed" == "1" ]]; then
  pass "sandbox 経由時、子プロセスに VIBECORP_SANDBOXED=1 が伝播"
else
  fail "sandbox 経由の子プロセスで VIBECORP_SANDBOXED=1 を期待（観測: '$observed', status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [5] sandbox 経由で ~/.ssh/denied.txt 書込が拒否される（EPERM） ==="
# ============================================
rm -f "${FAKE_HOME}/.ssh/denied.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-ssh) || status=$?
if [[ "$status" -ne 0 && ! -f "${FAKE_HOME}/.ssh/denied.txt" ]]; then
  pass "sandbox 経由で ~/.ssh への書込が拒否（status=$status, stderr=$(wc -c < "$STDERR_LOG") bytes）"
else
  fail "sandbox 経由で ~/.ssh 書込が拒否されるべき (status=$status, file_exists=$([[ -f "${FAKE_HOME}/.ssh/denied.txt" ]] && echo yes || echo no))"
fi

# ============================================
echo ""
echo "=== [6] sandbox 経由で worktree 配下への書込が成功 ==="
# ============================================
worktree_file="${FAKE_WORKTREE}/wrote.txt"
rm -f "$worktree_file"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-wt "$worktree_file") || status=$?
if [[ "$status" -eq 0 && -f "$worktree_file" ]]; then
  pass "sandbox 経由で worktree 配下への書込成功"
else
  fail "sandbox 経由で worktree 書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [7] sandbox 経由で ~/.gitconfig 読取が成功 ==="
# ============================================
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- read-config) || status=$?
observed=$(cat "$STDOUT_LOG")
if [[ "$status" -eq 0 && "$observed" == *"isolation-test"* ]]; then
  pass "sandbox 経由で ~/.gitconfig 読取成功"
else
  fail "sandbox 経由で ~/.gitconfig 読取失敗 (status=$status, stdout='$observed', stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
