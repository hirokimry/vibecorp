#!/bin/bash
# test_co_decisions_buffer.sh — Issue #439: C*O 6 エージェントが決定記録を buffer worktree 経由に書くことを検証

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
AGENTS_DIR="${PROJECT_DIR}/templates/claude/agents"

echo "=== Issue #439: C*O 決定記録 buffer 化テスト ==="

# 6 ロール全てに対して同一パターンを検証
for role in cfo cto cpo ciso clo sm; do
  agent_file="${AGENTS_DIR}/${role}.md"

  echo ""
  echo "--- ${role} エージェント定義の検証 ---"

  if [[ ! -f "$agent_file" ]]; then
    fail "${role}.md が存在しない"
    continue
  fi
  pass "${role}.md が存在する"

  # BUFFER_DIR 注入の前提が記述されている
  assert_file_contains "${role}: BUFFER_DIR 注入の前提が記述されている" "$agent_file" '${BUFFER_DIR}'

  # フォールバック分岐がある
  assert_file_contains "${role}: フォールバックで knowledge_buffer_ensure を呼ぶ" "$agent_file" 'knowledge_buffer_ensure'
  assert_file_contains "${role}: フォールバック失敗時に BUFFER_DIR=\"\" で書込みスキップ" "$agent_file" 'BUFFER_DIR=""'

  # 書込先が ${BUFFER_DIR}/.claude/knowledge/{role}/decisions/ に変更されている
  assert_file_contains "${role}: decisions 書込先が \${BUFFER_DIR}/.claude/knowledge/${role}/decisions/ である" "$agent_file" '${BUFFER_DIR}/.claude/knowledge/'"${role}"'/decisions'
  assert_file_contains "${role}: decisions-index 書込先が \${BUFFER_DIR}/.claude/knowledge/${role}/decisions-index.md である" "$agent_file" '${BUFFER_DIR}/.claude/knowledge/'"${role}"'/decisions-index.md'

  # フォールバック失敗時の厳格ヘッダ指定
  assert_file_contains "${role}: 厳格ヘッダ「### 判断記録（記録先取得失敗）」が指定されている" "$agent_file" '### 判断記録（記録先取得失敗）'
  assert_file_contains "${role}: ヘッダ名厳格指定の警告がある" "$agent_file" 'ヘッダー名は厳格指定'

  # 「判断の記録」節（4. または 5.）に作業ブランチ直書き相対パスが残っていないことを確認
  # 判定: 「### 判断の記録」見出しから次の「### 」見出しまでの範囲で
  #       `\.claude/knowledge/{role}/decisions/` の作業ブランチ直書き相対パスが行頭付近に存在しないこと
  decisions_section="$(awk -v role="$role" '
    /^### [0-9]+\. 判断の記録$/ { in_section = 1; next }
    in_section && /^### / { in_section = 0 }
    in_section { print }
  ' "$agent_file")"

  # ${BUFFER_DIR} を含まない `.claude/knowledge/{role}/decisions/` 相対パス言及（バックティック内）が無いこと
  if echo "$decisions_section" | grep -E '`\.claude/knowledge/'"${role}"'/decisions[/.]' >/dev/null 2>&1; then
    # ただし、レガシー互換セクションは除外（次の太字見出しで legacy を閉じる）
    legacy_match="$(echo "$decisions_section" | awk '
      /\*\*レガシー互換\*\*:/ { in_legacy = 1; next }
      in_legacy && /^\*\*[^*]+\*\*:/ { in_legacy = 0; print; next }
      in_legacy { next }
      { print }
    ')"
    if echo "$legacy_match" | grep -E '`\.claude/knowledge/'"${role}"'/decisions[/.]' >/dev/null 2>&1; then
      fail "${role}: 判断の記録節（レガシー互換除外）に作業ブランチ直書きパスが残っている"
    else
      pass "${role}: 判断の記録節に作業ブランチ直書きパスがない（レガシー互換除く）"
    fi
  else
    pass "${role}: 判断の記録節に作業ブランチ直書きパスがない"
  fi
done

# --- Issue #448: C*O 6 ロールに Edit/Write/MultiEdit が tools として宣言されている ---
echo ""
echo "--- Issue #448: tools フィールド検証 ---"

for role in cfo cto cpo ciso clo sm; do
  agent_file="${AGENTS_DIR}/${role}.md"
  if [ ! -f "$agent_file" ]; then
    fail "${role}: agent file が存在しない"
    continue
  fi
  tools_line="$(grep '^tools:' "$agent_file" || echo "")"
  if [ -z "$tools_line" ]; then
    fail "${role}: tools フィールドがない"
    continue
  fi
  if echo "$tools_line" | grep -qE '\bEdit\b'; then
    pass "${role}: tools に Edit が含まれる"
  else
    fail "${role}: tools に Edit が含まれない（${tools_line}）"
  fi
  if echo "$tools_line" | grep -qE '\bWrite\b'; then
    pass "${role}: tools に Write が含まれる"
  else
    fail "${role}: tools に Write が含まれない（${tools_line}）"
  fi
  if echo "$tools_line" | grep -qE '\bMultiEdit\b'; then
    pass "${role}: tools に MultiEdit が含まれる"
  else
    fail "${role}: tools に MultiEdit が含まれない（${tools_line}）"
  fi
done

# --- Issue #448: Bash redirect 禁止が agent 定義に明文化 ---
echo ""
echo "--- Issue #448: Bash redirect 禁止の明文化 ---"

for role in cfo cto cpo ciso clo sm; do
  agent_file="${AGENTS_DIR}/${role}.md"
  if [ ! -f "$agent_file" ]; then
    continue
  fi
  if grep -q "Bash redirect で knowledge 配下に書き込まない" "$agent_file"; then
    pass "${role}: Bash redirect 禁止記述あり"
  else
    fail "${role}: Bash redirect 禁止記述がない"
  fi
done

print_test_summary
