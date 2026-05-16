---
description: LLM 向けプロンプト（CLAUDE.md / rules / agents / SKILL.md / knowledge / MVV / 配布版 / templates 配布元）に追加適用する作成基準。claude-code-guide サブエージェントで Claude Code 公式仕様を確認することを MUST 化する
paths:
  - "CLAUDE.md"
  - "CLAUDE.local.md"
  - "MVV.md"
  - ".claude/CLAUDE.md"
  - ".claude/rules/**/*.md"
  - ".claude/agents/**/*.md"
  - ".claude/knowledge/**/*.md"
  - "skills/**/SKILL.md"
  - ".claude/vibecorp-base/CLAUDE.md"
  - ".claude/vibecorp-base/MVV.md"
  - ".claude/vibecorp-base/rules/**/*.md"
  - ".claude/vibecorp-base/skills/**/SKILL.md"
  - "templates/claude/agents/**/*.md"
  - "templates/claude/rules/**/*.md"
  - "templates/claude/knowledge/**/*.md"
---

# プロンプト作成基準

> [!IMPORTANT]
> 新規プロンプト作成・既存プロンプト改修（`skills/**/SKILL.md`, `.claude/agents/*.md`, `.claude/rules/*.md`）の前に、**必ず `claude-code-guide` サブエージェントで Claude Code 公式仕様 (`docs.claude.com`) を確認すること**。確認対象トピックは下記「[claude-code-guide 参照（MUST）](#claude-code-guide-参照must)」を参照。仕様確認なしの新規作成・改修は禁止パターン①に該当する。

## 対象範囲

本ルールは frontmatter の `paths` で指定された LLM 向けプロンプトファイルを Claude が読む / 編集する際に lazy-load される（公式仕様: https://code.claude.com/docs/en/memory#path-specific-rules ）。

| 対象種別 | 役割 |
|---------|------|
| Claude Code 公式メモリ | プロジェクト共通指示（`CLAUDE.md` / `CLAUDE.local.md` / 階層内 `.claude/CLAUDE.md`） |
| プロジェクト規範 | Mission / Vision / Values 等の根本方針 |
| 常駐ルール | 全会話でロードされる規約（rules ディレクトリ配下の `.md`） |
| エージェント定義 | 専門家ロール（agents ディレクトリ配下の `.md`） |
| ナレッジ規範 | 領域別の原則文書（knowledge ディレクトリ配下の `.md`） |
| スキル本体 | 動線・オーケストレーション（`SKILL.md`） |
| 配布パッケージ | プラグインとして他プロジェクトに配布する基本セット |
| 配布元テンプレート | install 時に他プロジェクトへ展開されるテンプレート |

具体的なパスは frontmatter の `paths` で定義する。利用先プロジェクトでは自プロジェクトの構成に合わせて paths を上書き可能。

ベース基準として `document-writing.md` も同時に適用される（全 `.md` に paths で適用）。本ルールはその拡張として **claude-code-guide MUST 参照 + frontmatter + triggering** を追加する。

### 対象外

- YAML / TOML 等の `.md` 以外の LLM プロンプトファイル（paths 機能の対象外）
- 純粋なドキュメント（READMEなど、`document-writing.md` だけが適用される）
- 一時ファイル・キャッシュ（リポジトリ外）
- 各種 UI テンプレート（GitHub UI 等、`document-writing.md` だけが適用される）
- コード内コメント（`.md` 拡張子ではない）

CEO 向けの文面規約（対話応答・Issue / PR 本文・コミット・監査レポート）は `communication.md` で別途定義する。本ルールはプロンプト本体専用で、対象が重ならない。

## claude-code-guide 参照（MUST）

新規プロンプト作成・既存プロンプト改修では、`claude-code-guide` サブエージェントを用いて Claude Code 公式仕様（`docs.claude.com`）を確認してから書く。

### claude-code-guide の振る舞い

- 公式 Claude Code ドキュメント（`docs.claude.com`）を WebFetch + WebSearch で直接参照する SubAgent
- GitMCP には依存しない（`docs.claude.com` 直参照）

### 既存利用箇所（例: vibecorp での運用）

- diagnose スキルの仕様準拠チェック段階で claude-code-guide を呼び出す
- `hooks/guide-gate.sh`（standard 以上）が `.claude/` 配下テンプレ Edit/Write/MultiEdit 時に必須参照を強制し、スタンプ消費で許可する

利用先プロジェクトでは独自のフック / スキル動線に組み込んで運用する。

### 確認必須トピック

| トピック | 確認内容（公式正式キー名） | 逸脱時の帰結 |
|----------|--------------------------|----------------|
| Skill triggering | `name` / `description`（MUST）/ `when_to_use`（option）/ `disable-model-invocation` / `user-invocable`。`description` + `when_to_use` の合計 1,536 文字以内が自動呼び出し判定に使われる | スキルが triggering されず実質呼ばれない |
| Hook event types | `PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `UserPromptSubmit` / `SessionStart` / `SessionEnd` / `Stop` / `StopFailure` / `FileChanged` / `ConfigChange` / `CwdChanged`。matcher は `"*"` または正規表現、MCP ツールは `mcp__<server>__<tool>` 形式 | フックが発火しない・誤動作 |
| SubAgent context | `description` / `tools` / `model` / `context: fork` / `agent`（Explore / Plan / general-purpose 等）。`CLAUDE.md` は常時読み込まれるが **会話履歴は継承されない** | SubAgent 実行時に権限・情報不足で失敗 |
| MCP server 設定 | `.mcp.json` トップレベルキーは `mcpServers`（複数形）。サーバー定義は `type`（`http` / `sse` / `stdio`）/ `url`（リモート）/ `command` + `args`（stdio）/ `env`。`streamable-http` は `http` の公式 alias | MCP サーバーが起動しない |
| settings.json 構造 | セクション: `permissions`（`allow` / `ask` / `deny`）/ `hooks` / `env` / `model` / `effortLevel`。優先順位（高→低）: Managed > Command-line > Local（`.claude/settings.local.json`）> Project（`.claude/settings.json`）> User（`~/.claude/settings.json`）。permission ルールは `Tool` または `Tool(specifier)` 形式 | 意図しない権限漏れ・遮断 |

出典: `docs.claude.com` 配下の skills / hooks / subagents / mcp / configuration ドキュメント（`claude-code-guide` 経由で WebFetch することで最新仕様に追従）

### 起動例

```text
claude-code-guide サブエージェントに以下を依頼する:
「`PreToolUse` フックの最新仕様（イベント名・タイミング・matcher 構造）を docs.claude.com で確認してください」
```

### フォールバック

`claude-code-guide` が利用不可な場合（外部依存障害等）は、`hooks/guide-gate.sh` のフォールバック動作と整合させ、`docs.claude.com` を WebFetch で直参照する。**完全に省略はしない**（仕様ドリフト検出の最後の砦のため）。

## YAML frontmatter の書き方

スキル / エージェントの YAML frontmatter は **最小限・正確に書く**。

### スキル（`SKILL.md`）

```markdown
---
name: <kebab-case>
description: "<具体トリガー語句を含む 1〜3 行>"
---
```

- `name`: kebab-case で 1 行。スキルディレクトリ名と一致させる
- `description`: 後述「[description triggering 設計](#description-triggering-設計)」に従う。**MUST**（公式仕様）
- `when_to_use`: option。`description` と合算で 1,536 文字以内に収める
- `disable-model-invocation` / `user-invocable`: 自動呼び出しを禁止する場合のみ付ける
- 公式 docs に記載のないキーを足さない

### エージェント（`agents/*.md`）

```markdown
---
name: <kebab-case>
description: >
  <ロール概要 1 行>
  <主務 1〜2 行>
  「<トリガー語句>」と言った時に使用。
tools: Read, Edit, Write, MultiEdit, Bash, Grep, Glob
model: sonnet
---
```

- `tools`: そのエージェントが実際に使うツールのみ列挙する。`*` 指定は権限過剰で禁止
- `model`: 既存エージェントは `sonnet` を選んでいる。逸脱する場合は理由を本文に明記する
- `context: fork`: 隔離実行が必要な場合のみ付ける（会話履歴は元々継承されないため通常は不要）
- `description` 末尾に必ず日本語のトリガー語句を入れる（後述）

### ルール（`rules/*.md`）

ルールは frontmatter を省略可能だが、適用範囲を限定する場合は以下のキーを使う:

```markdown
---
description: <1 行説明>
paths: ["<glob1>", "<glob2>"]
---
```

例: あるルールが `paths: ["skills/**"]` でスコープをスキル領域に絞る。

## description triggering 設計

`description` は Claude Code がスキル・エージェントを triggering する判断材料。**具体トリガー語句を必ず含める**。

### MUST

- 「〜と言った時に使用」「〜と言われた時に使う」形式の日本語トリガー語句を 2 個以上列挙する
- スキル / エージェントが扱う **対象オブジェクト**（Issue / PR / コスト / コード / 等）を明記する
- 主務動詞（**確認 / 起票 / 修正 / 集計 / レビュー / 監査** 等）を含める
- `description` + `when_to_use`（あれば）の合計 1,536 文字以内に収める

### SKIP（明示するとさらに精度が上がる）

trigger 条件と紛らわしいケースを `SKIP:` 句で除外する。

例（`example-skills:claude-api` の SKIP 句を参考）:

```text
SKIP: file imports `openai`/other-provider SDK, filename like `*-openai.py`/`*-generic.py`, provider-neutral code
```

隣接スキル（例: 単発実行スキル + 定期実行ループスキル）が存在する場合、「<別用途>は <別スキル名> を使う」のように **隣接スキルへの誘導** で SKIP を表現すると、Claude Code 側の triggering 判断がより正確になる。

### 禁止

- 抽象動詞だけ（「補助する」「サポートする」）でトリガー語句なし
- 「色々できる」「便利」のような網羅的形容詞
- 命名規則の説明（命名そのものではなく、命名で何が triggering されるか）

## 役割境界

スキル / エージェント / ルールの **責務を曖昧にしない**。

| 種別 | 性質 | 主な動詞 |
|------|------|----------|
| スキル | 動線・オーケストレーション | 起票する / 作成する / 実行する / 委譲する |
| エージェント | 専門家ロール | 判断する / 評価する / レビューする |
| ルール | 常駐規約 | 〜すること / 〜しないこと |

### 境界を超えてはならない例

- ❌ スキル内で常駐規約を再定義する（ルールに置く）
- ❌ エージェント定義で動線オーケストレーションを兼務する（スキルに置く）
- ❌ ルールでツール呼び出しのオーケストレーションを書く（スキルに置く）

### 既存パターン（例: vibecorp での運用）

- 動線スキル（例: `/ship`）が別の動線スキル（例: `/plan`）と専門家エージェント（CTO / CFO / CISO 等）を呼び出す
- スキル間の呼び出し制約は専用ルール（例: `self-contained.md`）が規定する
- スキル使用そのものを義務化するのも別ルール（例: `use-skills.md`）が担う

## LLM 行動主語ルール

プロンプト本体（スキル / エージェント / ルール）は **LLM の行動そのものを記述する** ため、主語と語尾を以下で統一する。

### MUST

- 主語: 「このスキル / このエージェント / LLM 自身」を **省略主語** として書く
- 語尾: 「〜する / 〜しない / 〜すること / 〜禁止」を使う

### Before / After

| 形式 | Before（NG） | After（OK） |
|------|--------------|------------|
| 指示 | 〜してください | 〜する |
| 禁止 | 〜は避けてください | 〜しない / 〜禁止 |
| 条件 | もし〜なら、〜してもよい | 〜の場合は〜する |

### communication.md との違い

`communication.md` の「動作主語」は **CEO 報告向け文面**（「〜になった／〜できるようになった」）で、ソフトウェアの **挙動変化** を主語にする規約。本ルールの「LLM 行動主語」は **LLM 自身の行動** を主語にする規約。両者は対象文面が異なるため重ならない。

## 指針（MUST）

1. **claude-code-guide で仕様確認してから書く**
   - 新規プロンプト作成・既存プロンプト改修の前に必ず `claude-code-guide` で公式仕様 (`docs.claude.com`) を確認する
   - Skill triggering / Hook events / SubAgent context / MCP / settings.json の最新仕様を反映する

2. **frontmatter は最小限・正確に書く**
   - `name` は kebab-case でファイル名と一致
   - `description` は具体トリガー語句を含む 1〜3 行
   - 公式 docs に無いキーを足さない

3. **description には具体トリガー語句を含める**
   - 日本語の「〜と言った時に使用」を 2 個以上
   - 対象オブジェクトと主務動詞を含める
   - 紛らわしいケースは `SKIP:` 句で除外する

4. **役割境界を超えない**
   - スキル（動線）/ エージェント（専門家）/ ルール（常駐規約）の責務を曖昧にしない
   - スキルが規約を定義したり、エージェントが動線を兼務しない

5. **LLM の行動を主語にする**
   - 「〜してください」ではなく「〜する」「〜しない」で書く
   - 受け身・婉曲表現を避ける

## 禁止パターン

- ❌ **claude-code-guide 不使用での新規プロンプト作成・改修**
  - 仕様ドリフトの最大の原因。MUST 指針①に違反する
- ❌ **description にトリガー語句が無い**
  - スキル・エージェントが Claude Code 側で triggering されなくなる
- ❌ **役割越境**
  - スキルが常駐ルールを定義する／エージェントが動線オーケストレーションを兼務する／ルールがツール呼び出しの段取りを書く
- ❌ **テスト不能な記述**
  - 中核セクションが揃わない／必須項目が grep で検出できない／`tests/test_*_rule.sh` で静的検証できない
- ❌ **暗黙の Claude Code 仕様への依存**
  - 廃止イベント名・旧キー・SubAgent context の誤解。公式 docs を fetch せず手元の知識だけで書く

## テスト可能性

ルール本体は `tests/test_<rule_name>_rule.sh` で **中核セクション存在を静的検証** する。

### 静的検証で確認すること

- ルールファイル本体の存在
- 冒頭 `> [!IMPORTANT]` / `> [!NOTE]` 等のコールアウト存在
- 中核セクション見出し（`^## ` で grep）の存在
- 必須参照（claude-code-guide / 関連ルールへの相互参照）の存在
- 指針 / 禁止パターン項目数の下限

### shell.md 整合

- `grep -q -e` でパターン終端を明示（`-` 始まりパターン対策）
- `set -euo pipefail` 下で前提ファイル不在時は `fail` 後に `exit 1`（後続テスト無効化防止）
- `sed -i` 不使用、Bash 互換性確保

### 既存テストとの整合

`tests/test_communication_rule.sh` と同じ構造に従う。`tests/lib/test_helpers.sh` の `assert_file_exists` / `assert_file_contains` / `pass` / `fail` を使う。

## 関連ルール

- `communication.md`: CEO 報告向け文面規約（動作主語）。本ルールと対象文面が異なる
- `self-contained.md`: スキル間依存ガード。プリセット境界を越えない設計を支える
- `use-skills.md`: スキル使用義務。役割境界（動線はスキルが担う）を支える
- `markdown.md`: フェンスコードブロック言語指定義務。プロンプト内コードブロックも対象

## 関連エージェント

- `claude-code-guide`: Claude Code 公式仕様（`docs.claude.com`）参照用 SubAgent。本ルールの中核

## 関連ファイル（例: vibecorp での運用）

- 「指針 MUST + 禁止パターン」3 層構造の原型: PR スキルの概要書き方プロンプト
- `.claude/` 配下テンプレ編集時の必須参照ゲート: `hooks/guide-gate.sh`
- claude-code-guide 既存利用例: diagnose スキルの仕様準拠チェック段階
