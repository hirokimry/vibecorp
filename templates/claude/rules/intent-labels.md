vibecorp の Issue / PR には `intent/*` ラベルを **必ず 1 つだけ** 付与すること。

**revert PR の扱い**: `docs/conventional-commits.md` で `revert` を「intent ラベル付与なし対象（レビュー対象外）」と定義しているのは、CC prefix → intent の M:N マッピング表での扱い（revert は intent カテゴリに自然対応しない）の話。実際の **revert PR にも intent ラベル 1 つを付与すること**（差し戻しの目的に応じて、例: 回帰修正 → `intent/bugfix`、構造リファクタの取り消し → `intent/refactor`）。CI の `intent-label-check` ジョブは revert PR を特別扱いしないため、ラベル不在は fail になる。

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

### 旧 type 14 種は廃止予定

過去の `/vibecorp:issue` には独自 type 14 種（`design` / `agent` / `integrate` / `release` / `template` 等）のキーワード判定表が存在したが、Issue #469 議論結論「既存のキーワード判定表（独自 type 14 種）を廃止し、COO の文脈判断で intent を確定する形に書き換え」に従い廃止する。intent ラベル 7 種への 1:N マッピング表は **意図的に作らない**（主従関係を狂わせないため、COO の文脈判定で都度確定する）。

旧 type と intent の対応はおおよそ以下の自然な対応関係になるが、強制マッピングではなく COO の判断で都度決定する:

| 旧 type 例 | 自然な intent | 補足 |
|---|---|---|
| design | `intent/feature` または `intent/refactor` | 設計判断の対象が新機能か既存改善かで決定 |
| agent | `intent/feature` または `intent/infra` | 利用者が触れる挙動か開発基盤か |
| integrate | `intent/feature` | 外部統合の追加 |
| release | `intent/infra` または `intent/docs` | リリースプロセス整備か変更履歴か |
| template | `intent/refactor` または `intent/infra` | 構造改善か基盤拡張か |

`/vibecorp:issue` スキルの実装書き換え（旧 type 廃止 + COO 文脈判定への移行）は別 Issue で対応する（本ルールは判定基準の宣言のみ）。

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
