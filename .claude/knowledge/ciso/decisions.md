# CISO 判断記録

## 2026-04-16 — Issue #309 macOS sandbox-exec PoC（Phase 1）

### 判定

REQUEST_CHANGES（必須修正 3 点の対応後に再レビュー）

### 対象

- `templates/claude/bin/claude`（PATH シム）
- `templates/claude/bin/vibecorp-sandbox`（OS ディスパッチャ）
- `templates/claude/sandbox/claude.sb`（sandbox-exec プロファイル）
- `tests/test_isolation_macos.sh`（テスト）

### 合議状況

security-analyst 3名全員一致で脆弱性検出。全会一致ルール適用。
CodeRabbit CLI 11件の指摘も同領域を網羅。

### 必須修正（Phase 1 ブロッカー）

1. **$WORKTREE/$HOME 未サニタイズ注入**（S-001/S-011/T-003）
   - .claude/rules/shell.md 明確違反（Minor）
   - 修正内容: vibecorp-sandbox で -D 引数に渡す前に空文字列・ルートパス（/、~）・パストラバーサル（../）を拒否するバリデーションを追加

2. **VIBECORP_SANDBOXED=1 外部注入バイパス**（S-005/S-009/T-001）
   - Phase 1 設計目的（最低限の境界）を自己否定する構造（Major）
   - 修正内容: PID 検証導入、または既知の制限としてコメント明記 + Phase 2 Issue 起票

3. **テスト[3]がバイパスを正常動作として検証**（T-006）
   - 修正 2 に連動。バイパスのネガティブテストを追加（Minor）

### Phase 2 以降スコープ出し（設計変更レベル・Info 相当）

- process-exec ホワイトリスト化（S-004/T-002）
- network* 全許可の絞り込み（S-003/T-004）。~/.config/gh 読取との組み合わせによる PAT 漏洩経路を Issue に明記すること
- ~/.claude 全 RW 許可の範囲見直し（S-010）
- /Library・/private/var/db 過剰読取の限定（S-007/S-013/T-005/T-008）
- mach-lookup/ipc-posix-shm/sysctl-read の精査（S-006/S-015/S-016）
- HOME 改ざんリスク・CI 環境対策（S-012）
- PROFILE の TOCTOU 対策（T-007）

### 却下した指摘（Info 相当）

- S-008: テスト mktemp プレフィックス予測可能性（攻撃面限定的）
- S-017: ~/.aws/.gnupg 読取拒否テスト不在（deny default が機能）
- T-005（Keychains 明示 deny 不在）: deny default が保護機能中
- S-015/S-016: PoC で許可を広めに取ることが設計計画書に明記済み

### 判断根拠

Phase 1 は opt-in かつテンプレート配置のみ（install.sh 未連携）であるため、
設計変更レベルの指摘は Phase 2 以降に委ねた。
ただし .claude/rules/shell.md の明確な規約違反と、
Phase 1 の設計目的そのものを崩す VIBECORP_SANDBOXED バイパス構造は
スコープ内で修正すべきと判断した。

### 攻撃チェーン分析

最大リスク経路: 
VIBECORP_SANDBOXED=1 外部注入 → サンドボックス完全スキップ
→ WORKTREE=$HOME 設定（未サニタイズ） → プロファイル境界崩壊
→ ホームディレクトリ全体への書込権限 + ~/.config/gh 読取
→ GitHub PAT の外部送信（network* 全許可）

この経路は Phase 3（install.sh 配布）以降で全ユーザーに波及するため、
Phase 1 で入口部分（サニタイズ・バイパス構造）を修正しておくことが重要。

## 2026-04-16 — CR-001 CodeRabbit 第 2 回レビュー対応（WORKTREE ⊇ HOME 攻撃経路）

### 判定

承認（Phase 1 防御強化として対処済み）

### 対象

- `templates/claude/bin/vibecorp-sandbox`（境界検証ロジック）
- `tests/test_isolation_macos.sh`（ネガティブテスト [8] 追加）

### 合議状況

CodeRabbit 第 2 回レビューで CR-001（Critical）として検出。
S-001/S-011/T-003（WORKTREE の未サニタイズ注入）の追加攻撃経路として位置づける。

### 攻撃チェーン分析

WORKTREE ⊇ HOME 注入（`WORKTREE=/Users` / `$HOME/subdir` / symlink 経由）
→ `(subpath (param "WORKTREE"))` が `~/.ssh`・`~/.aws`・`~/.gnupg` を RW 範囲に包含
→ sandbox 境界崩壊
→ SSH 鍵 / AWS クレデンシャル / GPG 鍵への書込

初回レビュー（S-001/S-011/T-003）での等値比較バリデーションでは、symlink 経由・包含関係の攻撃経路を検出できなかった。

### 修正内容と根拠

- `canonicalize_dir()` で symlink を解決し、raw バリデーション → canonicalize → canonicalize 後の再バリデーションという 2 段階検証を実装
- WORKTREE ⊇ HOME の包含チェックを `case` 文で実装し、包含が検出された場合は起動を拒否
- 設計変更レベルではなく境界検証ロジックの精度向上と判断。Phase 1 スコープ内で対処が妥当
- `test_isolation_macos.sh [8]` のネガティブテストにより攻撃チェーン封鎖の根拠を確認（13/13 passed）

### 過去判断との一貫性

初回判断（2026-04-16 Issue #309）の S-001/S-011/T-003「$WORKTREE/$HOME 未サニタイズ注入」の追加対応。矛盾なし。Phase 2 以降の制約（ネットワーク全許可、process-exec 無制限等）は引き続き Phase 2 で追跡予定。
