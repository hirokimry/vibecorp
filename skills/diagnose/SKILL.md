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
- **3者承認ゲート**: CISO + CPO + SM の3者フィルタで自律実行不可領域（認証 / 暗号 / 課金構造 / ガードレール / MVV）を自動除外する（rules/autonomous-restrictions.md 準拠）

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
| `max_issues_per_run` | 5 | 1回の実行で起票する最大 Issue 数 |
| `max_issues_per_day` | 10 | 1日に起票する最大 Issue 数 |
| `max_files_per_issue` | 10 | 1つの Issue に含める最大ファイル数 |
| `scope` | "" | デフォルトの走査スコープ（空=全体） |
| `forbidden_targets` | (下記参照) | 改善対象から除外するパターン |

forbidden_targets のデフォルト値:

- `hooks/*.sh`
- `vibecorp.yml`
- `MVV.md`
- `SECURITY.md`
- `POLICY.md`

### 3. diagnose-active スタンプ作成

```bash
source "$CLAUDE_PROJECT_DIR"/.claude/lib/common.sh
stamp_dir="$(vibecorp_state_mkdir)"
touch "${stamp_dir}/diagnose-active"
```

このスタンプが存在する間、diagnose-guard.sh が保護ファイルへの変更を deny する。

### 4. 改善点の発見

以下の3つを並行して実行する:

#### 4a. /vibecorp:harvest-all --dry-run の実行

```text
/vibecorp:harvest-all --dry-run を実行してください。
```

結果のレポートを取得する。`--scope` が指定されている場合は `/vibecorp:harvest-all --dry-run --scope <path>` で実行する。

#### 4b. CTO による技術的負債分析

CTO エージェントに以下を依頼する:

```text
以下の観点でコードベースを分析し、改善候補をリストアップしてください:
- 技術的負債（コード重複、過度な複雑性、古い依存関係）
- テストカバレッジの不足
- エラーハンドリングの改善余地
- パフォーマンスボトルネック
- スピード/UX（ユーザー待ち時間の短縮）:
  - 並列化可能な逐次処理（独立したエージェント呼び出し・スキル呼び出し・テストが直列に並んでいる箇所）
  - 同期待ちが長いフェーズ（CI 待ち・レビュー待ち等の構造的ボトルネック）
  - フック実行時間の肥大化（PreToolUse / PostToolUse フックが 1 処理あたり閾値を超える）
  - スキル間の冗長な再実行（同じチェック・同じ走査が複数スキルで重複実行されている）

**スピード/UX 観点で出してはいけない提案（CFO 管轄に閉じ込める）**:
- モデル指定の変更提案（Opus → Sonnet 等）は出さない
- エージェント削減・合議制回数削減は出さない
- 並列度自体の削減は出さない
- `max_issues_per_run` / `max_issues_per_day` 等のコスト上限値の変更は出さない
```

`--scope` が指定されている場合はそのディレクトリに限定して分析する。

#### 4c. CPO によるプロダクト整合分析

CPO エージェントに以下を依頼する:

```text
以下の観点でコードベースを分析し、MVV・プロダクト方針に沿っていない箇所をリストアップしてください:
- MVV.md のバリューに属さない機能の検出（例: 規律の自動化に寄与しないフック）
- docs/specification.md / docs/design-philosophy.md と矛盾する実装
- 追加されたが使われていない機能（dead feature）
- プリセット間でのスコープ漏れ（full 専用機能が standard に露出している等）
```

`--scope` が指定されている場合はそのディレクトリに限定して分析する。

### 5. CISO フィルタリング（自己制約緩和チェック）

CISO エージェントに発見した改善候補を渡し、以下をチェックさせる:

```text
以下の改善候補について、自己制約の緩和に該当するものがないかチェックしてください:
- protect-files の保護対象を削減する提案
- hook の条件を緩和する提案
- セキュリティガードレールを弱める提案
- forbidden_targets に含まれるファイルの変更提案

該当する候補には「除外」と判定してください。
```

CISO が「除外」と判定した候補はリストから除外する。

### 6. CPO フィルタリング（MVV 整合チェック）

CPO エージェントに残った候補を渡し、以下をチェックさせる:

```text
以下の改善候補について、MVV.md に定義されたミッション・ビジョン・バリューとの整合性をチェックしてください:
- MVV に反する変更提案がないか
- プロジェクトの方向性と合致しているか

整合しない候補には「除外」と判定してください。
```

CPO が「除外」と判定した候補はリストから除外する。

### 6b. SM フィルタリング（自律実行可否チェック）

SM エージェントに残った候補を渡し、`rules/autonomous-restrictions.md` の不可領域に該当するものを除外させる。

```text
以下の改善候補について、rules/autonomous-restrictions.md に定義された不可領域に該当するものをチェックしてください:

不可領域:
1. 認証（hooks/*auth*, hooks/*permission*, settings.json の permissions, gh auth, ANTHROPIC_API_KEY 扱い）
2. 暗号（encrypt/decrypt/secret/credential/token を扱うコード）
3. 課金構造（docs/cost-analysis.md, max_issues_per_day 等のコスト上限, claude -p / npx / bunx で LLM を呼ぶ箇所、**モデル指定の変更（Opus → Sonnet 等）**）
4. ガードレール（protect-files.sh, diagnose-guard.sh, forbidden_targets, diagnose-active スタンプの制御、**エージェント削減・合議制回数削減・並列度自体の削減**）
5. MVV（MVV.md 自体の変更）

該当する候補には「除外」と判定し、理由として該当領域名を付記してください。
```

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
- SM 除外: {n} 件（不可領域 — 認証 / 暗号 / 課金構造 / ガードレール / MVV）
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
