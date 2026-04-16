# セキュリティ監査ログ

## 2026-04-16 — Issue #309 macOS sandbox-exec PoC（隔離レイヤ Phase 1）

### 対象範囲

- `templates/claude/bin/claude`（PATH シム）
- `templates/claude/bin/vibecorp-sandbox`（OS ディスパッチャ）
- `templates/claude/sandbox/claude.sb`（sandbox-exec プロファイル）
- `tests/test_isolation_macos.sh`（テスト）

### 検出脆弱性（第1回レビュー）

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| S-001 | High | `vibecorp-sandbox` L43-48 | `$HOME` / `$WORKTREE` / `$TMPDIR` の未検証値が sandbox-exec の `-D` パラメータに直接渡される。PATH traversal でプロファイル境界を拡大できる | 未対応 |
| S-002 | High | `claude.sb` L41-46 | `(subpath (param "WORKTREE"))` — WORKTREE が `/` や `~` に設定された場合、全ファイルへの書き込みが許可される | 未対応 |
| S-003 | High | `claude.sb` L29 | `(allow network*)` — ネットワーク全許可。機密データ外送を防げない | 未対応（将来対応予定と記述あり）|
| S-004 | Medium | `claude.sb` L26-27 | `(allow process-fork)(allow process-exec)` — exec 先の実行ファイルが PATH から解決されるが、PATH 自体を sandbox 内から書き換えることで任意バイナリを exec できる可能性 | 未対応 |
| S-005 | Medium | `vibecorp-sandbox` L43-48 | `VIBECORP_SANDBOXED=1` は環境変数で伝播するため、攻撃者がサンドボックス外から `VIBECORP_SANDBOXED=1` をセットしてシムを呼ぶことでサンドボックスをスキップできる（バイパス）| 未対応 |
| S-006 | Medium | `claude.sb` L32-38 | `mach-lookup` の全許可により、macOS の IPC 経由で外部プロセスやシステムサービスを呼び出せる | 未対応 |
| S-007 | Low | `claude.sb` L54-69 | `/Library` / `/private/var/db` 等の RO 許可範囲が広い。Keychain データベース（`/private/var/db/...`）が読取可能な可能性 | 未対応 |
| S-008 | Low | `test_isolation_macos.sh` L74 | `mktemp -d -t` のプレフィックスが固定値（`vibecorp-isolation-XXXXXX`）。予測可能なパス名によるシムリンク攻撃（TOCTOU）の余地 | 未対応 |

### 対応状況サマリー（第1回レビュー）

- 未対応: 8件（High: 3, Medium: 3, Low: 2）
- 対応済み: 0件
- 許容済み: 0件

---

## 2026-04-16 — Issue #309 第2回独立レビュー（セキュリティ分析員）

### 追加検出事項

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| S-009 | High | `claude` L25-27 | VIBECORP_SANDBOXED=1 は任意の外部プロセスから注入可能。sandbox 内プロセスが `env VIBECORP_SANDBOXED=1 claude ...` を実行すれば次の claude 呼び出しが sandbox をスキップする | 未対応 |
| S-010 | High | `claude.sb` L55 | `~/.claude` への全 RW 許可。Claude 設定・hooks の書き換えによるサンドボックス外の永続的挙動改変が可能 | 未対応 |
| S-011 | Medium | `vibecorp-sandbox` L45 | WORKTREE=$PWD をシンボリックリンク操作で迂回可能。sandbox-exec は symlink を追跡するため WORKTREE 境界内のシンボリックリンク先への書込が通る | 未対応 |
| S-012 | Medium | `vibecorp-sandbox` L46 | HOME=$HOME の信頼性問題。CI や外部環境で HOME が改ざんされると sandbox の HOME 系保護パスが実際のユーザーホームと一致しなくなる | 未対応 |
| S-013 | Medium | `claude.sb` L65 | /private/var/folders 全サブパス読取許可が過剰。他プロセスの一時クレデンシャルへのアクセス経路になりうる | 未対応 |
| S-014 | Medium | `test_isolation_macos.sh` L391-396 | VIBECORP_SANDBOXED バイパスのネガティブテストが存在しない | 未対応 |
| S-015 | Low | `claude.sb` L37 | ipc-posix-shm の全許可（操作種別・名前の制限なし） | 未対応 |
| S-016 | Low | `claude.sb` L35 | sysctl-read の全許可（プロセス情報・ネットワーク状態の読取可能） | 未対応 |
| S-017 | Low | `test_isolation_macos.sh` | ~/.aws, ~/.gnupg 読取拒否の検証テストが不在 | 未対応 |

### エスカレーション
High 脆弱性を複数検出（S-001〜S-003、S-009〜S-010）。CISO エスカレーション対象。

---

## 2026-04-16 — Issue #309 第3回独立レビュー（セキュリティ分析員）

### 追加検出事項

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| T-001 | High | `claude` L25-27 | `VIBECORP_SANDBOXED=1` の外部注入によるサンドボックス完全バイパス。外部から `VIBECORP_ISOLATION=1 VIBECORP_SANDBOXED=1` をセットするだけで隔離が無効化される。S-005/S-009 と同一の脆弱性を別視点で確認 | 未対応 |
| T-002 | High | `claude.sb` L28 | `(allow process-exec)` 無制限許可。パス・引数制限なしで任意バイナリを exec 可能。`/usr/bin/osascript`、スクリプトインタープリタ経由での書込・通信アクションをサンドボックスが止められない。S-004 と同一の脆弱性を確認 | 未対応 |
| T-003 | High | `vibecorp-sandbox` L45 | `$PWD`（WORKTREE）/ `$HOME` に空白・クォート・セミコロン等が含まれる場合、`-D` 引数が破損しプロファイル境界が意図せず変化する。`.rules/shell.md` のサニタイズルール違反。S-001 と同一の脆弱性を確認 | 未対応 |
| T-004 | Medium | `claude.sb` L31, L68 | `(allow network*)` + `~/.config/gh` 読取許可の組み合わせ。GitHub PAT（`hosts.yml`）を読取後に外部送信できる。S-003 に加えて具体的な漏洩経路として特定 | 未対応 |
| T-005 | Medium | `claude.sb` L61 | `(subpath "/Library")` 全読取。`~/Library/Keychains` の保護が `deny default` の暗黙依存のみ。明示的 `deny` 不在。S-007 を補強する指摘 | 未対応 |
| T-006 | Medium | `test_isolation_macos.sh` L389-396 | テスト[3]が H-1/T-001 のバイパス動作を「正常」として自動検証している。バイパス修正時はテスト自体の改修も必要 | 未対応 |
| T-007 | Low | `vibecorp-sandbox` L35 | PROFILE 検証が `-f` 存在確認のみ。シンボリックリンク経由の TOCTOU で悪意あるプロファイルが渡される可能性。S-008 の TOCTOU 指摘に類似 | 未対応 |
| T-008 | Low | `claude.sb` L64 | `/private/var/db` 全読取許可の範囲が過剰。S-007/S-013 と同一の過剰許可を確認 | 未対応 |

### 3回合議の一致事項（全員が共通指摘）

以下は3回全ての独立レビューで指摘された事項であり、全会一致として確定：

1. `$WORKTREE`/`$HOME` の未サニタイズ注入（S-001, S-011, T-003）
2. `process-exec` の無制限許可（S-004, T-002）
3. `VIBECORP_SANDBOXED=1` バイパス（S-005, S-009, T-001）
4. ネットワーク全許可（S-003, T-004）
5. `/Library`/`/private/var/db` 等の過剰読取（S-007, S-013, T-005, T-008）

### 判定
**問題あり** — High 脆弱性が3件以上全会一致で検出。CISO エスカレーション対象。全会一致ルールにより差し戻し推奨。

---

## 2026-04-16 — Issue #309 CISO メタレビュー対応（修正実装）

### 対応内容

CISO 判定（`.claude/knowledge/ciso/decisions.md`）に基づき、Phase 1 ブロッカー 3 点を修正:

| ID | 重要度 | 対応内容 | 対応後状態 |
|----|--------|---------|----------|
| S-001 / S-011 / T-003 | High / Minor | `vibecorp-sandbox` に `validate_abs_path()` 関数を追加。`-D` 引数に渡す前に WORKTREE / HOME / DARWIN_TMPDIR の空文字・非絶対パス・ルート・`..`・空白・クォート等を拒否。WORKTREE == HOME も拒否 | **対応済み** |
| S-005 / S-009 / T-001 | High / Major | `claude` シムに PPID チェーン走査の `is_inside_sandbox_exec()` を追加。祖先に `sandbox-exec` が存在する AND `VIBECORP_SANDBOXED=1` の両方を要求する。環境変数単独では passthrough しない | **対応済み** |
| T-006 | Medium / Minor | `tests/test_isolation_macos.sh` テスト[3] をネガティブテストに変換。外部から `VIBECORP_SANDBOXED=1` を注入しても sandbox がバイパスされないことを検証 | **対応済み** |

### Phase 2 以降にスコープ出し（新 Issue 起票予定）

CISO 判定により設計変更レベル（`.claude/rules/review-criteria.md` の Info / 過剰な設計変更提案）として、このPRのスコープ外:

- S-003 / T-004: `(allow network*)` 絞り込み（`~/.config/gh` 読取との組み合わせで PAT 漏洩経路）
- S-004 / T-002: `(allow process-exec)` ホワイトリスト化
- S-010: `~/.claude` への全 RW 許可の範囲見直し
- S-007 / S-013 / T-005 / T-008: `/Library` / `/private/var/db` / `/private/var/folders` の過剰読取の限定
- S-006 / S-015 / S-016: `mach-lookup` / `ipc-posix-shm` / `sysctl-read` の精査
- S-012: HOME 改ざんリスク（CI 環境対策）
- T-007: PROFILE の TOCTOU 対策（シンボリックリンク検証）

### 却下した指摘（Info）

- S-008: テストの mktemp プレフィックス予測可能性（攻撃面限定的）
- S-017: `~/.aws` / `~/.gnupg` 読取拒否テスト不在（`deny default` で保護）

### テスト結果

`bash tests/test_isolation_macos.sh` → 12/12 passed（修正後）。

### 対応状況サマリー

- 対応済み: 3件（ブロッカー）
- Phase 2 スコープ出し: 11件
- 却下: 2件

---

## 2026-04-16 — Issue #309 CodeRabbit 第2回レビュー対応

### 追加指摘と対応

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| CR-001 | Critical | `vibecorp-sandbox` L77-91 | WORKTREE が HOME を包含するケース（`/Users`、`$HOME/..`、symlink 経由の別名パス等）を弾けていない。単純な等値比較だと `(subpath (param "WORKTREE"))` 経由で `~/.ssh` / `~/.aws` まで RW になる | **対応済み** |
| CR-002 | Major | `test_isolation_macos.sh` L74-97, L151-163 | `FAKE_HOME` が `TMPDIR_TEST`（= ホスト `$TMPDIR` 配下）に置かれ、sandbox の `DARWIN_TMPDIR` 許可で `~/.ssh` への書込が通過してしまうため、拒否テストが境界を実際には検証していない | **対応済み** |
| CR-003 | Major | `.claude/knowledge/cto/macos-sandbox-exec.md` L34, L42 | `sandbox-exec -p "$profile"` は実装（`-f`）と不一致。`(allow ipc-posix-shm*)` はワイルドカード付きだが実装は `(allow ipc-posix-shm)` | **対応済み** |

### 対応内容

1. **CR-001**: `canonicalize_dir()` 関数を追加し `(cd "$p" && pwd -P)` で symlink 解決。WORKTREE / HOME / DARWIN_TMPDIR を raw → canonicalize の 2 段で検証。`case "${HOME_VALUE}/" in "${WORKTREE_VALUE}/"*)` で HOME が WORKTREE 配下にあるケースを拒否
2. **CR-002**: `SANDBOX_TMPDIR="${TMPDIR_TEST}/sandbox-tmp"` を分離し、`run_shim` の `TMPDIR` に渡す。FAKE_HOME は `SANDBOX_TMPDIR` の外（兄弟ディレクトリ）になるため sandbox の DARWIN_TMPDIR 境界外で deny される
3. **CR-003**: `-p` → `-f`、`ipc-posix-shm*` → `ipc-posix-shm` を実装と整合

### テスト結果

`bash tests/test_isolation_macos.sh` → 13/13 passed（ネガティブテスト [8] 追加、WORKTREE ⊇ HOME 拒否を検証）
