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
