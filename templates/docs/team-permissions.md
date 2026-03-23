# チームモードのパーミッション

## 概要

Agent Teams（`/ship-parallel` 等）でチームメイトを起動する際、パーミッション確認が team lead に大量に飛ぶ場合がある。本ドキュメントでは仕組みと対処法を説明する。

## パーミッションの2つのレイヤー

Claude Code のパーミッション制御は **2つの独立したレイヤー** で構成される。

| レイヤー | 機能 | チームメイト継承 |
|---------|------|----------------|
| `--permission-mode` | パーミッションモード（`acceptEdits` 等） | **継承される** |
| `--enable-auto-mode` | AI 自律リスク判定による自動承認 | **未対応**（2026-03-23 時点） |

### `--permission-mode`（継承される）

チームメイトはリーダーの permission mode を自動継承する。

> Teammates start with the lead's permission settings.
> You can't set per-teammate modes at spawn time.

### `--enable-auto-mode`（継承されない）

2026-03-12 に導入された研究プレビュー機能。Claude 自身が操作のリスクを判定し、低リスク操作を自動承認する。

**チームモードとの統合はドキュメントに明記がない**。新機能のため、チームメイトへの伝播が未実装の可能性が高い。リーダーが `--enable-auto-mode` で起動していても、チームメイトには効かない。

### Agent の `mode` パラメータ

Agent ツールの `mode` パラメータ（`"auto"`, `"bypassPermissions"` 等）は、チームモードではパーミッション制御に使えない（検証確認済み）。

## 確認プロンプトを減らす方法

### 推奨: allow リストの事前設定（公式推奨）

> Teammate permission requests bubble up to the lead, which can create friction.
> Pre-approve common operations in your permission settings before spawning teammates to reduce interruptions.

`settings.local.json` の `permissions.allow` に、`/ship` ワークフローで使うコマンドを事前登録する。

```json
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(echo:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(node:*)",
      "Bash(npm:*)",
      "Bash(python3:*)"
    ]
  }
}
```

### 代替: `--dangerously-skip-permissions`

リーダーをこのフラグで起動すると、全チームメイトもパーミッションチェックを全スキップする。セキュリティリスクがあるため、信頼できる環境でのみ使用すること。

### 代替: 起動後に個別変更

チームメイト spawn 後、tmux pane で個別にパーミッション設定を変更できる。ただし手動操作が必要。

## 検証結果（2026-03-23）

| テスト | mode 指定 | 実際の --permission-mode | team lead 承認 |
|--------|----------|------------------------|----------------|
| 単独 Agent | `"auto"` | （確認なし） | N/A |
| チーム Agent | `"auto"` | `acceptEdits` | 発生 |
| チーム Agent | `"bypassPermissions"` | `acceptEdits` | 発生 |

## 今後の見通し

`--enable-auto-mode` は研究プレビュー段階。チームモードとの統合が進めば、チームメイトにも自動承認が伝播するようになる可能性がある。[Agent Teams Documentation](https://code.claude.com/docs/en/agent-teams.md) を定期的に確認すること。
