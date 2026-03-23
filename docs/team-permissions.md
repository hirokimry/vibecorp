# チームモードのパーミッション

## 概要

Agent Teams（`/ship-parallel` 等）でチームメイトを起動する際、パーミッション確認が team lead に大量に飛ぶ場合がある。本ドキュメントでは仕組みと対処法を説明する。

## パーミッションの3つのレイヤー

Claude Code のパーミッション制御は **3つの独立したレイヤー** で構成される。

| レイヤー | 機能 | チームメイト継承 | 検証結果 |
|---------|------|----------------|---------|
| `--permission-mode` | パーミッションモード（`acceptEdits` 等） | **継承される**（公式記載） | — |
| `--enable-auto-mode` | AI 自律リスク判定による自動承認 | **未対応** | — |
| `settings.local.json` の `defaultMode` / `allow` | ファイルベースのパーミッション設定 | **継承されない** | 検証済み |

### `--permission-mode`（継承される）

チームメイトはリーダーの permission mode を自動継承する。

> Teammates start with the lead's permission settings.
> You can't set per-teammate modes at spawn time.

### `--enable-auto-mode`（継承されない）

2026-03-12 に導入された研究プレビュー機能。Claude 自身が操作のリスクを判定し、低リスク操作を自動承認する。

**チームモードとの統合はドキュメントに明記がない**。新機能のため、チームメイトへの伝播が未実装の可能性が高い。リーダーが `--enable-auto-mode` で起動していても、チームメイトには効かない。

### `settings.local.json`（継承されない — 検証済み）

`settings.local.json` の `permissions.defaultMode` および `permissions.allow` リストは **チームメイトに継承されない**。

以下を検証で確認:
- `defaultMode: "bypassPermissions"` に設定してもチームメイトは `acceptEdits` で起動する
- `allow` リストに `Write` / `Edit` を登録してもチームメイトの Write/Edit で team lead 承認が発生する

### Agent の `mode` パラメータ

Agent ツールの `mode` パラメータ（`"auto"`, `"bypassPermissions"` 等）は、チームモードではパーミッション制御に使えない（検証確認済み）。

## 確認プロンプトを減らす方法

### 推奨: PreToolUse hook による自動承認（検証済み）

PreToolUse hook で `permissionDecision: "allow"` を返すことで、チームメイトの承認プロンプトを排除できる。hooks はチームメイトにも伝播するため、プロジェクト settings.json に登録するだけで全チームメイトに適用される。

**重要**: `"approve"` は deprecated。**`"allow"` が正しい値**。`"approve"` だと Bash は通るが Write/Edit は team lead 承認が発生する。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit|Read|Glob|Grep",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/team-auto-approve.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

hook スクリプト（`.claude/hooks/team-auto-approve.sh`）の設計:

| ツール | 判定ロジック |
|--------|------------|
| Write/Edit | 機密ファイル（.env, secrets, credentials, MVV.md）以外を自動承認 |
| Read | 機密ファイル（.env, secrets, key, token 等）以外を自動承認 |
| Glob/Grep | 常に自動承認 |
| Bash | 危険コマンド（rm, sudo 等）と危険フラグ（--force, --hard, -rf 等）を除外し、安全コマンドリストのみ自動承認 |

#### `--dangerously-skip-permissions` との比較

| 項目 | hook 方式 | `--dangerously-skip-permissions` |
|------|----------|--------------------------------|
| 粒度 | コマンド・ファイル単位で制御可能 | 全操作一律スキップ |
| 安全性 | 危険コマンドは通常フローに委ねる | 全てバイパス |
| 既存 hook との共存 | block-api-bypass 等と共存可能 | 全 hook もスキップ |
| 保護ファイル | protect-files.sh が引き続き有効 | 無効化される |

### 代替: `--dangerously-skip-permissions`

リーダーをこのフラグで起動すると、全チームメイトもパーミッションチェックを全スキップする。セキュリティリスクがあるため、信頼できる環境でのみ使用すること。

### 参考: allow リストの事前設定（公式推奨だが効果未確認）

> Teammate permission requests bubble up to the lead, which can create friction.
> Pre-approve common operations in your permission settings before spawning teammates to reduce interruptions.

公式ドキュメントでは `settings.local.json` の `permissions.allow` に事前登録することを推奨しているが、**2026-03-23 時点の検証では効果が確認できなかった**。これは Claude Code の既知の問題（[anthropics/claude-code#26479](https://github.com/anthropics/claude-code/issues/26479)）。

## 検証結果（2026-03-23〜24）

### 全テスト結果

| テスト | 方法 | Write | Bash | Read | 承認プロンプト |
|--------|------|-------|------|------|--------------|
| Test 1 | `defaultMode: acceptEdits` + allow list | ❌ | - | - | **発生** |
| Test 2 | `defaultMode: bypassPermissions` + allow list | ❌ | - | - | **発生** |
| Test 3 | PreToolUse hook (`"approve"` ← deprecated) | ❌ | ✅ | ❌ | Write のみ発生 |
| **Test 4** | **PreToolUse hook (`"allow"`)** | **✅** | **✅** | **✅** | **なし** |

### 結論

- `settings.local.json` の設定（`defaultMode`、`allow` リスト）はチームメイトに一切継承されない
- Agent ツールの `mode` パラメータもチームモードでは無視される
- **PreToolUse hook の `permissionDecision: "allow"` がチームメイトの承認プロンプト排除に有効**
- hook はチームメイトにも伝播するため、既存の deny hook（protect-files, block-api-bypass）との共存が可能

## 関連する既知の問題

- [anthropics/claude-code#26479](https://github.com/anthropics/claude-code/issues/26479) — Agent Teams が bypassPermissions を無視 + settings.local.json 未継承（OPEN）
- [anthropics/claude-code#28584](https://github.com/anthropics/claude-code/issues/28584) — v2.1.56 以降サブエージェントが全ツールコールで承認要求（OPEN）
- [anthropics/claude-code#18950](https://github.com/anthropics/claude-code/issues/18950) — スキル/サブエージェントが settings.json の権限を継承しない（OPEN）

## 今後の見通し

- `--enable-auto-mode` は研究プレビュー段階。チームモードとの統合が進めば、チームメイトにも自動承認が伝播する可能性がある
- `settings.local.json` の `allow` リストがチームメイトに継承されない点は、バグまたは未実装機能の可能性がある
- [Agent Teams Documentation](https://code.claude.com/docs/en/agent-teams.md) を定期的に確認すること
