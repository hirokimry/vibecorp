#!/bin/bash
# test_isolation_linux.sh — Linux bwrap 隔離レイヤのテスト
#
# 対象:
#   - templates/claude/bin/claude           (PATH シム)
#   - templates/claude/bin/vibecorp-sandbox (OS ディスパッチャ)
#   - templates/claude/sandbox/bwrap-args.sh (bwrap 引数生成)
#
# 非 Linux では skip (exit 0)。bwrap 不在環境でも skip。
#
# 参照: #293 / #310

# 非 Linux では早期 skip（macOS CI が赤くならないように）
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: tests/test_isolation_linux.sh は Linux 以外では実行しない（現在: $(uname -s)）"
  exit 0
fi

# bwrap 不在環境でも skip（インストール未済の CI ランナーで誤検知させない）
if ! command -v bwrap >/dev/null 2>&1; then
  echo "SKIP: bwrap がインストールされていないためスキップ"
  exit 0
fi

# bwrap 試し実行（user namespace 等の前提が満たされない環境では skip）
# CI ランナーや Docker コンテナ内では unprivileged user namespace が無効化されている場合がある
if ! bwrap --unshare-pid --proc /proc --dev /dev --tmpfs /tmp /bin/true >/dev/null 2>&1; then
  echo "SKIP: bwrap が動作しない環境（user namespace 無効等）のためスキップ"
  exit 0
fi

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="${SCRIPT_DIR}/templates/claude/bin/claude"
DISPATCHER="${SCRIPT_DIR}/templates/claude/bin/vibecorp-sandbox"
BWRAP_ARGS_SH="${SCRIPT_DIR}/templates/claude/sandbox/bwrap-args.sh"
PROBE="${SCRIPT_DIR}/tests/fixtures/isolation-probe.sh"

# ----- 前提ファイル確認 -----

echo "=== 前提: ファイル存在と実行権限 ==="

prereq_ok=1
for f in "$SHIM" "$DISPATCHER" "$BWRAP_ARGS_SH" "$PROBE"; do
  if [[ -f "$f" ]]; then
    pass "存在: $f"
  else
    fail "前提ファイル不在: $f"
    prereq_ok=0
  fi
done

for f in "$SHIM" "$DISPATCHER" "$PROBE"; do
  if [[ -x "$f" ]]; then
    pass "実行権限: $f"
  else
    fail "実行権限が無い: $f"
    prereq_ok=0
  fi
done

if [[ "$prereq_ok" -ne 1 ]]; then
  echo ""
  echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="
  exit 1
fi

# ----- テスト環境構築 -----

TMPDIR_TEST=$(mktemp -d -t vibecorp-isolation-linux-XXXXXX)
STDERR_LOG="${TMPDIR_TEST}/stderr.log"
STDOUT_LOG="${TMPDIR_TEST}/stdout.log"

cleanup() {
  rm -rf "$TMPDIR_TEST" || true
}
trap cleanup EXIT

FAKE_HOME="${TMPDIR_TEST}/fake-home"
FAKE_WORKTREE="${TMPDIR_TEST}/fake-worktree"
FAKE_BIN="${TMPDIR_TEST}/fake-bin"
SANDBOX_TMPDIR="${TMPDIR_TEST}/sandbox-tmp"

# FAKE_HOME を構築
# ~/.ssh は事前作成（書込失敗理由を ENOENT ではなく EPERM/EROFS に限定するため、
# bind 拒否と「親ディレクトリ不在」を区別する）
mkdir -p "${FAKE_HOME}/.ssh"
mkdir -p "${FAKE_HOME}/.claude"
# read-ssh プローブ用のファイル（sandbox は読取を拒否すべき）
echo "secret-content" > "${FAKE_HOME}/.ssh/probe-read.txt"
cat > "${FAKE_HOME}/.gitconfig" <<'GITCONFIG'
[user]
  name = isolation-test
  email = test@example.com
GITCONFIG

mkdir -p "$FAKE_WORKTREE"
mkdir -p "$FAKE_BIN"
mkdir -p "$SANDBOX_TMPDIR"

# probe 経由で claude-real を fake する（shim → vibecorp-sandbox → bwrap 内で起動）
# isolation-probe.sh を claude-real としてエイリアスし、vibecorp-sandbox の引数で probe を呼ぶ
cat > "${FAKE_BIN}/claude-real" <<CLAUDEREAL
#!/bin/bash
exec "$PROBE" "\$@"
CLAUDEREAL
chmod +x "${FAKE_BIN}/claude-real"

# vibecorp-sandbox を直接呼ぶヘルパー（probe を引数として渡す）
# env -i でホスト環境を切り離し、テスト専用環境で起動する
run_sandbox() {
  local -a env_vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_vars+=("$1")
    shift
  done
  if [[ $# -eq 0 ]]; then
    echo "run_sandbox: '--' 区切りが必要" >&2
    return 64
  fi
  shift

  local status=0
  if [[ ${#env_vars[@]} -gt 0 ]]; then
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      "${env_vars[@]}" \
      bash "$DISPATCHER" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  else
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      bash "$DISPATCHER" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  fi
  return "$status"
}

# shim 経由のヘルパー
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
  shift

  local status=0
  if [[ ${#env_vars[@]} -gt 0 ]]; then
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      "${env_vars[@]}" \
      bash "$SHIM" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  else
    env -i \
      HOME="$FAKE_HOME" \
      PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$SANDBOX_TMPDIR" \
      bash "$SHIM" "$@" \
      > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  fi
  return "$status"
}

# ============================================
echo ""
echo "=== [1] VIBECORP_ISOLATION=0 で shim passthrough ==="
# ============================================
# passthrough なら probe (claude-real) が ~/.ssh に書けるはず
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=0 -- write-ssh) || status=$?
if [[ "$status" -eq 0 && -f "${FAKE_HOME}/.ssh/probe-write.txt" ]]; then
  pass "VIBECORP_ISOLATION=0: ~/.ssh に書けた（passthrough 動作）"
else
  fail "VIBECORP_ISOLATION=0: passthrough せず書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [2] VIBECORP_ISOLATION 未設定で shim passthrough ==="
# ============================================
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim -- write-ssh) || status=$?
if [[ "$status" -eq 0 && -f "${FAKE_HOME}/.ssh/probe-write.txt" ]]; then
  pass "未設定: ~/.ssh に書けた（既定が opt-in である）"
else
  fail "未設定: passthrough せず書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [3] 外部からの VIBECORP_SANDBOXED=1 注入で sandbox はバイパスされない（fail-closed 検証） ==="
# ============================================
# 祖先プロセスに bwrap がいない状態で VIBECORP_SANDBOXED=1 だけを外部から注入しても、
# claude シムの is_inside_sandbox（PPID 検証）により passthrough しない。
# 結果として VIBECORP_ISOLATION=1 経路に落ち、bwrap 経由で起動され、
# ~/.ssh への書込は bwrap が拒否するため probe-write.txt は生成されない。
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 VIBECORP_SANDBOXED=1 -- write-ssh) || status=$?
if [[ "${status}" -ne 0 && ! -f "${FAKE_HOME}/.ssh/probe-write.txt" ]]; then
  pass "外部からの VIBECORP_SANDBOXED=1 注入では sandbox をバイパスできない (status=${status})"
else
  fail "外部からの VIBECORP_SANDBOXED=1 注入で sandbox がバイパスされた (status=${status})"
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
echo "=== [5] sandbox 経由で ~/.ssh への書込が拒否される ==="
# ============================================
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-ssh) || status=$?
if [[ "$status" -ne 0 && ! -f "${FAKE_HOME}/.ssh/probe-write.txt" ]]; then
  pass "sandbox 経由で ~/.ssh への書込が拒否 (status=$status)"
else
  fail "sandbox 経由で ~/.ssh 書込が拒否されるべき (status=$status)"
fi

# ============================================
echo ""
echo "=== [6] sandbox 経由で worktree 配下への書込が成功 ==="
# ============================================
worktree_file="${FAKE_WORKTREE}/wrote.txt"
rm -f "$worktree_file"
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-worktree "$worktree_file") || status=$?
if [[ "$status" -eq 0 && -f "$worktree_file" ]]; then
  pass "sandbox 経由で worktree 配下への書込成功"
else
  fail "sandbox 経由で worktree 書込失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [7] sandbox 経由で /etc 読取は成功、/etc 書込は EROFS で拒否 ==="
# ============================================
status_read=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- read-etc) || status_read=$?
if [[ "$status_read" -eq 0 ]]; then
  pass "sandbox 経由で /etc 読取成功"
else
  fail "sandbox 経由で /etc 読取失敗 (status=$status_read, stderr=$(cat "$STDERR_LOG"))"
fi

status_write=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-etc) || status_write=$?
if [[ "$status_write" -ne 0 ]]; then
  pass "sandbox 経由で /etc 書込が拒否（status=$status_write）"
else
  fail "sandbox 経由で /etc 書込が拒否されるべき (status=$status_write)"
fi

# ============================================
echo ""
echo "=== [8] WORKTREE が HOME を包含する設定は vibecorp-sandbox が拒否する ==="
# ============================================
# TMPDIR_TEST を $PWD にして起動すると、FAKE_HOME（=${TMPDIR_TEST}/fake-home）が
# canonicalize 後に WORKTREE 配下となり包含判定に引っかかる。
status=0
(cd "$TMPDIR_TEST" && run_shim VIBECORP_ISOLATION=1 -- show-sandboxed) || status=$?
if [[ "$status" -ne 0 && "$(cat "$STDERR_LOG")" == *"WORKTREE が HOME を包含"* ]]; then
  pass "WORKTREE が HOME を包含する設定で vibecorp-sandbox が拒否 (status=${status})"
else
  fail "WORKTREE が HOME を包含する設定でも起動してしまった (status=${status}, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [8b] WORKTREE == HOME 同一設定は vibecorp-sandbox が拒否する ==="
# ============================================
# Issue #310 受け入れ条件「WORKTREE=HOME 拒否」を直接カバーする。
# cd "$FAKE_HOME" で起動すると PWD == FAKE_HOME となり、vibecorp-sandbox の
# 「WORKTREE を HOME と同一にはできません」分岐に引っかかる。
status=0
(cd "$FAKE_HOME" && run_shim VIBECORP_ISOLATION=1 -- show-sandboxed) || status=$?
if [[ "$status" -ne 0 && "$(cat "$STDERR_LOG")" == *"WORKTREE を HOME と同一にはできません"* ]]; then
  pass "WORKTREE == HOME 同一設定で vibecorp-sandbox が拒否 (status=${status})"
else
  fail "WORKTREE == HOME 同一設定でも起動してしまった (status=${status}, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [9] allow_ssh: true で ~/.ssh 読取成功 + 書込は EROFS で拒否 ==="
# ============================================
# vibecorp.yml を FAKE_WORKTREE に配置して isolation.allow_ssh: true を opt-in
mkdir -p "${FAKE_WORKTREE}/.claude"
cat > "${FAKE_WORKTREE}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
isolation:
  allow_ssh: true
YAML

# ~/.ssh 読取
status=0
(cd "$FAKE_WORKTREE" && CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" run_shim VIBECORP_ISOLATION=1 CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" -- read-ssh) || status=$?
if [[ "$status" -eq 0 ]]; then
  pass "allow_ssh: true で ~/.ssh 読取成功"
else
  fail "allow_ssh: true で ~/.ssh 読取失敗 (status=$status, stderr=$(cat "$STDERR_LOG"))"
fi

# ~/.ssh 書込（ro-bind なので EROFS）
rm -f "${FAKE_HOME}/.ssh/probe-write.txt"
status=0
(cd "$FAKE_WORKTREE" && CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" run_shim VIBECORP_ISOLATION=1 CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" -- write-ssh) || status=$?
if [[ "$status" -ne 0 && ! -f "${FAKE_HOME}/.ssh/probe-write.txt" ]]; then
  pass "allow_ssh: true でも ~/.ssh 書込は ro-bind で拒否 (status=$status)"
else
  fail "allow_ssh: true で ~/.ssh 書込が拒否されるべき (status=$status, file_exists=$([[ -f "${FAKE_HOME}/.ssh/probe-write.txt" ]] && echo yes || echo no))"
fi

# allow_ssh 設定なしに戻す（後続テストへの影響回避）
rm -rf "${FAKE_WORKTREE}/.claude"

# ============================================
echo ""
echo "=== [10] allow_ssh の strict 比較（true 以外は全て false） ==="
# ============================================
# isolation.allow_ssh: "true; --bind / /" のような注入を試みても ~/.ssh は bind されない
mkdir -p "${FAKE_WORKTREE}/.claude"
cat > "${FAKE_WORKTREE}/.claude/vibecorp.yml" <<'YAML'
name: test-project
preset: full
language: ja
isolation:
  allow_ssh: maybe
YAML

status=0
(cd "$FAKE_WORKTREE" && CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" run_shim VIBECORP_ISOLATION=1 CLAUDE_PROJECT_DIR="$FAKE_WORKTREE" -- read-ssh) || status=$?
if [[ "$status" -ne 0 ]]; then
  pass "allow_ssh: maybe（true 以外）で ~/.ssh は bind されず読取拒否 (status=$status)"
else
  fail "allow_ssh: maybe で ~/.ssh が見えてしまった（strict 比較失敗、status=$status）"
fi
rm -rf "${FAKE_WORKTREE}/.claude"

# ============================================
echo ""
echo "=== [11] bwrap-args.sh が WORKTREE_VALUE / HOME_VALUE 未設定で source されたら失敗 ==="
# ============================================
# 単体スクリプトとしての防御を検証
status=0
(unset WORKTREE_VALUE HOME_VALUE; bash -c "source '$BWRAP_ARGS_SH'") > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
if [[ "$status" -ne 0 && "$(cat "$STDERR_LOG")" == *"WORKTREE_VALUE / HOME_VALUE が未設定"* ]]; then
  pass "bwrap-args.sh が必須変数未設定で source されると拒否"
else
  fail "bwrap-args.sh が必須変数未設定でも source されてしまった (status=$status)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
