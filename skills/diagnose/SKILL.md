---
name: diagnose
description: >
  コードベースを自律的に診断し、改善点を発見→フィルタリング→GitHub Issue 起票まで行う。
  実装はユーザーが /ship で別途実行する。full プリセット専用。
  「/diagnose」「診断」「コード診断」と言った時に使用。
---

**ultrathink**

# コード診断スキル

コードベースを自律的に診断し、改善点を発見してフィルタリング後に GitHub Issue として起票する。
**実装は行わない。起票と実装を分離することで暴走を防止する。**

**スピード/UX 観点はモデル指定・コスト最適化には一切踏み込まない**。モデル指定の変更提案（Opus → Sonnet 等）・エージェント削減・合議制回数削減・並列度自体の削減・`max_issues_per_run` 等のコスト上限値の変更は CFO 管轄（Issue #354 系）に閉じ込め、品質劣化ルートを遮断する。スピード/UX 観点は逐次処理の並列化余地・同期待ちボトルネック・フック実行時間の肥大化・スキル間の冗長な再実行のみを対象とする。

## 使用方法

```bash
/vibecorp:diagnose               # 発見→フィルタ→確認→起票
/vibecorp:diagnose --dry-run     # レポート出力のみ（起票しない）
/vibecorp:diagnose --scope <path> # 走査対象を限定
```

## 前提条件

- **full プリセット専用**（CTO/CPO/CISO/SM エージェントがフィルタリングに必要）
- **3者承認ゲート**: CISO + CPO + SM の3者フィルタで自律実行不可領域（認証 / 暗号 / 課金構造 / ガードレール / MVV / CI エージェント）を自動除外する（rules/autonomous-restrictions.md 準拠）

## ワークフロー

### 1. プリセット確認

vibecorp.yml の preset を確認する。full 以外の場合は以下を出力して終了する:

```text
/vibecorp:diagnose は full プリセット専用です。現在のプリセット: <preset>
```

```bash
awk '/^preset:/ { print $2 }' "$CLAUDE_PROJECT_DIR/.claude/vibecorp.yml"
```

### 2. 設定読み込み

vibecorp.yml の diagnose セクションから設定を読み込む。セクションが存在しない場合はデフォルト値を使用する。

| 設定キー | デフォルト値 | 説明 |
|---------|------------|------|
| `max_issues_per_run` | 7 | 1回の実行で起票する最大 Issue 数 |
| `max_issues_per_day` | 14 | 1日に起票する最大 Issue 数 |
| `max_files_per_issue` | 10 | 1つの Issue に含める最大ファイル数 |
| `scope` | "" | デフォルトの走査スコープ（空=全体） |
| `forbidden_targets` | (下記参照) | 改善対象から除外するパターン |

forbidden_targets のデフォルト値:

- `hooks/*.sh`
- `vibecorp.yml`
- `MVV.md`
- `SECURITY.md`
- `POLICY.md`
- `skills/**`（再帰マッチ。`**` が `.*` に変換され、`.claude/skills/` 配下の全 SKILL.md・サブディレクトリを保護する）

### 3. diagnose-active スタンプ作成

```bash
source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
stamp_dir="$(vibecorp_state_mkdir)"
touch "${stamp_dir}/diagnose-active"
```

このスタンプが存在する間、diagnose-guard.sh が保護ファイルへの変更を deny する。

### 4. 改善点の発見

以下の4つを並行して実行する:

#### 4a. /vibecorp:harvest-all --dry-run の実行

```text
/vibecorp:harvest-all --dry-run を実行してください。
```

結果のレポートを取得する。`--scope` が指定されている場合は `/vibecorp:harvest-all --dry-run --scope <path>` で実行する。

#### 4b. CTO による技術的負債分析

CTO エージェントに以下を依頼する。プロンプトは `skills/diagnose/prompts/agent-call-cto-tech-debt.md` を参照する。

`--scope` が指定されている場合はそのディレクトリに限定して分析する。

#### 4c. CPO によるプロダクト整合分析

CPO エージェントに以下を依頼する。プロンプトは `skills/diagnose/prompts/agent-call-cpo-mvv-alignment.md` を参照する。

`--scope` が指定されている場合はそのディレクトリに限定して分析する。

#### 4d. Claude Code 仕様準拠分析

`claude-code-guide` エージェントに以下を依頼する。プロンプトは `skills/diagnose/prompts/agent-call-claude-code-guide-drift.md` を参照する。

`--scope` が指定されている場合はそのディレクトリに限定して分析する。

**スコープは仕様ドリフトの検出に限定する**。以下は 4d の対象外:
- MVV / プロダクト方針との整合（→ 4c CPO 分析の責務）
- 技術的負債一般（→ 4b CTO 分析の責務）
- セキュリティ脆弱性（→ ステップ 5 CISO フィルタの責務）

**フォールバック動作**: `claude-code-guide` が利用不可（外部依存の障害等）の場合は 4d をスキップし、4a / 4b / 4c の結果のみで続行する。スキップした事実はステップ 8 の候補一覧レポートに「4d: スキップ（claude-code-guide 利用不可）」として明記する。

**データ取得方式**:
- 取得頻度は `claude-code-guide` 側に委譲する（`/vibecorp:diagnose` 自身はキャッシュを持たない）
- GitMCP（`gitmcp.io`）には依存しない。`claude-code-guide` が WebFetch + WebSearch で `docs.claude.com` を直接参照する設計とする
- API 課金影響は full プリセットの想定コスト枠内に収める（詳細は `docs/cost-analysis.md` を参照）

### 5. CISO フィルタリング（自己制約緩和チェック）

CISO エージェントに発見した改善候補を渡し、以下をチェックさせる。プロンプトは `skills/diagnose/prompts/agent-call-ciso-self-constraint.md` を参照する。

CISO が「除外」と判定した候補はリストから除外する。

### 6. CPO フィルタリング（MVV 整合チェック）

CPO エージェントに残った候補を渡し、以下をチェックさせる。プロンプトは `skills/diagnose/prompts/agent-call-cpo-mvv-filter.md` を参照する。

CPO が「除外」と判定した候補はリストから除外する。

### 6b. SM フィルタリング（自律実行可否チェック）

SM エージェントに残った候補を渡し、`rules/autonomous-restrictions.md` の不可領域に該当するものを除外させる。プロンプトは `skills/diagnose/prompts/agent-call-sm-autonomous-filter.md` を参照する。

SM が「除外」と判定した候補はリストから除外する。

**3者承認ゲート**: ここまでで CISO + CPO + SM の3者フィルタを通過した候補のみが `/vibecorp:autopilot` → `/vibecorp:ship-parallel` での自律実行対象となる。

### 7. 起票上限チェック

既存の [diagnose] ラベル付き Issue を確認する:

```bash
gh issue list --label "diagnose" --state open --json number --jq 'length'
```

当日起票済みの diagnose Issue 数を確認する:

```bash
gh issue list --label "diagnose" --state all --json createdAt --jq '[.[] | select(.createdAt | startswith("'$(date -u +%Y-%m-%d)'"))] | length'
```

- オープン中の diagnose Issue 数 + 今回起票予定数が `max_issues_per_run` を超える場合、超過分を候補から除外する
- 当日起票済み + 今回起票予定数が `max_issues_per_day` を超える場合、超過分を候補から除外する

### 8. ユーザーへ候補一覧提示

```text
## /vibecorp:diagnose 改善候補

| # | カテゴリ | 優先度 | タイトル | 対象ファイル | 根拠 |
|---|---------|--------|---------|-------------|------|
| 1 | 技術的負債 | 高 | {タイトル} | {ファイルパス} | {理由} |
| 2 | テスト不足 | 中 | {タイトル} | {ファイルパス} | {理由} |

### フィルタ結果（3者承認ゲート）
- 発見: {n} 件
- CISO 除外: {n} 件（自己制約緩和）
- CPO 除外: {n} 件（MVV 不整合）
- SM 除外: {n} 件（不可領域 — 認証 / 暗号 / 課金構造 / ガードレール / MVV / CI エージェント）
- 上限除外: {n} 件
- 最終候補: {n} 件

起票しますか？
- 全て起票: y
- 選択して起票: 番号をカンマ区切りで指定（例: 1,3）
- 中止: n
```

`--dry-run` の場合はこのレポートを出力して終了する（スタンプも削除する）。

### 9. Issue 起票

ユーザーが承認した候補について、`/vibecorp:issue` スキルで起票する。

各 Issue には以下を付与する:
- ラベル: `diagnose`
- タイトルプレフィックス: `[diagnose]`
- 本文には Anthropic 公式推奨の 4 要素を構造的に含める（後段の `/vibecorp:plan-review-loop` が完了条件を前提に走るため、空欄にしない）

#### 自律起票時の本文テンプレ

`/vibecorp:diagnose` が自律起票する Issue は、以下のセクション構造で本文を生成する:

```markdown
## 💡 概要

<改善候補の概要 — 動作主語で「〜になる」「〜できるようになる」と書く>

## 🎯 背景

<なぜこの改善が必要か — CTO/CPO 分析の根拠>

## 📝 提案

<具体的な改善内容>

## ✅ 完了条件

<!-- 検証可能なチェックリスト形式（acceptance criteria）。空欄不可。 -->
- [ ] <検証可能な完了条件 1>
- [ ] <検証可能な完了条件 2>
- [ ] tests/ 配下に検証テストが追加され、CI で通っている

## 📍 関連ファイル

<!-- 触れるファイル・モジュールのパス（relevant file locations）。空欄不可。 -->
- `<対象ファイル 1>`
- `<対象ファイル 2>`

---
この Issue は /vibecorp:diagnose による自律改善ループで自動起票されました。
実装は /vibecorp:ship で別途実行してください。
```

`## ✅ 完了条件` と `## 📍 関連ファイル` セクションは必須。`/vibecorp:diagnose` が自律起票する場合も、CTO/CPO 分析時点でこの 2 要素を確定させてから `/vibecorp:issue` に渡すことで、`/vibecorp:issue` の CPO 4 要素チェック（ステップ 6b）を確実に通過させる。

### 10. diagnose-active スタンプ削除

```bash
source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
rm -f "$(vibecorp_state_path diagnose-active)"
```

### 11. 結果レポート

```text
## /vibecorp:diagnose 完了

### 起票済み Issue
| # | タイトル | URL |
|---|---------|-----|
| 1 | {タイトル} | {URL} |

### サマリ
- 発見: {n} 件
- フィルタ除外: {n} 件
- 起票: {n} 件
- スキップ（ユーザー判断）: {n} 件
```

## 介入ポイント

以下の状況ではユーザーに報告して判断を委ねる:

| 状況 | タイミング |
|------|-----------|
| full プリセットでない | ステップ 1 |
| 改善候補が 0 件 | ステップ 7 |
| ユーザーが起票を承認しない | ステップ 8 |
| gh CLI が利用できない | ステップ 9 |

## 制約

- **コード変更は一切行わない** — Issue 起票のみ
- **forbidden_targets に含まれるファイルの変更を提案しない**
- `--force`、`--hard`、`--no-verify` は使用しない
- **jq では string interpolation `\(...)` を使わない** — Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する
- **コマンドをそのまま実行する** — `2>/dev/null`、`|| echo`、`; echo` 等のリダイレクトやフォールバックを付加しない（[根拠](docs/design-philosophy.md#コマンドリダイレクトフォールバックの禁止)）
- 介入ポイントではユーザーの指示を待つ（自動でスキップしない）
- diagnose-active スタンプは正常終了・異常終了を問わず必ず削除する
