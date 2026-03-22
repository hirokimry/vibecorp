# Spike #107: EnterWorktree / ExitWorktree / TeamCreate の並列実行検証

## 検証日

2026-03-22

## 検証結果サマリ

| ツール | 並列実行 | .claude/ 同期 | ブランチ制御 | 推奨度 |
|--------|---------|--------------|-------------|--------|
| EnterWorktree / ExitWorktree | ❌ 不可 | ❌ 未追跡ファイルなし | ❌ 自動生成のみ | ❌ 不適 |
| Agent isolation: "worktree" | ✅ 可能 | ✅ 全ファイルあり | ❌ 自動生成のみ | ⭕ 有力 |
| TeamCreate + Agent worktree | ✅ 可能 | ✅ 全ファイルあり | ❌ 自動生成のみ | ✅ 推奨 |
| CLI spawn (`claude -p`) | ✅ 可能 | ⚠️ 手動rsync必要 | ✅ 完全制御 | ⭕ 代替案 |

## 詳細検証結果

### 1. EnterWorktree

#### スキーマ

```text
パラメータ:
  - name (optional): worktree の名前（英数字・ドット・アンダースコア・ハイフンのみ、最大64文字）

動作:
  - .claude/worktrees/{name}/ に worktree を作成
  - worktree-{name} という名前のブランチを HEAD から自動作成
  - セッションの作業ディレクトリを worktree に切り替え
```

#### 実機検証結果

```text
作成先: /Users/staff/Public/development/vibecorp/.claude/worktrees/spike-107-test
ブランチ: worktree-spike-107-test（自動命名）
.claude/ の状態:
  ✅ CLAUDE.md, vibecorp.yml, rules/, knowledge/ — 存在（git 追跡ファイル）
  ❌ skills/, hooks/, settings.json — 不在（.gitignore で除外されたファイル）
```

#### 制約

- **セッション単位**: 1セッションにつき1つの worktree のみ。並列不可
- **ブランチ名制御不可**: `worktree-{name}` 形式で固定。`dev/{issue}_{summary}` は指定できない
- **未追跡ファイル未同期**: `.gitignore` で除外されたファイルが worktree に存在しない
- **既に worktree 内にいる場合は使用不可**

#### 結論: #106 には不適

並列実行できず、ブランチ名も制御できないため、COO並列ship には使えない。

---

### 2. ExitWorktree

#### スキーマ

```text
パラメータ:
  - action (required): "keep" | "remove"
  - discard_changes (optional): true にすると未コミット変更があっても強制削除

動作:
  - EnterWorktree で作成した worktree からのみ退出可能
  - 手動作成の worktree や前セッションの worktree には一切触れない
  - "keep": worktree とブランチをディスクに残す
  - "remove": worktree とブランチを削除
```

#### 制約

- **スコープが厳密**: 同一セッションの EnterWorktree で作った worktree のみ操作可能
- 手動の `git worktree add` で作った worktree は操作対象外
- `/branch --worktree` で作った worktree も操作対象外

---

### 3. Agent isolation: "worktree"

#### スキーマ

```text
パラメータ:
  - Agent ツールに isolation: "worktree" を指定

動作:
  - .claude/worktrees/agent-{id}/ に一時的な worktree を作成
  - worktree-agent-{id} ブランチを自動作成
  - エージェント終了後、変更がなければ自動削除
  - 変更があれば worktree パスとブランチ名を返却
```

#### 実機検証結果

```text
作成先: /Users/staff/Public/development/vibecorp/.claude/worktrees/agent-a5f0922d
ブランチ: worktree-agent-a5f0922d（自動命名）
.claude/ の状態:
  ✅ CLAUDE.md, vibecorp.yml, rules/, knowledge/ — 存在
  ✅ skills/, hooks/, settings.json, agents/ — 存在（全ファイルあり）
```

#### EnterWorktree との違い

| 項目 | EnterWorktree | Agent worktree |
|------|--------------|----------------|
| .claude/ 未追跡ファイル | ❌ なし | ✅ あり |
| 並列実行 | ❌ 1セッション1つ | ✅ 複数エージェント並列可 |
| ブランチ名 | worktree-{name} | worktree-agent-{id} |
| ライフサイクル | 手動 keep/remove | 変更なし→自動削除 |

#### 重要な発見

Agent worktree では `.claude/` の全ファイル（skills/, hooks/ 含む）が利用可能。
これは EnterWorktree と異なり、**エージェントが worktree 内で `/ship` 等のスキルを実行できる可能性がある**ことを意味する。

#### 制約

- **ブランチ名が自動生成**: `dev/{issue}_{summary}` 形式にできない → エージェント内で `git checkout -b` でリネームする必要がある
- **worktree パスが `.claude/worktrees/` 固定**: `/branch --worktree` の `../{project}.worktrees/` パターンとは異なる
- **変更なしで自動削除**: /ship の中間状態で失敗した場合のリカバリ設計が必要

---

### 4. TeamCreate

#### スキーマ

```text
パラメータ:
  - team_name (required): チーム名
  - description (optional): チームの説明
  - agent_type (optional): チームリードのタイプ

動作:
  - ~/.claude/teams/{team-name}.json にチーム設定ファイルを作成
  - ~/.claude/tasks/{team-name}/ にタスクリストディレクトリを作成
  - Agent ツールで team_name を指定してチームメイトを起動
  - TaskCreate/TaskUpdate でタスク管理
  - SendMessage でチームメイト間通信
```

#### 並列 ship への適用可能性

TeamCreate + Agent(isolation: "worktree") の組み合わせ:

```text
COO（チームリード）
  → TeamCreate で "parallel-ship" チームを作成
  → TaskCreate で各 Issue をタスク化
  → Agent(isolation: "worktree", team_name: "parallel-ship") でチームメイトを起動
  → 各チームメイトが worktree 内で /ship 相当の処理を実行
  → TaskUpdate で完了報告
  → COO が結果を統合
```

#### 制約

- チームメイトは Agent ツールで起動するため、**スキル（/ship 等）を直接呼び出せない**可能性
  - ただしスキルの内容をプロンプトに埋め込むことで同等の処理は実行可能
- チームメイトの idle 状態管理が必要
- チーム設定は `~/.claude/teams/` に作成される（プロジェクトローカルではない）

---

## 方式決定

### 推奨: C. ハイブリッド方式

**TeamCreate（調整）+ Agent isolation: "worktree"（隔離）+ カスタムブランチ管理**

```text
COO（メインセッション / チームリード）
  │
  ├─ 1. Issue 一覧を分析、並列可能なタスク群を特定
  ├─ 2. TeamCreate でチーム作成
  ├─ 3. 各 Issue に対して Agent(isolation: "worktree") でチームメイト起動
  │     └─ チームメイトのプロンプトに /ship 相当のワークフローを埋め込み
  │        └─ worktree 内で: ブランチリネーム → 実装 → コミット → push → PR作成
  ├─ 4. 各チームメイトの完了報告を受信
  └─ 5. 結果統合、レポート出力
```

### 選定理由

| 観点 | A. EnterWorktree | B. CLI spawn | C. ハイブリッド |
|------|-----------------|-------------|---------------|
| 並列実行 | ❌ | ✅ | ✅ |
| .claude/ 同期 | ❌ | ⚠️ 手動 | ✅ 自動 |
| プロセス管理 | - | 複雑 | Claude Code 内蔵 |
| 進捗監視 | - | ポーリング必要 | TaskList で確認 |
| エラー通知 | - | ログ監視必要 | SendMessage で即時 |
| スキル利用 | ✅ | ✅ | ⚠️ プロンプト埋込 |

### 未解決課題（#106 で対応）

1. **ブランチ名のリネーム**: Agent worktree は `worktree-agent-{id}` ブランチを自動作成する。`dev/{issue}_{summary}` へのリネームをワークフロー内で行う必要がある
2. **スキル呼び出し**: チームメイト（Agent）から `/ship` スキルを直接呼べるか要検証。呼べない場合はプロンプトにワークフローを埋め込む
3. **worktree クリーンアップ**: Agent worktree は変更ありの場合残る。PR マージ後の削除を COO が `/worktree clean` で行うか、自動化するか
4. **コンフリクト管理**: 並列 PR 同士がコンフリクトする場合の検知・解消フロー
