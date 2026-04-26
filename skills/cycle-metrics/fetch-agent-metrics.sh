#!/bin/bash
# fetch-agent-metrics.sh — Claude Code セッション JSONL からエージェント呼び出しを集計する
#
# 出力: stdout に JSON。ブランチ単位（dev/{Issue番号}_*）で集計。
#   {
#     "branches": [
#       {
#         "branch": "dev/353_cycle_metrics",
#         "issue_number": 353,
#         "session_count": N,
#         "first_seen": "2026-04-27T01:00:00Z",
#         "last_seen": "2026-04-27T03:00:00Z",
#         "total_input_tokens": ...,
#         "total_output_tokens": ...,
#         "total_cache_creation_tokens": ...,
#         "total_cache_read_tokens": ...,
#         "sidechain_count": ...,
#         "models": { "claude-opus-4-7": { "input_tokens": ..., "output_tokens": ... } },
#         "subagent_types": { "general-purpose": N, "Explore": N }
#       }
#     ]
#   }
#
# 使い方:
#   bash skills/cycle-metrics/fetch-agent-metrics.sh [--projects-dir DIR] [--from-fixture PATH]
#
# 制約:
#   - LLM を呼ばない（claude -p / npx / bunx 不使用）
#   - jq の static 解析のみで集計

set -euo pipefail

PROJECTS_DIR="${HOME}/.claude/projects"
FIXTURE=""

usage() {
  cat <<'USAGE'
Usage: fetch-agent-metrics.sh [--projects-dir DIR] [--from-fixture PATH]

Options:
  --projects-dir DIR  Claude Code セッション JSONL の格納ディレクトリ
                      （デフォルト: ~/.claude/projects）
  --from-fixture P    1 つの JSONL ファイルを直接読む（テスト用）
  -h, --help          このヘルプを表示

出力: stdout にブランチ別エージェント集計を JSON で出力する。
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --projects-dir) PROJECTS_DIR="$2"; shift 2 ;;
    --from-fixture) FIXTURE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# 集計対象の JSONL を列挙
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}" || true' EXIT

JSONL_LIST="${TMP_DIR}/jsonl-list.txt"

if [ -n "$FIXTURE" ]; then
  if [ ! -f "$FIXTURE" ]; then
    echo "fixture ファイルが見つかりません: ${FIXTURE}" >&2
    exit 4
  fi
  printf '%s\n' "$FIXTURE" > "$JSONL_LIST"
else
  if [ ! -d "$PROJECTS_DIR" ]; then
    echo "{\"branches\": []}"
    exit 0
  fi
  find "$PROJECTS_DIR" -maxdepth 2 -type f -name '*.jsonl' > "$JSONL_LIST"
fi

# 各 JSONL から (branch, model, usage..., isSidechain, subagent_type) を抽出して集約
ALL_LINES="${TMP_DIR}/all-lines.jsonl"
: > "$ALL_LINES"

while IFS= read -r jsonl; do
  [ -z "$jsonl" ] && continue
  [ ! -f "$jsonl" ] && continue

  jq -c '
    select(.gitBranch != null and (.gitBranch | startswith("dev/")))
    | {
        branch: .gitBranch,
        timestamp: .timestamp,
        sessionId: .sessionId,
        isSidechain: (.isSidechain // false),
        model: (.message.model // null),
        usage: (.message.usage // null),
        agent_calls: (
          [ .message.content[]? | select(.type == "tool_use" and (.name == "Agent" or .name == "Task"))
            | .input.subagent_type ]
          | map(select(. != null))
        )
      }
  ' "$jsonl" >> "$ALL_LINES" || true
done < "$JSONL_LIST"

# ブランチ単位で集約
jq -s '
  def issue_num($s):
    if ($s | test("^dev/[0-9]+_"))
    then ($s | capture("^dev/(?<n>[0-9]+)_") | .n | tonumber)
    else null
    end;

  def add_safe($a; $b): (($a // 0) + ($b // 0));

  group_by(.branch)
  | map({
      branch: .[0].branch,
      issue_number: (issue_num(.[0].branch)),
      session_count: ([.[].sessionId] | unique | length),
      first_seen: ([.[].timestamp] | sort | (.[0] // null)),
      last_seen: ([.[].timestamp] | sort | reverse | (.[0] // null)),
      total_input_tokens: ([.[].usage.input_tokens // 0] | add),
      total_output_tokens: ([.[].usage.output_tokens // 0] | add),
      total_cache_creation_tokens: ([.[].usage.cache_creation_input_tokens // 0] | add),
      total_cache_read_tokens: ([.[].usage.cache_read_input_tokens // 0] | add),
      sidechain_count: ([.[] | select(.isSidechain == true)] | length),
      models: (
        [.[] | select(.model != null)]
        | group_by(.model)
        | map({
            key: .[0].model,
            value: {
              input_tokens: ([.[].usage.input_tokens // 0] | add),
              output_tokens: ([.[].usage.output_tokens // 0] | add),
              cache_creation_tokens: ([.[].usage.cache_creation_input_tokens // 0] | add),
              cache_read_tokens: ([.[].usage.cache_read_input_tokens // 0] | add),
              message_count: length
            }
          })
        | from_entries
      ),
      subagent_types: (
        [.[].agent_calls[]?]
        | group_by(.)
        | map({key: .[0], value: length})
        | from_entries
      )
    })
  | sort_by(.issue_number)
  | { branches: . }
' "$ALL_LINES"
