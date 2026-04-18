# SM 判断記録

## 2026-04-17: Issue #329 実装計画のメタレビュー

### 対象
`.claude/plans/dev/329_isolation_login_sidecars.md`

### 判断内容

#### Phase 間依存関係の妥当性
- Phase 1（sandbox修正）→ Phase 2（テスト）→ Phase 3（docs）の順は妥当。
  - Phase 2 は Phase 1 の変更があって初めてテストが意味を持つ（依存あり、直列）
  - Phase 3 は Phase 1/2 と独立してdocs編集のみだが、Phase 1 の最終仕様が確定してから書くのが安全。実質直列が無難
  - Phase 4 は Phase 1 完成が前提の手動検証。直列
- 並列化余地: Phase 3（SECURITY.md更新）は Phase 1 の仕様が固まればdocs-onlyなので、Phase 2 と並列実行は技術的に可能。ただし得られる時間短縮が小さく、調整コストの方が高い。直列維持を推奨

#### ブロッカー判定
- **ブロッカーなし**（本 Issue は単独で完結可能）
- セキュリティ系 Critical 扱いの「CEO承認トレーサビリティ欠落」は、計画 L153 に `autonomous-restrictions.md #2 暗号領域（本修正は認証情報のファイル保存パス変更に該当、CEO 承認済み）` と記載済み。SECURITY.md や PR本文への明示転記が未確認だが実装のブロッカーにはならない（PR作成時にdocs更新で対応可）

#### 現ブランチで完結するか / 別 Issue へ切り出すべき指摘
| 指摘 | 判定 | 根拠 |
|------|------|------|
| CEO承認トレーサビリティ欠落 | **本件で対応**（Phase 3 SECURITY.md 更新 + PR本文への記載で完結） | scope内 |
| HOME regex エスケープ | **別 Issue 推奨** | `vibecorp-sandbox` の `validate_abs_path` が `.` 等の regex メタ文字を現状ブロックしていない（危険文字チェックは空白・クォート等のみ）。エスケープ追加は vibecorp-sandbox 側の修正であり本件の修正対象ファイル（claude.sb）とは層が異なる。ただし実害発生条件は「HOME に `.` 等が含まれる場合」であり macOS の慣習上ほぼ発生しないため、低優先でよい |
| date +%s 精度の説明不足 | **本件で対応**（計画コメントへの補足追記レベル、大きくない） | scope内 |
| diff 同期チェックの CI 組込み不明 | **本件で対応**（Phase 2 のテストケースとして追加する設計がすでにある） | scope内 |
| /login 完了条件が手動依存 | **仕様上やむなし**（Phase 4 は手動検証と明示されている。CI で /login の OAuth フローをモックするのは過大） | scope外・別Issue候補だが緊急性低 |
| ユーザーへのフィードバック不在 | **別 Issue 推奨** | UX改善であり本件のバグ修正スコープを超える |
| 成功側の肯定的確認手順不在 | **別 Issue 推奨** | 同上 |
| 境界値テスト不足 | **本件で対応**（Phase 2 テスト [12] で `.claude.jsonEVIL` 等を検証する設計済み）追加パターンを補足する程度 | scope内 |

### 結論
- 実装着手を阻むブロッカーなし
- HOME regex エスケープ・UX系フィードバック指摘は別 Issue が適切
- 現計画の Phase 順序（直列）は妥当。並列化しても効果が薄い

## 2026-04-18: Issue #296 ガードレール領域変更の通過承認トレーサビリティ

### 対象
`protect-branch.sh`（worktree cwd 誤検知修正）— PR #363

### 判断内容

#### ガードレール例外の根拠
`autonomous-restrictions.md` §4「ガードレール」領域（`protect-branch.sh` の改修）に該当する変更だが、以下の理由で実装を通過させた。

- **承認経路**: CEO（ユーザー）から直接 `/ship https://github.com/hirokimry/vibecorp/issues/296` が指示された人間主導実装
- `autonomous-restrictions.md` 末尾「人間承認ルート」に明示された経路であり、自律実行禁止制約（`/diagnose` → `/autopilot` → `/ship-parallel` ループ）とは別枠
- 自律実行ループ経由ではなく CEO → COO 経由のため、自律実行禁止制約には抵触しない

#### 変更範囲
- `.claude/hooks/protect-branch.sh` および `templates/claude/hooks/protect-branch.sh` の worktree 対応改修
- `tests/` 配下のテスト追加
- `docs/known-limitations.md` 新規作成

#### 整合確認
- ガードレール自体の緩和・削除ではなく、誤検知（worktree 内 cwd 判定バグ）の修正
- 修正後もガードレールの保護目的（保護ブランチへの直接操作防止）は維持されている

### 関連
- PR #292（誤検知の発覚契機）、PR #363（レビュー指摘反映後の最終実装）
- Issue #258（Bash compound コマンド分割制限）
- CTO/CPO/CISO 各 `decisions.md` 2026-04-18 エントリ

## 2026-04-18: docs/design-philosophy.md の CPO 管轄追記（訂正）

### 対象
`docs/ai-organization.md` および `templates/docs/ai-organization.md.tpl` の CPO 行・CTO 行

### 経緯

前回エントリ（同日）で `docs/design-philosophy.md` を CPO 管轄として追記したが、**これは誤りであった**。

### 訂正内容

- **誤**: `design-philosophy.md` を CPO 管轄に追記
- **正**: `design-philosophy.md` は CTO 管轄。CPO 行から削除し、CTO 行に移動

### 訂正理由

`design-philosophy.md` は 3層アーキテクチャ・agents vs skills 設計・プラグイン配布方式・フック設計パターン・スキル設計原則・CI/Branch Protection・プロセス隔離（sandbox-exec）・ゲートスタンプなど、内容・セクション構成・編集履歴（#327 ゲートスタンプ移行・#317 sandbox PoC・#256 スタンプ移行等）いずれも技術設計であり、CTO 管轄が適切。CEO 承認のもと訂正した。

### 認識した原則

**仕様は CPO、設計は CTO** — プロダクト仕様（ユーザー視点・機能・プリセット）は CPO 管轄、技術設計（アーキテクチャ・フック・スキル・sandbox 等）は CTO 管轄。今後この基準で管轄判定を行う。

### 変更ファイル
- `/docs/ai-organization.md`（CTO 行に `docs/design-philosophy.md` 追加・CPO 行から削除・原則注記を表直下に追加）
- `/templates/docs/ai-organization.md.tpl`（同上）

## 2026-04-18: Issue #366 実装計画のメタレビュー

### 対象
`.claude/plans/dev/366_distribution_template_redesign.md`

### 判断内容

#### autonomous-restrictions.md 抵触チェック
不可領域 5 カテゴリ（認証・暗号・課金・ガードレール・MVV）いずれにも抵触しないことを確認。`/diagnose` → `/ship-parallel` 自律改善ループで扱える領域。

#### Phase 間依存関係の妥当性
- Phase 1 → 2 → 3 → 4 → 5 の直列順序は実装上正しいが、Phase 2 の依存理由が計画に未記載
- **SM-1**: Phase 2 依存理由の欠落。両 Phase とも install.sh を変更するためマージコンフリクトリスクがあり、「Phase 1 と独立・並行可能」の記載は誤解を招く。計画の依存関係表に理由を追記推奨

#### 平社員層指摘（architect A1/A3, testing T1-T4, dx D1-D3）
全指摘採用済み。除外すべき指摘なし。

#### 新規指摘
- **SM-2**（軽微）: `--no-migrate` の `--install` 時挙動を usage テキスト / log_warn で明示する提案
- **SM-3**: Phase 4（design-philosophy.md 更新）実装時に CTO ゲート通過を確認（decisions.md 2026-04-18 エントリ: design-philosophy.md は CTO 管轄）
- **SM-4**: Phase 5 実装前に既存 `cleanup()` が `trap cleanup EXIT` パターンかを確認

#### consumer への既存運用破壊リスク
移行ロジック・`--no-migrate` フラグ・README 注意書きで十分ケアされている。問題なし。

### 結論
- SM-1 のみ計画への追記を推奨（実装ブロッカーではない）
- SM-2 は軽微、実装者判断に委ねてよい
- SM-3・SM-4 は実装時確認事項として記録
- **実装着手を阻むブロッカーなし**
