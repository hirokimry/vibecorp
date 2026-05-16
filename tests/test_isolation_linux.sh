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
# Issue #579 (mock テスト [12]〜[15]) について:
#   本ファイル末尾に mock bwrap を使った区分別エラーメッセージ検証テスト群を追加している。
#   mock テスト群は実 bwrap を使わないが、テストファイル冒頭の SKIP ガード
#   （uname / `command -v bwrap` / `bwrap --unshare-pid` 試し実行）を共有するため、
#   GHA `ubuntu-latest` (Ubuntu 24.04) のような実 bwrap 不動環境では **全体が SKIP** される。
#   mock テストを通すには CEO ローカル環境 or 自前ホストランナー（実 bwrap が動作する Linux）
#   が必要。CI ログの SKIP 状態の解釈に注意。
#
# 参照: #293 / #310 / #579

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
# Issue #579: mock bwrap 配置先（FAKE_BIN とは別ディレクトリ）
# mock テスト [12]〜[15] でのみ PATH に追加するため、既存テスト [1]〜[11] への副作用なし
MOCK_BIN="${TMPDIR_TEST}/mock-bin"
# Issue #579: 区分 A テスト用に「bwrap が PATH に存在しないが、uname / dirname 等の基本コマンドは
# 使える」状態を作るためのディレクトリ。/usr/bin の symlink を入れるが bwrap は入れない。
NOBWRAP_BIN="${TMPDIR_TEST}/nobwrap-bin"
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
mkdir -p "$MOCK_BIN"
mkdir -p "$NOBWRAP_BIN"
mkdir -p "$SANDBOX_TMPDIR"

# Issue #579: NOBWRAP_BIN に vibecorp-sandbox が必要とする基本コマンドのみ symlink する
# （uname / dirname / cd / pwd 等）。bwrap は意図的に含めない。
# これにより区分 A テスト [12] で `command -v bwrap` を確実に失敗させる。
for cmd in uname dirname; do
  if real_path="$(command -v "$cmd" 2>/dev/null)"; then
    ln -sf "$real_path" "${NOBWRAP_BIN}/${cmd}"
  fi
done

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
# Issue #579: 区分別エラーメッセージ検証テスト [12]〜[15]
#
# mock bwrap を MOCK_BIN に配置して、bwrap 起動失敗の 4 区分（A/B/C/D）それぞれが
# 期待される日本語メッセージと exit code = 1 を返すことを検証する。
# MOCK_BIN は FAKE_BIN とは別ディレクトリで、テスト [12]〜[15] でのみ PATH 先頭に置く。
# 既存テスト [1]〜[11] のヘルパー `run_sandbox` / `run_shim` は FAKE_BIN のみを PATH に
# 含めているため、MOCK_BIN の存在は既存テストに影響しない。
# ============================================

# run_sandbox_with_mock_bwrap — mock bwrap を有効化して vibecorp-sandbox を実行する
#
# 第 1 引数: mock_bin_path
#   - MOCK_BIN（実際のディレクトリパス）を渡すと PATH 先頭に追加 → mock bwrap が使われる
#   - 空文字列を渡すと PATH を NOBWRAP_BIN のみに絞る → bwrap 不在状態（区分 A テスト用）
# 第 2 引数以降: vibecorp-sandbox に渡す引数列（probe 等）
#
# 既存 `run_sandbox` と異なり PATH 制御を mock_bin_path で切り替える。
run_sandbox_with_mock_bwrap() {
  local mock_bin_path="$1"
  shift

  local path_value
  if [[ -n "$mock_bin_path" ]]; then
    # mock bwrap を MOCK_BIN から提供。FAKE_BIN と /usr/bin 等は補助コマンド用に維持
    path_value="${mock_bin_path}:${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  else
    # 区分 A テスト用: bwrap が PATH に存在しない状態を作る
    # NOBWRAP_BIN は uname / dirname のみを持ち、bwrap は意図的に含まれない
    path_value="${NOBWRAP_BIN}"
  fi

  local status=0
  env -i \
    HOME="$FAKE_HOME" \
    PATH="$path_value" \
    TMPDIR="$SANDBOX_TMPDIR" \
    bash "$DISPATCHER" "$@" \
    > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  return "$status"
}

# write_mock_bwrap — MOCK_BIN に mock bwrap スクリプトを配置する
#
# 第 1 引数: mock 内容（heredoc で渡す bash スクリプト本文）
write_mock_bwrap() {
  local mock_content="$1"
  cat > "${MOCK_BIN}/bwrap" <<MOCK_EOF
#!/bin/bash
${mock_content}
MOCK_EOF
  chmod +x "${MOCK_BIN}/bwrap"
}

# ============================================
echo ""
echo "=== [12] 区分 A: bwrap バイナリ不在で区分 A メッセージと exit 1 ==="
# ============================================
# MOCK_BIN を空にして bwrap 不在状態を作る（FAKE_BIN に bwrap は元々無い）
rm -f "${MOCK_BIN}/bwrap"
status=0
(cd "$FAKE_WORKTREE" && run_sandbox_with_mock_bwrap "" probe) || status=$?
stderr_content="$(cat "$STDERR_LOG")"
if [[ "$status" -eq 1 \
   && "$stderr_content" == *"bwrap (bubblewrap) が見つかりません"* \
   && "$stderr_content" == *"Debian/Ubuntu"* \
   && "$stderr_content" == *"Fedora/RHEL"* \
   && "$stderr_content" == *"Alpine"* ]]; then
  pass "区分 A: 不在メッセージ + exit 1 (status=$status)"
else
  fail "区分 A: 不在メッセージまたは exit 1 が出ない (status=$status, stderr=$stderr_content)"
fi

# ============================================
echo ""
echo "=== [13] 区分 B: bwrap --version 失敗で区分 B メッセージと exit 1 ==="
# ============================================
# mock bwrap: --version 引数のとき exit 1、それ以外（preflight C / 本番）は exit 0
# 引数判定は全引数列に対する case " $* " in *' --version '*) パターンで位置非依存
write_mock_bwrap '
case " $* " in
  *" --version "*) exit 1 ;;
  *) exit 0 ;;
esac
'
status=0
(cd "$FAKE_WORKTREE" && run_sandbox_with_mock_bwrap "$MOCK_BIN" probe) || status=$?
stderr_content="$(cat "$STDERR_LOG")"
if [[ "$status" -eq 1 \
   && "$stderr_content" == *"\`--version\` で起動失敗"* \
   && "$stderr_content" == *"apt-get install --reinstall bubblewrap"* \
   && "$stderr_content" == *"dnf reinstall bubblewrap"* \
   && "$stderr_content" == *"apk add --upgrade bubblewrap"* ]]; then
  pass "区分 B: バイナリ破損 / 権限メッセージ + exit 1 (status=$status)"
else
  fail "区分 B: 期待メッセージまたは exit 1 が出ない (status=$status, stderr=$stderr_content)"
fi

# ============================================
echo ""
echo "=== [14] 区分 C: user namespace 制限で区分 C メッセージと exit 1 ==="
# ============================================
# mock bwrap: --version は成功、引数列に --unshare-pid を含む場合は exit 1
# preflight C と本番は両方とも --unshare-pid を含むが、本テストは preflight C で止まることを期待
write_mock_bwrap '
case " $* " in
  *" --unshare-pid "*) exit 1 ;;
  *" --version "*) exit 0 ;;
  *) exit 0 ;;
esac
'
status=0
(cd "$FAKE_WORKTREE" && run_sandbox_with_mock_bwrap "$MOCK_BIN" probe) || status=$?
stderr_content="$(cat "$STDERR_LOG")"
if [[ "$status" -eq 1 \
   && "$stderr_content" == *"user namespace で bwrap が動作しません"* \
   && "$stderr_content" == *"kernel.unprivileged_userns_clone"* \
   && "$stderr_content" == *"apparmor"* \
   && "$stderr_content" == *"docs/SECURITY.md"* ]]; then
  pass "区分 C: user namespace 制限メッセージ + exit 1 (status=$status)"
else
  fail "区分 C: 期待メッセージまたは exit 1 が出ない (status=$status, stderr=$stderr_content)"
fi

# ============================================
echo ""
echo "=== [15] 区分 D: preflight 通過後の本番 bwrap 失敗で区分 D メッセージと exit 1 ==="
# ============================================
# mock bwrap: --version 成功、preflight C パターン（-- /bin/sh -c :）も成功、
# それ以外の --unshare-pid を含む本番引数列で exit 1（preflight 通過後の本番失敗を模擬）
write_mock_bwrap '
case " $* " in
  *" -- /bin/sh -c : "*) exit 0 ;;
  *" --version "*) exit 0 ;;
  *" --unshare-pid "*) exit 1 ;;
  *) exit 0 ;;
esac
'
status=0
(cd "$FAKE_WORKTREE" && run_sandbox_with_mock_bwrap "$MOCK_BIN" probe) || status=$?
stderr_content="$(cat "$STDERR_LOG")"
if [[ "$status" -eq 1 \
   && "$stderr_content" == *"preflight は通過しましたが"* \
   && "$stderr_content" == *"kernel / distro 固有"* \
   && "$stderr_content" == *"docs/SECURITY.md"* ]]; then
  pass "区分 D: kernel/distro 固有メッセージ + exit 1（bwrap 終了コード伝播） (status=$status)"
else
  fail "区分 D: 期待メッセージまたは exit 1 が出ない (status=$status, stderr=$stderr_content)"
fi

# mock bwrap を片付ける（既存テストに影響させないため）
rm -f "${MOCK_BIN}/bwrap"

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
