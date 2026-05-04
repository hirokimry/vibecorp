#!/bin/bash
# test_review_skill_claude_cli.sh
# ─────────────────────────────────────────────
# Issue #499: skills/review/SKILL.md が Claude Code CLI 直接呼び出しに置換されたかの静的検証
#
# 検証範囲:
#   1. SKILL.md の本体置換（claude -p / REVIEW.md 参照 / cr review --plain 削除）
#   2. 4 ガード（--bare 不在、ANTHROPIC_API_KEY fail-fast、guidance 文言、CLAUDE_CODE_OAUTH_TOKEN）
#   3. SKILL.md 内 bash コードブロックの構文検証（bash -n）
#   4. docs/cost-analysis.md の追記（コスト経路シフト + fail-fast 運用）
#   5. docs/ai-review-dependency.md の追記（既存 CodeRabbit CLI 利用者の移行パス）
#   6. .claude/knowledge/agents-vs-skills.md の旧記述削除
#
# 実機検証（claude -p 実起動）はコスト・OAuth 認証・ネットワーク依存のため対象外。
# 親エピック #455 検証フェーズ（Issue #475）で実施する。

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SKILL_FILE="${PROJECT_DIR}/skills/review/SKILL.md"
COST_DOC="${PROJECT_DIR}/docs/cost-analysis.md"
DEP_DOC="${PROJECT_DIR}/docs/ai-review-dependency.md"
KNOWLEDGE_DOC="${PROJECT_DIR}/.claude/knowledge/agents-vs-skills.md"

echo ""
echo "=== Issue #499 ローカル cr → Claude Code CLI 直接呼び出し置換 静的検証 ==="

# ============================================
# 1. SKILL.md の存在と本体置換
# ============================================
echo ""
echo "--- 1. skills/review/SKILL.md の存在と本体置換 ---"

assert_file_exists "skills/review/SKILL.md が存在する" "$SKILL_FILE"

# 前提ファイル不在 → 後続テストは全て無意味なので即終了
if [[ ! -f "$SKILL_FILE" ]]; then
  exit 1
fi

# claude -p 呼び出しが入っている
assert_file_contains "claude -p 呼び出しが存在する" "$SKILL_FILE" 'claude -p'

# REVIEW.md がプロンプトとして使われる
assert_file_contains "REVIEW.md 参照が存在する" "$SKILL_FILE" 'REVIEW\.md'

# 旧 cr review --plain が実行コマンドとして含まれない
# （歴史的言及はあり得るため、bash コードブロックで起動コマンドとして使われていないかを検証する）
EXTRACTED_BASH_FOR_CR_CHECK="$(mktemp)"
awk '
  /^```bash$/ { in_block = 1; next }
  /^```$/ && in_block { in_block = 0; print ""; next }
  in_block { print }
' "$SKILL_FILE" > "$EXTRACTED_BASH_FOR_CR_CHECK"
if grep -q -e 'cr review --plain' "$EXTRACTED_BASH_FOR_CR_CHECK"; then
  fail "bash コードブロック内に 'cr review --plain' 実行コマンドが残っている"
else
  pass "bash コードブロックから 'cr review --plain' 実行コマンドが削除されている"
fi
rm -f "$EXTRACTED_BASH_FOR_CR_CHECK"

# --allowed-tools が指定されている
assert_file_contains "--allowed-tools 指定が存在する" "$SKILL_FILE" 'allowed-tools'

# ============================================
# 2. 4 ガードの実装確認
# ============================================
echo ""
echo "--- 2. 4 ガードの実装確認 ---"

# ガード 1: --bare が実行コマンドのフラグとして使われていない
# （説明文での言及は OK だが、claude 起動コマンド内に --bare が入っていないことを検証）
EXTRACTED_BASH_FOR_BARE_CHECK="$(mktemp)"
awk '
  /^```bash$/ { in_block = 1; next }
  /^```$/ && in_block { in_block = 0; print ""; next }
  in_block { print }
' "$SKILL_FILE" > "$EXTRACTED_BASH_FOR_BARE_CHECK"
# claude のコマンドラインに --bare が含まれる行を探す（grep -E で正規表現マッチ）
if grep -E -q '(^|[^a-zA-Z0-9_-])claude([[:space:]]|$).*--bare' "$EXTRACTED_BASH_FOR_BARE_CHECK"; then
  fail "ガード1: claude コマンドラインに --bare フラグが含まれている"
else
  pass "ガード1: claude コマンドラインに --bare フラグが含まれない"
fi
rm -f "$EXTRACTED_BASH_FOR_BARE_CHECK"

# ガード 2: ANTHROPIC_API_KEY 混在 fail-fast チェック
assert_file_contains "ガード2: ANTHROPIC_API_KEY の存在チェックが含まれる" "$SKILL_FILE" 'ANTHROPIC_API_KEY'
assert_file_contains "ガード2: fail-fast の bash 条件式が含まれる" "$SKILL_FILE" 'ANTHROPIC_API_KEY:-'
assert_file_contains "ガード2: exit 1 で停止する" "$SKILL_FILE" 'exit 1'

# ガード 2 の guidance: ユーザーに対処方法を案内
assert_file_contains "ガード2: unset ANTHROPIC_API_KEY の guidance がある" "$SKILL_FILE" 'unset ANTHROPIC_API_KEY'
assert_file_contains "ガード2: claude setup-token への誘導がある" "$SKILL_FILE" 'claude setup-token'

# ガード 3: docs/cost-analysis.md への参照
assert_file_contains "ガード3: docs/cost-analysis.md への参照がある" "$SKILL_FILE" 'docs/cost-analysis\.md'

# ガード 4: GitHub Actions では CLAUDE_CODE_OAUTH_TOKEN を明示することの記述
assert_file_contains "ガード4: CLAUDE_CODE_OAUTH_TOKEN の言及がある" "$SKILL_FILE" 'CLAUDE_CODE_OAUTH_TOKEN'

# ============================================
# 3. coderabbit.enabled フラグの意味論変更
# ============================================
echo ""
echo "--- 3. coderabbit.enabled フラグとの関係 ---"

# 旧フラグ判定ロジック（awk で coderabbit.enabled を読む）が削除されている
assert_file_not_contains "旧 coderabbit.enabled の awk 判定が削除されている" "$SKILL_FILE" 'awk .*coderabbit.*enabled'

# 意味論変更が明記されている（影響を受けない / coderabbit.enabled）
assert_file_contains "coderabbit.enabled の意味論変更が明記されている" "$SKILL_FILE" 'coderabbit\.enabled'

# ============================================
# 4. 出力フォーマット指示
# ============================================
echo ""
echo "--- 4. 出力フォーマット指示 ---"

# stdout 出力を明示
assert_file_contains "stdout への出力が明記されている" "$SKILL_FILE" 'stdout'

# severity マーカーの出力指示
assert_file_contains "severity マーカー指示がある" "$SKILL_FILE" 'severity'

# 結果報告セクションが新サマリ形式（severity 5 段階）に更新されている
assert_file_contains "結果報告に Critical 件数が含まれる" "$SKILL_FILE" 'Critical'
assert_file_contains "結果報告に Major 件数が含まれる" "$SKILL_FILE" 'Major'
assert_file_contains "結果報告に Minor 件数が含まれる" "$SKILL_FILE" 'Minor'

# ============================================
# 5. SKILL.md 内 bash コードブロックの構文検証
# ============================================
echo ""
echo "--- 5. SKILL.md 内 bash コードブロックの構文検証 ---"

# SKILL.md から ```bash ～ ``` で囲まれたブロックを抽出して bash -n でチェック
EXTRACTED_BASH="$(mktemp)"
trap 'rm -f "$EXTRACTED_BASH"' EXIT

awk '
  /^```bash$/ { in_block = 1; next }
  /^```$/ && in_block { in_block = 0; print ""; next }
  in_block { print }
' "$SKILL_FILE" > "$EXTRACTED_BASH"

if [[ -s "$EXTRACTED_BASH" ]]; then
  if bash -n "$EXTRACTED_BASH" 2>/dev/null; then
    pass "SKILL.md の bash コードブロックが構文エラーなし"
  else
    fail "SKILL.md の bash コードブロックに構文エラーあり"
    echo "    抽出したコードブロックの構文エラー詳細:" >&2
    bash -n "$EXTRACTED_BASH" >&2 || true
  fi
else
  fail "SKILL.md に bash コードブロックが見つからない"
fi

# ============================================
# 6. docs/cost-analysis.md の追記確認
# ============================================
echo ""
echo "--- 6. docs/cost-analysis.md の追記確認 ---"

assert_file_exists "docs/cost-analysis.md が存在する" "$COST_DOC"

# コスト経路シフトの記述
assert_file_contains "Issue #499 のコスト経路シフト節が追加されている" "$COST_DOC" 'Issue #499'
assert_file_contains "/vibecorp:review への言及がある" "$COST_DOC" '/vibecorp:review'
assert_file_contains "Claude Max OAuth quota への言及がある" "$COST_DOC" 'Claude Max OAuth quota'

# ANTHROPIC_API_KEY fail-fast 運用の記述
assert_file_contains "ANTHROPIC_API_KEY 混在 fail-fast の記述がある" "$COST_DOC" '混在 fail-fast'

# ============================================
# 7. docs/ai-review-dependency.md の追記確認
# ============================================
echo ""
echo "--- 7. docs/ai-review-dependency.md の移行パスセクション ---"

assert_file_exists "docs/ai-review-dependency.md が存在する" "$DEP_DOC"

# 移行パスセクションの追加
assert_file_contains "「既存 CodeRabbit CLI 利用者の移行パス」セクションが追加されている" "$DEP_DOC" '既存 CodeRabbit CLI 利用者の移行パス'

# Issue #499 への言及
assert_file_contains "Issue #499 への言及がある" "$DEP_DOC" 'Issue #499'

# 残論点 3 の結論（オプトイン経路は新設しない）
assert_file_contains "オプトイン経路を新設しない結論が明記されている" "$DEP_DOC" 'オプトイン経路は新設しない'

# coderabbit.enabled の意味論変更が明記
assert_file_contains "coderabbit.enabled の意味論変更が明記されている" "$DEP_DOC" 'coderabbit\.enabled'

# ============================================
# 8. .claude/knowledge/agents-vs-skills.md の旧記述削除
# ============================================
echo ""
echo "--- 8. agents-vs-skills.md の旧記述更新 ---"

assert_file_exists ".claude/knowledge/agents-vs-skills.md が存在する" "$KNOWLEDGE_DOC"

# 旧 coderabbit-reviewer の能動記述（: で始まる先頭定義）が削除されている
# 行頭 `- coderabbit-reviewer:` のような能動定義の不在を検証する（履歴文脈での言及は OK）
if grep -E -q '^- coderabbit-reviewer:' "$KNOWLEDGE_DOC"; then
  fail "旧 '- coderabbit-reviewer:' の能動定義が削除されていない"
else
  pass "旧 '- coderabbit-reviewer:' の能動定義が削除されている"
fi

# 新しい local-reviewer の能動定義がある
assert_file_contains "新しい local-reviewer の能動定義がある" "$KNOWLEDGE_DOC" 'local-reviewer'

# 新しい Claude Code CLI 直接呼び出しの記述
assert_file_contains "新しい Claude Code CLI 直接呼び出しの記述がある" "$KNOWLEDGE_DOC" 'claude -p'

# ============================================
# 結果サマリ
# ============================================
print_test_summary
