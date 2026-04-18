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
