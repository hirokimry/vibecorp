#!/bin/bash
# install.sh — vibecorp プラグインインストーラー
# Usage: install.sh --name <project-name> [--preset minimal|standard|full] [--language ja|en|...] [--version v1.0.0]
#        install.sh --update [--preset minimal|standard|full]
set -euo pipefail

# ${BASH_SOURCE[0]} を使用することで、`bash install.sh` 実行時だけでなく
# `source install.sh`（テストからの内部関数呼び出し等）でも install.sh 自身のディレクトリを解決できる
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Git タグからバージョンを動的取得（タグがない場合は開発版として扱う）
VIBECORP_VERSION=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
VIBECORP_VERSION="${VIBECORP_VERSION#v}"

# コピー済みファイル追跡用（lock 生成で使用）
COPIED_DOCS=""
COPIED_KNOWLEDGE=""
COPIED_RULES=""
COPIED_ISSUE_TEMPLATES=""

# OS 判定結果（detect_os で設定）。set -u 環境下で未初期化参照を防ぐため空文字で初期化する
OS=""

# ── ユーティリティ ─────────────────────────────────────

log_info()     { printf '\033[32m[INFO]\033[0m     %s\n' "$*" >&2; }
log_warn()     { printf '\033[33m[WARN]\033[0m     %s\n' "$*" >&2; }
log_error()    { printf '\033[31m[ERROR]\033[0m    %s\n' "$*" >&2; }
log_skip()     { printf '\033[33m[SKIP]\033[0m     %s\n' "$*" >&2; }
log_merge()    { printf '\033[36m[MERGE]\033[0m    %s\n' "$*" >&2; }
log_conflict() { printf '\033[35m[CONFLICT]\033[0m %s\n' "$*" >&2; }

# コンフリクトが発生したファイルを追跡
CONFLICT_FILES=""

fetch_latest_tags() {
  # リモートから最新のタグ情報を取得する（--update モード用）
  # fetch 失敗時（オフライン等）はローカルのタグで続行し、エラーで止めない
  if git -C "$SCRIPT_DIR" fetch --tags --quiet 2>/dev/null; then
    log_info "リモートから最新のタグ情報を取得しました"
  else
    log_info "タグの取得に失敗しました。ローカルのタグ情報で続行します"
  fi
  # fetch 後にバージョンを再取得して最新化
  VIBECORP_VERSION=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
  VIBECORP_VERSION="${VIBECORP_VERSION#v}"
}

usage() {
  local exit_code="${1:-1}"
  cat >&2 <<'USAGE'
Usage: install.sh --name <project-name> [--preset minimal|standard|full] [--language ja] [--version v1.0.0]
       install.sh --update [--preset minimal|standard|full]

Options:
  --name         プロジェクト名（初回インストール時に必須）
  --update       既存インストールを更新（vibecorp.yml から設定を読み取る）
  --preset       組織プリセット: minimal, standard, full（デフォルト: minimal）
  --language     回答言語: ja, en, または任意（デフォルト: ja）
  --version      インストールする vibecorp のバージョン（例: v1.0.0）
  --no-migrate   旧 consumer 向け tracked artifact 自動 untrack をスキップする
                 （--name / --update の両モードで受け付けるが、通常は既存環境の移行時に意味を持つ）
  -h, --help     このヘルプを表示

--name と --update は同時に指定できません。
USAGE
  exit "$exit_code"
}

resolve_language() {
  case "$1" in
    ja) echo "日本語" ;;
    en) echo "English" ;;
    *)  echo "$1" ;;
  esac
}

resolve_coderabbit_language() {
  case "$1" in
    ja) echo "ja-JP" ;;
    en) echo "en-US" ;;
    *)  echo "$1" ;;
  esac
}

is_item_enabled() {
  # vibecorp.yml の指定セクション内で、指定キーが false かどうかを判定する
  # 使い方: is_item_enabled <section> <name>
  # yml が存在しない、セクションがない、キーがない場合は有効（0）を返す
  # 明示的に false の場合のみ無効（1）を返す
  local section="$1"
  local name="$2"
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  [[ -f "$yml" ]] || return 0

  local val
  val=$(awk -v section="$section" -v key="$name" '
    /^[^ #]/ { current_section = $0; gsub(/:.*/, "", current_section) }
    current_section == section && $0 ~ "^  " key ":" {
      val = $2
      gsub(/^[ \t]+/, "", val)
      print val
      exit
    }
  ' "$yml")

  [[ "$val" == "false" ]] && return 1
  return 0
}

is_skill_enabled() {
  # vibecorp.yml の skills セクションを参照し、有効かどうかを返す
  is_item_enabled "skills" "$1"
}

compute_hash() {
  # ファイルの SHA256 ハッシュを計算する（macOS/Linux 互換）
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{ print $1 }'
  else
    # フォールバック: ハッシュ計算不可の場合は空を返す（上書きモードにフォールバック）
    echo ""
  fi
}

read_base_hash() {
  # vibecorp.lock の base_hashes セクションから指定パスのハッシュを取得
  local lock="$1"
  local rel_path="$2"

  [[ -f "$lock" ]] || return 0

  awk -v path="$rel_path" '
    /^  base_hashes:/ { in_hashes = 1; next }
    in_hashes && /^  [a-z]/ { exit }
    in_hashes && /^[^ ]/ { exit }
    in_hashes {
      # "    hooks/protect-files.sh: abc123..." の形式をパース
      gsub(/^[ \t]+/, "")
      split($0, parts, ": ")
      if (parts[1] == path) {
        print parts[2]
        exit
      }
    }
  ' "$lock"
}

save_base_snapshot() {
  # テンプレートファイルをベーススナップショットとして保存
  local src="$1"
  local rel_path="$2"
  local base_dir="${REPO_ROOT}/.claude/vibecorp-base"
  local dest="${base_dir}/${rel_path}"
  local dest_dir
  dest_dir=$(dirname "$dest")

  mkdir -p "$dest_dir"
  cp "$src" "$dest"
}

get_base_snapshot() {
  # ベーススナップショットのパスを返す（存在しない場合は空）
  local rel_path="$1"
  local base_dir="${REPO_ROOT}/.claude/vibecorp-base"
  local path="${base_dir}/${rel_path}"

  if [[ -f "$path" ]]; then
    echo "$path"
  fi
}

merge_or_overwrite() {
  # 3-way マージまたは上書きを実行する
  # 引数: <テンプレートファイル> <配置先ファイル> <相対パス>
  # 戻り値: 0=成功, 1=コンフリクト
  local template="$1"
  local target="$2"
  local rel_path="$3"
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"

  # 配置先が存在しない場合は単純コピー
  if [[ ! -f "$target" ]]; then
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # ベースハッシュを取得
  local base_hash
  base_hash=$(read_base_hash "$lock" "$rel_path")

  # ベースハッシュがない場合（旧バージョンからの移行）は上書き
  if [[ -z "$base_hash" ]]; then
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # 現在のファイルのハッシュを計算
  local current_hash
  current_hash=$(compute_hash "$target")

  # ハッシュ計算不可の場合は上書き
  if [[ -z "$current_hash" ]]; then
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # カスタマイズされていない場合は上書き
  if [[ "$current_hash" == "$base_hash" ]]; then
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # カスタマイズされている場合: テンプレート変更を確認
  local template_hash
  template_hash=$(compute_hash "$template")
  if [[ "$template_hash" == "$base_hash" ]]; then
    # テンプレート未変更 → カスタム版を保持
    log_skip "${rel_path} はカスタマイズ済みでテンプレート未変更のためスキップ"
    return 0
  fi

  # 両方変更あり → 3-way マージ
  local base_snapshot
  base_snapshot=$(get_base_snapshot "$rel_path")

  if [[ -z "$base_snapshot" ]]; then
    log_merge "${rel_path} はカスタマイズ済みですが、ベーススナップショットがないため上書きします"
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # スナップショットの hash が lock の base_hash と一致するか検証
  local snapshot_hash
  snapshot_hash=$(compute_hash "$base_snapshot")
  if [[ -n "$snapshot_hash" && "$snapshot_hash" != "$base_hash" ]]; then
    log_merge "${rel_path} のベーススナップショットが base_hash と不一致のため上書きします"
    cp "$template" "$target"
    save_base_snapshot "$template" "$rel_path"
    return 0
  fi

  # git merge-file で 3-way マージ
  # git merge-file <current> <base> <other>
  # current = カスタム版、base = 前回テンプレート、other = 新テンプレート
  local tmp_current tmp_base tmp_other
  tmp_current=$(mktemp)
  tmp_base=$(mktemp)
  tmp_other=$(mktemp)

  # 異常終了（set -e による途中失敗を含む）時にも tmp ファイルを掃除するため EXIT も対象にする。
  # 親の EXIT trap（restore_original_ref など）を退避し、関数末尾で復元する。
  local prev_exit_trap
  prev_exit_trap=$(trap -p EXIT)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_current' '$tmp_base' '$tmp_other'" EXIT INT TERM

  cp "$target" "$tmp_current"
  cp "$base_snapshot" "$tmp_base"
  cp "$template" "$tmp_other"

  local merge_exit=0
  git merge-file \
    -L "カスタム版" \
    -L "前回テンプレート" \
    -L "新テンプレート" \
    "$tmp_current" "$tmp_base" "$tmp_other" 2>/dev/null || merge_exit=$?

  if [[ "$merge_exit" -eq 0 ]]; then
    # マージ成功（コンフリクトなし）
    cp "$tmp_current" "$target"
    save_base_snapshot "$template" "$rel_path"
    log_merge "${rel_path} を 3-way マージで自動解消しました"
  elif [[ "$merge_exit" -gt 0 ]]; then
    # コンフリクト発生
    cp "$tmp_current" "$target"
    save_base_snapshot "$template" "$rel_path"
    log_conflict "${rel_path} にコンフリクトが発生しました。手動で解消してください"
    CONFLICT_FILES="${CONFLICT_FILES}  - ${rel_path}"$'\n'
  fi

  rm -f "$tmp_current" "$tmp_base" "$tmp_other"
  # 元の EXIT trap を復元し、INT/TERM をクリア
  if [[ -n "$prev_exit_trap" ]]; then
    eval "$prev_exit_trap"
  else
    trap - EXIT
  fi
  trap - INT TERM

  if [[ "$merge_exit" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ── ステップ関数 ───────────────────────────────────────

parse_args() {
  PROJECT_NAME=""
  PRESET=""
  LANGUAGE=""
  TARGET_VERSION=""
  UPDATE_MODE=false
  PRESET_SPECIFIED=false
  LANGUAGE_SPECIFIED=false
  NO_MIGRATE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--name に値が必要です"; usage; }; PROJECT_NAME="$2"; shift 2 ;;
      --update)   UPDATE_MODE=true; shift ;;
      --preset)   [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--preset に値が必要です"; usage; }; PRESET="$2"; PRESET_SPECIFIED=true; shift 2 ;;
      --language) [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--language に値が必要です"; usage; }; LANGUAGE="$2"; LANGUAGE_SPECIFIED=true; shift 2 ;;
      --version)  [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--version に値が必要です"; usage; }; TARGET_VERSION="$2"; shift 2 ;;
      --no-migrate) NO_MIGRATE=true; shift ;;
      -h|--help)  usage 0 ;;
      *)          log_error "不明なオプション: $1"; usage ;;
    esac
  done

  if [[ "$UPDATE_MODE" == true && -n "$PROJECT_NAME" ]]; then
    log_error "--name と --update は同時に指定できません"
    usage
  fi

  if [[ "$UPDATE_MODE" == false && -z "$PROJECT_NAME" ]]; then
    log_error "--name は必須です"
    usage
  fi

  # --version のバリデーション（v付きのセマンティックバージョニング形式）
  if [[ -n "$TARGET_VERSION" ]]; then
    if [[ ! "$TARGET_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log_error "--version はセマンティックバージョニング形式で指定してください（例: v1.0.0）"
      exit 1
    fi
  fi

  # デフォルト値の設定（--update 時は read_vibecorp_yml で上書きされる）
  if [[ -z "$PRESET" ]]; then PRESET="minimal"; fi
  if [[ -z "$LANGUAGE" ]]; then LANGUAGE="ja"; fi
}

validate_name() {
  if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,48}[A-Za-z0-9]$ ]] && [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9]$ ]]; then
    log_error "プロジェクト名が不正です（英数字とハイフンのみ、1-50文字）"
    exit 1
  fi
}

validate_preset() {
  case "$PRESET" in
    minimal|standard|full) ;;
    *)
      log_error "--preset は minimal, standard, full のいずれかを指定してください"
      exit 1
      ;;
  esac
}

validate_language() {
  # sed 区切り文字やシェル特殊文字を含む値を拒否（英数字、ハイフン、アンダースコアのみ許可）
  if [[ ! "$LANGUAGE" =~ ^[A-Za-z0-9_-]+$ ]]; then
    log_error "言語コードが不正です（英数字、ハイフン、アンダースコアのみ）"
    exit 1
  fi
}

# uname -s の出力から OS 種別を返す純粋関数（副作用なし）
detect_os() {
  local kernel
  kernel=$(uname -s)
  case "$kernel" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)      echo "unknown" ;;
  esac
}

# サポート外 OS の場合に exit 2（Windows ネイティブ・FreeBSD 等）
check_unsupported_os() {
  case "$OS" in
    windows)
      log_error "Windows ネイティブは非対応です。WSL2 を使用してください。"
      log_error "詳細: docs/design-philosophy.md#os-support"
      exit 2
      ;;
    unknown)
      log_error "サポート外の OS です（$(uname -s)）。macOS または Linux を使用してください。"
      log_error "詳細: docs/design-philosophy.md#os-support"
      exit 2
      ;;
  esac
}

# 隔離レイヤの依存を確認する（full プリセット時のみ呼ばれる）
# Darwin は sandbox-exec、Linux は bwrap の存在を検証する
# 不在時は distro に応じたインストール手順を表示して exit 1 する
check_isolation_deps() {
  # 隔離レイヤは full プリセット専用。minimal / standard では依存チェック不要
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi
  case "$OS" in
    darwin)
      if ! command -v sandbox-exec >/dev/null 2>&1; then
        log_error "sandbox-exec が見つかりません。インストールを中断します。"
        exit 1
      fi
      ;;
    linux)
      if ! command -v bwrap >/dev/null 2>&1; then
        log_error "bwrap (bubblewrap) が見つかりません。隔離レイヤには bwrap が必要です。"
        local os_release_path distro_id distro_id_like
        # VIBECORP_OS_RELEASE_PATH はテスト時に /etc/os-release を差し替えるための環境変数。
        # awk フィルタが ID / ID_LIKE 行のみを抽出し、結果は case パターンマッチでメッセージ選択にしか使われないため、任意パス指定による情報漏洩経路は成立しない
        os_release_path="${VIBECORP_OS_RELEASE_PATH:-/etc/os-release}"
        distro_id=""
        distro_id_like=""
        if [[ -r "$os_release_path" ]]; then
          distro_id=$(awk -F= '$1=="ID"{gsub(/"/,"",$2); print $2}' "$os_release_path")
          distro_id_like=$(awk -F= '$1=="ID_LIKE"{gsub(/"/,"",$2); print $2}' "$os_release_path")
        fi
        case " ${distro_id} ${distro_id_like} " in
          *" ubuntu "*|*" debian "*)
            log_error "  Debian/Ubuntu: sudo apt-get install bubblewrap"
            ;;
          *" fedora "*|*" rhel "*|*" centos "*)
            log_error "  Fedora/RHEL: sudo dnf install bubblewrap"
            ;;
          *" alpine "*)
            log_error "  Alpine: sudo apk add bubblewrap"
            ;;
          *)
            log_error "  Debian/Ubuntu: sudo apt-get install bubblewrap"
            log_error "  Fedora/RHEL:   sudo dnf install bubblewrap"
            log_error "  Alpine:        sudo apk add bubblewrap"
            ;;
        esac
        exit 1
      fi
      ;;
  esac
}

check_prerequisites() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq が必要です。インストール: brew install jq"
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    log_error "git が必要です"
    exit 1
  fi
}

detect_repo_root() {
  if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    log_error "git リポジトリ内で実行してください"
    exit 1
  fi
}

read_vibecorp_yml() {
  # vibecorp.yml からプロジェクト設定を読み取る（--update モード用）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ ! -f "$yml" ]]; then
    log_error "vibecorp.yml が見つかりません。初回は --name でインストールしてください"
    exit 1
  fi

  # awk でトップレベルキーの値を抽出
  PROJECT_NAME=$(awk '/^name:/ { print $2 }' "$yml")
  local yml_preset
  yml_preset=$(awk '/^preset:/ { print $2 }' "$yml")
  local yml_language
  yml_language=$(awk '/^language:/ { print $2 }' "$yml")

  # --preset 未指定なら yml の値を使う
  if [[ "$PRESET_SPECIFIED" == false ]]; then
    PRESET="${yml_preset:-minimal}"
  fi
  # --language 未指定なら yml の値を使う
  if [[ "$LANGUAGE_SPECIFIED" == false ]]; then
    LANGUAGE="${yml_language:-ja}"
  fi

  if [[ -z "$PROJECT_NAME" ]]; then
    log_error "vibecorp.yml に name が定義されていません"
    exit 1
  fi

  log_info "vibecorp.yml から設定を読み取り (name: ${PROJECT_NAME}, preset: ${PRESET})"
}

update_vibecorp_yml() {
  # --update + --preset 指定時に vibecorp.yml の preset を更新
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  [[ "$PRESET_SPECIFIED" == true ]] || return 0
  [[ -f "$yml" ]] || return 0

  local current_preset
  current_preset=$(awk '/^preset:/ { print $2 }' "$yml")

  if [[ "$current_preset" != "$PRESET" ]]; then
    sed "s|^preset: .*|preset: ${PRESET}|" "$yml" > "${yml}.tmp" && mv "${yml}.tmp" "$yml"
    log_info "vibecorp.yml の preset を更新: ${current_preset} → ${PRESET}"
  fi
}

migrate_forbidden_targets_skills() {
  # --update 時のセキュリティ移行: 既存 vibecorp.yml の diagnose.forbidden_targets に
  # skills/** が無ければ自動追加する（Issue #460 / CodeRabbit 指摘）。
  #
  # 仕様根拠: Issue #460 — `.claude/skills/` を自律ループの保護対象に昇格。
  # 既存ユーザーは vibecorp.yml に独自 forbidden_targets を持つため、hook デフォルト変更だけでは
  # 防御が届かない。--update 実行時にここで一度だけ補完する（冪等）。
  # bash 3.2 互換、`sed -i` 禁止（mktemp + mv で原子的置換）。
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  [[ -f "$yml" ]] || return 0

  # diagnose.forbidden_targets セクションに skills/** が既にあるかチェック
  local found
  found=$(awk '
    /^diagnose:/ { in_diagnose = 1; next }
    in_diagnose && /^[^ #]/ { exit }
    in_diagnose && /^  forbidden_targets:/ { in_targets = 1; next }
    in_diagnose && in_targets && /^  [^ -]/ { exit }
    in_diagnose && in_targets && /^    - / {
      sub(/^    - /, "")
      sub(/[[:space:]]*$/, "")
      gsub(/"/, "")
      gsub(/'\''/, "")
      if ($0 == "skills/**") { print "yes"; exit }
    }
  ' "$yml")

  if [[ "$found" == "yes" ]]; then
    return 0
  fi

  # forbidden_targets セクション自体が存在するかチェック（diagnose セクション内）
  local has_targets
  has_targets=$(awk '
    /^diagnose:/ { in_diagnose = 1; next }
    in_diagnose && /^[^ #]/ { exit }
    in_diagnose && /^  forbidden_targets:/ { print "yes"; exit }
  ' "$yml")

  if [[ "$has_targets" != "yes" ]]; then
    # forbidden_targets セクション自体が無い場合は安全のため触らない（利用者が意図的に削除した可能性）
    return 0
  fi

  # forbidden_targets: 行の直後に skills/** エントリを挿入
  # inline 空配列形式（`forbidden_targets: []`）の場合は block 形式に正規化してから挿入する
  # （挿入しただけだと `[]` の後に block エントリが続いて YAML が壊れる）。
  local tmp
  tmp="$(mktemp "$(dirname "$yml")/.${yml##*/}.XXXXXX")"
  awk '
    BEGIN { in_diagnose = 0; inserted = 0 }
    {
      # inline 空配列を検出したら block 形式に正規化して skills/** を 1 件目として挿入
      if (!inserted && in_diagnose && /^  forbidden_targets:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
        print "  forbidden_targets:"
        print "    - \"skills/**\""
        inserted = 1
        next
      }
      print
      if (!inserted && in_diagnose && /^  forbidden_targets:/) {
        print "    - \"skills/**\""
        inserted = 1
      }
      if (/^diagnose:/) in_diagnose = 1
      else if (in_diagnose && /^[^ #]/) in_diagnose = 0
    }
  ' "$yml" > "$tmp" && mv "$tmp" "$yml"

  log_info "vibecorp.yml の diagnose.forbidden_targets に skills/** を追加（Issue #460 セキュリティ移行）"
}

read_lock_list() {
  # lock ファイルから指定セクションのファイル一覧を取得
  # 使い方: read_lock_list <lock_file> <section_name>
  # awk でブロック単位に抽出（grep -A N はセクション境界を越えるため使わない）
  local lock_file="$1"
  local section="$2"

  [[ -f "$lock_file" ]] || return 0

  awk -v section="$section" '
    /^  [a-z_]+:/ {
      current = $1
      gsub(/:$/, "", current)
      next
    }
    current == section && /^    - / {
      sub(/^    - /, "")
      print
    }
  ' "$lock_file"
}

# 機能: plugin native 配布以前の旧レイアウト残滓を --update 時に物理削除する（Issue #708）
# - .claude/vibecorp-base/hooks/ と .claude/vibecorp-base/lib/ は #710 以前の 3-way マージ基準スナップショット
#   plugin native 配布化後は不要だが、過去の利用者リポジトリには残り続けるため明示的に migration する
migrate_legacy_layout() {
  [[ "$UPDATE_MODE" == true ]] || return 0

  local removed=0
  local base_hooks="${REPO_ROOT}/.claude/vibecorp-base/hooks"
  local base_lib="${REPO_ROOT}/.claude/vibecorp-base/lib"
  local legacy_hooks="${REPO_ROOT}/.claude/hooks"
  local legacy_lib="${REPO_ROOT}/.claude/lib"

  if [[ -d "$base_hooks" ]]; then
    rm -rf "$base_hooks"
    log_info "migration: 旧 .claude/vibecorp-base/hooks/ を削除"
    removed=1
  fi
  if [[ -d "$base_lib" ]]; then
    rm -rf "$base_lib"
    log_info "migration: 旧 .claude/vibecorp-base/lib/ を削除"
    removed=1
  fi

  # vibecorp-base/ 全体が空になったら ディレクトリも削除（rmdir は中身があれば失敗 = 安全）
  if [[ -d "${REPO_ROOT}/.claude/vibecorp-base" ]]; then
    rmdir "${REPO_ROOT}/.claude/vibecorp-base" 2>/dev/null || true
  fi

  # 機能: 旧 .claude/hooks/ / .claude/lib/ 配下の vibecorp 配布物を物理削除（Issue #708 完了条件 [1]）
  # plugin native 配布 (#716) で hooks / lib は ${CLAUDE_PLUGIN_ROOT}/hooks/ + ${CLAUDE_PLUGIN_ROOT}/lib/
  # に一元化されたため、.claude/hooks/ / .claude/lib/ 配下の vibecorp 配布物は不要。
  # ユーザー独自フックは .claude/settings.local.json の hooks ブロックで追加する運用に統一する
  # （CISO 必須対策③、docs/SECURITY.md 参照）。
  # 安全側に倒すため、vibecorp 配布物として既知の basename のみを削除し、未知ファイルは保持する。
  local vibecorp_hook_basenames=(
    block-api-bypass.sh
    command-log.sh
    diagnose-guard.sh
    guide-gate.sh
    protect-branch.sh
    protect-files.sh
    protect-knowledge-bash-writes.sh
    protect-knowledge-direct-writes.sh
    review-gate.sh
    role-gate.sh
    sync-gate.sh
    session-harvest-gate.sh
  )
  local vibecorp_lib_basenames=(
    common.sh
    knowledge_buffer.sh
    path_normalize.sh
    zombie_agent.sh
  )

  # vibecorp 管理判定: 旧 lock (v1 形式 hooks: / lib: セクション) に basename が記載されていれば確定。
  # 記載がない場合は content cmp で「現行配布と同一」のみ削除（同名ユーザーフック保護）。
  # CR PR #731 Major #5 v2 対応: 旧 consumer が前バージョンの managed ファイルを持っていても
  # lock 記載なら vibecorp 管理として削除する。
  local lock_file="${REPO_ROOT}/.claude/vibecorp.lock"
  local lock_hooks="" lock_libs=""
  if [[ -f "$lock_file" ]]; then
    lock_hooks="$(read_lock_list "$lock_file" hooks 2>/dev/null || true)"
    lock_libs="$(read_lock_list "$lock_file" lib 2>/dev/null || true)"
  fi

  if [[ -d "$legacy_hooks" ]]; then
    local removed_legacy_hook=0
    local hook_basename plugin_hook legacy_hook
    for hook_basename in "${vibecorp_hook_basenames[@]}"; do
      legacy_hook="${legacy_hooks}/${hook_basename}"
      [[ -f "$legacy_hook" ]] || continue
      # 判定 A: lock に記載があれば vibecorp 管理確定 → 削除
      if [[ -n "$lock_hooks" ]] && printf '%s\n' "$lock_hooks" | grep -Fxq "$hook_basename"; then
        rm -f "$legacy_hook"
        removed_legacy_hook=1
        continue
      fi
      # 判定 B: lock に記載なし → content 一致のみ削除（同名ユーザーフック保護）
      plugin_hook="${SCRIPT_DIR}/hooks/${hook_basename}"
      if [[ -f "$plugin_hook" ]] && cmp -s "$legacy_hook" "$plugin_hook"; then
        rm -f "$legacy_hook"
        removed_legacy_hook=1
      fi
    done
    if [[ $removed_legacy_hook -eq 1 ]]; then
      log_info "migration: 旧 .claude/hooks/ から vibecorp 配布フックを削除（lock + content 判定）"
      removed=1
    fi
    rmdir "$legacy_hooks" 2>/dev/null || true
  fi

  if [[ -d "$legacy_lib" ]]; then
    local removed_legacy_lib=0
    local lib_basename plugin_lib legacy_lib_file
    for lib_basename in "${vibecorp_lib_basenames[@]}"; do
      legacy_lib_file="${legacy_lib}/${lib_basename}"
      [[ -f "$legacy_lib_file" ]] || continue
      if [[ -n "$lock_libs" ]] && printf '%s\n' "$lock_libs" | grep -Fxq "$lib_basename"; then
        rm -f "$legacy_lib_file"
        removed_legacy_lib=1
        continue
      fi
      plugin_lib="${SCRIPT_DIR}/lib/${lib_basename}"
      if [[ -f "$plugin_lib" ]] && cmp -s "$legacy_lib_file" "$plugin_lib"; then
        rm -f "$legacy_lib_file"
        removed_legacy_lib=1
      fi
    done
    if [[ $removed_legacy_lib -eq 1 ]]; then
      log_info "migration: 旧 .claude/lib/ から vibecorp 配布 lib を削除（lock + content 判定）"
      removed=1
    fi
    rmdir "$legacy_lib" 2>/dev/null || true
  fi

  # 機能: 既存 .claude/settings.json から hooks ブロックを物理除去（Issue #721）
  # plugin native 配布 (#716) 後は plugin/hooks/hooks.json が唯一の登録元。settings.json 側に
  # 古い hooks ブロックが残っていると hook が二重発火する可能性があるため migration する。
  # CR PR #731 Major #4 v2 / Major #6 v3 対応:
  # 1) settings.json から vibecorp 由来 hooks のみ抽出して除去
  # 2) custom hooks は settings.local.json の hooks へ移送 (CISO 責務分離要件、SECURITY.md 規定)
  # 3) settings.json から hooks ブロックを完全削除 (plugin native 統一)
  local settings_json="${REPO_ROOT}/.claude/settings.json"
  local settings_local_json="${REPO_ROOT}/.claude/settings.local.json"
  # self-install で settings.json が SSOT (templates/claude/settings.json) への symlink の場合は
  # migration を行わない (Issue #759)。SSOT は plugin native 配布で hooks ブロックを持たず、
  # symlink 経由で del(.hooks) すると mv が symlink を実体に detach し SSOT 接続が切れるため、
  # symlink を明示除外して暗黙依存を防御に格上げする（#748 の symlink 先書き換え防止と同型）。
  if [[ ! -L "$settings_json" ]] && [[ -f "$settings_json" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.hooks' "$settings_json" >/dev/null 2>&1; then
      local vibecorp_hooks_json
      vibecorp_hooks_json="$(printf '%s\n' "${vibecorp_hook_basenames[@]}" | jq -R . | jq -s .)"

      # custom hooks を抽出 (vibecorp 由来でない hook エントリのみ残した hooks サブツリー)
      # CR PR #731 Major #8 v4 対応: contains() 部分一致は ".sh-wrapper" のような同名衝突を誤判定する。
      # ファイル名境界 (前: 行頭|スペース|/、後: スペース|行末|引用符) を含む正規表現で厳密判定する。
      local custom_hooks
      custom_hooks="$(jq --argjson vibehooks "$vibecorp_hooks_json" '
        def is_vibecorp_legacy_hook($cmd):
          $vibehooks | any(. as $h |
            $cmd | test("(^|[[:space:]\"\u0027`(/])\\.claude/hooks/" + ($h | gsub("\\."; "\\.")) + "([[:space:]\"\u0027`)]|$)")
          );
        (.hooks // {}) | with_entries(
          .value |= map(
            .hooks |= map(
              select((.command // "") as $cmd
                | (is_vibecorp_legacy_hook($cmd)) | not)
            )
            | select((.hooks // []) | length > 0)
          )
          | select((.value | length) > 0)
        )
      ' "$settings_json")"

      # custom hooks が存在すれば settings.local.json にマージ
      if [[ "$(printf '%s' "$custom_hooks" | jq 'length')" -gt 0 ]]; then
        local tmp_local
        tmp_local="$(mktemp "$(dirname "$settings_json")/.settings.local.json.XXXXXX")"
        if [[ -f "$settings_local_json" ]]; then
          # 既存 settings.local.json の hooks に追記マージ (同名 event の hooks 配列を連結)
          jq --argjson new "$custom_hooks" '
            .hooks = ((.hooks // {}) as $old
              | reduce ($new | to_entries[]) as $entry ($old;
                  .[$entry.key] = ((.[$entry.key] // []) + $entry.value)
                )
            )
          ' "$settings_local_json" > "$tmp_local" && mv "$tmp_local" "$settings_local_json"
        else
          # 新規作成
          jq -n --argjson custom "$custom_hooks" '{hooks: $custom}' > "$tmp_local" && mv "$tmp_local" "$settings_local_json"
        fi
        log_info "migration: settings.json の custom hook を settings.local.json へ移送（CISO 責務分離）"
      fi

      # settings.json から hooks ブロックを完全削除
      local tmp_settings
      tmp_settings="$(mktemp "$(dirname "$settings_json")/.settings.json.XXXXXX")"
      if jq 'del(.hooks)' "$settings_json" > "$tmp_settings"; then
        if ! cmp -s "$settings_json" "$tmp_settings"; then
          mv "$tmp_settings" "$settings_json"
          log_info "migration: .claude/settings.json から hooks ブロックを完全削除（plugin native 統一）"
          removed=1
        else
          rm -f "$tmp_settings"
        fi
      else
        rm -f "$tmp_settings"
      fi
    fi
  fi

  # 旧 .claude/agents/ 配下の vibecorp 配布物清掃は remove_managed_files() に移動済み
  # （Issue #735 完了条件: --update 限定ガードを外して --name 経路でも清掃される）

  [[ $removed -eq 0 ]] || log_info "Issue #708 / #721 / #735: plugin native 移行に伴う旧レイアウト migration 完了"
}

remove_managed_files() {
  # lock に記載された vibecorp 管理ファイルを削除
  # --update 時は skills を 3-way マージ対象として保持する
  # hooks は plugin native 配布 (#716) に移行済のため install.sh は配置・削除を行わない
  # agents は plugin native 配布 (#737 / #735) に移行済のため install.sh は配置しないが、
  # 旧バージョンが配置した .claude/agents/ を消し残さないため lock 記載分の削除は両経路で行う
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local skills_dir="${REPO_ROOT}/.claude/skills"
  local agents_dir="${REPO_ROOT}/.claude/agents"

  [[ -f "$lock" ]] || return 0

  if [[ "$UPDATE_MODE" != true ]]; then
    # 再インストール（--name）時は管理ファイルを削除して再配置
    while IFS= read -r name; do
      [[ -n "$name" ]] && rm -rf "${skills_dir:?}/${name:?}"
    done < <(read_lock_list "$lock" "skills")
  fi
  # --update 時は skills を削除しない（merge_or_overwrite で処理）

  # 旧 vibecorp 配布 agents を物理削除（Issue #735 完了条件、両経路で実行）
  # plugin native 配布 (#737) で agents は ${CLAUDE_PLUGIN_ROOT}/agents/ に一元化されたため、
  # ユーザーリポジトリの .claude/agents/ 配下に残った旧版 vibecorp 配布 agent を清掃する。
  # 判定 A: lock 記載があれば vibecorp 管理確定 → 削除（ユーザー独自 agent は lock 未記載のため保護される）
  # 判定 B: lock が v3 形式（agents セクション無し）等で記載が無い場合は、
  #         現行プラグイン配布物と content 一致する旧 managed agent のみ削除する
  #         （hooks migration #716 と同じパターン、同名ユーザー agent 保護）
  if [[ -d "$agents_dir" ]]; then
    local lock_agents_found=0
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      [[ "$name" =~ ^[A-Za-z0-9._-]+\.md$ ]] || continue
      lock_agents_found=1
      rm -f "${agents_dir}/${name}"
    done < <(read_lock_list "$lock" "agents")

    # 判定 B フォールバック: v3 lock 等で agents セクション不在の場合、
    # 現行プラグイン配布物と content 一致する旧 managed agent のみ削除する
    if [[ "$lock_agents_found" -eq 0 ]]; then
      local plugin_agent agent_basename legacy_agent
      for plugin_agent in "${SCRIPT_DIR}/agents/"*.md; do
        [[ -f "$plugin_agent" ]] || continue
        agent_basename="$(basename "$plugin_agent")"
        legacy_agent="${agents_dir}/${agent_basename}"
        if [[ -f "$legacy_agent" ]] && cmp -s "$legacy_agent" "$plugin_agent"; then
          rm -f "$legacy_agent"
        fi
      done
    fi

    # agents/ が空になったら rmdir（中身があれば失敗 = ユーザー独自 agent は安全に保護される）
    rmdir "$agents_dir" 2>/dev/null || true
  fi

  # knowledge は運用中にユーザーが蓄積するデータのため削除しない

  log_info "管理ファイルを整理（lock ベース）"
}

copy_managed_files() {
  # テンプレートをコピー（既存ユーザーファイルはスキップ）
  # hooks は plugin native 配布 (#716) に移行済のため install.sh は配置しない
  # agents は plugin native 配布 (#737 / #735) に移行済のため install.sh は配置しない
  # .claude/ ディレクトリ自体は他の生成処理（vibecorp.yml / settings.json / lock 等）の前提として
  # 必ず作成する。以前は agents/skills の mkdir が暗黙に作成していたが、両者の plugin native 移行で
  # 明示的な mkdir が必要になった。
  mkdir -p "${REPO_ROOT}/.claude"
  local skills_dir="${REPO_ROOT}/.claude/skills"

  # --update: plugin skills マイグレーション（プラグインキャッシュに移行済み）
  if [[ "$UPDATE_MODE" == true ]]; then
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    if [[ -f "$lock" ]]; then
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
        if [[ -d "${REPO_ROOT}/skills/${name}" ]]; then
          rm -rf "${REPO_ROOT:?}/skills/${name:?}"
          log_info "skills/${name} をプラグインキャッシュに移行（ローカルコピーを削除）"
        fi
        if [[ -d "${skills_dir:?}/${name:?}" ]]; then
          rm -rf "${skills_dir:?}/${name:?}"
          log_info ".claude/skills/${name} 互換スタブを削除"
        fi
      done < <(read_lock_list "$lock" "plugin_skills")
      if [[ -d "${REPO_ROOT}/skills" ]] && [[ -z "$(ls -A "${REPO_ROOT}/skills" 2>/dev/null)" ]]; then
        rmdir "${REPO_ROOT}/skills"
        log_info "skills/ を削除（空）"
      fi
      if [[ -d "$skills_dir" ]] && [[ -z "$(ls -A "$skills_dir" 2>/dev/null)" ]]; then
        rmdir "$skills_dir"
        log_info ".claude/skills/ を削除（空）"
      fi
    fi
  fi

  # agents は plugin native 配布 (#737 / #735) で plugin/agents/ に一元化されたため、
  # install.sh は配置しない。利用先プロジェクトの Claude Code が plugin cache 経由で自動検出する。

  # .claude-plugin/plugin.json は利用者 repo に配布しない (Issue #764)。
  # プラグイン消費側は ~/.claude/plugins/cache/ から読むため利用者 repo にマニフェストは不要。
  # #700/#737/#744 の plugin native 化で利用者 repo にプラグイン実体が無くなったため、
  # マニフェストだけ置いても指す相手がいない。vibecorp 自身の .claude-plugin/plugin.json は
  # 開発元の必須マニフェスト (SoT) として git 管理下で保持される。

  # プレースホルダー置換
  # macOS 互換: sed ... > tmp && mv tmp original（sed -i の BSD/GNU 差異を回避）
  # bash 3.2 + set -u: ${arr[@]} は空配列で「unbound variable」となるため、
  # ${arr[@]+"${arr[@]}"} 形式で安全に展開する。
  local target_dirs=()
  [[ -d "$skills_dir" ]] && target_dirs+=("$skills_dir")
  local placeholder_errors=0
  for dir in ${target_dirs[@]+"${target_dirs[@]}"}; do
    while IFS= read -r f; do
      # vibecorp が管理する 3 つのプレースホルダーのみを対象にする
      # （docker inspect の {{.State.Status}} 等、テンプレート構文を含む正当なコンテンツを誤検知しないため）
      if grep -q '{{PROJECT_NAME}}\|{{PRESET}}\|{{LANGUAGE}}' "$f" 2>/dev/null; then
        local tmp
        tmp="$(mktemp "$(dirname "$f")/.${f##*/}.XXXXXX")"
        if sed \
          -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
          -e "s|{{PRESET}}|${PRESET}|g" \
          -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
          "$f" > "$tmp"; then
          mv "$tmp" "$f"
        else
          log_error "プレースホルダー置換に失敗しました: $f"
          rm -f "$tmp"
          placeholder_errors=$((placeholder_errors + 1))
        fi
        # 置換後も vibecorp プレースホルダーが残っていないか検証
        if grep -q '{{PROJECT_NAME}}\|{{PRESET}}\|{{LANGUAGE}}' "$f" 2>/dev/null; then
          log_error "未解決のプレースホルダーが残っています: $f"
          placeholder_errors=$((placeholder_errors + 1))
        fi
      fi
    done < <(find "$dir" -type f \( -name '*.sh' -o -name '*.md' \))
  done
  if [[ "$placeholder_errors" -gt 0 ]]; then
    log_error "プレースホルダー置換で ${placeholder_errors} 件のエラーが発生しました"
    return 1
  fi

  # 全プリセット共通レガシー clean-up: 廃止済みスキル・フックを除去（#343 spike-loop 等）
  rm -rf "${skills_dir}/spike-loop"

  # プリセット別削除（引き算方式）
  # hooks 自体は plugin native 配布 (#716) に移行済のため、ここでの hooks ファイル削除は不要
  case "$PRESET" in
    minimal)
      # レガシー clean-up: 旧バージョンのインストールが残した古いスキル
      rm -rf "${skills_dir}/review-to-rules"
      # 現行: minimal プリセットから除外するスキル
      rm -rf "${skills_dir}/sync-check"
      rm -rf "${skills_dir}/sync-edit"
      rm -rf "${skills_dir}/session-harvest"
      rm -rf "${skills_dir}/harvest-all"
      rm -rf "${skills_dir}/review-harvest"
      rm -rf "${skills_dir}/knowledge-pr"
      rm -rf "${skills_dir}/diagnose"
      rm -rf "${skills_dir}/context7"
      # ヘッドレス並列スキルは full プリセット専用（隔離レイヤが full でしか効かないため）
      rm -rf "${skills_dir}/ship-parallel"
      rm -rf "${skills_dir}/autopilot"
      # エピック化スキルは full プリセット専用（3 者承認ゲートで CISO/CPO/SM が必須なため）
      rm -rf "${skills_dir}/plan-epic"
      # エピックリリーススキルは full プリセット専用（エピック運用は full でのみ整備）
      rm -rf "${skills_dir}/release-epic"
      # agents は plugin native 配布 (#737 / #735) のため install.sh は削除しない。
      # minimal/standard プリセットでの agent 呼出ゲートは vibecorp.yml の
      # plan.review_agents 設定で行われており、plugin cache に存在しても呼ばれない。
      # 隔離レイヤは full 専用。vibecorp が配置した既知ファイルのみ削除し、
      # ディレクトリが空になったら rmdir（ユーザー独自配置は rmdir 失敗で保持される）
      rm -f "${REPO_ROOT}/.claude/bin/claude"
      rm -f "${REPO_ROOT}/.claude/bin/claude-real"
      rm -f "${REPO_ROOT}/.claude/bin/vibecorp-sandbox"
      rm -f "${REPO_ROOT}/.claude/bin/activate.sh"
      # macOS / Linux 両 OS の sandbox ファイルを削除（インストール時の OS と
      # ダウングレード時の OS が異なる可能性に備える）
      rm -f "${REPO_ROOT}/.claude/sandbox/claude.sb"
      rm -f "${REPO_ROOT}/.claude/sandbox/bwrap-args.sh"
      rmdir "${REPO_ROOT}/.claude/bin" 2>/dev/null || true
      rmdir "${REPO_ROOT}/.claude/sandbox" 2>/dev/null || true
      ;;
    standard)
      rm -rf "${skills_dir}/diagnose"
      # ヘッドレス並列スキルは full プリセット専用（隔離レイヤが full でしか効かないため）
      rm -rf "${skills_dir}/ship-parallel"
      rm -rf "${skills_dir}/autopilot"
      # エピック化スキルは full プリセット専用（3 者承認ゲートで CISO/CPO/SM が必須なため）
      rm -rf "${skills_dir}/plan-epic"
      # エピックリリーススキルは full プリセット専用（エピック運用は full でのみ整備）
      rm -rf "${skills_dir}/release-epic"
      # plan-cost / plan-legal は full プリセット限定だが、agents は plugin native 配布 (#737 / #735)
      # に移行済のため install.sh は削除しない。呼出ゲートは vibecorp.yml の plan.review_agents が
      # standard デフォルト [architect, security, testing] で plan-cost / plan-legal を呼ばないことで担保される。
      # 隔離レイヤは full 専用。vibecorp が配置した既知ファイルのみ削除し、
      # ディレクトリが空になったら rmdir（ユーザー独自配置は rmdir 失敗で保持される）
      rm -f "${REPO_ROOT}/.claude/bin/claude"
      rm -f "${REPO_ROOT}/.claude/bin/claude-real"
      rm -f "${REPO_ROOT}/.claude/bin/vibecorp-sandbox"
      rm -f "${REPO_ROOT}/.claude/bin/activate.sh"
      # macOS / Linux 両 OS の sandbox ファイルを削除（インストール時の OS と
      # ダウングレード時の OS が異なる可能性に備える）
      rm -f "${REPO_ROOT}/.claude/sandbox/claude.sb"
      rm -f "${REPO_ROOT}/.claude/sandbox/bwrap-args.sh"
      rmdir "${REPO_ROOT}/.claude/bin" 2>/dev/null || true
      rmdir "${REPO_ROOT}/.claude/sandbox" 2>/dev/null || true
      ;;
  esac

  log_info "テンプレートをコピー (preset: ${PRESET})"
}

# 隔離レイヤ（bin/sandbox）を配置する。full プリセット専用。
# OS 別の sandbox 実装を明示的にコピーする:
#   - Darwin: claude.sb (sandbox-exec プロファイル)
#   - Linux:  bwrap-args.sh (bwrap 引数生成スクリプト)
# 逆クロス配置（macOS に bwrap-args.sh / Linux に claude.sb）を防ぐため、
# templates/claude/sandbox/ 配下を glob ではなく OS 別ファイル名で明示的にコピーする。
copy_isolation_templates() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi
  case "$OS" in
    darwin|linux) ;;
    *) return 0 ;;  # 未対応 OS は隔離レイヤを配置しない
  esac

  local bin_dir="${REPO_ROOT}/.claude/bin"
  local sandbox_dir="${REPO_ROOT}/.claude/sandbox"
  mkdir -p "$bin_dir" "$sandbox_dir"

  # bin/ 配下は両 OS 共通（claude / vibecorp-sandbox / activate.sh）。
  # bin/ は汎用機構で vibecorp 固有に成長しないため symlink SSOT 化する (Issue #760)。
  # self-install（dogfooding）は templates/claude/bin/ へのファイル単位 symlink で SSOT を直結し、
  # user-install（配布先）は実体コピーで上書きする（symlink は配布しない、#748 と同型）。
  # claude-real（マシン固有 symlink）は setup_claude_real_symlink が別途実体配置するため本ループ対象外。
  # self/user 判定は bin/ と sandbox/ の両方で共有する（Issue #760 / #761）。
  local isolation_self_install=false
  if [[ "$(_canonical_dir "$SCRIPT_DIR")" == "$(_canonical_dir "$REPO_ROOT")" ]]; then
    isolation_self_install=true
  fi

  local src
  for src in "${SCRIPT_DIR}/templates/claude/bin/"*; do
    # symlink はサプライチェーン侵害時の任意ファイル配置経路になるため明示除外する
    [[ -f "$src" && ! -L "$src" ]] || continue
    local name
    name=$(basename "$src")
    if [[ "$isolation_self_install" == true ]]; then
      # self-install: .claude/bin/<name> → ../../templates/claude/bin/<name> の相対 symlink を貼り直す。
      # ラッパー（claude / vibecorp-sandbox）は自己位置を cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
      # （readlink -f を使わない）で解決するため、symlink 経由でも SCRIPT_DIR は .claude/bin に解決され、
      # 隣接の vibecorp-sandbox や ../sandbox/claude.sb を正しく辿る（挙動不変の前提）。
      ln -sfn "../../templates/claude/bin/${name}" "${bin_dir}/${name}"
    else
      # user-install: symlink 経由でリンク先実体を書き換えないよう除去してから実体コピー（#748）
      if [[ -L "${bin_dir}/${name}" ]]; then
        rm -f "${bin_dir}/${name}"
      fi
      cp "$src" "${bin_dir}/${name}"
      chmod +x "${bin_dir}/${name}"
    fi
    log_info "隔離レイヤを配置: .claude/bin/${name}"
  done

  # sandbox/ 配下は OS 別ファイル名（darwin=claude.sb / linux=bwrap-args.sh）で配置する (Issue #761)。
  # symlink SSOT 化できるかは「ファイルがどう使われるか」で決まる:
  #   - claude.sb（macOS）  : sandbox-exec が -f で読むだけのデータ → self-install で symlink SSOT 化できる
  #   - bwrap-args.sh（Linux）: vibecorp-sandbox が source 実行するコード → symlink にすると
  #       任意コード実行経路になり、vibecorp-sandbox の Link Following 拒否ガード（#310）が
  #       fail-closed で隔離起動を拒否する。よって self-install でも必ず実体コピーで配置する。
  # user-install は OS 該当ファイルを常に実体コピーする（symlink は配布しない、#748 と同型）。
  local sandbox_file=""
  case "$OS" in
    darwin) sandbox_file="claude.sb" ;;
    linux)  sandbox_file="bwrap-args.sh" ;;
  esac

  local sandbox_src="${SCRIPT_DIR}/templates/claude/sandbox/${sandbox_file}"
  if [[ -f "$sandbox_src" && ! -L "$sandbox_src" ]]; then
    if [[ "$isolation_self_install" == true && "$OS" == "darwin" ]]; then
      # self-install + macOS: 読むだけのプロファイル claude.sb を SSOT への相対 symlink で直結
      ln -sfn "../../templates/claude/sandbox/${sandbox_file}" "${sandbox_dir}/${sandbox_file}"
    else
      # user-install、または source 実行される bwrap-args.sh（Linux self-install 含む）: 実体コピー。
      # symlink 経由でリンク先実体を書き換えないよう、コピー前に既存 symlink を除去する（#748）。
      if [[ -L "${sandbox_dir}/${sandbox_file}" ]]; then
        rm -f "${sandbox_dir}/${sandbox_file}"
      fi
      cp "$sandbox_src" "${sandbox_dir}/${sandbox_file}"
    fi
    log_info "隔離レイヤを配置: .claude/sandbox/${sandbox_file}"
  else
    log_error "sandbox ファイルが見つかりません: ${sandbox_src}"
    exit 1
  fi
}

# ゲートスタンプ・state・plans の保存先 ~/.cache/vibecorp/ を事前作成する (#326, #334)。
# sandbox-exec 内では ~/.cache/ の親ディレクトリ作成が拒否されるため、
# install.sh（sandbox 外で実行）が一度作っておくことで、
# sandbox 内の gate hook は subpath 配下の create のみで済む。
#
# templates/claude/lib/common.sh の vibecorp_stamp_dir() / vibecorp_plans_dir() と
# XDG 解決規則を一致させる:
# - XDG_CACHE_HOME は絶対パスのみ有効（XDG 仕様）。相対値は $HOME/.cache にフォールバック
# - chmod 700 は既存ディレクトリにも毎回適用（広い権限が残らないように）
#
# 作成するディレクトリ:
# - ~/.cache/vibecorp/state/   — ゲートスタンプ、command-log、agent-role、diagnose-active 等の state
# - ~/.cache/vibecorp/plans/   — /plan スキルが出力する計画ファイル（#334 で移行）
setup_xdg_cache_dirs() {
  local cache_root="${HOME}/.cache"
  if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then
    cache_root="${XDG_CACHE_HOME}"
  fi
  local state_dir="${cache_root}/vibecorp/state"
  local plans_dir="${cache_root}/vibecorp/plans"
  mkdir -p "$state_dir" "$plans_dir"
  chmod 700 "$state_dir" "$plans_dir" 2>/dev/null || true
  log_info "state 保存先を確保: ${state_dir}"
  log_info "plans 保存先を確保: ${plans_dir}"
}

# 隔離レイヤラッパーが exec する `claude-real` symlink を配置する。full プリセット専用。
# Darwin / Linux 両 OS で動作する。
# templates/claude/bin/claude は `exec claude-real "$@"` する設計のため、
# ラッパー自身を除外して PATH 上の本物 claude を検出し、`.claude/bin/claude-real` に symlink する。
# 検出失敗時は警告のみ出してインストールを続行する（passthrough は引き続き利用可能）。
setup_claude_real_symlink() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi
  case "$OS" in
    darwin|linux) ;;
    *) return 0 ;;  # 未対応 OS は隔離レイヤ自体が配置されないため symlink も不要
  esac

  local bin_dir="${REPO_ROOT}/.claude/bin"
  local target="${bin_dir}/claude-real"
  local real_claude=""

  # PATH 上の本物 claude を検出する（自身のラッパーディレクトリは除外）
  local IFS=":"
  local p
  for p in $PATH; do
    [[ -z "$p" || "$p" == "$bin_dir" ]] && continue
    if [[ -x "$p/claude" ]]; then
      # symlink の場合は解決先が vibecorp ラッパーでないことを確認
      local resolved
      resolved=$(cd "$p" && readlink claude || echo "$p/claude")
      [[ "$resolved" == *"/.claude/bin/claude" ]] && continue
      real_claude="$p/claude"
      break
    fi
  done

  if [[ -z "$real_claude" ]]; then
    log_skip "本物の claude が PATH 上に見つかりません。手動で symlink を貼ってください: ln -s <claude path> ${target}"
    return 0
  fi

  # 既存の非 symlink ファイルは保持（ユーザーが手動配置した可能性があるため）
  if [[ -e "$target" && ! -L "$target" ]]; then
    log_skip "${target} は既存ファイル（非 symlink）のため変更しません"
    return 0
  fi

  ln -sf "$real_claude" "$target"
  log_info "claude-real symlink を作成: .claude/bin/claude-real -> ${real_claude}"
}

generate_plan_yaml_section() {
  # プリセット別に plan.review_agents デフォルトを出力する
  # minimal:  architect のみ
  # standard: architect / security / testing
  # full:     architect / security / testing / performance / dx / cost / legal
  echo "plan:"
  echo "  review_agents:"
  case "$PRESET" in
    minimal)
      echo "    - architect"
      ;;
    standard)
      printf '    - architect\n    - security\n    - testing\n'
      ;;
    full)
      printf '    - architect\n    - security\n    - testing\n    - performance\n    - dx\n    - cost\n    - legal\n'
      ;;
  esac
}

generate_vibecorp_yml() {
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ -f "$yml" ]]; then
    log_skip "vibecorp.yml は既存のためスキップ"
    return
  fi

  cat > "$yml" <<YAML
# vibecorp.yml — プロジェクト設定
name: ${PROJECT_NAME}
preset: ${PRESET}
language: ${LANGUAGE}
base_branch: main
protected_files:
  - MVV.md
coderabbit:
  enabled: true
claude_action:
  enabled: true
  skip_paths:
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"
branch_protection:
  required_approvals: 1
diagnose:
  enabled: true
  max_issues_per_run: 7
  max_issues_per_day: 14
  max_files_per_issue: 10
  scope: ""
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
    - "skills/**"
$(generate_plan_yaml_section)
YAML
  log_info "vibecorp.yml を生成"
}

ensure_claude_action_section() {
  # 既存 vibecorp.yml に claude_action セクション（および未定義キー）を追加する。
  # 既存値は絶対に上書きしない（利用者カスタマイズを尊重）。
  #
  # 仕様根拠: Issue #468 最終確定 3「既存 vibecorp.yml の設定値を保ち、未定義キーだけ追加」
  # bash 3.2 互換、`sed -i` 禁止（mktemp + mv で原子的置換）。
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  [[ -f "$yml" ]] || return 0

  # claude_action: セクション全体の存在確認
  if ! grep -q -e "^claude_action:" "$yml"; then
    # ファイル末尾が改行で終わっていない場合は改行を補う（追記境界の壊れ防止）
    if [[ -s "$yml" ]] && [[ "$(tail -c 1 "$yml")" != $'\n' ]]; then
      printf '\n' >> "$yml"
    fi
    cat >> "$yml" <<'YAML'
claude_action:
  enabled: true
  skip_paths:
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"
YAML
    log_info "vibecorp.yml に claude_action セクションを追加"
    return 0
  fi

  # セクションは存在する。各キーの有無を確認（awk でブロック単位パース）
  local has_enabled has_skip_paths
  has_enabled=$(awk '
    /^claude_action:/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+enabled:/ { print "yes"; exit }
  ' "$yml")
  has_skip_paths=$(awk '
    /^claude_action:/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+skip_paths:/ { print "yes"; exit }
  ' "$yml")

  if [[ "$has_enabled" == "yes" && "$has_skip_paths" == "yes" ]]; then
    return 0
  fi

  # 欠けているキーをセクション末尾に挿入する（次のトップレベルキー直前 or EOF）
  local tmp
  tmp="$(mktemp "$(dirname "$yml")/.${yml##*/}.XXXXXX")"
  awk \
    -v add_enabled="${has_enabled:-no}" \
    -v add_skip_paths="${has_skip_paths:-no}" '
    BEGIN { in_block = 0; appended = 0 }
    function emit_missing() {
      if (add_enabled != "yes") print "  enabled: true"
      if (add_skip_paths != "yes") {
        print "  skip_paths:"
        print "    - \"*.lock\""
        print "    - \".git/**\""
        print "    - \"node_modules/**\""
        print "    - \"dist/**\""
        print "    - \"build/**\""
        print "    - \".cache/**\""
        print "    - \"vendor/**\""
      }
      appended = 1
    }
    {
      if (in_block && /^[^[:space:]#]/ && !appended) {
        emit_missing()
        in_block = 0
      }
      print
      if (/^claude_action:/) in_block = 1
    }
    END {
      if (in_block && !appended) emit_missing()
    }
  ' "$yml" > "$tmp" && mv "$tmp" "$yml"
  log_info "vibecorp.yml の claude_action セクションに不足キーを追加"
}

generate_coderabbit_yaml() {
  local target="${REPO_ROOT}/.coderabbit.yaml"
  local template="${SCRIPT_DIR}/templates/coderabbit.yaml.tpl"

  # vibecorp.yml の coderabbit.enabled を確認（未定義時は true）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  local cr_enabled="true"
  if [[ -f "$yml" ]]; then
    local val
    val=$(awk '/^coderabbit:/{found=1; next} found && /^[^ ]/{exit} found && /enabled:/{print $2}' "$yml")
    if [[ "$val" == "false" ]]; then
      cr_enabled="false"
    fi
  fi

  if [[ "$cr_enabled" == "false" ]]; then
    log_skip ".coderabbit.yaml の生成をスキップ（coderabbit.enabled: false）"
    return
  fi

  if [[ -f "$target" ]]; then
    log_skip ".coderabbit.yaml は既存のためスキップ"
    return
  fi

  local lang_code
  lang_code=$(resolve_coderabbit_language "$LANGUAGE")

  # vibecorp.yml の claude_action.skip_paths を CodeRabbit の path_filters 形式に変換
  # awk -v では改行を含む値を渡せないため、一時ファイル経由で getline する
  local path_filters_file
  path_filters_file="$(mktemp -t coderabbit_path_filters.XXXXXX)"
  _render_coderabbit_path_filters "$yml" > "$path_filters_file"

  awk -v lang="$lang_code" -v paths_file="$path_filters_file" '
    /\{\{PATH_FILTERS_BLOCK\}\}/ {
      while ((getline line < paths_file) > 0) print line
      close(paths_file)
      next
    }
    {
      gsub(/\{\{LANGUAGE\}\}/, lang)
      print
    }
  ' "$template" > "$target"

  rm -f "$path_filters_file"
  log_info ".coderabbit.yaml を生成"
}

# vibecorp.yml の claude_action.skip_paths を CodeRabbit の path_filters ブロックに変換する
# vibecorp の各 skip_path に `!` プレフィックスを付け、CodeRabbit の除外指定形式にする。
# 出力例:
#   path_filters:
#     - "!*.lock"
#     - "!.git/**"
_render_coderabbit_path_filters() {
  local yml="$1"
  local skip_paths
  skip_paths=$(_read_skip_paths "$yml")

  if [[ -z "$skip_paths" ]]; then
    # フォールバック: 旧来のデフォルト（lock ファイル除外）
    printf '  path_filters:\n    - "!**/*.lock"\n'
    return 0
  fi

  printf '  path_filters:\n'
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    printf '    - "!%s"\n' "$path"
  done <<<"$skip_paths"
}

# vibecorp.yml の claude_action.skip_paths からパス文字列を 1 行ずつ取り出す
# （前後ダブルクォートは除去）
_read_skip_paths() {
  local yml="$1"
  [[ -f "$yml" ]] || return 0

  awk '
    /^claude_action:[[:space:]]*$/ { in_action = 1; next }
    in_action && /^[^[:space:]#]/ { exit }
    in_action && /^[[:space:]]+skip_paths:[[:space:]]*$/ { in_paths = 1; next }
    # skip_paths ブロック内のコメント行・空行は読み飛ばす（途中終了させない）
    in_paths && /^[[:space:]]*#/ { next }
    in_paths && /^[[:space:]]*$/ { next }
    in_paths && /^[[:space:]]+[^[:space:]-]/ && !/^[[:space:]]+-/ { exit }
    in_paths && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      # YAML の double quote と single quote (\047 = octal for ASCII 0x27) の双方を剥がす
      gsub(/^["\047]|["\047]$/, "", $0)
      print
    }
  ' "$yml"
}

generate_ci_workflow() {
  local target="${REPO_ROOT}/.github/workflows/test.yml"
  local template="${SCRIPT_DIR}/templates/.github/workflows/test.yml"

  if [[ -f "$target" ]]; then
    log_skip ".github/workflows/test.yml は既存のためスキップ"
    return
  fi

  mkdir -p "${REPO_ROOT}/.github/workflows"
  cp "$template" "$target"
  log_info ".github/workflows/test.yml を生成"
}

generate_review_md() {
  # claude-code-action 用プロンプト REVIEW.md を生成する。
  # 仕様根拠: Issue #465 最終確定（vibecorp.yml の language / claude_action.skip_paths を反映）
  #
  # - claude_action.enabled: false の場合は生成しない
  # - 既存ファイルがあれば 3-way マージ（merge_or_overwrite）
  local target="${REPO_ROOT}/REVIEW.md"
  local template="${SCRIPT_DIR}/templates/REVIEW.md.tpl"
  local rel_path="REVIEW.md"
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  [[ -f "$template" ]] || return 0
  [[ -f "$yml" ]] || return 0

  # claude_action.enabled の判定
  local enabled="true"
  local val
  val=$(awk '
    /^claude_action:[[:space:]]*$/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
      sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$yml")
  if [[ "$val" == "false" ]]; then
    enabled="false"
  fi

  if [[ "$enabled" == "false" ]]; then
    # generate_ai_review_workflow と同じパターンで snapshot/target を掃除する
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    local was_managed="false"
    if [[ -f "$lock" ]] && [[ -n "$(read_base_hash "$lock" "$rel_path")" ]]; then
      was_managed="true"
    fi
    local base_snapshot
    base_snapshot=$(get_base_snapshot "$rel_path")
    if [[ -n "$base_snapshot" ]]; then
      rm -f "$base_snapshot"
    fi
    if [[ -f "$target" ]]; then
      if [[ "$was_managed" == "true" ]]; then
        rm -f "$target"
        log_info "REVIEW.md を削除（claude_action.enabled: false）"
      else
        log_skip "REVIEW.md は vibecorp 管理外のため残置（claude_action.enabled: false）"
      fi
    else
      log_skip "REVIEW.md の生成をスキップ（claude_action.enabled: false）"
    fi
    return 0
  fi

  # 利用者が手動配置した REVIEW.md（管理外: lock に base_hash 記録なし）は上書きしない。
  # merge_or_overwrite は base_hash 不在時にデフォルトで上書きする仕様だが、REVIEW.md は
  # ユーザー編集を想定するため初回 install / 旧バージョンからの移行で既存ファイルを保護する。
  if [[ -f "$target" ]]; then
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    if [[ ! -f "$lock" ]] || [[ -z "$(read_base_hash "$lock" "$rel_path")" ]]; then
      log_skip "REVIEW.md は vibecorp 管理外のため既存ファイルを保護"
      return 0
    fi
  fi

  # language / skip_paths を取得して REVIEW.md を生成
  local language
  language=$(awk '/^language:[[:space:]]*/ { sub(/^language:[[:space:]]*/, ""); print; exit }' "$yml")
  language="${language:-ja}"

  # skip_paths を `- "<path>"` 形式のブロックとして一時ファイルに書き出す
  # awk -v では改行を含む値を渡せないため、getline で読み込む
  local skip_paths_file
  skip_paths_file="$(mktemp -t review_md_skip_paths.XXXXXX)"
  local has_skip_paths=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    printf -- '- "%s"\n' "$path" >> "$skip_paths_file"
    has_skip_paths=1
  done < <(_read_skip_paths "$yml")
  if [[ "$has_skip_paths" -eq 0 ]]; then
    echo "（skip_paths は空です）" > "$skip_paths_file"
  fi

  # 一時ファイルにレンダリング → merge_or_overwrite で 3-way マージ
  local rendered_tmp
  rendered_tmp="$(mktemp -t REVIEW.md.XXXXXX)"
  awk -v lang="$language" -v skip_file="$skip_paths_file" '
    /\{\{SKIP_PATHS_BLOCK\}\}/ {
      while ((getline line < skip_file) > 0) print line
      close(skip_file)
      next
    }
    {
      gsub(/\{\{LANGUAGE\}\}/, lang)
      print
    }
  ' "$template" > "$rendered_tmp"

  merge_or_overwrite "$rendered_tmp" "$target" "$rel_path" || true
  rm -f "$rendered_tmp" "$skip_paths_file"
  log_info "REVIEW.md を生成"
}

generate_ai_review_workflow() {
  # claude-code-action 用ワークフロー（ai-review.yml）の配布。
  # 仕様根拠: Issue #461 最終確定（claude_action.enabled で制御 + 既存ファイルは 3-way マージ）
  #
  # 1. vibecorp.yml の claude_action.enabled を確認（未定義/false なら生成しない）
  # 2. 既存ファイルがあれば merge_or_overwrite による 3-way マージ
  # 3. 無ければテンプレートをコピー
  local target="${REPO_ROOT}/.github/workflows/ai-review.yml"
  local template="${SCRIPT_DIR}/templates/.github/workflows/ai-review.yml"
  local rel_path=".github/workflows/ai-review.yml"

  # claude_action.enabled の判定（awk でブロック単位パース）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  local enabled="true"
  if [[ -f "$yml" ]]; then
    local val
    val=$(awk '
      /^claude_action:[[:space:]]*$/ { in_block = 1; next }
      in_block && /^[^[:space:]#]/ { exit }
      in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
        sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
        sub(/[[:space:]]*$/, "", $0)
        print
        exit
      }
    ' "$yml")
    if [[ "$val" == "false" ]]; then
      enabled="false"
    fi
  fi

  if [[ "$enabled" == "false" ]]; then
    # vibecorp 管理下（lock に base_hash 記録あり）の既存 ai-review.yml は削除して
    # AI レビューを実質無効化する。利用者が手動で配置したファイル（base_hash 無し）は
    # 触らない（誤削除防止）。
    #
    # base snapshot は $target の有無に関係なく必ず削除する。snapshot だけが残っていると
    # 次回 generate_vibecorp_lock() がそこから base_hash を再生成し、後で利用者が手動で
    # 置いた ai-review.yml まで「管理下」と誤認されて削除される。
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    local was_managed="false"
    if [[ -f "$lock" ]] && [[ -n "$(read_base_hash "$lock" "$rel_path")" ]]; then
      was_managed="true"
    fi

    # Issue #532: 旧版（〜0.33.6）で copy_workflows() 経由で配置された ai-review.yml は
    # base_hash が未登録だが、テンプレートと完全一致するため vibecorp 管理下とみなす。
    # ユーザーが内容を編集していればハッシュ不一致となり管理外残置となる（誤削除防止）。
    if [[ "$was_managed" == "false" ]] && [[ -f "$target" ]] && [[ -f "$template" ]]; then
      local target_hash template_hash
      target_hash=$(compute_hash "$target")
      template_hash=$(compute_hash "$template")
      if [[ -n "$target_hash" ]] && [[ "$target_hash" == "$template_hash" ]]; then
        was_managed="true"
      fi
    fi

    # snapshot は管理状態に関わらず常に掃除する（stale snapshot 残置防止）
    local base_snapshot
    base_snapshot=$(get_base_snapshot "$rel_path")
    if [[ -n "$base_snapshot" ]]; then
      rm -f "$base_snapshot"
    fi

    if [[ -f "$target" ]]; then
      if [[ "$was_managed" == "true" ]]; then
        rm -f "$target"
        log_info ".github/workflows/ai-review.yml を削除（claude_action.enabled: false）"
      else
        log_skip ".github/workflows/ai-review.yml は vibecorp 管理外のため残置（claude_action.enabled: false）"
      fi
    else
      log_skip ".github/workflows/ai-review.yml の生成をスキップ（claude_action.enabled: false）"
    fi
    return 0
  fi

  if [[ ! -f "$template" ]]; then
    return 0
  fi

  mkdir -p "${REPO_ROOT}/.github/workflows"

  # 既存ファイルがあれば 3-way マージ、無ければ単純コピー
  merge_or_overwrite "$template" "$target" "$rel_path" || true
  log_info ".github/workflows/ai-review.yml を生成"
}

generate_ai_review_golden_test_workflow() {
  # claude-code-action 用 golden test ワークフロー（ai-review-golden-test.yml）の配布。
  # 仕様根拠: Issue #532（claude-code-action 一時無効化に追従して golden test も停止する）
  #
  # claude_action.enabled で制御する（claude-action 自体が無効化されたら golden test も停止）。
  # 構造は generate_ai_review_workflow() と同じ（snapshot 掃除 + 管理下削除 + 管理外残置）。
  # 共通ヘルパー化は intent/refactor 別 Issue で対応する方針。
  local target="${REPO_ROOT}/.github/workflows/ai-review-golden-test.yml"
  local template="${SCRIPT_DIR}/templates/.github/workflows/ai-review-golden-test.yml"
  local rel_path=".github/workflows/ai-review-golden-test.yml"

  # claude_action.enabled の判定（awk でブロック単位パース）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  local enabled="true"
  if [[ -f "$yml" ]]; then
    local val
    val=$(awk '
      /^claude_action:[[:space:]]*$/ { in_block = 1; next }
      in_block && /^[^[:space:]#]/ { exit }
      in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
        sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
        sub(/[[:space:]]*$/, "", $0)
        print
        exit
      }
    ' "$yml")
    if [[ "$val" == "false" ]]; then
      enabled="false"
    fi
  fi

  if [[ "$enabled" == "false" ]]; then
    # vibecorp 管理下（lock に base_hash 記録あり）の既存 ai-review-golden-test.yml は削除して
    # golden test を実質無効化する。利用者が手動で配置したファイル（base_hash 無し）は
    # 触らない（誤削除防止）。
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    local was_managed="false"
    if [[ -f "$lock" ]] && [[ -n "$(read_base_hash "$lock" "$rel_path")" ]]; then
      was_managed="true"
    fi

    # Issue #532: 旧版（〜0.33.6）で copy_workflows() 経由で配置された
    # ai-review-golden-test.yml は base_hash が未登録だが、テンプレートと完全一致するため
    # vibecorp 管理下とみなす。ユーザーが内容を編集していればハッシュ不一致となり管理外残置
    # となる（誤削除防止）。これにより 0.33.6 から本版に更新したユーザーのリポジトリでも
    # claude_action.enabled: false 切替で golden test ワークフローが綺麗に削除される。
    if [[ "$was_managed" == "false" ]] && [[ -f "$target" ]] && [[ -f "$template" ]]; then
      local target_hash template_hash
      target_hash=$(compute_hash "$target")
      template_hash=$(compute_hash "$template")
      if [[ -n "$target_hash" ]] && [[ "$target_hash" == "$template_hash" ]]; then
        was_managed="true"
      fi
    fi

    # snapshot は管理状態に関わらず常に掃除する（stale snapshot 残置防止）
    local base_snapshot
    base_snapshot=$(get_base_snapshot "$rel_path")
    if [[ -n "$base_snapshot" ]]; then
      rm -f "$base_snapshot"
    fi

    if [[ -f "$target" ]]; then
      if [[ "$was_managed" == "true" ]]; then
        rm -f "$target"
        log_info ".github/workflows/ai-review-golden-test.yml を削除（claude_action.enabled: false）"
      else
        log_skip ".github/workflows/ai-review-golden-test.yml は vibecorp 管理外のため残置（claude_action.enabled: false）"
      fi
    else
      log_skip ".github/workflows/ai-review-golden-test.yml の生成をスキップ（claude_action.enabled: false）"
    fi
    return 0
  fi

  if [[ ! -f "$template" ]]; then
    return 0
  fi

  mkdir -p "${REPO_ROOT}/.github/workflows"

  # 既存ファイルがあれば 3-way マージ、無ければ単純コピー
  merge_or_overwrite "$template" "$target" "$rel_path" || true
  log_info ".github/workflows/ai-review-golden-test.yml を生成"
}

print_manual_guidance() {
  local base_branch="$1"
  local checks="$2"
  cat >&2 <<GUIDANCE
[推奨設定]
  Settings > General > Pull Requests:
    - Allow squash merging のみ有効
    - Allow auto-merge 有効
    - Automatically delete head branches 有効
  Settings > General > Update branch:
    - Always suggest updating pull request branches 有効
  Settings > Branches > Branch protection rules (${base_branch}):
    - Require a pull request before merging
    - Require approvals: 1
    - Dismiss stale pull request approvals when new commits are pushed
    - Require status checks to pass before merging (strict)
    - Required checks: ${checks}
    - Include administrators
    - Do not allow force pushes
    - Do not allow deletions
GUIDANCE
}

resolve_github_checks() {
  # .coderabbit.yaml が存在すれば CodeRabbit を required check に追加
  if [[ -f "${REPO_ROOT}/.coderabbit.yaml" ]]; then
    echo "test, CodeRabbit"
  else
    echo "test"
  fi
}

resolve_base_branch() {
  local base_branch="main"
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  if [[ -f "$yml" ]]; then
    local parsed
    parsed=$(awk '/^base_branch:/ { print $2 }' "$yml")
    [[ -n "$parsed" ]] && base_branch="$parsed"
  fi
  echo "$base_branch"
}

configure_github_repo() {
  local base_branch
  base_branch=$(resolve_base_branch)
  local checks_display
  checks_display=$(resolve_github_checks)

  # gh CLI が利用できない場合はスキップ
  if ! command -v gh >/dev/null 2>&1; then
    log_skip "gh CLI が見つかりません。リポジトリ設定は手動で行ってください"
    print_manual_guidance "$base_branch" "$checks_display"
    return
  fi

  # GitHub リポジトリ情報を取得
  local name_with_owner
  if ! name_with_owner=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null); then
    log_skip "GitHub リポジトリに接続できません。リポジトリ設定は手動で行ってください"
    print_manual_guidance "$base_branch" "$checks_display"
    return
  fi

  # マージ戦略の設定
  if gh api "repos/${name_with_owner}" -X PATCH \
    -f allow_squash_merge=true \
    -f allow_merge_commit=false \
    -f allow_rebase_merge=false \
    -f allow_auto_merge=true \
    -f delete_branch_on_merge=true \
    -f allow_update_branch=true \
    >/dev/null 2>&1; then
    log_info "マージ戦略を設定（squash merge のみ、auto-merge 有効）"
  else
    log_error "マージ戦略の設定に失敗しました（admin 権限が必要です）"
    print_manual_guidance "$base_branch" "$checks_display"
  fi

  # Branch Protection の設定
  # vibecorp が必須とする contexts
  local vibecorp_checks='["test"]'
  if [[ -f "${REPO_ROOT}/.coderabbit.yaml" ]]; then
    vibecorp_checks='["test","CodeRabbit"]'
  fi

  # 既存の required status checks を取得してマージ（既存 contexts を保持）
  local existing_contexts="[]"
  local get_error
  local existing_raw
  if existing_raw=$(gh api "repos/${name_with_owner}/branches/${base_branch}/protection/required_status_checks" \
    --jq '.contexts' 2>&1); then
    # 有効な JSON 配列かどうか検証（-e: false/null で非ゼロ終了）
    if [[ -n "$existing_raw" ]] && echo "$existing_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
      existing_contexts="$existing_raw"
    fi
  else
    get_error="$existing_raw"
    # 404 = Branch Protection 未設定（正常）、それ以外 = 権限不足等で既存 contexts 不明
    if ! echo "$get_error" | grep -qi "404\|not found"; then
      log_error "既存の required status checks を取得できません。上書き回避のため自動設定をスキップします: ${get_error}"
      print_manual_guidance "$base_branch" "$checks_display"
      return
    fi
  fi

  # 既存 + vibecorp を UNION（重複排除・ソート）
  local merged_contexts
  merged_contexts=$(jq -n --argjson existing "$existing_contexts" --argjson new "$vibecorp_checks" \
    '($existing + $new) | unique')

  # 手動ガイダンス用にマージ済み contexts を文字列化
  local merged_checks_display
  merged_checks_display=$(echo "$merged_contexts" | jq -r 'join(", ")')

  # vibecorp.yml から required_approvals を読み取る（未設定時はデフォルト 1）
  # awk でブロック単位パース（shell.md「YAML パース」ルール準拠）
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  local required_approvals=1
  if [[ -f "$yml" ]]; then
    local val
    val=$(awk '
      /^branch_protection:[[:space:]]*$/ { in_block = 1; next }
      in_block && /^[^[:space:]#]/ { exit }
      in_block && /^[[:space:]]+required_approvals:[[:space:]]*/ {
        sub(/^[[:space:]]+required_approvals:[[:space:]]*/, "", $0)
        sub(/[[:space:]]*$/, "", $0)
        print
        exit
      }
    ' "$yml")
    # 1 以上の整数のみ受理（0 や非数値はデフォルト 1 にフォールバック）
    # 0 を許すと「approve N件以上必須」の前提を崩すため明示的に拒否
    if [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
      required_approvals="$val"
    fi
  fi

  local protection_json
  protection_json=$(jq -n \
    --argjson contexts "$merged_contexts" \
    --argjson required_approvals "$required_approvals" \
    '{
      required_status_checks: {
        strict: true,
        contexts: $contexts
      },
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false,
        require_last_push_approval: false,
        required_approving_review_count: $required_approvals
      },
      enforce_admins: true,
      restrictions: null,
      allow_force_pushes: false,
      allow_deletions: false,
      block_creations: false,
      required_conversation_resolution: false
    }')

  local put_error
  if put_error=$(echo "$protection_json" | gh api "repos/${name_with_owner}/branches/${base_branch}/protection" \
    -X PUT --input - 2>&1 >/dev/null); then
    log_info "ブランチ保護を設定（${base_branch}: CI必須、PR必須、approve ${required_approvals}件以上必須、push 毎に既存 approve 自動 dismiss）"
  else
    log_error "ブランチ保護の設定に失敗しました（admin 権限が必要です）: ${put_error}"
    print_manual_guidance "$base_branch" "$merged_checks_display"
  fi
}

verify_claude_action_secrets() {
  # claude_action.enabled: true のとき GitHub secrets に CLAUDE_CODE_OAUTH_TOKEN が
  # 登録されているかを確認する。未登録なら WARN を出力して設定を促す（exit はしない）。
  #
  # 仕様の Source of Truth: docs/ai-review-auth.md「install.sh の secrets 検証」
  # 議論結果根拠: Issue #462 最終確定 5（install.sh の secrets 検証ロジック: 入れる）
  #
  # vibecorp.yml の claude_action セクション schema 自体は #468 で追加されるため、
  # セクション不在時は no-op として安全にスキップする。
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"
  [[ -f "$yml" ]] || return 0

  # claude_action.enabled をブロック単位でパース（次のトップレベルキーで停止）
  # shell.md「YAML パース」ルールに従い grep -A は使わず awk でブロック抽出する
  local enabled
  enabled=$(awk '
    /^claude_action:[[:space:]]*$/ { in_block = 1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && /^[[:space:]]+enabled:[[:space:]]*/ {
      sub(/^[[:space:]]+enabled:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$yml")

  if [[ "$enabled" != "true" ]]; then
    return 0
  fi

  # gh CLI が利用できない場合はスキップ
  if ! command -v gh >/dev/null 2>&1; then
    log_skip "gh CLI が見つかりません。CLAUDE_CODE_OAUTH_TOKEN の確認は手動で行ってください"
    return 0
  fi

  # GitHub 認証済みか確認
  if ! gh auth status >/dev/null 2>&1; then
    log_skip "gh が未認証のため CLAUDE_CODE_OAUTH_TOKEN の確認をスキップします"
    return 0
  fi

  # gh secret list の出力先頭カラムが secret 名（タブ区切り）
  # awk で先頭フィールドだけ抜き出して完全一致で判定する（部分一致を防ぐ）
  if gh secret list 2>/dev/null | awk '{print $1}' | grep -qx 'CLAUDE_CODE_OAUTH_TOKEN'; then
    log_info "CLAUDE_CODE_OAUTH_TOKEN が登録されています"
    return 0
  fi

  log_warn "CLAUDE_CODE_OAUTH_TOKEN が登録されていません"
  cat >&2 <<'WARN_BODY'
       claude-code-action を有効化するには以下を実行してください:
         claude setup-token
         gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
       詳細: docs/ai-review-auth.md

       なお secret 名が登録されていても値が空文字列の場合、
       ai-review.yml の preflight ガードが PR にコメントを残して
       claude-code-action 起動を明示的に止めます（Issue #509）。
WARN_BODY
}

setup_git_config() {
  # vibecorp 運用（Issue 駆動 + squash マージ + 短寿命ブランチ）に合わせた
  # local git config を適用する。squash マージ後の `git pull origin main` で
  # 空の merge commit が生成される問題（Issue #383）を防ぐ。
  #
  # - merge.ff only: FF 可能時は merge commit を作らず、不可能時はエラーで手動判断させる
  # - pull.ff only: pull で FF 不可能な状況ではエラー終了して手動判断させる
  # - pull.rebase (local) を unset: global の `pull.rebase merges` 等を活かす
  git -C "${REPO_ROOT}" config --local merge.ff only
  log_info "git config --local merge.ff only を適用（空 merge commit 防止）"

  git -C "${REPO_ROOT}" config --local pull.ff only
  log_info "git config --local pull.ff only を適用（非 FF pull はエラー）"

  # local に pull.rebase が設定されている場合のみ unset する。
  # 未設定のまま `git config --unset` を呼ぶと exit 5 で失敗するため、
  # 事前に `--get` で存在確認してから unset する（冪等性）。
  if git -C "${REPO_ROOT}" config --local --get pull.rebase >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" config --local --unset pull.rebase
    log_info "git config --local pull.rebase を unset（global 設定を活かす）"
  else
    log_skip "local pull.rebase は未設定（unset スキップ）"
  fi
}

generate_vibecorp_lock() {
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local installed_at
  installed_at=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
  local vibecorp_commit
  vibecorp_commit=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # vibecorp が管理するファイルのマニフェストを生成（テンプレート由来のみ）
  # hooks は plugin native 配布 (#716) に移行済のため lock では空リストを維持する（後方互換）
  # agents は plugin native 配布 (#737 / #735) に移行済のため lock では agents セクション自体を書かない
  local skills_list="" rules_list="" issue_templates_list="" docs_list="" knowledge_list=""

  # テンプレートに存在し、プリセット削除後も残っているファイルを記録
  for d in "${SCRIPT_DIR}/skills/"*/; do
    [[ -d "$d" ]] || continue
    local name
    name=$(basename "$d")
    [[ -d "${REPO_ROOT}/.claude/skills/${name}" ]] && skills_list="${skills_list}    - ${name}"$'\n'
  done
  # コピー済みファイルリストから lock に記録（ユーザー既存ファイルを誤登録しない）
  while IFS= read -r name; do
    [[ -n "$name" ]] && rules_list="${rules_list}    - ${name}"$'\n'
  done <<< "$COPIED_RULES"
  while IFS= read -r name; do
    [[ -n "$name" ]] && issue_templates_list="${issue_templates_list}    - ${name}"$'\n'
  done <<< "$COPIED_ISSUE_TEMPLATES"
  # コピー済みファイルリストから lock に記録（ユーザー既存ファイルを誤登録しない）
  while IFS= read -r name; do
    [[ -n "$name" ]] && docs_list="${docs_list}    - ${name}"$'\n'
  done <<< "$COPIED_DOCS"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && knowledge_list="${knowledge_list}    - ${rel}"$'\n'
  done <<< "$COPIED_KNOWLEDGE"

  # base_hashes: ベーススナップショットの SHA256 ハッシュ
  local base_hashes=""
  local base_dir="${REPO_ROOT}/.claude/vibecorp-base"
  if [[ -d "$base_dir" ]]; then
    while IFS= read -r base_file; do
      [[ -f "$base_file" ]] || continue
      local rel="${base_file#"$base_dir"/}"
      local hash
      hash=$(compute_hash "$base_file")
      if [[ -n "$hash" ]]; then
        base_hashes="${base_hashes}    ${rel}: ${hash}"$'\n'
      fi
    done < <(find "$base_dir" -type f | sort)
  fi

  # 空リスト時は YAML の明示的空リスト表記 [] を使用（null を防止）
  _lock_list_section() {
    local key="$1" items="$2"
    if [[ -z "$items" ]]; then
      printf '  %s: []\n' "$key"
    else
      printf '  %s:\n%s' "$key" "$items"
    fi
  }
  _lock_map_section() {
    local key="$1" items="$2"
    if [[ -z "$items" ]]; then
      printf '  %s: {}\n' "$key"
    else
      printf '  %s:\n%s' "$key" "$items"
    fi
  }

  local files_block=""
  # $() は末尾改行を除去するため、各セクション連結時に明示的に改行を補う
  # v2 形式 (#722): hooks: / lib: セクションは plugin native 配布 (#716) で plugin/hooks/hooks.json に
  # 一元化されたため、新規 lock では一切書き込まない。read_lock_list は v1 形式の hooks: / lib: も
  # 引き続き読めるため後方互換は維持される（test_install_legacy_migration.sh で検証済）。
  # v3 形式 (#735): agents: セクションは plugin native 配布 (#737) で plugin/agents/ に一元化された
  # ため、新規 lock では一切書き込まない。read_lock_list は v1/v2 形式の agents: も引き続き
  # 読めるため migration 経路（migrate_legacy_layout）で旧 lock 記載の agent を物理削除できる。
  files_block+="$(_lock_list_section "skills" "$skills_list")"$'\n'
  files_block+="$(_lock_list_section "rules" "$rules_list")"$'\n'
  files_block+="$(_lock_list_section "issue_templates" "$issue_templates_list")"$'\n'
  files_block+="$(_lock_list_section "docs" "$docs_list")"$'\n'
  files_block+="$(_lock_list_section "knowledge" "$knowledge_list")"$'\n'
  files_block+="$(_lock_map_section "base_hashes" "$base_hashes")"$'\n'

  cat > "$lock" <<YAML
# vibecorp.lock — 自動生成、手動編集禁止
# format_version 3 は agents セクション廃止後の lock 形式 (#735)
# 履歴: v1 (hooks / lib あり) → v2 (#722: hooks/lib 廃止) → v3 (#735: agents 廃止)
format_version: 3
version: ${VIBECORP_VERSION}
installed_at: ${installed_at}
preset: ${PRESET}
vibecorp_commit: ${vibecorp_commit}
files:
${files_block}
YAML
  log_info "vibecorp.lock を生成"
}

generate_settings_json() {
  # hooks は plugin native 配布 (#716) に移行済のため settings.json には書き込まない。
  # ここでは permissions / extraKnownMarketplaces / enabledPlugins のみを扱う。
  # 配布元は単一 SSOT templates/claude/settings.json (Issue #759、settings.json.tpl は廃止)。
  local settings="${REPO_ROOT}/.claude/settings.json"
  local template="${SCRIPT_DIR}/templates/claude/settings.json"

  # self-install（dogfooding）は .claude/settings.json を SSOT への symlink で直結する (Issue #759)。
  # 利用者設定を保全する必要がないため merge は行わない（symlink 経由で SSOT を書き換えないよう
  # 既存実体/symlink を除去してから貼り直す）。user-install は実体コピー + merge（下記）で
  # 既存 permissions を保全する（#748 と異なり settings は成長しうるため上書きせず併合）。
  if [[ "$(_canonical_dir "$SCRIPT_DIR")" == "$(_canonical_dir "$REPO_ROOT")" ]]; then
    rm -f "$settings"
    ln -sfn "../templates/claude/settings.json" "$settings"
    log_info "settings.json を symlink SSOT 化（self-install）"
    return 0
  fi

  local new_settings
  new_settings=$(cat "$template")

  # user-install: symlink が残っていると merge が SSOT を書き換える恐れがあるため除去する
  if [[ -L "$settings" ]]; then
    rm -f "$settings"
  fi

  if [[ ! -f "$settings" ]]; then
    # 新規: テンプレートをそのまま書き出し（permissions / marketplace / enabledPlugins）
    echo "$new_settings" | jq '.' > "$settings"
    log_info "settings.json を生成"
  else
    # 既存: 既存ユーザー設定を保持しつつ permissions.allow / marketplace / enabledPlugins を併合する
    local new_permissions_allow
    new_permissions_allow=$(echo "$new_settings" | jq '.permissions.allow // []')
    local new_marketplaces
    new_marketplaces=$(echo "$new_settings" | jq '.extraKnownMarketplaces // {}')
    local new_enabled_plugins
    new_enabled_plugins=$(echo "$new_settings" | jq '.enabledPlugins // {}')

    jq --argjson new_allow "$new_permissions_allow" \
       --argjson new_mkts "$new_marketplaces" \
       --argjson new_plugins "$new_enabled_plugins" '
      .permissions = ((.permissions // {}) | .allow = (((.allow // []) + $new_allow) | unique))
      | .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) + $new_mkts)
      | .enabledPlugins = ((.enabledPlugins // {}) + $new_plugins)
    ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    log_info "settings.json をマージ（permissions / marketplace / enabledPlugins）"
  fi
}

copy_issue_templates() {
  local src="${SCRIPT_DIR}/templates/.github/ISSUE_TEMPLATE"
  local dest="${REPO_ROOT}/.github/ISSUE_TEMPLATE"

  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"

  for f in "${src}"/*; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    if [[ -f "${dest}/${name}" ]]; then
      log_skip "ISSUE_TEMPLATE/${name} は既存のためスキップ"
    else
      cp "$f" "${dest}/${name}"
      COPIED_ISSUE_TEMPLATES="${COPIED_ISSUE_TEMPLATES}${name}"$'\n'
    fi
  done

  log_info "Issue テンプレートをコピー"
}

copy_pr_template() {
  local src="${SCRIPT_DIR}/templates/.github/pull_request_template.md"
  local dest="${REPO_ROOT}/.github/pull_request_template.md"

  [[ -f "$src" ]] || return 0

  mkdir -p "${REPO_ROOT}/.github"

  if [[ -f "$dest" ]]; then
    log_skip "pull_request_template.md は既存のためスキップ"
  else
    cp "$src" "$dest"
    log_info "PR テンプレートをコピー"
  fi
}

copy_workflows() {
  local src="${SCRIPT_DIR}/templates/.github/workflows"
  local dest="${REPO_ROOT}/.github/workflows"

  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"

  for f in "${src}"/*; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    # ai-review.yml と ai-review-golden-test.yml は
    # generate_ai_review_workflow() / generate_ai_review_golden_test_workflow() が
    # claude_action.enabled の判定と 3-way マージを担うため、ここでは扱わない
    if [[ "$name" == "ai-review.yml" ]] || [[ "$name" == "ai-review-golden-test.yml" ]]; then
      continue
    fi
    # close-on-feature-merge.yml は full プリセット限定の opt-in 配布のため、
    # copy_close_on_feature_merge_workflow() が担う (Issue #347)
    if [[ "$name" == "close-on-feature-merge.yml" ]]; then
      continue
    fi
    if [[ -f "${dest}/${name}" ]]; then
      log_skip "workflows/${name} は既存のためスキップ"
    else
      cp "$f" "${dest}/${name}"
    fi
  done

  log_info "ワークフローをコピー"
}

# feature/epic-* ブランチへのマージ時に PR 本文の Closes/Fixes/Resolves から
# Issue 番号を抽出して自動 close するワークフローを配布する (Issue #347)。
#
# 設計:
#   - full プリセット限定 (エピック運用は full でのみ整備されているため)
#   - 既存ファイルは上書きしない (opt-in、ユーザーカスタマイズ尊重)
#   - LLM 呼び出し一切なし (決定論的 / 課金ゼロ)
#
# 配布判断の根拠: docs/design-philosophy.md「統合問題は配布先のデフォルト CI で担保する」
# (vibecorp が GHA を配布する例外ケース: GitHub の default branch 自動 close 仕様の制約回避)
copy_close_on_feature_merge_workflow() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi

  local src="${SCRIPT_DIR}/templates/.github/workflows/close-on-feature-merge.yml"
  local dest_dir="${REPO_ROOT}/.github/workflows"
  local dest="${dest_dir}/close-on-feature-merge.yml"

  [[ -f "$src" ]] || return 0
  mkdir -p "$dest_dir"

  if [[ -f "$dest" ]]; then
    log_skip "workflows/close-on-feature-merge.yml は既存のためスキップ"
    return 0
  fi

  cp "$src" "$dest"
  log_info ".github/workflows/close-on-feature-merge.yml を配置 (full プリセット)"
}

create_labels() {
  # gh 未インストール or リポジトリ未接続ならスキップ
  if ! command -v gh >/dev/null 2>&1; then
    log_skip "gh 未インストールのためラベル作成をスキップ"
    return 0
  fi
  if ! gh repo view >/dev/null 2>&1; then
    log_skip "リポジトリ未接続のためラベル作成をスキップ"
    return 0
  fi

  local VIBECORP_LABELS=(
    "bug:d73a4a:不具合の報告"
    "enhancement:a2eeef:機能追加・改善"
    "documentation:0075ca:ドキュメントの追加・修正"
    "question:d876e3:質問・相談"
    "good first issue:7057ff:初心者向けのタスク"
    "help wanted:008672:協力者募集"
    "design:f9d0c4:設計・計画"
    "testing:bfd4f2:テスト関連"
    "refactor:d4c5f9:リファクタリング"
    "priority/high:b60205:優先度: 高"
    "priority/low:c2e0c6:優先度: 低"
    "intent/feature:0e8a16:新機能を確実に動かす（影響を与える系）"
    "intent/bugfix:b60205:既存バグを最小修正で直す（影響を与える系）"
    "intent/performance:fbca04:性能を測定可能な形で改善する（影響を与える系）"
    "intent/security:5319e7:脆弱性を塞ぐ（影響を与える系）"
    "intent/refactor:d4c5f9:構造の品質を高める（挙動不変系）"
    "intent/infra:c5def5:開発基盤の品質を底上げする（挙動不変系）"
    "intent/docs:0075ca:ドキュメントの正確性を担保する（挙動不変系）"
  )

  # 既存ラベル一覧を取得
  local existing_labels
  existing_labels=$(gh label list --json name --jq '.[].name' --limit 100 2>/dev/null || echo "")

  for entry in "${VIBECORP_LABELS[@]}"; do
    local label_name label_color label_desc
    label_name="${entry%%:*}"
    local rest="${entry#*:}"
    label_color="${rest%%:*}"
    label_desc="${rest#*:}"

    if echo "$existing_labels" | grep -qxF "$label_name"; then
      log_skip "ラベル '${label_name}' は既存のためスキップ"
    else
      if gh label create "$label_name" --color "$label_color" --description "$label_desc" 2>/dev/null; then
        log_info "ラベル '${label_name}' を作成"
      else
        log_skip "ラベル '${label_name}' の作成に失敗（スキップ）"
      fi
    fi
  done
}

# 機能: .claude/rules/<rel> から SSOT rules/<rel> への相対 symlink ターゲット文字列を返す。
# self-install（dogfooding）でファイル単位 symlink を貼り直す際に使う。
# .claude/rules の 2 階層 + rel のサブディレクトリ深さ分だけ ".." を遡り、rules/<rel> を付ける。
# 例: markdown.md → ../../rules/markdown.md / severity/coderabbit.md → ../../../rules/severity/coderabbit.md
_relpath_to_rules() {
  local rel="$1"
  # rel に含まれる "/" の個数がサブディレクトリ深さ（トップ直下は 0）
  local slash_count
  slash_count=$(printf '%s' "$rel" | tr -cd '/' | wc -c | tr -d ' ')
  # .claude/rules/ から見た遡り段数 = 2（.claude/rules）+ サブディレクトリ深さ
  local up_levels=$((2 + slash_count))
  local prefix=""
  local i
  for ((i = 0; i < up_levels; i++)); do
    prefix="${prefix}../"
  done
  printf '%s' "${prefix}rules/${rel}"
}

# 機能: ディレクトリパスを symlink 解決済みの絶対パスに正規化する（realpath 非依存）。
# realpath は古い macOS に不在で shell.md の BSD/GNU 互換要件に反するため pwd -P を使う。
_canonical_dir() {
  ( cd "$1" 2>/dev/null && pwd -P )
}

copy_rules() {
  # 配布元はプラグインルート rules/ が SSOT（Issue #747）。
  # SCRIPT_DIR（plugin root）と REPO_ROOT が同一ディレクトリなら vibecorp 自身への
  # install（self-install）と判定し、.claude/rules/ を rules/ への symlink で再生成する
  # （dogfooding の symlink を破壊しない）。異なる場合は配布先への install（user-install）
  # と判定し、実体ファイルを物理コピーで上書きする（symlink は配布しない、Issue #748）。
  local src="${SCRIPT_DIR}/rules"
  local dest="${REPO_ROOT}/.claude/rules"
  mkdir -p "$dest"

  local self_install=false
  if [[ "$(_canonical_dir "$SCRIPT_DIR")" == "$(_canonical_dir "$REPO_ROOT")" ]]; then
    self_install=true
  fi

  # トップレベル *.md と 1 階層下のサブディレクトリ（severity/ 等）の *.md を対象とする。
  # find -maxdepth 2 でサブディレクトリ 1 階層まで対応（深いネストは想定外）。
  # 配布物だけを列挙するため、dest 側にある配布対象外ファイル（user 固有 rule）は
  # 両モードで一切触れられず保持される。
  while IFS= read -r rule; do
    [[ -f "$rule" ]] || continue
    local rel_path="${rule#"${src}"/}"  # 例: severity/coderabbit.md
    local rel_dir
    rel_dir=$(dirname "$rel_path")
    if [[ "$rel_dir" != "." ]]; then
      mkdir -p "${dest}/${rel_dir}"
    fi
    if [[ "$self_install" == true ]]; then
      # self-install: ファイル単位 symlink を貼り直す（既存 symlink / 実体は上書き）
      ln -sfn "$(_relpath_to_rules "$rel_path")" "${dest}/${rel_path}"
    else
      # user-install: 3-way マージは行わず常に最新で上書きする（Issue #748）
      # symlink 経由でリンク先実体を書き換えないよう、コピー前に symlink を除去する
      if [[ -L "${dest}/${rel_path}" ]]; then
        rm -f "${dest}/${rel_path}"
      fi
      cp -f "$rule" "${dest}/${rel_path}"
    fi
    COPIED_RULES="${COPIED_RULES}${rel_path}"$'\n'
  done < <(find "$src" -maxdepth 2 -type f -name "*.md" 2>/dev/null)
}

copy_docs() {
  local src="${SCRIPT_DIR}/templates/docs"
  local dest="${REPO_ROOT}/docs"

  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"

  for tpl in "${src}"/*.tpl; do
    [[ -f "$tpl" ]] || continue
    local tpl_name
    tpl_name=$(basename "$tpl")
    # .tpl 拡張子を除去してコピー先ファイル名を決定
    local name="${tpl_name%.tpl}"
    if [[ -f "${dest}/${name}" ]]; then
      log_skip "docs/${name} は既存のためスキップ"
    else
      # プレースホルダー置換してコピー
      sed \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
        "$tpl" > "${dest}/${name}"
      COPIED_DOCS="${COPIED_DOCS}${name}"$'\n'
      log_info "docs/${name} をコピー"
    fi
  done
}

copy_knowledge() {
  local src="${SCRIPT_DIR}/templates/claude/knowledge"
  local dest="${REPO_ROOT}/.claude/knowledge"

  # knowledge テンプレートが存在しない場合はスキップ
  [[ -d "$src" ]] || return 0

  # minimal プリセットでは knowledge をコピーしない（agents がないため不要）
  case "$PRESET" in
    minimal) return 0 ;;
  esac

  # ディレクトリ構造を維持してコピー（既存ファイルはスキップ）
  while IFS= read -r f; do
    local rel="${f#"$src"/}"
    local dest_file="${dest}/${rel}"
    local dest_dir
    dest_dir=$(dirname "$dest_file")

    mkdir -p "$dest_dir"

    if [[ -f "$dest_file" ]]; then
      log_skip "knowledge/${rel} は既存のためスキップ"
    else
      # コピー時にプレースホルダー置換（既存ファイルは対象外）
      sed \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        -e "s|{{PRESET}}|${PRESET}|g" \
        -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
        "$f" > "$dest_file"
      COPIED_KNOWLEDGE="${COPIED_KNOWLEDGE}${rel}"$'\n'
    fi
  done < <(find "$src" -type f)

  log_info "knowledge テンプレートをコピー"
}

# 末尾が改行で終わっていないファイルに改行を追加する。
# `>>` 追記前に呼び出すことで、既存行と追記行が連結されて破損するのを防ぐ。
_ensure_trailing_newline() {
  local file="$1"
  [[ -s "$file" ]] || return 0
  # tail -c 1 でファイル末尾の1バイトを取得。wc -l は改行文字があれば1、なければ0を返す
  local last_nl
  last_nl=$(tail -c 1 "$file" | wc -l | tr -d ' ')
  if [[ "$last_nl" -eq 0 ]]; then
    printf '\n' >> "$file"
  fi
}

# `.gitignore.tpl` の `# ---- machine-specific artifacts ----` セクション配下から
# 相対パス行のみを stdout に出力する純粋関数。テストから source して直接呼び出せる。
_extract_gitignore_artifacts() {
  local tpl="$1"
  [[ -f "$tpl" ]] || return 0
  awk '
    /^# ---- machine-specific artifacts/ { in_section = 1; next }
    in_section && /^# ----/ { in_section = 0; next }
    in_section && /^#/ { next }
    in_section && /^[[:space:]]*$/ { next }
    in_section { print }
  ' "$tpl"
}

migrate_tracked_artifacts() {
  # 旧バージョン install で誤って tracked 化された machine-specific artifact を untrack する
  # untrack 対象は templates/claude/.gitignore.tpl の `# ---- machine-specific artifacts ----`
  # マーカー配下の相対パスから自動抽出する（DRY: .gitignore.tpl が Source of Truth）。
  #
  # --no-migrate は --name / --update の両モードで受け付けるが、通常は既存環境の移行時に意味を持つ。
  # 新規 --name モードでも legacy artifact を tracked 化した consumer には影響するため、
  # フラグが立っていれば本関数はスキップする。
  if [[ "$NO_MIGRATE" == true ]]; then
    log_info "--no-migrate 指定のため tracked artifact の untrack をスキップ"
    return 0
  fi

  # REPO_ROOT が git リポジトリでない場合はスキップ
  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    log_info "${REPO_ROOT} は git リポジトリではないため tracked artifact の untrack をスキップ"
    return 0
  fi

  local tpl="${SCRIPT_DIR}/templates/claude/.gitignore.tpl"
  if [[ ! -f "$tpl" ]]; then
    log_skip "${tpl} が見つからないため migrate をスキップ"
    return 0
  fi

  # machine-specific マーカー配下の非コメント・非空行を artifacts 配列に抽出
  local artifacts=()
  local line
  while IFS= read -r line; do
    artifacts+=(".claude/${line}")
  done < <(_extract_gitignore_artifacts "$tpl")

  if [[ ${#artifacts[@]} -eq 0 ]]; then
    log_info "untrack 対象の artifact なし（${tpl} の machine-specific セクションが空またはマーカー行が未検出）"
    return 0
  fi

  local artifact
  for artifact in "${artifacts[@]}"; do
    # path traversal / prefix 検証（`.claude/` プレフィックス + `..` 拒否）
    if [[ "$artifact" != .claude/* ]] || [[ "$artifact" == *..* ]]; then
      log_skip "不正なパスをスキップ: ${artifact}"
      continue
    fi

    if git -C "$REPO_ROOT" ls-files --error-unmatch "$artifact" >/dev/null 2>&1; then
      if git -C "$REPO_ROOT" rm --cached "$artifact" >/dev/null 2>&1; then
        log_info "旧バージョンで tracked 化した ${artifact} を untrack しました（working tree は保持。次回コミットで untrack が反映されます）"
      else
        # 失敗しても install 全体は継続。ユーザーに手動対応を促す
        log_skip "${artifact} の untrack に失敗しました。必要に応じて 'git rm --cached ${artifact}' を手動実行してください"
      fi
    fi
  done
}

copy_claude_gitignore() {
  # .claude/.gitignore を templates/ から配布する（Source of Truth: templates/claude/.gitignore.tpl）
  local src="${SCRIPT_DIR}/templates/claude/.gitignore.tpl"
  local dest="${REPO_ROOT}/.claude/.gitignore"
  mkdir -p "$(dirname "$dest")"

  if [[ ! -f "$src" ]]; then
    log_error "${src} が見つかりません。vibecorp リポジトリが破損している可能性があります"
    return 1
  fi

  if [[ "$UPDATE_MODE" == true ]]; then
    # 旧 consumer 対応: ベースハッシュ未記録 + 既存独自エントリを保護する
    # テンプレートに含まれない行（ユーザー独自エントリ）を事前に抽出し、merge_or_overwrite 後に追記する
    local lock="${REPO_ROOT}/.claude/vibecorp.lock"
    local existing_custom_lines=""
    if [[ -f "$dest" ]]; then
      local base_hash
      base_hash=$(read_base_hash "$lock" ".gitignore")
      if [[ -z "$base_hash" ]]; then
        # `-F`（固定文字列）`-x`（行全体一致）`-v`（否定）: テンプレートに含まれない行のみ抽出
        existing_custom_lines=$(grep -vxF -f "$src" "$dest" || true)
      fi
    fi

    # merge_or_overwrite の失敗（3-way merge コンフリクト等）は警告を出して継続する
    if ! merge_or_overwrite "$src" "$dest" ".gitignore"; then
      log_skip "${dest} のマージに失敗しました（コンフリクトマーカーが混入している可能性があります）。当該ファイルを手動で確認してください"
    fi

    # 旧 consumer で存在した独自エントリを末尾に追記し、base snapshot を再更新する
    if [[ -n "$existing_custom_lines" ]]; then
      _ensure_trailing_newline "$dest"
      # merge 後の dest に残っていない独自行のみ追記（重複防止）
      local line
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! grep -qxF -- "$line" "$dest"; then
          printf '%s\n' "$line" >> "$dest"
        fi
      done <<< "$existing_custom_lines"
      log_info "${dest} に旧 consumer の独自エントリを復元しました"
    fi
  elif [[ -f "$dest" ]]; then
    # 新規 install で既存 .gitignore がある場合: ユーザー独自エントリを保持しつつ、vibecorp 管理エントリで不足しているものを追記する
    local added=0
    _ensure_trailing_newline "$dest"
    local tpl_line
    while IFS= read -r tpl_line; do
      # コメント行・空行はスキップ
      [[ -z "$tpl_line" || "$tpl_line" =~ ^[[:space:]]*# ]] && continue
      if ! grep -qxF -- "$tpl_line" "$dest"; then
        printf '%s\n' "$tpl_line" >> "$dest"
        added=1
      fi
    done < "$src"
    if [[ "$added" -eq 1 ]]; then
      log_info "${dest} に不足している vibecorp 管理エントリを追記"
    else
      log_skip "${dest} は既存のためスキップ（不足エントリなし）"
    fi
    # 次回 --update 時の 3-way merge 判定に必要なベースハッシュを記録
    save_base_snapshot "$src" ".gitignore"
  else
    cp "$src" "$dest"
    save_base_snapshot "$src" ".gitignore"
    log_info "${dest} を ${src} からコピー"
  fi
}

generate_claude_md() {
  local target="${REPO_ROOT}/.claude/CLAUDE.md"
  local src_template="${SCRIPT_DIR}/templates/CLAUDE.md.tpl"
  local rel_path="CLAUDE.md"

  local lang_display
  lang_display=$(resolve_language "$LANGUAGE")

  # 置換済みテンプレートを一時ファイルに出力し、以降のマージ/比較で使い回す
  local tmp_tpl
  tmp_tpl=$(mktemp)
  # 異常終了時にも tmp を掃除するため EXIT も対象にする。親の EXIT trap は退避・復元する。
  local prev_exit_trap
  prev_exit_trap=$(trap -p EXIT)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_tpl'" EXIT INT TERM

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{LANGUAGE}}|${lang_display}|g" \
    "$src_template" > "$tmp_tpl"

  if [[ ! -f "$target" ]]; then
    # 新規作成
    cp "$tmp_tpl" "$target"
    save_base_snapshot "$tmp_tpl" "$rel_path"
    log_info "CLAUDE.md を生成"
  elif [[ "$UPDATE_MODE" != true ]]; then
    # 通常インストールで既存ファイルあり → カスタマイズを保護
    log_skip "CLAUDE.md は既存のためスキップ"
  else
    # --update 時は 3-way マージまたはスキップ判定
    update_user_managed_file "$tmp_tpl" "$target" "$rel_path"
  fi

  rm -f "$tmp_tpl"
  if [[ -n "$prev_exit_trap" ]]; then
    eval "$prev_exit_trap"
  else
    trap - EXIT
  fi
  trap - INT TERM
}

generate_mvv_md() {
  local target="${REPO_ROOT}/MVV.md"
  local src_template="${SCRIPT_DIR}/templates/MVV.md.tpl"
  local rel_path="MVV.md"

  # 置換済みテンプレートを一時ファイルに出力
  local tmp_tpl
  tmp_tpl=$(mktemp)
  # 異常終了時にも tmp を掃除するため EXIT も対象にする。親の EXIT trap は退避・復元する。
  local prev_exit_trap
  prev_exit_trap=$(trap -p EXIT)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_tpl'" EXIT INT TERM

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    "$src_template" > "$tmp_tpl"

  if [[ ! -f "$target" ]]; then
    # 新規作成
    cp "$tmp_tpl" "$target"
    save_base_snapshot "$tmp_tpl" "$rel_path"
    log_info "MVV.md を生成"
  elif [[ "$UPDATE_MODE" != true ]]; then
    log_skip "MVV.md は既存のためスキップ"
  else
    update_user_managed_file "$tmp_tpl" "$target" "$rel_path"
  fi

  rm -f "$tmp_tpl"
  if [[ -n "$prev_exit_trap" ]]; then
    eval "$prev_exit_trap"
  else
    trap - EXIT
  fi
  trap - INT TERM
}

# --update 時に CLAUDE.md / MVV.md のようなユーザーカスタマイズ前提ファイルを
# 安全に更新するためのヘルパー。
# - 既存ファイルが置換済みテンプレートと一致 → ベーススナップショットのみ保存
# - ベーススナップショットありで差分あり → merge_or_overwrite（3-way マージ）に委譲
# - ベーススナップショットなしで差分あり → 上書きせず警告（手動マージを促す）
update_user_managed_file() {
  local tpl="$1"
  local target="$2"
  local rel_path="$3"
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"

  if cmp -s "$target" "$tpl"; then
    # 内容一致 → 次回のマージ判定用にベーススナップショットだけ保存
    save_base_snapshot "$tpl" "$rel_path"
    return
  fi

  local base_hash
  base_hash=$(read_base_hash "$lock" "$rel_path")

  local base_snapshot
  base_snapshot=$(get_base_snapshot "$rel_path")

  if [[ -n "$base_hash" && -n "$base_snapshot" ]]; then
    # ベースハッシュ・スナップショット両方あり → hash 整合性を検証してから 3-way マージ
    local snapshot_hash
    snapshot_hash=$(compute_hash "$base_snapshot")
    if [[ -n "$snapshot_hash" && "$snapshot_hash" != "$base_hash" ]]; then
      # スナップショットが lock の base_hash と不一致 → 信頼できないのでスキップ
      save_base_snapshot "$tpl" "$rel_path"
      local snapshot_path="${REPO_ROOT}/.claude/vibecorp-base/${rel_path}"
      log_skip "${rel_path} のベーススナップショットが base_hash と不一致のためスキップ"
      log_info "新テンプレートを反映する場合は手動でマージしてください: diff ${snapshot_path} ${target}"
      CONFLICT_FILES="${CONFLICT_FILES}  - ${rel_path}（ベーススナップショット不整合のためスキップ）"$'\n'
      return
    fi
    merge_or_overwrite "$tpl" "$target" "$rel_path" || true
  else
    # ベース情報が不完全（旧バージョンからの移行、またはスナップショット欠落）。
    # ユーザーカスタマイズが上書きで消えるのを防ぐため、テンプレートは適用せず手動マージを促す。
    # 次回の --update で 3-way マージが働くよう、現テンプレートをベースとして記録する。
    save_base_snapshot "$tpl" "$rel_path"
    local snapshot_path="${REPO_ROOT}/.claude/vibecorp-base/${rel_path}"
    log_skip "${rel_path} はカスタマイズ済みの可能性があり、ベース情報が不完全なためスキップ"
    log_info "新テンプレートを反映する場合は手動でマージしてください: diff ${snapshot_path} ${target}"
    CONFLICT_FILES="${CONFLICT_FILES}  - ${rel_path}（カスタマイズ保護のためスキップ）"$'\n'
  fi
}

# full プリセット用の事前警告（Issue #339）
# 警告 A: ANTHROPIC_API_KEY 検出時の従量課金警告（CFO 条件）
# 警告 B: macOS で sandbox 未有効時の推奨警告
# - minimal / standard では何も警告しない（API キー設定も無害）
# - 対話モード（[[ -t 0 ]] が true）: y/N プロンプトを出し、N または非 y なら exit 1
# - 非対話環境（CI 等）: 警告のみ stderr に出力して継続（インストールを止めない）
check_full_preset_warnings() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi

  # 警告 A: ANTHROPIC_API_KEY 検出時の従量課金警告
  # full プリセットのヘッドレス並列スキル（/ship-parallel, /autopilot, /spike-loop, /diagnose）は
  # API キー経由で起動されると Anthropic API の従量課金に到達するため、Claude Max 定額の利用を促す。
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    cat >&2 <<'WARN_API_KEY'

⚠️  ANTHROPIC_API_KEY が設定されています（従量課金リスク）

  full プリセットのヘッドレス並列スキル（/ship-parallel, /autopilot,
  /spike-loop, /diagnose）は、ANTHROPIC_API_KEY 経由で起動されると
  Anthropic API の従量課金に到達します。

  推奨:
  - Claude Max 定額プラン経由で起動する（環境変数を unset するか、
    Claude Code を Max ログインで使用する）
  - Anthropic Console (https://console.anthropic.com/) で
    使用量アラート（予算上限通知）を有効化する

  詳細は docs/cost-analysis.md の「実行モード別の課金モデル」を参照してください。

WARN_API_KEY
    if [[ -t 0 ]]; then
      printf '続行しますか? [y/N]: ' >&2
      local reply=""
      read -r reply
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *)
          log_error "ユーザーがインストール続行を拒否しました（ANTHROPIC_API_KEY 警告）"
          exit 1
          ;;
      esac
    fi
  fi

  # 警告 B: macOS で sandbox 未有効時の推奨警告
  # full プリセットの並列実行は sandbox + --dangerously-skip-permissions が前提で設計されている。
  # sandbox なしでも動作するが、並列実行時に承認ダイアログが多数発生する。
  # 「VIBECORP_ISOLATION 未設定」または「~/.zshrc / ~/.bashrc に activate.sh の source 記述なし」
  # のいずれかに該当すれば警告する（両方そろっていない限り推奨設定が完成していないため）。
  if [[ "$OS" == "darwin" ]]; then
    local rc_has_activate=false
    # 「activate.sh」を実際に source / . している行のみを検出する。
    # 単なる文字列一致だと、コメント行や文字列定数に "activate.sh" が含まれるだけで
    # 偽陽性（rc_has_activate=true）になり警告 B が誤って抑止されてしまう。
    # 正規表現: 行頭のオプショナルな空白 + (source|.) + 空白 + 任意 + activate.sh + 行末/空白
    local activate_source_re='^[[:space:]]*(source|\.)[[:space:]]+.*activate\.sh([[:space:]]|$)'
    if [[ -f "${HOME}/.zshrc" ]] && grep -Eq -- "$activate_source_re" "${HOME}/.zshrc" 2>/dev/null; then
      rc_has_activate=true
    fi
    if [[ -f "${HOME}/.bashrc" ]] && grep -Eq -- "$activate_source_re" "${HOME}/.bashrc" 2>/dev/null; then
      rc_has_activate=true
    fi

    if [[ -z "${VIBECORP_ISOLATION:-}" || "$rc_has_activate" == "false" ]]; then
      cat >&2 <<'WARN_SANDBOX'

⚠️  sandbox 隔離レイヤが未有効です（並列実行時の推奨設定）

  full プリセットの並列実行（/ship-parallel, /autopilot 等）は
  sandbox + --dangerously-skip-permissions の組み合わせが前提で設計されています。
  sandbox なしでも動作しますが、並列実行時に承認ダイアログが多数発生します。

  推奨設定（macOS）:
  1. インストール完了後に配置される .claude/bin/activate.sh を
     ~/.zshrc または ~/.bashrc から source する:
       echo 'source <repo>/.claude/bin/activate.sh' >> ~/.zshrc
  2. 現在のシェルで sandbox を有効化する:
       export VIBECORP_ISOLATION=1
  3. シェルを再起動する（または rc を再 source する）

  詳細は templates/claude/bin/activate.sh のヘッダコメントを参照してください。

WARN_SANDBOX
      if [[ -t 0 ]]; then
        printf '続行しますか? [y/N]: ' >&2
        local reply=""
        read -r reply
        case "$reply" in
          [yY]|[yY][eE][sS]) ;;
          *)
            log_error "ユーザーがインストール続行を拒否しました（sandbox 推奨警告）"
            exit 1
            ;;
        esac
      fi
    fi
  fi
}

print_completion() {
  local action="インストール"
  [[ "$UPDATE_MODE" == true ]] && action="更新"

  cat >&2 <<DONE

────────────────────────────────────────────
  vibecorp ${VIBECORP_VERSION} の${action}が完了しました
  プロジェクト: ${PROJECT_NAME}
  プリセット:   ${PRESET}
  リポジトリ:   ${REPO_ROOT}
────────────────────────────────────────────

DONE

  if [[ "$UPDATE_MODE" != true ]]; then
    cat >&2 <<PLUGIN

🔌 プラグインのセットアップ（初回のみ）

  Claude Code を起動し、以下を実行してください:
  /plugin marketplace add hirokimry/vibecorp
  /plugin install vibecorp@vibecorp --scope project

  これにより /vibecorp:* スキルが利用可能になります。

PLUGIN
  fi

  # コンフリクトが発生したファイル／カスタマイズ保護でスキップされたファイルがあれば警告表示
  if [[ -n "$CONFLICT_FILES" ]]; then
    cat >&2 <<CONFLICT
⚠️  以下のファイルは手動での確認が必要です:
${CONFLICT_FILES}
- 3-way マージでコンフリクトしたファイル: コンフリクトマーカー（<<<<<<<, =======, >>>>>>>）を検索して手動で解消してください
- 「カスタマイズ保護のためスキップ」と記されたファイル: ベース情報が不完全なため自動マージを行いませんでした。ログに表示された diff コマンドで現行ファイルと新テンプレートの差分を確認し、必要に応じて手動で取り込んでください

CONFLICT
  fi

  # full プリセット選択時の課金警告
  # 背景: full プリセットは C-suite + 分析員（計 14 ロール）を並列起動するため、
  # Claude Max のレート制限に到達すると ANTHROPIC_API_KEY 従量課金に自動フォールバックする。
  # 想定外の請求を防ぐため、install 完了時に課金モデルを明示する。
  if [[ "$PRESET" == "full" ]]; then
    cat >&2 <<BILLING
💰 課金モデルに関する注意（full プリセット）

  full プリセットは C-suite と分析員が並列で起動するため、
  Claude Max 定額プランのレート制限に到達しやすくなります。
  ANTHROPIC_API_KEY が設定されている場合、レート制限到達後は通知なしで
  API 従量課金（Anthropic 公式価格）にフォールバックします。

  詳細は docs/cost-analysis.md の「実行モード別の課金モデル」を参照してください。
  Anthropic Console (https://console.anthropic.com/) で使用量アラートの有効化を推奨します。

BILLING
  fi
}

# ── バージョン管理 ──────────────────────────────────────

checkout_target_version() {
  # --version 指定時に vibecorp リポジトリを指定バージョンに checkout する
  if [[ -z "$TARGET_VERSION" ]]; then
    return 0
  fi

  # 指定タグが存在するか確認
  if ! git -C "$SCRIPT_DIR" rev-parse "$TARGET_VERSION" >/dev/null 2>&1; then
    log_error "指定されたバージョン ${TARGET_VERSION} が見つかりません"
    log_error "利用可能なバージョン: $(git -C "$SCRIPT_DIR" tag -l 'v*' | sort -V | tr '\n' ' ')"
    exit 1
  fi

  # 現在のブランチ/コミットを記録（後で戻すため）
  # ブランチ名を優先し、detached HEAD の場合は SHA にフォールバック
  ORIGINAL_REF=$(git -C "$SCRIPT_DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse HEAD)

  log_info "vibecorp を ${TARGET_VERSION} に切り替え中..."
  git -C "$SCRIPT_DIR" checkout "$TARGET_VERSION" --quiet 2>/dev/null

  # exec で現在のプロセスが置き換わると trap EXIT が失われるため、exec 前に設定する
  trap 'restore_original_ref' EXIT

  # 無限ループ防止: 既に re-exec 済みならスキップ
  if [[ "${VIBECORP_REEXEC:-}" != "1" ]]; then
    # checkout 後の新バージョンの install.sh で再実行する
    export VIBECORP_REEXEC=1
    exec bash "${SCRIPT_DIR}/install.sh" "$@"
  fi

  # checkout 後の Git タグからバージョンを再取得
  local checked_out_version
  checked_out_version=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
  checked_out_version="${checked_out_version#v}"
  VIBECORP_VERSION="$checked_out_version"
}

restore_original_ref() {
  # --version 指定後、元のブランチ/コミットに戻す
  # ORIGINAL_REF にはブランチ名が優先保存されているため、detached HEAD にならない
  if [[ -n "${ORIGINAL_REF:-}" ]]; then
    git -C "$SCRIPT_DIR" checkout "$ORIGINAL_REF" --quiet 2>/dev/null || true
    unset ORIGINAL_REF
  fi
}

show_version_diff() {
  # --update 時にインストール済みバージョンと現在のバージョンの差分を表示する
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  [[ -f "$lock" ]] || return 0

  local installed_version
  installed_version=$(awk '/^version:/ { print $2 }' "$lock")

  if [[ -n "$installed_version" && "$installed_version" != "$VIBECORP_VERSION" ]]; then
    log_info "バージョン更新: ${installed_version} → ${VIBECORP_VERSION}"
  elif [[ -n "$installed_version" && "$installed_version" == "$VIBECORP_VERSION" ]]; then
    log_info "バージョン: ${VIBECORP_VERSION}（変更なし）"
  fi
}

# ── メイン ─────────────────────────────────────────────

main() {
  parse_args "$@"

  # OS 判定（Windows ネイティブ・unknown OS はここで exit 2 する）
  OS=$(detect_os)
  check_unsupported_os

  check_prerequisites
  detect_repo_root

  # --version 指定時は vibecorp リポジトリを指定バージョンに checkout
  # trap EXIT は checkout_target_version 内で exec 前に設定される
  checkout_target_version "$@"

  if [[ "$UPDATE_MODE" == true ]]; then
    fetch_latest_tags
    read_vibecorp_yml
    show_version_diff
  fi

  validate_name
  validate_preset
  validate_language

  # full プリセット用の事前警告（Issue #339）
  # ANTHROPIC_API_KEY 検出と sandbox 未有効を、隔離依存チェックの前にユーザーに告知する
  check_full_preset_warnings

  # full プリセット時は隔離レイヤの依存を確認（sandbox-exec 等）
  check_isolation_deps

  migrate_legacy_layout
  remove_managed_files
  copy_managed_files
  setup_xdg_cache_dirs
  copy_isolation_templates
  setup_claude_real_symlink
  generate_vibecorp_yml
  ensure_claude_action_section

  if [[ "$UPDATE_MODE" == true ]]; then
    update_vibecorp_yml
    migrate_forbidden_targets_skills
  fi

  generate_coderabbit_yaml
  generate_ci_workflow
  generate_review_md
  generate_ai_review_workflow
  generate_ai_review_golden_test_workflow
  configure_github_repo
  verify_claude_action_secrets
  setup_git_config

  generate_settings_json
  copy_rules
  copy_docs
  copy_knowledge
  copy_issue_templates
  copy_pr_template
  copy_workflows
  copy_close_on_feature_merge_workflow
  migrate_tracked_artifacts
  copy_claude_gitignore
  generate_claude_md
  generate_mvv_md
  create_labels
  generate_vibecorp_lock
  print_completion
}

# テストから source して内部関数（_extract_gitignore_artifacts 等）を直接呼び出せるよう、
# 直接実行時（bash install.sh）のみ main を起動する。source 時は関数定義のみ取り込む。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
