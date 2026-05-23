#!/bin/bash
# path_normalize.sh — protect-knowledge-direct-writes.sh と protect-knowledge-bash-writes.sh が
# 共通で使うパス正規化ヘルパー（DRY 化、Issue #448）
#
# 使い方: source "${HOOK_DIR}/../lib/path_normalize.sh"
#
# - realpath -m が使える環境では realpath を優先
# - macOS BSD 等で利用不能な場合は Python フォールバック
# - Python コード内に変数展開を埋め込まず引数渡しでインジェクション回避

_pkw_normalize_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    realpath -m -- "$p"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p"
  else
    return 1
  fi
}
