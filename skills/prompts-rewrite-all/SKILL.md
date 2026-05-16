---
name: prompts-rewrite-all
description: "skills/**/SKILL.md・.claude/agents/*.md・.claude/rules/*.md を .claude/rules/prompt-writing.md 基準で一括書き直し提案するスキル。「/prompts-rewrite-all」「プロンプト書き直し」「スキル一括書き直し」「エージェント書き直し」と言った時に使用。claude-code-guide サブエージェントで Claude Code 公式仕様（docs.claude.com）を確認し、frontmatter / description triggering / 行動主語の 3 軸を検証する。diff 提案 → CEO 承認 → 書き換えの 2 段階で挙動を壊さず適用する。自動マージ禁止。"
---

# 🤖 プロンプト一括書き直しスキル

> [!IMPORTANT]
> 本スキルは `.claude/rules/prompt-writing.md` 基準で LLM 向けプロンプト群を一括書き直しする。
> 書き直し前に必ず `claude-code-guide` サブエージェントで Claude Code 公式仕様（`docs.claude.com`）を確認する。
> diff 提案 → CEO 承認 → 書き換えの 2 段階を必須とする。自動マージは禁止。

## 🎯 対象範囲

本スキルが書き直しの対象とするファイルは以下とする。

| 種別 | パス |
|------|------|
| ⚙️ スキル | `skills/**/SKILL.md` |
| 🤝 エージェント | `.claude/agents/*.md` |
| 📜 ルール | `.claude/rules/*.md` |

配布版も同期チェックの対象とする。

- `.claude/vibecorp-base/skills/**/SKILL.md`
- `templates/claude/agents/*.md`
- `templates/claude/rules/*.md`

### 対象外

- YAML / TOML 等の `.md` 以外のプロンプトファイル
- README.md・docs/ 配下の純粋なドキュメント（→ `/vibecorp:docs-rewrite-all`）
- コード内コメント

## 📝 使用方法

```bash
/vibecorp:prompts-rewrite-all
/vibecorp:prompts-rewrite-all --target skills
/vibecorp:prompts-rewrite-all --target agents
/vibecorp:prompts-rewrite-all --target rules
```

- `--target` 未指定なら 3 種別を順次処理する
- 1 ファイル単位で diff 提案 → CEO 承認 → 書き換えを繰り返す

## 🔁 ワークフロー

### 1. 対象ファイル列挙

3 種別の対象を列挙する。

```bash
find skills -name 'SKILL.md' -type f
find .claude/agents -maxdepth 1 -name '*.md' -type f
find .claude/rules -maxdepth 1 -name '*.md' -type f
```

- 隠しファイルやサブディレクトリ配下は対象外
- 配布版（`.claude/vibecorp-base/` / `templates/`）は本体書き換え後の同期で扱う

### 2. 基準ファイル照合

基準ファイルは `.claude/rules/prompt-writing.md` とする。

各対象ファイルを基準と照合する。

照合観点:
- 📝 frontmatter スキーマが最小限・正確
- 🪝 description に具体トリガー語句あり
- 🗣️ 本文が LLM 行動主語で書かれている

### 3. 📡 claude-code-guide サブエージェント呼出（MUST）

書き直し提案を生成する前に `claude-code-guide` サブエージェントを呼ぶ。

依頼内容のテンプレートは以下のとおり。

```text
claude-code-guide に以下を依頼する:

対象ファイル <path> と公式 Claude Code 仕様（docs.claude.com）を照合し、
仕様逸脱を検出してください。

確認トピック:
- Skill triggering（name / description / when_to_use / 1,536 文字制限）
- Hook event types（公式 29 種・matcher 構造）
- SubAgent context（description / tools / model / context: fork）
- MCP server 設定（mcpServers / type / url / command）
- settings.json 構造（permissions / hooks / env / model）

逸脱箇所と公式仕様の差分を返してください。
```

#### 🛟 フォールバック

`claude-code-guide` が利用不可な時は代替手段を取る。

- `docs.claude.com` を WebFetch で直参照する
- 完全省略は禁止（仕様ドリフト検出の最後の砦）

### 4. 🔍 3 軸検証

`claude-code-guide` の結果と基準照合の結果を 3 軸でまとめる。

| 軸 | 検証内容 |
|----|---------|
| 📝 frontmatter スキーマ | `name` / `description` / `paths` / `tools` / `model` の有無と正確性 |
| 🪝 description triggering | 日本語トリガー語句 2 個以上・対象オブジェクト・主務動詞・SKIP 句 |
| 🗣️ LLM 行動主語 | 「〜する／〜しない／〜すること／〜禁止」の語尾統一 |

1 軸でも逸脱があれば書き直し対象とする。

### 5. 書き直し提案

3 軸検証の結果を踏まえ書き直し案を生成する。

提案ルール:
- frontmatter と本文の両方を対象とする
- 既存セクション構造（見出し・表・コード）は可能な限り保持する
- 1 文 50 文字以下のスキャン性を担保する
- マークダウンフェンスには言語指定を付ける（`markdown.md` 整合）

### 6. 🛑 diff を CEO に提示（承認ゲート）

書き直し案を `git diff` 形式の差分で CEO に提示する。

提示フォーマット例:

```diff
--- a/<path>
+++ b/<path>
@@ -1,3 +1,3 @@
- description: ぼんやりした説明
+ description: 「/foo」「foo して」と言った時に使用。...
```

承認ゲートのルール:
- CEO が「承認」と返した場合のみ次ステップに進む
- 「却下」または無回答ならスキップして次のファイルに移る
- 自動マージは禁止する
- CEO 承認なしに本体ファイルを書き換えない

### 7. 承認後にファイル書き換え

CEO 承認を受けたファイルのみ `Edit` または `Write` で書き換える。

- 対象は本体（`skills/**/SKILL.md` / `.claude/agents/*.md` / `.claude/rules/*.md`）
- 書き換え後に `git status` と `git diff` で差分が想定どおりか確認する
- 想定外の差分があれば CEO に再提示する

### 8. 📦 配布版同期チェック

書き換えた本体に対応する配布版を同期する。

| 本体 | 配布版 |
|------|--------|
| `skills/**/SKILL.md` | `.claude/vibecorp-base/skills/**/SKILL.md` |
| `.claude/agents/*.md` | `templates/claude/agents/*.md` |
| `.claude/rules/*.md` | `templates/claude/rules/*.md`（該当する場合） |

- 配布版が存在する場合は本体と同内容で更新する
- 差分が残ったら CEO に再提示する
- 配布版が存在しない種別（対象外パス）は同期不要

### 9. レポート出力

最終的に以下のレポートを返す。

```text
## /vibecorp:prompts-rewrite-all レポート

- 対象ファイル数: N
- 書き直し提案: M
- CEO 承認: A
- 書き換え完了: A
- 配布版同期: B
- スキップ: S
- claude-code-guide: 呼出 / フォールバック / エラー の内訳
```

## ✅ 指針（MUST）

1. 📡 **claude-code-guide で仕様確認してから書き直す**
   - 各ファイル書き直し提案前に `claude-code-guide` を呼ぶ
   - フォールバック時も `docs.claude.com` を WebFetch する
   - 完全省略は禁止

2. 🔍 **3 軸検証を全ファイルに適用する**
   - frontmatter / description triggering / 行動主語の 3 軸を必ず通す
   - 1 軸でも逸脱があれば書き直し対象とする

3. 🛑 **diff 提案 → CEO 承認 → 書き換えの 2 段階を守る**
   - CEO 承認なしに本体ファイルを書き換えない
   - 自動マージは禁止する

4. 📦 **配布版を同期する**
   - 本体書き換え後に配布版を同期する
   - 差分が残ったら CEO に再提示する

5. 🗣️ **書き直し後の本文も LLM 行動主語で書く**
   - 「〜する」「〜しない」で統一する
   - 受け身・婉曲表現は使わない

## ❌ 禁止パターン

- ❌ **claude-code-guide を経由せずに書き直し提案を生成する**
  - 仕様ドリフト検出の最後の砦を破壊する
- ❌ **CEO 承認なしにファイルを書き換える**
  - 自動マージ禁止に違反する
- ❌ **本体だけ書き換えて配布版を放置する**
  - 利用先プロジェクトに伝搬しない
- ❌ **行動主語以外の語尾で本文を書き直す**
  - 「〜してください」「〜するとよい」は禁止
- ❌ **frontmatter の公式キー以外を勝手に追加する**
  - 公式仕様逸脱を引き起こす

## 🔗 関連

- 基準ルール: `.claude/rules/prompt-writing.md`
- ベース基準: `.claude/rules/document-writing.md`
- 動作主語規約: `.claude/rules/communication.md`
- マークダウン規約: `.claude/rules/markdown.md`
- 兄弟スキル（ドキュメント類）: `/vibecorp:docs-rewrite-all`
- 仕様確認 SubAgent: `claude-code-guide`
