#!/bin/bash
# bwrap-args.sh — Linux bwrap 引数生成スクリプト（vibecorp 隔離レイヤ Phase 2）
#
# 目的:
#   vibecorp-sandbox から source されて呼ばれる。
#   bwrap 起動に必要な引数を BWRAP_ARGS 配列に組み立てる。
#
# 境界:
#   書込許可 : WORKTREE, ~/.claude, ~/.cache/vibecorp,
#              ~/.cache/claude, ~/.local/state/claude（Claude Code 2.1.112+ XDG サイドカー）,
#              ~/.claude.json (+.backup/.lock), /tmp, /run
#   読取許可 : /usr, /bin, /sbin, /lib, /lib64, /etc,
#              ~/.gitconfig, ~/.config/gh, ~/.npm, ~/.local/share/claude
#   ネット  : 全許可（--unshare-net は採用しない、npm/pip/cargo/API 全壊回避）
#   拒否    : ~/.ssh, ~/.aws, ~/.gnupg, ~/.config/gcloud（bind しない = bwrap default deny）
#
# 入力（呼出側 vibecorp-sandbox が export 済みの想定）:
#   WORKTREE_VALUE  — canonicalize 済みの作業ツリールート
#   HOME_VALUE      — canonicalize 済みのユーザーホーム
#   LINUX_TMPDIR_VALUE — canonicalize 済みの一時ディレクトリ
#
# 出力:
#   BWRAP_ARGS      — bash 配列（bwrap に渡す引数列）
#
# 既知制約（Phase 2）:
#   - .claude.json.tmp.<pid>.<ms> 動的サイドカーは bwrap で個別許可不可
#     （bwrap には regex 許可が無いため、起動時点で存在しないファイルは bind 不可）
#     Claude Code 側の rename 失敗時の挙動仮説（docs/SECURITY.md Phase 2.1 と分類体系を統一）:
#       (A) クラッシュ — 再ログイン不能なら Phase 2 ロールバック発火（唯一の発火条件）
#       (B) ハング     — SIGINT で復旧可能、実用上は問題なし
#       (C) エラー続行  — sandbox 利用継続可、エラーメッセージ品質改善は別検討
#       (D) ~/.claude.json への直接 write fallback — 最良ケース、信頼境界変化なし
#     (A) のみがロールバック発火条件。(B)(C)(D) いずれの場合でも信頼境界は
#     ~/.claude 全 RW と同等以下であり、本スクリプトの bind 設計に影響しない
#   - bind 対象 dir 内の攻撃者制御 symlink によるバインドエスケープリスク
#   - 本スクリプト実行から bwrap 起動までの TOCTOU
#
# 参照: #293 / #310 / #578

# 必須変数チェック（vibecorp-sandbox 側で canonicalize 済みであることを前提）
if [[ -z "${WORKTREE_VALUE:-}" || -z "${HOME_VALUE:-}" ]]; then
  echo "bwrap-args.sh: WORKTREE_VALUE / HOME_VALUE が未設定です（vibecorp-sandbox 経由で起動してください）" >&2
  return 1 2>/dev/null || exit 1
fi

# vibecorp.yml の isolation.allow_ssh を厳格に読み出す
# 責務分離: install.sh の read_vibecorp_yml は name/preset/language を読む。
#           bwrap-args.sh は isolation セクションのみ読む。両者は直交。
_bwrap_args_read_allow_ssh() {
  # CLAUDE_PROJECT_DIR が未設定なら WORKTREE_VALUE を起点とする
  local project_dir="${CLAUDE_PROJECT_DIR:-${WORKTREE_VALUE}}"
  local vibecorp_yml="${project_dir}/.claude/vibecorp.yml"

  if [[ ! -f "$vibecorp_yml" ]]; then
    echo "false"
    return 0
  fi

  # awk でブロック単位抽出（.claude/rules/shell.md 準拠）
  # grep -A N はセクション境界を越えるため使わない
  local raw
  raw=$(awk '
    /^isolation:/ { in_block=1; next }
    in_block && /^  allow_ssh:/ {
      gsub(/^[[:space:]]+allow_ssh:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      print
      exit
    }
    /^[a-z]/ && !/^isolation:/ { in_block=0 }
  ' "$vibecorp_yml")

  # 厳格比較: "true" 文字列に完全一致した場合のみ true、その他は全て false に倒す。
  # これにより BWRAP_ARGS への任意文字列注入を物理的に排除する。
  case "$raw" in
    true) echo "true" ;;
    *)    echo "false" ;;
  esac
}

ALLOW_SSH="$(_bwrap_args_read_allow_ssh)"

# BWRAP_ARGS を組み立てる
# 配列形式で組み立てることで word splitting / quote 問題を回避する
BWRAP_ARGS=()

# プロセス隔離
BWRAP_ARGS+=(--die-with-parent)
BWRAP_ARGS+=(--unshare-pid)
BWRAP_ARGS+=(--unshare-uts)
BWRAP_ARGS+=(--unshare-ipc)
# --unshare-net は採用しない（npm/pip/cargo/API 全壊のため。
# Phase 1 macOS の (allow network*) と整合）

# ファイルシステム
BWRAP_ARGS+=(--proc /proc)
BWRAP_ARGS+=(--dev /dev)
BWRAP_ARGS+=(--tmpfs /tmp)
BWRAP_ARGS+=(--tmpfs /run)

# RO bind: システムランタイム
# /usr は必須、それ以外は distro 差異吸収のため bind-try
BWRAP_ARGS+=(--ro-bind /usr /usr)
BWRAP_ARGS+=(--ro-bind-try /bin /bin)
BWRAP_ARGS+=(--ro-bind-try /sbin /sbin)
BWRAP_ARGS+=(--ro-bind-try /lib /lib)
BWRAP_ARGS+=(--ro-bind-try /lib64 /lib64)
BWRAP_ARGS+=(--ro-bind-try /etc /etc)

# RO bind: ユーザー設定（読取のみ、書込は EROFS）
BWRAP_ARGS+=(--ro-bind-try "${HOME_VALUE}/.gitconfig" "${HOME_VALUE}/.gitconfig")
BWRAP_ARGS+=(--ro-bind-try "${HOME_VALUE}/.config/gh" "${HOME_VALUE}/.config/gh")
BWRAP_ARGS+=(--ro-bind-try "${HOME_VALUE}/.npm" "${HOME_VALUE}/.npm")

# RO bind: Claude Code バイナリ実体（~/.local/share/claude/versions/<ver>/）
BWRAP_ARGS+=(--ro-bind-try "${HOME_VALUE}/.local/share/claude" "${HOME_VALUE}/.local/share/claude")

# RW bind: 作業ツリーと Claude 設定
BWRAP_ARGS+=(--bind "${WORKTREE_VALUE}" "${WORKTREE_VALUE}")
BWRAP_ARGS+=(--bind "${HOME_VALUE}/.claude" "${HOME_VALUE}/.claude")

# RW bind: vibecorp ゲートスタンプ保存先 (#326)
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.cache/vibecorp" "${HOME_VALUE}/.cache/vibecorp")

# RW bind: Claude Code 2.1.112+ XDG サイドカー (#331)
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.cache/claude" "${HOME_VALUE}/.cache/claude")
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.local/state/claude" "${HOME_VALUE}/.local/state/claude")

# RW bind: ~/.claude.json 系（個別ファイル単位）
# bwrap は regex 許可が無いため起動時点で存在するサイドカーのみ bind 可能。
# .claude.json.tmp.<pid>.<ms> 動的サイドカーは Phase 2 既知制約（#578）。
# 実機検証手順は docs/SECURITY.md を SoT とする。
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.claude.json" "${HOME_VALUE}/.claude.json")
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.claude.json.backup" "${HOME_VALUE}/.claude.json.backup")
BWRAP_ARGS+=(--bind-try "${HOME_VALUE}/.claude.json.lock" "${HOME_VALUE}/.claude.json.lock")

# allow_ssh opt-in（厳格比較済みの ALLOW_SSH 変数で分岐）
# "true" 以外は _bwrap_args_read_allow_ssh 内で全て "false" に倒される
if [[ "$ALLOW_SSH" == "true" ]]; then
  BWRAP_ARGS+=(--ro-bind-try "${HOME_VALUE}/.ssh" "${HOME_VALUE}/.ssh")
fi

# 二重サンドボックス防止フラグを bwrap 内環境変数として設定
# claude シム側の is_inside_sandbox（祖先 bwrap 検出）と AND で評価される
BWRAP_ARGS+=(--setenv VIBECORP_SANDBOXED 1)

# 注: 呼出側 vibecorp-sandbox は最後に "-- env VIBECORP_SANDBOXED=1 \"\$@\"" を追加して
# bwrap を exec する（マイクロ等価の二重設定で取りこぼし防止）
