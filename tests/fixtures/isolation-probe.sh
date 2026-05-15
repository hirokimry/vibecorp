#!/bin/bash
# isolation-probe.sh — macOS / Linux 隔離レイヤ共通プローブ
#
# 目的:
#   sandbox 内（macOS sandbox-exec / Linux bwrap）で実行され、
#   引数で指定された操作を試行して exit code で結果を返す。
#
# サブコマンド:
#   write-ssh                   — $HOME/.ssh/probe-write.txt への書込（拒否されるべき）
#   read-ssh                    — $HOME/.ssh 配下のファイル読取（拒否されるべき）
#                                 テスト側で $HOME/.ssh/probe-read.txt を事前作成しておく
#   write-worktree <path>       — 指定パスへの書込（許可されるべき）
#   read-etc                    — /etc/passwd 読取（macOS / Linux 両方に存在、許可されるべき）
#   write-etc                   — /etc/probe-write への書込（EROFS で拒否されるべき）
#   write-claude-json-tmp       — $HOME/.claude.json.tmp.<pid>.<ms> への書込
#                                 （macOS は許可、Linux は拒否される既知制約）
#   show-sandboxed              — VIBECORP_SANDBOXED の値を stdout に出力
#
# 終了コード:
#   0  — 操作成功
#   1  — 操作失敗（権限拒否・EROFS・ENOENT 等、すべて非ゼロに集約）
#
# 参照: #293 / #310

set -u

case "${1:-}" in
  write-ssh)
    : > "$HOME/.ssh/probe-write.txt" || exit 1
    ;;
  read-ssh)
    # 直下のファイル読取を試行（ls は file-read-metadata 単独で成立するため検出力が弱い）
    cat "$HOME/.ssh/probe-read.txt" > /dev/null || exit 1
    ;;
  write-worktree)
    # コメント仕様どおり「絶対パスが必要」を厳密に検証（相対パス・空文字を拒否）
    if [[ -z "${2:-}" || "${2}" != /* ]]; then
      echo "isolation-probe: write-worktree には絶対パスが必要" >&2
      exit 64
    fi
    : > "$2" || exit 1
    ;;
  read-etc)
    cat /etc/passwd > /dev/null || exit 1
    ;;
  write-etc)
    : > /etc/probe-write || exit 1
    ;;
  write-claude-json-tmp)
    # Claude Code 等価の動的 OAuth サイドカー書込試行
    tmpfile="$HOME/.claude.json.tmp.$$.$(date +%s)"
    : > "$tmpfile" || exit 1
    rm -f "$tmpfile"
    ;;
  show-sandboxed)
    printf '%s\n' "${VIBECORP_SANDBOXED:-UNSET}"
    ;;
  *)
    echo "isolation-probe: 未知のサブコマンド: ${1:-}" >&2
    echo "  サブコマンド: write-ssh / read-ssh / write-worktree <path> / read-etc / write-etc / write-claude-json-tmp / show-sandboxed" >&2
    exit 64
    ;;
esac
