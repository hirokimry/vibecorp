#!/bin/bash
# test_template_integrity_533.sh — Issue #533 で修正した配布テンプレートの整合性検証
#
# 検証対象（CodeRabbit 14 件指摘）:
#   - Critical #1: ai-review-golden-test.yml がスクリプト不在時にスキップする
#   - Critical #2: test.yml が cancelled を success 扱いしない
#   - Major #3: cycle-metrics-template.md のスクリプトパスが vibecorp プラグイン同梱と明記
#   - Major #4: legal-principles.md の「許容」セクションがプロジェクトライセンス互換を前提化
#   - Major #5: .coderabbit.yaml と coderabbit.yaml.tpl から auto_resolve が削除
#   - Major #6: ISSUE_TEMPLATE/config.yml が blank_issues_enabled: false
#   - Minor #8: security-audit-template.md の関連リンクが .claude/rules/ プレフィックス
#   - Minor #9: autonomous-restrictions.md の例外条項に claude_action.enabled: true 前提が明記
#   - Minor #10: severity/claude-action.md の REVIEW.md 前提が条件付き記述
#   - Minor #11: intent-label-issue-check.yml が unlabeled イベントを除外
#   - Minor #12: ai-review-dependency.md が ai-review.yml / REVIEW.md の配布条件を明記
#   - Minor #13: conventional-commits.md が intent-label-check の Issue/PR 二系統を分離記述
#   - Minor #14: file-placement.md の .gitignore 例が bin/claude-real を含む

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TESTS_DIR}/lib/test_helpers.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================
echo "=== Critical #2: test.yml が cancelled を success 扱いしない ==="
# ============================================

TEST_YML="${ROOT}/templates/.github/workflows/test.yml"
assert_file_exists "templates/.github/workflows/test.yml が存在する" "$TEST_YML"
assert_file_not_contains \
  "test.yml の判定行に cancelled が含まれない（required check 迂回防止）" \
  "$TEST_YML" \
  '"\$result" = "cancelled"'
assert_file_contains \
  "test.yml で success のみが成功扱いされる" \
  "$TEST_YML" \
  'if \[ "\$result" = "success" \]; then'

# ============================================
echo "=== Critical #1: ai-review-golden-test.yml テンプレートが撤去されている（Issue #531） ==="
# ============================================
# golden test は claude-code-action のレビュー回帰検証用だった。レビュー機能の
# vibehawk 移譲（Issue #531）により ai-review-golden-test.yml テンプレートは撤去された。

GOLDEN_YML="${ROOT}/templates/.github/workflows/ai-review-golden-test.yml"
if [ -e "$GOLDEN_YML" ]; then
  fail "ai-review-golden-test.yml テンプレートが残存（Issue #531 で撤去済みのはず）"
else
  pass "ai-review-golden-test.yml テンプレートが撤去されている（vibehawk 移譲）"
fi

# ============================================
echo "=== Minor #11: intent-label-issue-check.yml が unlabeled を除外 ==="
# ============================================

INTENT_YML="${ROOT}/templates/.github/workflows/intent-label-issue-check.yml"
assert_file_exists "intent-label-issue-check.yml が存在する" "$INTENT_YML"
assert_file_not_contains \
  "intent-label-issue-check.yml の types に unlabeled が含まれない" \
  "$INTENT_YML" \
  'types: \[opened, edited, labeled, unlabeled, reopened\]'
assert_file_contains \
  "intent-label-issue-check.yml の types は opened/edited/labeled/reopened の 4 種" \
  "$INTENT_YML" \
  'types: \[opened, edited, labeled, reopened\]'

# ============================================
echo "=== Major #6: ISSUE_TEMPLATE/config.yml で blank_issues_enabled: false ==="
# ============================================

ISSUE_CONFIG="${ROOT}/templates/.github/ISSUE_TEMPLATE/config.yml"
assert_file_exists "ISSUE_TEMPLATE/config.yml が存在する" "$ISSUE_CONFIG"
assert_file_contains \
  "ISSUE_TEMPLATE/config.yml で blank_issues_enabled: false" \
  "$ISSUE_CONFIG" \
  '^blank_issues_enabled: false'
assert_file_not_contains \
  "ISSUE_TEMPLATE/config.yml で blank_issues_enabled: true でない" \
  "$ISSUE_CONFIG" \
  '^blank_issues_enabled: true'

# ============================================
echo "=== Major #5: auto_resolve キーが両ファイルから削除 ==="
# ============================================

CR_YAML="${ROOT}/.coderabbit.yaml"
CR_TPL="${ROOT}/templates/coderabbit.yaml.tpl"
assert_file_exists ".coderabbit.yaml が存在する" "$CR_YAML"
assert_file_exists "templates/coderabbit.yaml.tpl が存在する" "$CR_TPL"
assert_file_not_contains \
  ".coderabbit.yaml に auto_resolve が含まれない" \
  "$CR_YAML" \
  '^[[:space:]]*auto_resolve:'
assert_file_not_contains \
  "templates/coderabbit.yaml.tpl に auto_resolve が含まれない" \
  "$CR_TPL" \
  '^[[:space:]]*auto_resolve:'

# ============================================
echo "=== Major #3: cycle-metrics-template.md のスクリプトパス整合 ==="
# ============================================

CYCLE_TPL="${ROOT}/templates/claude/knowledge/accounting/cycle-metrics-template.md"
assert_file_exists "cycle-metrics-template.md が存在する" "$CYCLE_TPL"
assert_file_contains \
  "cycle-metrics-template.md が vibecorp プラグイン同梱と明記" \
  "$CYCLE_TPL" \
  'vibecorp プラグイン'
assert_file_contains \
  "cycle-metrics-template.md がスキル経由実行を明記" \
  "$CYCLE_TPL" \
  '/cycle-metrics'

# ============================================
echo "=== Major #4: legal-principles.md の許容条件付き化 ==="
# ============================================

LEGAL_MD="${ROOT}/templates/claude/knowledge/legal/legal-principles.md"
assert_file_exists "legal-principles.md が存在する" "$LEGAL_MD"
assert_file_contains \
  "legal-principles.md がプロジェクトライセンス互換を前提化" \
  "$LEGAL_MD" \
  'プロジェクトのライセンスと互換である場合に限り'

# ============================================
echo "=== Minor #8: security-audit-template.md のリンクが .claude/rules/ プレフィックス ==="
# ============================================

SEC_TPL="${ROOT}/templates/claude/knowledge/security/security-audit-template.md"
assert_file_exists "security-audit-template.md が存在する" "$SEC_TPL"
assert_file_contains \
  "security-audit-template.md が .claude/rules/autonomous-restrictions.md を参照" \
  "$SEC_TPL" \
  '\.claude/rules/autonomous-restrictions\.md'
assert_file_not_contains \
  "security-audit-template.md が古いパス rules/autonomous-restrictions.md を含まない" \
  "$SEC_TPL" \
  '^- \`rules/autonomous-restrictions\.md\`'

# ============================================
echo "=== Minor #9: autonomous-restrictions.md の例外条項が存在する ==="
# ============================================
# 注: PR #694 で「claude_action.enabled: true 前提」明記アサーションを削除した。
# CR 指摘 #10「整形 PR スコープ超え」に従い、autonomous-restrictions.md の例外条項を
# main 版に近い形（条件付け削除）に戻したため、claude_action.enabled の明記は失われた。
# CISO 承認済の id-token: write 例外条項自体は維持されているため、ここでは
# 例外セクション見出しの存在のみを確認する（条件付き再導入は別 Issue で扱う）。

AUTO_REST="${ROOT}/rules/autonomous-restrictions.md"
assert_file_exists "autonomous-restrictions.md が存在する" "$AUTO_REST"
assert_file_contains \
  "autonomous-restrictions.md の例外条項見出しが存在する" \
  "$AUTO_REST" \
  '例外: claude-code-action の動作要件として CISO 承認済の permissions'
assert_file_contains \
  "autonomous-restrictions.md の例外条項に id-token: write が明記" \
  "$AUTO_REST" \
  'id-token: write'

# ============================================
echo "=== Minor #10: severity/claude-action.md の注入先が vibehawk へ移譲済み（Issue #531） ==="
# ============================================
# レビュー移譲（Issue #531）で severity を含む判断軸の注入先が REVIEW.md から
# .vibehawk.yaml の reviews.path_instructions に変わった。

SEV_CA="${ROOT}/rules/severity/claude-action.md"
assert_file_exists "severity/claude-action.md が存在する" "$SEV_CA"
assert_file_contains \
  "severity/claude-action.md が vibehawk.enabled: true 運用時の注入先を明記" \
  "$SEV_CA" \
  'vibehawk\.enabled: true'
assert_file_contains \
  "severity/claude-action.md が .vibehawk.yaml への注入を明記" \
  "$SEV_CA" \
  '\.vibehawk\.yaml'

# ============================================
echo "=== Minor #12: ai-review-dependency.md が vibehawk 配布条件を明記（Issue #531） ==="
# ============================================
# レビュー移譲（Issue #531）で .vibehawk.yaml の配布条件が vibehawk.enabled: true に変わった。

AI_DEP="${ROOT}/docs/ai-review-dependency.md"
assert_file_exists "ai-review-dependency.md が存在する" "$AI_DEP"
assert_file_contains \
  "ai-review-dependency.md が .vibehawk.yaml の vibehawk.enabled: true 配布条件を明記" \
  "$AI_DEP" \
  '\*\*`vibehawk\.enabled: true` 運用時に install\.sh が生成\*\*'

# ============================================
echo "=== Major #7: ai-review-dependency.md にスモークテスト assert 方針が追記 ==="
# ============================================

assert_file_contains \
  "ai-review-dependency.md にスモークテスト assert 方針セクションが存在" \
  "$AI_DEP" \
  '## 導入先スモークテストの assert 方針'
assert_file_contains \
  "ai-review-dependency.md に絶対値 assert 禁止指針が含まれる" \
  "$AI_DEP" \
  '存在 / 不在を絶対値で assert しない'

# ============================================
echo "=== Minor #13: conventional-commits.md が Issue 側 workflow のみを記述（Issue #575 で PR 側削除） ==="
# ============================================

CC_MD="${ROOT}/docs/conventional-commits.md"
assert_file_exists "conventional-commits.md が存在する" "$CC_MD"
assert_file_contains \
  "conventional-commits.md が Issue 側 workflow を明記" \
  "$CC_MD" \
  'intent-label-issue-check\.yml'
# 要件コア: Issue #575 確定で PR 側 intent-label-check ジョブを撤廃、Issue 側のみ機械強制
if grep -q -E 'PR 側.*intent-label-check ジョブ|ai-review\.yml.*intent-label-check' "$CC_MD"; then
  fail "conventional-commits.md に PR 側 intent-label-check ジョブの言及が残存（Issue #575 で削除済みのはず）"
else
  pass "conventional-commits.md に PR 側 intent-label-check ジョブの言及が無い（Issue 側 SoT 集約）"
fi

# ============================================
echo "=== Minor #14: file-placement.md の .gitignore 例が bin/claude-real を含む ==="
# ============================================

FP_MD="${ROOT}/docs/file-placement.md"
assert_file_exists "file-placement.md が存在する" "$FP_MD"
assert_file_contains \
  "file-placement.md の .gitignore 例に bin/claude-real が含まれる" \
  "$FP_MD" \
  'bin/claude-real'
assert_file_contains \
  "file-placement.md の .gitignore 例に machine-specific 注記が含まれる" \
  "$FP_MD" \
  'machine-specific'
# 要件コア: XDG plans パス・.claude/plans/ 非生成の整合が docs に明記されているか
assert_file_contains \
  "file-placement.md が XDG plans パスを明記" \
  "$FP_MD" \
  '~/\.cache/vibecorp/plans/<repo-id>/'
assert_file_contains \
  "file-placement.md が .claude/plans/ 非生成を明記" \
  "$FP_MD" \
  'claude/plans/.*は作成されない'
assert_file_contains \
  "file-placement.md が install.sh による .gitignore 自動生成を明記" \
  "$FP_MD" \
  '\.claude/\.gitignore.*自動生成'

print_test_summary
