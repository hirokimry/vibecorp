vibecorp の Issue / PR には必ず `intent/*` ラベルを **1 つだけ** 付与すること。

## intent ラベル 7 種

| ラベル | 一言（何を重視するか） | カテゴリ |
|--------|----------------------|--------|
| `intent/feature` | 新機能を確実に動かす | 影響を与える系 |
| `intent/bugfix` | 既存バグを最小修正で直す | 影響を与える系 |
| `intent/performance` | 性能を測定可能な形で改善する | 影響を与える系 |
| `intent/security` | 脆弱性を塞ぐ | 影響を与える系 |
| `intent/refactor` | 構造の品質を高める（挙動不変） | 影響を与えない系 |
| `intent/infra` | 開発基盤の品質を底上げする（挙動不変） | 影響を与えない系 |
| `intent/docs` | ドキュメントの正確性を担保する（挙動不変） | 影響を与えない系 |

### 大カテゴリ別の性質

| カテゴリ | 含まれるラベル | 性質 |
|---------|-------------|------|
| 影響を与える系 | feature / bugfix / performance / security | プロダクト挙動を変える |
| 影響を与えない系 | refactor / infra / docs | プロダクト挙動を変えない（挙動不変。「挙動不変性の確認」観点を必ず適用） |

## 主従関係（絶対条件）

| 役割 | 軸 |
|------|---|
| **主** | **intent ラベル**（vibecorp 独自要件、判定の起点） |
| **従** | **CC prefix**（業界標準、機械可読の保険） |

判定フロー: **intent → CC prefix の順で決める**。逆引き（CC prefix → intent）は行わない。

CC prefix の厳格定義と intent ラベル → CC prefix 対応表は `docs/conventional-commits.md` を参照。

## 判定主体: COO

`/vibecorp:issue` で Issue 起票時、メインセッション（COO）が Issue 本文を読み、文脈判断で intent を確定する。
キーワード辞書ではなく LLM の文脈理解で判断する。

```text
/vibecorp:issue 起動
  ↓
COO が Issue 本文を読む
  ↓
COO が intent を判定（7 種から 1 つ選択、絶対条件: 1 つだけ）
  ↓
COO が intent に対応する CC prefix を選択
  ↓
COO が CC prefix 付き形式（絵文字 + prefix + 動作主語）でタイトル整形
  ↓
gh issue create で起票（intent ラベル + 既存ラベル）
```

## 1 Issue / 1 PR / 1 intent 厳守

- 1 つの Issue / PR には intent ラベルを **1 つだけ** 付与する
- 複数 intent にまたがる変更は Issue を分割する
- `intent-label-check` CI ジョブが intent 数（0 個 / 2 個以上）を機械的に検知して fail コメントを投稿する

## 関連

- CC prefix 厳格定義: `docs/conventional-commits.md`
- communication 規約: `.claude/rules/communication.md`
- 役割定義: `.claude/rules/roles.md`
