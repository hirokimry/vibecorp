#!/bin/bash
# test_no_direct_knowledge_writes.sh — Issue #439: knowledge への直接書込み記述を検出
# 各スキル定義 / エージェント定義に作業ブランチ直書きの記述（${BUFFER_DIR} を経由しない .claude/knowledge/ 言及）が
# 残っていないことを検証するスキャナ。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
WHITELIST="${TESTS_DIR}/whitelist_direct_knowledge_writes.txt"

echo "=== Issue #439: 直接書込み記述スキャナ ==="

# --- テスト1: ホワイトリストファイル存在 ---
if [[ -f "$WHITELIST" ]]; then
  pass "ホワイトリストファイルが存在する"
else
  fail "ホワイトリストファイルが存在しない"
  exit 1
fi

# ホワイトリストを配列に読み込む（コメントと空行を除外）
whitelist_paths=()
while IFS= read -r line; do
  case "$line" in
    \#*|"") continue ;;
  esac
  whitelist_paths+=("$line")
done < "$WHITELIST"

# is_whitelisted: パスがホワイトリストに含まれるか判定
is_whitelisted() {
  local target="$1"
  local rel="${target#${PROJECT_DIR}/}"
  local p
  for p in "${whitelist_paths[@]}"; do
    if [ "$rel" = "$p" ]; then
      return 0
    fi
  done
  return 1
}

# --- テスト2: スキル定義の検査 ---
echo ""
echo "--- テスト2: skills/**/SKILL.md の検査 ---"

violations=0
for skill_file in "${PROJECT_DIR}"/skills/*/SKILL.md; do
  if is_whitelisted "$skill_file"; then
    continue
  fi

  rel="${skill_file#${PROJECT_DIR}/}"
  # 検出パターン: 「書込みコンテキスト」での `.claude/knowledge/{role}/decisions/` 系列
  # 「書込みコンテキスト」とは:
  #   - cp / mv コマンドで宛先として書く
  #   - `>` リダイレクトで書き込む
  #   - 「に書く」「に追記」「に保存」「に作成」等の日本語の書込み動詞と同一行
  # 単なる参照リンク（「- 設計判断: `<path>`」「参照:」「Read」「読み込む」等）は対象外
  matches="$(grep -nE '`[^`$]*\.claude/knowledge/[^`]*/(decisions/|decisions-index|audit-log/)' "$skill_file" \
    | grep -v '\${BUFFER_DIR}' \
    | grep -v '#' \
    | grep -v -E '^[0-9]+:- 設計判断: ' \
    | grep -v -E '^[0-9]+:- 参照: ' \
    | grep -v -E '^[0-9]+:[[:space:]]*-[[:space:]]+`\.claude/knowledge/' \
    | grep -E '(に書く|に追記|に保存|に作成|^[0-9]+:[^:]*\b(cp|mv|cat|Write|Edit)\b|>)' \
    || true)"

  if [ -n "$matches" ]; then
    fail "${rel} に作業ブランチ直書きパス言及（書込みコンテキスト）がある"
    echo "$matches" | head -3 | sed 's/^/    /'
    violations=$((violations + 1))
  fi
done

if [ "$violations" -eq 0 ]; then
  pass "全 SKILL.md に作業ブランチ直書きパス言及が無い"
fi

# --- テスト3: エージェント定義の検査 ---
echo ""
echo "--- テスト3: templates/claude/agents/*.md の検査 ---"

violations=0
for agent_file in "${PROJECT_DIR}"/templates/claude/agents/*.md; do
  if is_whitelisted "$agent_file"; then
    continue
  fi

  rel="${agent_file#${PROJECT_DIR}/}"

  # 「判断の記録」セクション内のレガシー互換セクションを除外したテキストで検査
  # awk セクション境界判定:
  # - 「### N. 判断の記録」開始
  # - 次の「### N. 」または末尾で終了
  # - その範囲内で「**レガシー互換**:」セクションを除外
  filtered="$(awk '
    /^### [0-9]+\. 判断の記録$/ { in_section = 1; next }
    in_section && /^### / { in_section = 0 }
    in_section && /\*\*レガシー互換\*\*:/ { in_legacy = 1; next }
    in_section && in_legacy && /^\*\*[^*]+\*\*:/ { in_legacy = 0; print; next }
    in_section && in_legacy { next }
    in_section { print }
  ' "$agent_file")"

  # フィルタ済みテキストで作業ブランチ直書きパスの言及をチェック
  if echo "$filtered" | grep -nE '`[^`$]*\.claude/knowledge/[^`]*/(decisions/|decisions-index)' \
     | grep -v '\${BUFFER_DIR}' >/dev/null 2>&1; then
    fail "${rel} の判断の記録節に作業ブランチ直書きパス言及がある"
    echo "$filtered" | grep -nE '`[^`$]*\.claude/knowledge/[^`]*/(decisions/|decisions-index)' \
      | grep -v '\${BUFFER_DIR}' | head -3 | sed 's/^/    /'
    violations=$((violations + 1))
  fi
done

if [ "$violations" -eq 0 ]; then
  pass "全 C*O 定義（レガシー互換除外後）に作業ブランチ直書きパス言及が無い"
fi

print_test_summary
