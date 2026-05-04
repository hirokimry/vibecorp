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

is_hook_enabled() {
  # vibecorp.yml の hooks セクションを参照し、有効かどうかを返す
  is_item_enabled "hooks" "$1"
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

get_disabled_hooks() {
  # vibecorp.yml の hooks セクションから無効化された hook 名の JSON 配列を返す
  # settings.json の jq フィルタで使用する
  local yml="${REPO_ROOT}/.claude/vibecorp.yml"

  if [[ ! -f "$yml" ]]; then
    echo "[]"
    return
  fi

  awk '
    /^hooks:/ { in_hooks = 1; next }
    in_hooks && /^[^ #]/ { exit }
    in_hooks && $2 == "false" {
      key = $1
      gsub(/:$/, "", key)
      gsub(/^[ \t]+/, "", key)
      print key
    }
  ' "$yml" | jq -R -s 'split("\n") | map(select(length > 0))'
}

get_orphan_hooks() {
  # .claude/vibecorp.lock に記載されているが templates/claude/hooks/ に実体がない
  # hook 名（basename）を 1 行 1 件で stdout に出力する。
  # vibecorp 開発側で廃止された hook（例: team-auto-approve.sh）を検出するために使う。
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local templates_hooks_dir="${SCRIPT_DIR}/templates/claude/hooks"

  [[ -f "$lock" ]] || return 0

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ ! -f "${templates_hooks_dir}/${name}" ]]; then
      echo "$name"
    fi
  done < <(read_lock_list "$lock" "hooks")
}

remove_orphan_hooks() {
  # lock 記載かつ templates 実体なしの hook を .claude/hooks/ から物理削除する。
  # --update モードでのみ呼ぶ前提。
  # settings.json からのエントリ除去は generate_settings_json の既存マージロジックが担当する
  # （lock 基準の managed_hooks_json で既存エントリを除去 → 新テンプレートと結合）。
  local hooks_dir="${REPO_ROOT}/.claude/hooks"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    # lock 改ざん時の防御: パス区切り文字を含む name は拒否（basename のみ許可）
    [[ "$name" == */* ]] && continue
    if [[ -f "${hooks_dir:?}/${name:?}" ]]; then
      rm -f "${hooks_dir:?}/${name:?}"
      log_info "hooks/${name} は廃止されたため削除"
    fi
  done < <(get_orphan_hooks)
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
      exit 2
      ;;
    unknown)
      log_error "サポート外の OS です（$(uname -s)）。macOS または Linux を使用してください。"
      exit 2
      ;;
  esac
}

# 隔離レイヤの依存を確認する（full プリセット時のみ呼ばれる）
# Darwin は sandbox-exec の存在を検証、Linux は現在未対応のためスキップ
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
      log_skip "Linux 隔離レイヤは現在未対応のためスキップします"
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

remove_managed_files() {
  # lock に記載された vibecorp 管理ファイルを削除
  # --update 時は hooks/skills を 3-way マージ対象として保持する
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"
  local hooks_dir="${REPO_ROOT}/.claude/hooks"
  local skills_dir="${REPO_ROOT}/.claude/skills"
  local agents_dir="${REPO_ROOT}/.claude/agents"

  [[ -f "$lock" ]] || return 0

  if [[ "$UPDATE_MODE" != true ]]; then
    # 再インストール（--name）時は管理ファイルを削除して再配置
    while IFS= read -r name; do
      [[ -n "$name" ]] && rm -f "${hooks_dir:?}/${name:?}"
    done < <(read_lock_list "$lock" "hooks")

    while IFS= read -r name; do
      [[ -n "$name" ]] && rm -rf "${skills_dir:?}/${name:?}"
    done < <(read_lock_list "$lock" "skills")
  fi
  # --update 時は hooks/skills を削除しない（merge_or_overwrite で処理）

  # lock 記載の agents を削除（agents は 3-way マージ対象外）
  while IFS= read -r name; do
    [[ -n "$name" ]] && rm -f "${agents_dir}/${name}"
  done < <(read_lock_list "$lock" "agents")

  # knowledge は運用中にユーザーが蓄積するデータのため削除しない

  log_info "管理ファイルを整理（lock ベース）"
}

copy_managed_files() {
  # テンプレートをコピー（既存ユーザーファイルはスキップ）
  local hooks_dir="${REPO_ROOT}/.claude/hooks"
  local skills_dir="${REPO_ROOT}/.claude/skills"
  local agents_dir="${REPO_ROOT}/.claude/agents"

  mkdir -p "$hooks_dir"

  # lib: フック共通ユーティリティをコピー（常に最新で上書き）
  local lib_dir="${REPO_ROOT}/.claude/lib"
  if [[ -d "${SCRIPT_DIR}/templates/claude/lib" ]]; then
    mkdir -p "$lib_dir"
    for src in "${SCRIPT_DIR}/templates/claude/lib/"*.sh; do
      [[ -f "$src" ]] || continue
      cp "$src" "${lib_dir}/$(basename "$src")"
    done
  fi

  # hooks: --update 時は 3-way マージ、通常時は既存スキップ（yml で無効化されたものはスキップ）
  for src in "${SCRIPT_DIR}/templates/claude/hooks/"*.sh; do
    [[ -f "$src" ]] || continue
    local name
    name=$(basename "$src")
    local hook_key="${name%.sh}"
    if ! is_hook_enabled "$hook_key"; then
      # --update 時は無効化されたフックを削除（lock に記載されている場合のみ）
      if [[ "$UPDATE_MODE" == true ]]; then
        local lock="${REPO_ROOT}/.claude/vibecorp.lock"
        if [[ -f "$lock" ]] && read_lock_list "$lock" "hooks" | grep -qxF "$name"; then
          rm -f "${hooks_dir}/${name}"
        fi
      fi
      log_skip "hooks/${name} は yml で無効化されているためスキップ"
      continue
    fi
    if [[ "$UPDATE_MODE" == true ]]; then
      merge_or_overwrite "$src" "${hooks_dir}/${name}" "hooks/${name}" || true
    elif [[ -f "${hooks_dir}/${name}" ]]; then
      log_skip "hooks/${name} は既存のためスキップ"
    else
      cp "$src" "${hooks_dir}/${name}"
      save_base_snapshot "$src" "hooks/${name}"
    fi
  done

  # --update: テンプレートから廃止された hook（lock 記載 + templates 不在）を削除
  if [[ "$UPDATE_MODE" == true ]]; then
    remove_orphan_hooks
  fi

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

  # agents: 同名ファイルが既存ならスキップ
  if [[ -d "${SCRIPT_DIR}/templates/claude/agents" ]]; then
    mkdir -p "$agents_dir"
    for src in "${SCRIPT_DIR}/templates/claude/agents/"*.md; do
      [[ -f "$src" ]] || continue
      local name
      name=$(basename "$src")
      if [[ -f "${agents_dir}/${name}" ]]; then
        log_skip "agents/${name} は既存のためスキップ"
      else
        cp "$src" "${agents_dir}/${name}"
      fi
    done
  fi

  # .claude-plugin/plugin.json: プラグインメタデータ（常に最新で上書き）
  if [[ -f "${SCRIPT_DIR}/templates/claude-plugin/plugin.json" ]]; then
    mkdir -p "${REPO_ROOT}/.claude-plugin"
    cp "${SCRIPT_DIR}/templates/claude-plugin/plugin.json" "${REPO_ROOT}/.claude-plugin/plugin.json"
  fi

  # プレースホルダー置換
  # macOS 互換: sed ... > tmp && mv tmp original（sed -i の BSD/GNU 差異を回避）
  local target_dirs=("$hooks_dir")
  [[ -d "$skills_dir" ]] && target_dirs+=("$skills_dir")
  [[ -d "$agents_dir" ]] && target_dirs+=("$agents_dir")
  local placeholder_errors=0
  for dir in "${target_dirs[@]}"; do
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

  # hooks に実行権限を付与
  for f in "${hooks_dir}/"*.sh; do
    [[ -f "$f" ]] && chmod +x "$f"
  done

  # 全プリセット共通レガシー clean-up: 廃止済みスキル・フックを除去（#343 spike-loop 等）
  rm -rf "${skills_dir}/spike-loop"

  # プリセット別削除（引き算方式）
  case "$PRESET" in
    minimal)
      # レガシー clean-up: 旧バージョンのインストールが残した古いフック/スキル
      rm -f "${hooks_dir}/review-to-rules-gate.sh"
      rm -rf "${skills_dir}/review-to-rules"
      # 現行: minimal プリセットから除外するフック/スキル
      rm -f "${hooks_dir}/sync-gate.sh"
      rm -f "${hooks_dir}/session-harvest-gate.sh"
      rm -f "${hooks_dir}/review-gate.sh"
      rm -f "${hooks_dir}/guide-gate.sh"
      rm -f "${hooks_dir}/role-gate.sh"
      rm -f "${hooks_dir}/diagnose-guard.sh"
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
      rm -rf "${agents_dir}"
      # 隔離レイヤは full 専用。vibecorp が配置した既知ファイルのみ削除し、
      # ディレクトリが空になったら rmdir（ユーザー独自配置は rmdir 失敗で保持される）
      rm -f "${REPO_ROOT}/.claude/bin/claude"
      rm -f "${REPO_ROOT}/.claude/bin/claude-real"
      rm -f "${REPO_ROOT}/.claude/bin/vibecorp-sandbox"
      rm -f "${REPO_ROOT}/.claude/bin/activate.sh"
      rm -f "${REPO_ROOT}/.claude/sandbox/claude.sb"
      rmdir "${REPO_ROOT}/.claude/bin" 2>/dev/null || true
      rmdir "${REPO_ROOT}/.claude/sandbox" 2>/dev/null || true
      ;;
    standard)
      rm -f "${hooks_dir}/role-gate.sh"
      rm -f "${hooks_dir}/diagnose-guard.sh"
      rm -rf "${skills_dir}/diagnose"
      # ヘッドレス並列スキルは full プリセット専用（隔離レイヤが full でしか効かないため）
      rm -rf "${skills_dir}/ship-parallel"
      rm -rf "${skills_dir}/autopilot"
      # エピック化スキルは full プリセット専用（3 者承認ゲートで CISO/CPO/SM が必須なため）
      rm -rf "${skills_dir}/plan-epic"
      # エピックリリーススキルは full プリセット専用（エピック運用は full でのみ整備）
      rm -rf "${skills_dir}/release-epic"
      # plan-cost / plan-legal は full プリセット限定
      rm -f "${agents_dir}/plan-cost.md"
      rm -f "${agents_dir}/plan-legal.md"
      # 隔離レイヤは full 専用。vibecorp が配置した既知ファイルのみ削除し、
      # ディレクトリが空になったら rmdir（ユーザー独自配置は rmdir 失敗で保持される）
      rm -f "${REPO_ROOT}/.claude/bin/claude"
      rm -f "${REPO_ROOT}/.claude/bin/claude-real"
      rm -f "${REPO_ROOT}/.claude/bin/vibecorp-sandbox"
      rm -f "${REPO_ROOT}/.claude/bin/activate.sh"
      rm -f "${REPO_ROOT}/.claude/sandbox/claude.sb"
      rmdir "${REPO_ROOT}/.claude/bin" 2>/dev/null || true
      rmdir "${REPO_ROOT}/.claude/sandbox" 2>/dev/null || true
      ;;
  esac

  log_info "テンプレートをコピー (preset: ${PRESET})"
}

# 隔離レイヤ（bin/sandbox）を配置する。full + Darwin のみ動作。
# Linux は Phase 2 (#310) で bwrap 対応を追加予定のため、現時点ではスキップ。
copy_isolation_templates() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi
  if [[ "$OS" != "darwin" ]]; then
    return 0
  fi

  local bin_dir="${REPO_ROOT}/.claude/bin"
  local sandbox_dir="${REPO_ROOT}/.claude/sandbox"
  mkdir -p "$bin_dir" "$sandbox_dir"

  local src
  for src in "${SCRIPT_DIR}/templates/claude/bin/"*; do
    # symlink はサプライチェーン侵害時の任意ファイル配置経路になるため明示除外する
    [[ -f "$src" && ! -L "$src" ]] || continue
    local name
    name=$(basename "$src")
    cp "$src" "${bin_dir}/${name}"
    chmod +x "${bin_dir}/${name}"
    # ベーススナップショットを記録し、--update 時の 3-way マージ判定を有効化する
    save_base_snapshot "$src" "bin/${name}"
    log_info "隔離レイヤを配置: .claude/bin/${name}"
  done

  for src in "${SCRIPT_DIR}/templates/claude/sandbox/"*; do
    # symlink はサプライチェーン侵害時の任意ファイル配置経路になるため明示除外する
    [[ -f "$src" && ! -L "$src" ]] || continue
    local name
    name=$(basename "$src")
    cp "$src" "${sandbox_dir}/${name}"
    save_base_snapshot "$src" "sandbox/${name}"
    log_info "隔離レイヤを配置: .claude/sandbox/${name}"
  done
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

# 隔離レイヤラッパーが exec する `claude-real` symlink を配置する。full + Darwin のみ動作。
# templates/claude/bin/claude は `exec claude-real "$@"` する設計のため、
# ラッパー自身を除外して PATH 上の本物 claude を検出し、`.claude/bin/claude-real` に symlink する。
# 検出失敗時は警告のみ出してインストールを続行する（passthrough は引き続き利用可能）。
setup_claude_real_symlink() {
  if [[ "$PRESET" != "full" ]]; then
    return 0
  fi
  if [[ "$OS" != "darwin" ]]; then
    return 0
  fi

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
$(generate_plan_yaml_section)
YAML
  log_info "vibecorp.yml を生成"
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

  sed \
    -e "s|{{LANGUAGE}}|${lang_code}|g" \
    "$template" > "$target"
  log_info ".coderabbit.yaml を生成"
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

  local protection_json
  protection_json=$(jq -n \
    --argjson contexts "$merged_contexts" \
    '{
      required_status_checks: {
        strict: true,
        contexts: $contexts
      },
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false,
        require_last_push_approval: false,
        required_approving_review_count: 1
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
    log_info "ブランチ保護を設定（${base_branch}: CI必須、PR必須、approve必須）"
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
         gh secret set CLAUDE_CODE_OAUTH_TOKEN
       詳細: docs/ai-review-auth.md
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
  local hooks_list="" skills_list="" agents_list="" rules_list="" issue_templates_list="" docs_list="" knowledge_list=""

  # テンプレートに存在し、プリセット削除後も残っているファイルを記録
  for f in "${SCRIPT_DIR}/templates/claude/hooks/"*.sh; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    # 実際に配置先に存在するもののみ記録（プリセット削除分を除外）
    [[ -f "${REPO_ROOT}/.claude/hooks/${name}" ]] && hooks_list="${hooks_list}    - ${name}"$'\n'
  done
  for d in "${SCRIPT_DIR}/skills/"*/; do
    [[ -d "$d" ]] || continue
    local name
    name=$(basename "$d")
    [[ -d "${REPO_ROOT}/.claude/skills/${name}" ]] && skills_list="${skills_list}    - ${name}"$'\n'
  done
  for f in "${SCRIPT_DIR}/templates/claude/agents/"*.md; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f")
    [[ -f "${REPO_ROOT}/.claude/agents/${name}" ]] && agents_list="${agents_list}    - ${name}"$'\n'
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
  files_block+="$(_lock_list_section "hooks" "$hooks_list")"$'\n'
  files_block+="$(_lock_list_section "skills" "$skills_list")"$'\n'
  files_block+="$(_lock_list_section "agents" "$agents_list")"$'\n'
  files_block+="$(_lock_list_section "rules" "$rules_list")"$'\n'
  files_block+="$(_lock_list_section "issue_templates" "$issue_templates_list")"$'\n'
  files_block+="$(_lock_list_section "docs" "$docs_list")"$'\n'
  files_block+="$(_lock_list_section "knowledge" "$knowledge_list")"$'\n'
  files_block+="$(_lock_map_section "base_hashes" "$base_hashes")"$'\n'

  cat > "$lock" <<YAML
# vibecorp.lock — 自動生成、手動編集禁止
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
  local settings="${REPO_ROOT}/.claude/settings.json"
  local template="${SCRIPT_DIR}/templates/settings.json.tpl"
  local lock="${REPO_ROOT}/.claude/vibecorp.lock"

  # テンプレートにプリセットフィルタを適用
  local new_settings
  new_settings=$(cat "$template")

  case "$PRESET" in
    minimal)
      new_settings=$(echo "$new_settings" | jq '
        .hooks.PreToolUse |= [
          .[]
          | .hooks |= [.[] | select((.command | contains("review-to-rules-gate") | not) and (.command | contains("sync-gate") | not) and (.command | contains("session-harvest-gate") | not) and (.command | contains("review-gate") | not) and (.command | contains("guide-gate") | not) and (.command | contains("role-gate") | not) and (.command | contains("diagnose-guard") | not))]
          | select((.hooks | length) > 0)
        ]
      ')
      ;;
    standard)
      new_settings=$(echo "$new_settings" | jq '
        .hooks.PreToolUse |= [
          .[]
          | .hooks |= [.[] | select((.command | contains("role-gate") | not) and (.command | contains("diagnose-guard") | not))]
          | select((.hooks | length) > 0)
        ]
      ')
      ;;
  esac

  # yml で無効化された hooks を settings.json からも除外
  local disabled_hooks_json
  disabled_hooks_json=$(get_disabled_hooks)
  if [[ "$disabled_hooks_json" != "[]" ]]; then
    new_settings=$(echo "$new_settings" | jq --argjson disabled "$disabled_hooks_json" '
      .hooks.PreToolUse |= [
        .[]
        | .hooks |= [.[] | select(
            (.command | split("/") | last | gsub("\\.sh$";"") | gsub("^\"";"";"g")) as $hook_name |
            any($disabled[]; . == $hook_name) | not
          )]
        | select((.hooks | length) > 0)
      ]
    ')
  fi

  if [[ ! -f "$settings" ]]; then
    # 新規: フィルタ済みテンプレートをそのまま書き出し（permissions / hooks 両方）
    echo "$new_settings" | jq '.' > "$settings"
    log_info "settings.json を生成"
  else
    # 既存: lock のフック名リストで vibecorp 管理判定（パス文字列判定をやめる）
    local managed_hooks_json="[]"
    if [[ -f "$lock" ]]; then
      # lock 記載のフック名から jq フィルタ用の JSON 配列を生成
      managed_hooks_json=$(read_lock_list "$lock" "hooks" | jq -R -s 'split("\n") | map(select(length > 0))')
    fi

    local new_hooks
    new_hooks=$(echo "$new_settings" | jq '.hooks.PreToolUse')
    local new_permissions_allow
    new_permissions_allow=$(echo "$new_settings" | jq '.permissions.allow // []')
    local new_marketplaces
    new_marketplaces=$(echo "$new_settings" | jq '.extraKnownMarketplaces // {}')
    local new_enabled_plugins
    new_enabled_plugins=$(echo "$new_settings" | jq '.enabledPlugins // {}')

    jq --argjson new "$new_hooks" --argjson managed "$managed_hooks_json" \
       --argjson new_allow "$new_permissions_allow" \
       --argjson new_mkts "$new_marketplaces" --argjson new_plugins "$new_enabled_plugins" '
      def is_managed_hook:
        (.command | split("/") | last) as $basename |
        any($managed[]; . == $basename);
      def strip_managed_hooks:
        .hooks |= map(select(is_managed_hook | not));
      # 既存から vibecorp 管理フックを除去し、新規と結合後、同一 matcher をマージ
      # 結合後に同一 command の重複を排除（lock 未登録フックとテンプレートの衝突防止）
      .hooks.PreToolUse = (
        [(.hooks.PreToolUse // [])[] | strip_managed_hooks | select((.hooks | length) > 0)]
        + $new
        | group_by(.matcher)
        | map({matcher: .[0].matcher, hooks: ([.[].hooks[]] | unique_by(.command))})
      )
      | .permissions = ((.permissions // {}) | .allow = (((.allow // []) + $new_allow) | unique))
      | .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) + $new_mkts)
      | .enabledPlugins = ((.enabledPlugins // {}) + $new_plugins)
    ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    log_info "settings.json をマージ（ユーザーフック・permissions・marketplace 保持）"
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
    if [[ -f "${dest}/${name}" ]]; then
      log_skip "workflows/${name} は既存のためスキップ"
    else
      cp "$f" "${dest}/${name}"
    fi
  done

  log_info "ワークフローをコピー"
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
      gh label create "$label_name" --color "$label_color" --description "$label_desc" 2>/dev/null \
        && log_info "ラベル '${label_name}' を作成" \
        || log_skip "ラベル '${label_name}' の作成に失敗（スキップ）"
    fi
  done
}

copy_rules() {
  local src="${SCRIPT_DIR}/templates/claude/rules"
  local dest="${REPO_ROOT}/.claude/rules"
  mkdir -p "$dest"

  for rule in "${src}"/*.md; do
    local basename
    basename=$(basename "$rule")
    if [[ "$UPDATE_MODE" == true ]]; then
      merge_or_overwrite "$rule" "${dest}/${basename}" "rules/${basename}" || true
      COPIED_RULES="${COPIED_RULES}${basename}"$'\n'
    elif [[ -f "${dest}/${basename}" ]]; then
      log_skip "rules/${basename} は既存のためスキップ"
    else
      cp "$rule" "${dest}/${basename}"
      save_base_snapshot "$rule" "rules/${basename}"
      COPIED_RULES="${COPIED_RULES}${basename}"$'\n'
      log_info "rules/${basename} をコピー"
    fi
  done
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

  # full プリセット時は隔離レイヤの依存を確認（sandbox-exec 等）
  check_isolation_deps

  remove_managed_files
  copy_managed_files
  setup_xdg_cache_dirs
  copy_isolation_templates
  setup_claude_real_symlink
  generate_vibecorp_yml

  if [[ "$UPDATE_MODE" == true ]]; then
    update_vibecorp_yml
  fi

  generate_coderabbit_yaml
  generate_ci_workflow
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
