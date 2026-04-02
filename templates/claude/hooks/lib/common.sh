#!/bin/bash
# common.sh — フック間の共通関数ライブラリ
# 各フックから source して使用する

# vibecorp.yml からプロジェクト名を取得し、サニタイズして返す
# デフォルト値: vibecorp-project
# 使い方: PROJECT_NAME=$(get_project_name)
get_project_name() {
  local vibecorp_yml="${CLAUDE_PROJECT_DIR:-.}/.claude/vibecorp.yml"
  local project_name="vibecorp-project"
  if [ -f "$vibecorp_yml" ]; then
    local raw_name
    raw_name=$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$vibecorp_yml")
    if [ -n "${raw_name:-}" ]; then
      project_name=$(printf '%s' "$raw_name" | tr -cs 'A-Za-z0-9._-' '_')
    fi
  fi
  printf '%s' "$project_name"
}
