# Claude Code における agents と skills の使い分け

## 結論

agents は「役割・アイデンティティ・判断」を持つものだけに使う。
ツール制限やモデル選択のためだけに agent を作るのはアンチパターン。

## agents と skills の本質的な違い

| 観点 | agents | skills |
|---|---|---|
| 本質 | 「誰が」— アイデンティティと権限の境界 | 「何を・どう」— ワークフローと手順 |
| 起動方法 | Agent ツールで spawn | `/skill-name` でユーザーが呼ぶ |
| 制御できるもの | model選択、tools制限、isolated context | ステップの順序、並列/順次、ループ制御 |
| 適する場面 | 判断が必要、権限を絞りたい、モデルを変えたい | 手順定義、複数ステップの組み合わせ |

## agents にすべきもの（Role Agents）

- 専門領域の判断者: CTO, CPO, SM, CFO, CLO, CISO 等
- 特徴:
  - MVV や principles に基づいて自律的に意思決定する
  - knowledge/ に判断を蓄積する（decisions.md）
  - 「私は○○です」という持続的なアイデンティティがある
  - 他のエージェントとの権限境界が明確（role-gate で管轄ファイルを制限）

## agents にすべきでないもの（スキル内のステップで十分）

### CLIラッパー型
- coderabbit-reviewer: `cr review` を叩くだけ。判断しない
- flutter-reviewer: `flutter analyze` を叩くだけ。同上
- → スキル内のステップとして「Bash で○○を実行」と記述すれば済む
- → model を haiku にしたいなら、スキル内の Agent 起動パラメータで指定

### タスク実行型
- review-fixer: 計画に従ってコードを書き換える。自分では判断しない
- → スキル内のステップとして、必要な tools と指示を書けば済む

### 判断するが役割アイデンティティのないもの
- review-validator: actionable か却下かを判断。opus で深く考える
- review-planner: 修正方針を立てる
- → 判断はしているが、持続的なアイデンティティや knowledge 蓄積がない
- → スキル内で Agent ツールを呼ぶ際に model: opus を指定すれば済む

## スキル内でのAgent起動パターン

```markdown
# /review-loop の SKILL.md 内で

### Step 2: バリデーション
Agent ツールで以下を実行（model: opus）:
- 各指摘が actionable か判定する
- 判定基準: ...

### Step 3: 修正
Agent ツールで以下を実行（model: sonnet, tools: Bash(限定), Edit, Write）:
- Step 2 で actionable と判定された指摘を修正する
- ...
```

## 判断基準フローチャート

```
そのエンティティは...

1. 持続的なアイデンティティがある？（「私は CTO です」）
   → No → スキル内のステップ
   → Yes ↓

2. 自律的に判断し、knowledge に蓄積する？
   → No → スキル内のステップ（model/tools は Agent 起動時に指定）
   → Yes ↓

3. 他のエージェントと権限境界がある？（管轄ファイルが異なる）
   → agents/ に定義する
```

## vibecorp への適用

```
.claude/agents/     ← 「役割」を持つもののみ（組織図と1:1対応）
  cto.md
  cpo.md
  sm.md
  cfo.md
  clo.md
  ciso.md

.claude/skills/     ← ワークフロー（内部で Agent 起動時に model/tools 指定）
  review/           ← CodeRabbit CLI実行 + カスタムレビュー
  review-loop/      ← validator(opus) → planner(opus) → fixer(sonnet) を内包
  pr-merge-loop/    ← 統合ワークフロー
  review-to-rules/  ← 各 Role Agent を順次起動して知識蓄積
  ...
```

## メリット

- agents/ が組織図と完全に一致する（conceptual clarity）
- 「flutter-reviewer って誰？」という混乱がなくなる
- スキルファイルを読めばワークフローの全体像が見える
- vibecorp.yml の設定が整理される（agents = 組織、skills = ワークフロー）
