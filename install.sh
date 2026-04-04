#!/bin/bash
# install.sh — vibecorp プラグインインストーラー
# Usage: install.sh --name <project-name> [--preset minimal|standard|full] [--language ja|en|...] [--version v1.0.0]
#        install.sh --update [--preset minimal|standard|full]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Git タグからバージョンを動的取得（タグがない場合は開発版として扱う）
VIBECORP_VERSION=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
VIBECORP_VERSION="${VIBECORP_VERSION#v}"

# コピー済みファイル追跡用（lock 生成で使用）
COPIED_DOCS=""
COPIED_KNOWLEDGE=""
COPIED_RULES=""
COPIED_ISSUE_TEMPLATES=""

# ── ユーティリティ ─────────────────────────────────────

log_info()     { printf '\033[32m[INFO]\033[0m     %s\n' "$*" >&2; }
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
  --name      プロジェクト名（初回インストール時に必須）
  --update    既存インストールを更新（vibecorp.yml から設定を読み取る）
  --preset    組織プリセット: minimal, standard, full（デフォルト: minimal）
  --language  回答言語: ja, en, または任意（デフォルト: ja）
  --version   インストールする vibecorp のバージョン（例: v1.0.0）
  -h, --help  このヘルプを表示

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
    # ベーススナップショットがない場合は上書き（ユーザーに警告）
    log_merge "${rel_path} はカスタマイズ済みですが、ベーススナップショットがないため上書きします"
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

  # SIGINT/SIGTERM 時に tmp ファイルをクリーンアップする trap を設定
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_current' '$tmp_base' '$tmp_other'" INT TERM

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
  # trap をリセット
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

# ── ステップ関数 ───────────────────────────────────────

parse_args() {
  PROJECT_NAME=""
  PRESET=""
  LANGUAGE=""
  TARGET_VERSION=""
  UPDATE_MODE=false
  PRESET_SPECIFIED=false
  LANGUAGE_SPECIFIED=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--name に値が必要です"; usage; }; PROJECT_NAME="$2"; shift 2 ;;
      --update)   UPDATE_MODE=true; shift ;;
      --preset)   [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--preset に値が必要です"; usage; }; PRESET="$2"; PRESET_SPECIFIED=true; shift 2 ;;
      --language) [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--language に値が必要です"; usage; }; LANGUAGE="$2"; LANGUAGE_SPECIFIED=true; shift 2 ;;
      --version)  [[ $# -ge 2 && "$2" != --* && "$2" != -h ]] || { log_error "--version に値が必要です"; usage; }; TARGET_VERSION="$2"; shift 2 ;;
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

  mkdir -p "$hooks_dir" "$skills_dir"

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

  # skills: --update 時は SKILL.md を 3-way マージ、通常時は既存スキップ（yml で無効化されたものはスキップ）
  for src_dir in "${SCRIPT_DIR}/templates/claude/skills/"*/; do
    [[ -d "$src_dir" ]] || continue
    local name
    name=$(basename "$src_dir")
    if ! is_skill_enabled "$name"; then
      # --update 時は無効化されたスキルを削除（lock に記載されている場合のみ）
      if [[ "$UPDATE_MODE" == true ]]; then
        local lock="${REPO_ROOT}/.claude/vibecorp.lock"
        if [[ -f "$lock" ]] && read_lock_list "$lock" "skills" | grep -qxF "$name"; then
          rm -rf "${skills_dir:?}/${name:?}"
        fi
      fi
      log_skip "skills/${name} は yml で無効化されているためスキップ"
      continue
    fi
    if [[ "$UPDATE_MODE" == true ]]; then
      if [[ -d "${skills_dir}/${name}" ]]; then
        # SKILL.md を 3-way マージ、その他のファイルは上書き
        for src_file in "${src_dir}"*; do
          [[ -f "$src_file" ]] || continue
          local fname
          fname=$(basename "$src_file")
          if [[ "$fname" == "SKILL.md" ]]; then
            merge_or_overwrite "$src_file" "${skills_dir}/${name}/${fname}" "skills/${name}/${fname}" || true
          else
            cp "$src_file" "${skills_dir}/${name}/${fname}"
          fi
        done
      else
        cp -R "$src_dir" "${skills_dir}/${name}"
        # ベーススナップショットを保存
        for src_file in "${src_dir}"*; do
          [[ -f "$src_file" ]] || continue
          local fname
          fname=$(basename "$src_file")
          save_base_snapshot "$src_file" "skills/${name}/${fname}"
        done
      fi
    elif [[ -d "${skills_dir}/${name}" ]]; then
      log_skip "skills/${name} は既存のためスキップ"
    else
      cp -R "$src_dir" "${skills_dir}/${name}"
      # ベーススナップショットを保存
      for src_file in "${src_dir}"*; do
        [[ -f "$src_file" ]] || continue
        local fname
        fname=$(basename "$src_file")
        save_base_snapshot "$src_file" "skills/${name}/${fname}"
      done
    fi
  done

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

  # プレースホルダー置換
  # macOS 互換: sed ... > tmp && mv tmp original（sed -i の BSD/GNU 差異を回避）
  local target_dirs=("$hooks_dir" "$skills_dir")
  [[ -d "$agents_dir" ]] && target_dirs+=("$agents_dir")
  for dir in "${target_dirs[@]}"; do
    find "$dir" -type f \( -name '*.sh' -o -name '*.md' \) | while IFS= read -r f; do
      if grep -q '{{' "$f" 2>/dev/null; then
        sed \
          -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
          -e "s|{{PRESET}}|${PRESET}|g" \
          -e "s|{{LANGUAGE}}|$(resolve_language "$LANGUAGE")|g" \
          "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
      fi
    done
  done

  # hooks に実行権限を付与
  for f in "${hooks_dir}/"*.sh; do
    [[ -f "$f" ]] && chmod +x "$f"
  done

  # プリセット別削除（引き算方式）
  case "$PRESET" in
    minimal)
      rm -f "${hooks_dir}/review-to-rules-gate.sh"
      rm -f "${hooks_dir}/sync-gate.sh"
      rm -f "${hooks_dir}/session-harvest-gate.sh"
      rm -f "${hooks_dir}/review-gate.sh"
      rm -f "${hooks_dir}/role-gate.sh"
      rm -f "${hooks_dir}/diagnose-guard.sh"
      rm -rf "${skills_dir}/review-to-rules"
      rm -rf "${skills_dir}/sync-check"
      rm -rf "${skills_dir}/sync-edit"
      rm -rf "${skills_dir}/session-harvest"
      rm -rf "${skills_dir}/harvest-all"
      rm -rf "${skills_dir}/diagnose"
      rm -rf "${skills_dir}/context7"
      rm -rf "${agents_dir}"
      ;;
    standard)
      rm -f "${hooks_dir}/role-gate.sh"
      rm -f "${hooks_dir}/diagnose-guard.sh"
      rm -rf "${skills_dir}/diagnose"
      ;;
  esac

  log_info "テンプレートをコピー (preset: ${PRESET})"
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
  max_issues_per_run: 5
  max_issues_per_day: 10
  max_files_per_issue: 10
  scope: ""
  forbidden_targets:
    - "hooks/*.sh"
    - "vibecorp.yml"
    - "MVV.md"
    - "SECURITY.md"
    - "POLICY.md"
# plan:
#   review_agents:
#     - architect
#     - security
#     - testing
#     - performance
#     - dx
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
  for d in "${SCRIPT_DIR}/templates/claude/skills/"*/; do
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
  files_block+=$(_lock_list_section "hooks" "$hooks_list")
  files_block+=$(_lock_list_section "skills" "$skills_list")
  files_block+=$(_lock_list_section "agents" "$agents_list")
  files_block+=$(_lock_list_section "rules" "$rules_list")
  files_block+=$(_lock_list_section "issue_templates" "$issue_templates_list")
  files_block+=$(_lock_list_section "docs" "$docs_list")
  files_block+=$(_lock_list_section "knowledge" "$knowledge_list")
  files_block+=$(_lock_map_section "base_hashes" "$base_hashes")

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
          | .hooks |= [.[] | select((.command | contains("review-to-rules-gate") | not) and (.command | contains("sync-gate") | not) and (.command | contains("session-harvest-gate") | not) and (.command | contains("review-gate") | not) and (.command | contains("role-gate") | not) and (.command | contains("diagnose-guard") | not))]
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
    # 新規: フィルタ済みテンプレートをそのまま書き出し
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

    jq --argjson new "$new_hooks" --argjson managed "$managed_hooks_json" '
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
    ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    log_info "settings.json をマージ（ユーザーフック保持）"
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

generate_claude_gitignore() {
  local target="${REPO_ROOT}/.claude/.gitignore"

  # vibecorp が管理する除外エントリ
  local entries=("plans/" "vibecorp-base/" "lib/")

  if [[ -f "$target" ]]; then
    # 既存ファイルがある場合は不足エントリのみ追記（ユーザー独自エントリは保持）
    local added=0
    for entry in "${entries[@]}"; do
      if ! grep -qxF "$entry" "$target"; then
        echo "$entry" >> "$target"
        added=1
      fi
    done
    if [[ "$added" -eq 1 ]]; then
      log_info ".claude/.gitignore にエントリを追加"
    fi
    return
  fi

  cat > "$target" <<'GITIGNORE'
# 会話中の一時的な実装計画（git 追跡しない）
plans/
# アップデート時の 3-way マージ用ベーススナップショット
vibecorp-base/
# フック共通ライブラリ（テンプレートからコピーされる生成物）
lib/
GITIGNORE
  log_info ".claude/.gitignore を生成"
}

generate_claude_md() {
  local target="${REPO_ROOT}/.claude/CLAUDE.md"

  if [[ -f "$target" ]]; then
    log_skip "CLAUDE.md は既存のためスキップ"
    return
  fi

  local lang_display
  lang_display=$(resolve_language "$LANGUAGE")

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{LANGUAGE}}|${lang_display}|g" \
    "${SCRIPT_DIR}/templates/CLAUDE.md.tpl" > "$target"
  log_info "CLAUDE.md を生成"
}

generate_mvv_md() {
  local target="${REPO_ROOT}/MVV.md"

  if [[ -f "$target" ]]; then
    log_skip "MVV.md は既存のためスキップ"
    return
  fi

  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    "${SCRIPT_DIR}/templates/MVV.md.tpl" > "$target"
  log_info "MVV.md を生成"
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

  # コンフリクトが発生したファイルがある場合、警告を表示
  if [[ -n "$CONFLICT_FILES" ]]; then
    cat >&2 <<CONFLICT
⚠️  以下のファイルにコンフリクトが発生しています:
${CONFLICT_FILES}
コンフリクトマーカー（<<<<<<<, =======, >>>>>>>）を検索し、手動で解消してください。

CONFLICT
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
  remove_managed_files
  copy_managed_files
  generate_vibecorp_yml

  if [[ "$UPDATE_MODE" == true ]]; then
    update_vibecorp_yml
  fi

  generate_coderabbit_yaml
  generate_ci_workflow
  configure_github_repo

  generate_settings_json
  copy_rules
  copy_docs
  copy_knowledge
  copy_issue_templates
  copy_pr_template
  copy_workflows
  generate_claude_gitignore
  generate_claude_md
  generate_mvv_md
  create_labels
  generate_vibecorp_lock
  print_completion
}

main "$@"
