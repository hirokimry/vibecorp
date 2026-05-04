# Conventional Commits — vibecorp 厳格定義

vibecorp は Conventional Commits (CC) v1.0.0 標準仕様を採用する。本ドキュメントは CC 11 種の vibecorp での厳格な解釈と、絵文字との 1:1 対応を定義する。

## 主従関係（絶対条件）

| 役割 | 軸 |
|------|---|
| **主**（vibecorp 独自要件、判定の起点） | **intent ラベル** |
| **従**（業界標準、機械可読の保険） | **CC prefix** |

判定フロー: **intent → CC prefix の順で決める**。逆引き（CC prefix → intent）は行わない。

intent ラベル定義の SoT は `.claude/rules/intent-labels.md` を参照。

## CC 11 種の vibecorp 厳格定義

### feat — 新機能追加

- **CC 公式**: 新機能をアプリ・ライブラリに追加する commit
- **vibecorp 厳格定義**: 利用者が触れる挙動が増える変更。新規スキル / 新規フック / 新規エンドポイントなど
- **絵文字**: ✨

### fix — バグ修正

- **CC 公式**: バグ修正の commit
- **vibecorp 厳格定義**: 既存挙動の不具合を最小修正で直す変更。挙動を増やさない
- **絵文字**: 🐛

### perf — パフォーマンス改善

- **CC 公式**: コード変更によりパフォーマンスを改善する commit
- **vibecorp 厳格定義**: 測定可能な形で性能を改善する変更（挙動は変えない）
- **絵文字**: ⚡

### refactor — リファクタリング

- **CC 公式**: バグ修正でも機能追加でもないコード変更
- **vibecorp 厳格定義**: 挙動不変で構造の品質を高める変更。**挙動が変わるなら refactor ではない**
- **絵文字**: 🔄

### style — フォーマット・スタイル修正

- **CC 公式**: コードの意味に影響しない変更（空白、フォーマット、セミコロンなど）
- **vibecorp 厳格定義**: コード意味を変えないフォーマット変更のみ。命名変更や構造変更は `refactor`
- **絵文字**: 💄

### docs — ドキュメント

- **CC 公式**: ドキュメントのみの変更
- **vibecorp 厳格定義**: `docs/` / `README.md` / コード内コメントの変更。実コードは変更しない
- **絵文字**: 📖

### test — テスト

- **CC 公式**: 不足テストの追加または既存テストの修正
- **vibecorp 厳格定義**: `tests/` 配下の変更のみ。テスト対象コードは変更しない
- **絵文字**: 🧪

### ci — CI 設定

- **CC 公式**: CI 設定ファイル・スクリプトの変更
- **vibecorp 厳格定義**: `.github/workflows/` などの CI 設定変更のみ。アプリコードは変更しない
- **絵文字**: 🔧

### chore — 雑務

- **CC 公式**: ソース・テストを変更しないその他の変更
- **vibecorp 厳格定義**: 設定ファイル更新、依存パッケージのバージョン上げなど。挙動を変えない
- **絵文字**: ⚙️

### build — ビルドシステム

- **CC 公式**: ビルドシステムや外部依存に影響する変更
- **vibecorp 厳格定義**: ビルドツールやランタイム設定の変更。**ランタイム挙動が変わる build 変更は不可**（その場合は `feat` / `fix`）
- **絵文字**: 📦

### revert — 差し戻し

- **CC 公式**: 過去の commit を取り消す commit
- **vibecorp 厳格定義**: 既検証コードへの差し戻しのみ。レビュー対象外
- **絵文字**: ⏪

## intent ラベル → CC prefix 対応表（M:N）

intent ラベル（主）から CC prefix（従）を選ぶ際の対応表。

| intent ラベル | 対応する CC prefix |
|--------------|------------------|
| `intent/feature` | `feat` |
| `intent/bugfix` | `fix` |
| `intent/performance` | `perf`, `feat`（性能向上目的の機能）, `fix`（パフォーマンス系バグ） |
| `intent/security` | `fix`（脆弱性修正）, `feat`（セキュリティ機能追加）, `chore`（依存パッケージのセキュリティアップデート） |
| `intent/refactor` | `refactor`, `style` |
| `intent/infra` | `test`, `ci`, `chore`, `build` |
| `intent/docs` | `docs` |

### 対象外（intent ラベル付与なし）

| CC prefix | 扱い |
|-----------|------|
| `revert` | レビュー対象外（既検証コードへの差し戻し） |

### CC 11 種の網羅性（読み手向け参考、判定では使わない）

CC 11 種すべてが少なくとも 1 つの intent または対象外に対応する:

- feat → intent/feature, intent/performance, intent/security
- fix → intent/bugfix, intent/performance, intent/security
- perf → intent/performance
- refactor → intent/refactor
- style → intent/refactor
- docs → intent/docs
- test → intent/infra
- ci → intent/infra
- chore → intent/infra, intent/security
- build → intent/infra
- revert → 対象外

⚠️ **逆引き（CC prefix → intent）は判定で使わない。** 主従関係を狂わせる。

## タイトル形式

PR / Issue / commit のタイトルは以下のいずれか:

```text
{絵文字} {CC prefix}: {動作主語の説明}
{絵文字} {CC prefix}({scope}): {動作主語の説明}
```

例:
- `✨ feat: AI レビューワークフローが配布されるようになった`
- `🐛 fix(install): 既存 REVIEW.md が初回 install で保護されるようになった`
- `📖 docs: cost-analysis に warning セクションが追加された`

説明文は `.claude/rules/communication.md` の動作主語規約に従う。

## 1 PR 1 intent 厳守

- 1 つの Issue / PR には intent ラベルを **1 つだけ** 付与する
- 複数 intent にまたがる変更は Issue を分割する
- `templates/.github/workflows/ai-review.yml` の `intent-label-check` ジョブが機械的に強制（複数付与で fail コメント）

## 関連

- intent ラベル定義の SoT: `.claude/rules/intent-labels.md`
- communication 規約: `.claude/rules/communication.md`
- レビュー判定基準: `.claude/rules/review-criteria.md`（#470 で 4 ファイル分割予定）
