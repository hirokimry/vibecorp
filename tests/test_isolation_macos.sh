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

# sandbox に DARWIN_TMPDIR として渡す専用ディレクトリ。
# FAKE_HOME は TMPDIR_TEST 直下に作るため、ここと同じディレクトリを TMPDIR に設定すると
# `(subpath (param "DARWIN_TMPDIR"))` の RW 許可で FAKE_HOME/.ssh までもが許可範囲になり、
# 拒否テストが意味を失う。FAKE_HOME とは兄弟関係のサブディレクトリに分離する。
SANDBOX_TMPDIR="${TMPDIR_TEST}/sandbox-tmp"
mkdir -p "$SANDBOX_TMPDIR"

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
  write-claude-json-sidecar)
    # Claude Code の原子的置換パターンを再現:
    # $HOME/.claude.json.lock（固定名） + $HOME/.claude.json.tmp.<pid>.<epoch_ms>（動的名）
    # 実際の Claude Code は Date.now()（ミリ秒）で suffix を生成するため、
    # 秒精度（date +%s）だと sandbox 側の誤狭化（"秒だけ許可"）を検知できない。
    # perl の Time::HiRes でミリ秒精度を生成する（macOS 標準搭載）。
    # 両方成功すれば exit 0、片方でも失敗すれば exit 1
    : > "$HOME/.claude.json.lock" || exit 1
    : > "$HOME/.claude.json.tmp.$$.$(perl -MTime::HiRes=time -e 'printf "%d", time()*1000')" || exit 1
    ;;
  write-path)
    # 第2引数で受け取った絶対パスに 1 バイト書込を試みる（拒否境界検証用）
    : > "$2" || exit 1
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
echo "=== [8] WORKTREE が HOME を包含する設定は vibecorp-sandbox が拒否する（ネガティブ） ==="
# ============================================
# WORKTREE（$PWD）が HOME の祖先だと (subpath (param "WORKTREE")) の RW 許可が
# ~/.ssh / ~/.aws / ~/.gnupg まで広がってしまう。vibecorp-sandbox はこれを拒否するべき。
# 参照: CodeRabbit PRRT_kwDORsBHcs57Uynh（Critical）/ audit-log.md 第4回レビュー
#
# TMPDIR_TEST（= canonicalized 共通親）を $PWD にして run_shim を起動すると、
# FAKE_HOME（=${TMPDIR_TEST}/fake-home）が canonicalize 後に WORKTREE 配下となり
# 包含判定に引っかかる。
status=0
(cd "$TMPDIR_TEST" && run_shim VIBECORP_ISOLATION=1 -- show-sandboxed) || status=$?
if [[ "$status" -ne 0 && "$(cat "$STDERR_LOG")" == *"WORKTREE が HOME を包含"* ]]; then
  pass "WORKTREE が HOME を包含する設定で vibecorp-sandbox が拒否 (status=${status})"
else
  fail "WORKTREE が HOME を包含する設定でも起動してしまった (status=${status}, stderr=$(cat "$STDERR_LOG"))"
fi

# ============================================
echo ""
echo "=== [9] 実機 claude --version が sandbox 経由で通る（実機検証） ==="
# ============================================
# Issue #320 の修正検証: sandbox プロファイルが real claude のバイナリ実体読取
# （~/.local/share/claude/**）と ~/.claude.json を許可しているかを確認する。
#
# このテストは実機の claude バイナリと実 HOME に依存するため、
# ローカル開発環境専用の検証として位置付ける（CI では skip される）。
#
# テスト [1]〜[8] と異なり、ここでは FAKE_HOME ではなく実 HOME を使う。
# 理由: real claude は ~/.local/share/claude/versions/<ver>/ を実 HOME 配下に
# 配置するため、HOME を override すると本物 claude が見つからない。
real_claude=""
if command -v claude >/dev/null 2>&1; then
  real_claude="$(command -v claude)"
fi
if [[ -z "$real_claude" || "$real_claude" == "$SHIM" || "$real_claude" == *"/.claude/bin/claude" ]]; then
  echo "  SKIP: 実機 claude が見つからない（または vibecorp ラッパーのみ）ためスキップ"
else
  # 実 HOME を使う real-env テスト用の bin を別途用意し、claude-real だけを実機 claude に向ける
  REAL_BIN="${TMPDIR_TEST}/real-bin"
  REAL_WORKTREE="${TMPDIR_TEST}/real-worktree"
  mkdir -p "$REAL_BIN" "$REAL_WORKTREE"
  ln -sf "$real_claude" "${REAL_BIN}/claude-real"

  status=0
  (cd "$REAL_WORKTREE" && \
    env -i \
      HOME="$HOME" \
      PATH="${REAL_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="${TMPDIR:-/tmp}" \
      VIBECORP_ISOLATION=1 \
      bash "$SHIM" --version \
      > "$STDOUT_LOG" 2> "$STDERR_LOG") || status=$?

  observed=$(cat "$STDOUT_LOG")
  if [[ "$status" -eq 0 && "$observed" =~ [Cc]laude ]]; then
    pass "実機 claude --version が sandbox 経由で通った (output='$observed')"
  else
    fail "実機 claude --version が sandbox 経由で失敗 (status=$status, stdout='$observed', stderr=$(cat "$STDERR_LOG"))"
  fi
fi

# ============================================
echo ""
echo "=== [10] 実機 claude TUI が sandbox 経由で raw mode に入れる（expect） ==="
# ============================================
# Issue #320 の修正検証: sandbox プロファイルが /dev 配下の file-ioctl を許可しているか
# （TTY raw mode 切替が拒否されないか）を確認する。
#
# expect で TUI を起動し、5 秒以内に ANSI エスケープシーケンス（TUI raw mode の証跡）が
# 出力されることを検証する。expect 不在環境または実機 claude 不在環境では skip する。
if ! command -v expect >/dev/null 2>&1; then
  echo "  SKIP: expect がインストールされていないためスキップ"
elif [[ -z "$real_claude" || "$real_claude" == "$SHIM" || "$real_claude" == *"/.claude/bin/claude" ]]; then
  echo "  SKIP: 実機 claude が見つからないためスキップ"
else
  status=0
  # expect スクリプトは raw mode 切替で出る ANSI ESC を検出した時点で成功とする
  # （プロンプト内容や認証状態に依存しない最小限のシグナル）
  expect -c "
    set timeout 5
    spawn env -i HOME=$HOME PATH=${REAL_BIN}:/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=${TMPDIR:-/tmp} VIBECORP_ISOLATION=1 bash $SHIM
    expect {
      -re \"\\x1b\\\\\[\" { exit 0 }
      timeout { exit 124 }
      eof { exit 1 }
    }
  " > "$STDOUT_LOG" 2> "$STDERR_LOG" || status=$?
  if [[ "$status" -eq 0 ]]; then
    pass "実機 claude TUI が sandbox 経由で raw mode に入れた"
  else
    fail "実機 claude TUI が sandbox 経由で起動できない (status=$status, expect_log=$(tail -20 "$STDOUT_LOG"), stderr=$(cat "$STDERR_LOG"))"
  fi
fi

# ============================================
echo ""
echo "=== [11] sandbox 経由で .claude.json サイドカー (.lock / .tmp.<pid>.<ms>) 書込が成功 ==="
# ============================================
# Issue #329: Claude Code は OAuth state を原子的置換で保存する。
# literal 許可の .lock と regex 許可の .tmp.<pid>.<ms> 双方が sandbox を通ることを検証する。
rm -f "${FAKE_HOME}/.claude.json.lock" "${FAKE_HOME}"/.claude.json.tmp.*
status=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-claude-json-sidecar) || status=$?
lock_exists="no"
tmp_exists="no"
[[ -f "${FAKE_HOME}/.claude.json.lock" ]] && lock_exists="yes"
# shellcheck disable=SC2012
if ls "${FAKE_HOME}"/.claude.json.tmp.* >/dev/null 2>&1; then
  tmp_exists="yes"
fi
if [[ "$status" -eq 0 && "$lock_exists" == "yes" && "$tmp_exists" == "yes" ]]; then
  pass "サイドカー書込成功（.lock と .tmp.<pid>.<ms> 両方生成）"
else
  fail "サイドカー書込失敗 (status=$status, lock=$lock_exists, tmp=$tmp_exists, stderr=$(cat "$STDERR_LOG"))"
fi
rm -f "${FAKE_HOME}/.claude.json.lock" "${FAKE_HOME}"/.claude.json.tmp.*

# ============================================
echo ""
echo "=== [12] sandbox 経由で .claude.json 類似の範囲外パスへの書込が拒否される（regex 境界検証） ==="
# ============================================
# regex パターン ^HOME/\.claude\.json\.tmp\.[0-9]+\.[0-9]+$ の境界を検証する。
# また .lock 側の literal 境界（prefix / regex への誤拡張）も検証する。
# 以下は deny default で拒否されるべきパス:
#   .claude.jsonEVIL            — 類似名・サフィックス付加（. 始まりの拡張ではない）
#   .claude.json.locked         — .lock literal の prefix 誤拡張検知
#   .claude.json.lock.extra     — .lock literal の sub-path 誤拡張検知
#   .claude.json.tmp.1.2.extra  — regex 末尾 $ 境界（余計なサフィックス）
#   .claude.json.tmp.abc.1      — [0-9]+ 先頭が数値以外
#   .claude.json.tmp.1.         — 末尾が . で数値が続かない
deny_paths=(
  "${FAKE_HOME}/.claude.jsonEVIL"
  "${FAKE_HOME}/.claude.json.locked"
  "${FAKE_HOME}/.claude.json.lock.extra"
  "${FAKE_HOME}/.claude.json.tmp.1.2.extra"
  "${FAKE_HOME}/.claude.json.tmp.abc.1"
  "${FAKE_HOME}/.claude.json.tmp.1."
)
test12_all_ok=1
for deny_path in "${deny_paths[@]}"; do
  rm -f "$deny_path"
  status=0
  (cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-path "$deny_path") || status=$?
  if [[ "$status" -ne 0 && ! -f "$deny_path" ]]; then
    pass "範囲外パス拒否: ${deny_path##${FAKE_HOME}/}"
  else
    fail "範囲外パスが許可された: ${deny_path##${FAKE_HOME}/} (status=$status, file_exists=$([[ -f "$deny_path" ]] && echo yes || echo no))"
    test12_all_ok=0
  fi
  rm -f "$deny_path"
done

# ============================================
echo ""
echo "=== [13] sandbox 経由で既存 .lock への上書き（ロック再取得）が成功 ==="
# ============================================
# ロック再取得パターン: 2 回連続で write-claude-json-sidecar を実行し、
# .lock への上書きが 2 回とも成功することを検証する。
# .tmp.<pid>.<epoch_ms> はミリ秒精度なので sleep なしで衝突しない。
rm -f "${FAKE_HOME}/.claude.json.lock" "${FAKE_HOME}"/.claude.json.tmp.*
status1=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-claude-json-sidecar) || status1=$?
status2=0
(cd "$FAKE_WORKTREE" && run_shim VIBECORP_ISOLATION=1 -- write-claude-json-sidecar) || status2=$?
if [[ "$status1" -eq 0 && "$status2" -eq 0 && -f "${FAKE_HOME}/.claude.json.lock" ]]; then
  pass ".lock への 2 回目の上書きが成功（ロック再取得）"
else
  fail ".lock 上書き失敗 (status1=$status1, status2=$status2, lock_exists=$([[ -f "${FAKE_HOME}/.claude.json.lock" ]] && echo yes || echo no), stderr=$(cat "$STDERR_LOG"))"
fi
rm -f "${FAKE_HOME}/.claude.json.lock" "${FAKE_HOME}"/.claude.json.tmp.*

# ============================================
echo ""
echo "=== [14] .claude/sandbox/claude.sb と templates/claude/sandbox/claude.sb が同一 ==="
# ============================================
# C4: 本体とテンプレートの同期ずれ防止（#329）
LIVE_PROFILE="${SCRIPT_DIR}/.claude/sandbox/claude.sb"
TEMPLATE_PROFILE="${SCRIPT_DIR}/templates/claude/sandbox/claude.sb"
if [[ -f "$LIVE_PROFILE" && -f "$TEMPLATE_PROFILE" ]]; then
  if diff -q "$LIVE_PROFILE" "$TEMPLATE_PROFILE" > /dev/null; then
    pass "sandbox プロファイル本体とテンプレートが同一"
  else
    fail "sandbox プロファイルに差分あり（$LIVE_PROFILE vs $TEMPLATE_PROFILE）"
  fi
else
  fail "sandbox プロファイル不在: live=$([[ -f "$LIVE_PROFILE" ]] && echo yes || echo no), template=$([[ -f "$TEMPLATE_PROFILE" ]] && echo yes || echo no)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
