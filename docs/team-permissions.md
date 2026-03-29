# チームモードのパーミッション

## 概要

Agent Teams（`/ship-parallel` 等）でチームメイトを起動すると、パーミッション確認が team lead に大量に飛ぶ。これは Claude Code の既知バグ（[anthropics/claude-code#26479](https://github.com/anthropics/claude-code/issues/26479)）で、`settings.local.json` の allow リストがチームメイトに継承されないことが原因。

vibecorp では **PreToolUse hook による自動承認** でこの問題を解消している。

## 対策: PreToolUse hook による自動承認

### 仕組み

hooks はチームメイトにも伝播する。この性質を利用し、PreToolUse hook で安全なツールコールに `permissionDecision: "allow"` を返すことで承認プロンプトをスキップする。

### hook の実行順序

```text
ツールコール発生
  │
  ├─ 1. team-auto-approve.sh  ← 安全なら "allow" を返す
  │
  ├─ 2. block-api-bypass.sh   ← gh api merge 等を "deny"
  ├─ 3. review-to-rules-gate.sh
  ├─ 4. sync-gate.sh
  │
  ├─ 5. protect-files.sh      ← MVV.md 等を "deny"
  │
  └─ パーミッションシステム
       └─ deny が1つでもあれば → ブロック（allow より優先）
```

**allow は「入口を開ける」だけ。deny は「どこで開けても止める」。** この非対称性が安全性を担保する。

### 判定ロジック（ホワイトリスト方式）

```text
┌─────────────┬──────────────────────────────────────────────┐
│ ツール       │ 判定                                         │
├─────────────┼──────────────────────────────────────────────┤
│ Write/Edit  │ 機密ファイル → スキップ（通常フロー）          │
│             │ それ以外   → allow                           │
├─────────────┼──────────────────────────────────────────────┤
│ Read        │ 機密ファイル → スキップ（通常フロー）          │
│             │ それ以外   → allow                           │
├─────────────┼──────────────────────────────────────────────┤
│ Glob/Grep   │ 常に allow                                   │
├─────────────┼──────────────────────────────────────────────┤
│ Bash        │ 危険コマンド → スキップ（通常フロー）          │
│             │ 危険フラグ  → スキップ（通常フロー）           │
│             │ 安全リスト  → allow                           │
│             │ リスト外    → スキップ（通常フロー）           │
├─────────────┼──────────────────────────────────────────────┤
│ その他       │ スキップ（通常フロー）                        │
└─────────────┴──────────────────────────────────────────────┘
```

「スキップ」= hook が何も返さない（exit 0）→ 通常の承認プロンプトが表示される。

### hooks 無効化時の影響（ガードレール消滅）

`vibecorp.yml` の `hooks:` セクションで hooks を無効化すると、対応するガードレールが完全に消滅する。hooks は単なる補助機能ではなく、開発フローを強制するゲートであるため、無効化の影響を理解してから判断すること。

| 無効化する hook | 消滅するガードレール |
|---|---|
| `protect-files` | MVV.md 等の保護ファイルへの直接編集がブロックされなくなる |
| `sync-gate` | `git push` 前の `/sync-check` 強制が解除される |
| `review-to-rules-gate` | `gh pr merge` 前の `/review-to-rules` 強制が解除される |
| `role-gate` | エージェントの管轄外ファイル編集がブロックされなくなる |
| `block-api-bypass` | `gh api` 経由でのマージ・approve バイパスがブロックされなくなる |
| `team-auto-approve` | Agent Teams での自動承認が無効になり、承認プロンプトが頻発する |

**注意**: ガードレールを外すと、フックが担っていた品質・セキュリティ保証が人の運用に依存することになる。プロジェクトの成熟度やチームの規律を考慮した上で判断すること。

---

## 安全性の多層構造

```text
第1層: team-auto-approve.sh（allow のゲートキーパー）
  - 機密ファイル（.env, secrets, credentials, MVV.md）は allow しない
  - 危険コマンド（rm, sudo, kill 等）は allow しない
  - 危険フラグ（--force, --hard, -rf, -fr, --no-verify, --delete）は allow しない
  - 未知のコマンドは allow しない（ホワイトリスト方式）

第2層: 既存の deny hook（deny のガードレール）
  - block-api-bypass.sh: gh api merge / @coderabbitai approve をブロック
  - protect-files.sh: MVV.md 等の保護ファイルをブロック
  - sync-gate.sh / review-to-rules-gate.sh: push/merge 前チェック

第3層: settings.local.json の deny リスト
  - git rebase, git reset, git push --force 等
```

### `--dangerously-skip-permissions` との比較

| 項目 | hook 方式 | `--dangerously-skip-permissions` |
|------|----------|--------------------------------|
| 粒度 | コマンド・ファイル単位で制御可能 | 全操作一律スキップ |
| 安全性 | 危険コマンドは通常フローに委ねる | 全てバイパス |
| 既存 hook との共存 | block-api-bypass 等と共存可能 | 全 hook もスキップ |
| 保護ファイル | protect-files.sh が引き続き有効 | 無効化される |

### settings.json への登録

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

**注意**: `permissionDecision` の値は `"allow"` を使うこと。`"approve"` は deprecated で、Bash には効くが Write/Edit には効かない。

---

## 背景: なぜ hook が必要なのか

### パーミッションの3つのレイヤー

Claude Code のパーミッション制御は **3つの独立したレイヤー** で構成される。

| レイヤー | 機能 | チームメイト継承 |
|---------|------|----------------|
| `--permission-mode` | パーミッションモード（`acceptEdits` 等） | **継承される**（公式記載） |
| `--enable-auto-mode` | AI 自律リスク判定による自動承認 | **未対応** |
| `settings.local.json` の `defaultMode` / `allow` | ファイルベースのパーミッション設定 | **継承されない** |

### チームメイトに継承されないもの

- **`settings.local.json`**: `defaultMode: "bypassPermissions"` にしてもチームメイトは `acceptEdits` で起動する。`allow` リストも無視される
- **`--enable-auto-mode`**: 研究プレビュー段階。チームメイトへの伝播は未実装
- **Agent の `mode` パラメータ**: `"auto"`, `"bypassPermissions"` 等を指定してもチームモードでは無視される

### 代替手段

| 方法 | 効果 | 制約 |
|------|------|------|
| `--dangerously-skip-permissions` | 全チームメイトの承認スキップ | 全 hook もスキップ。セキュリティリスク大 |
| tmux pane で個別設定変更 | 個別に対応可能 | 手動操作が必要 |
| allow リスト事前設定（公式推奨） | **効果なし**（バグ） | [#26479](https://github.com/anthropics/claude-code/issues/26479) |

## 検証結果（2026-03-23〜24）

| テスト | 方法 | Write | Bash | Read | 承認プロンプト |
|--------|------|-------|------|------|--------------|
| Test 1 | `defaultMode: acceptEdits` + allow list | ❌ | - | - | **発生** |
| Test 2 | `defaultMode: bypassPermissions` + allow list | ❌ | - | - | **発生** |
| Test 3 | PreToolUse hook (`"approve"` ← deprecated) | ❌ | ✅ | ❌ | Write のみ発生 |
| **Test 4** | **PreToolUse hook (`"allow"`)** | **✅** | **✅** | **✅** | **なし** |

## 関連する既知の問題

- [anthropics/claude-code#26479](https://github.com/anthropics/claude-code/issues/26479) — Agent Teams が bypassPermissions を無視 + settings.local.json 未継承（OPEN）
- [anthropics/claude-code#28584](https://github.com/anthropics/claude-code/issues/28584) — v2.1.56 以降サブエージェントが全ツールコールで承認要求（OPEN）
- [anthropics/claude-code#18950](https://github.com/anthropics/claude-code/issues/18950) — スキル/サブエージェントが settings.json の権限を継承しない（OPEN）

## 今後の見通し

- `--enable-auto-mode` のチームモード統合が進めば、hook が不要になる可能性がある
- `settings.local.json` の継承バグが修正されれば、hook との二重管理を解消できる
- [Agent Teams Documentation](https://code.claude.com/docs/en/agent-teams) を定期的に確認すること
