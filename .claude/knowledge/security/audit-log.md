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
- T-007: PROFILE の TOCTOU 対策（シンボリックリンク経由）

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

---

## 2026-04-16 — Issue #318 Phase 3a install.sh macOS 統合（第1回セキュリティ分析員レビュー）

### 対象範囲

- `install.sh`（+147行: detect_os, check_unsupported_os, check_isolation_deps, copy_isolation_templates, generate_activate_script の追加）
- `tests/test_install.sh`（+121行: OS 判定テスト T1〜T6）
- `tests/test_install_isolation.sh`（新規 +277行: Phase 3a 専用テスト A〜G）
- `docs/SECURITY.md`、`docs/specification.md`、`README.md`、`.claude/knowledge/cpo/decisions.md`（ドキュメント更新）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P318-001 | Minor | `install.sh` copy_isolation_templates | `[[ -f "$src" ]]` チェックがシンボリックリンクを通過させる。攻撃者が templates/claude/bin/ 配下にシンボリックリンクを配置していた場合、導入先リポジトリへリンク先の任意ファイルがコピーされる。ただし SCRIPT_DIR は install.sh と同一リポジトリを指すため通常の利用では発生しない | 未対応（リスク低） |
| P318-002 | Minor | `install.sh` generate_activate_script L276-279 | `cat > "$activate"` でヒアドキュメントを書いた直後に `[[ ! -f "$activate" ]]` でファイル存在を再確認しているが、`cat >` が失敗した場合は `set -e` で既に exit しているため、このチェックは実質デッドコード。防御として冗長 | 未対応（Info） |
| P318-003 | Minor | `tests/test_install_isolation.sh` F1テスト L676 | `bash -c "source '$R/.claude/bin/activate.sh' && echo \"\$PATH\""` でパス変数に単一引用符でクォートしているが、`$R` に単一引用符が含まれる場合に構文が破損する。mktemp の出力は通常英数字と `/` のみのためリスクは低い | 未対応（Info） |
| P318-004 | Info | `install.sh` check_isolation_deps | `command -v sandbox-exec` によるチェックは PATH 操作で誤魔化せる。sandbox-exec は `/usr/bin/sandbox-exec` に固定されているため、絶対パスで存在確認する方が堅固 | 未対応（Info） |
| P318-005 | Info | `docs/SECURITY.md` / `README.md` | `source .claude/bin/activate.sh` を `~/.zshrc` に追記するよう案内しているが、プロジェクトの絶対パスをシェル設定に書き込むことの副作用（リポジトリ削除後の PATH 汚染）への警告がない | 未対応（Info） |

### SECURITY.md 準拠確認

Phase 1 既知制約（S-003 ネットワーク全許可、S-004/T-002 process-exec 無制限、S-010 ~/.claude 全 RW、S-012 HOME 改ざん対策未実装、T-007 PROFILE TOCTOU 未実装）は SECURITY.md に明記済みで Phase 2 スコープ。本差分（Phase 3a）はこれらの制約を変更しておらず SECURITY.md 違反はない。

### リスク評価

- 高: なし
- 中: なし
- 低: P318-001（templates/ シンボリックリンク経由のファイルコピー — 通常環境では発生しない）

### 判定

- 要注意: P318-001（Minor）— `[[ -f "$src" ]]` の代わりに `[[ -f "$src" ]] && [[ ! -L "$src" ]]` でシンボリックリンクを除外すること推奨
- Info（対応不要）: P318-002〜P318-005

---

## 2026-04-16 — Issue #318 Phase 3a install.sh macOS 統合（第2回セキュリティ分析員レビュー）

### 対象範囲

第1回レビューと同一（`install.sh` +147行、テスト 2ファイル、ドキュメント更新）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P318-H-001 | High | `install.sh` L7 + `copy_isolation_templates()` | `SCRIPT_DIR` が `$(cd "$(dirname "$0")" && pwd)` で取得されており `pwd -P` を使っていないため symlink を物理パスに解決しない。templates/ が symlink にすり替えられた場合、任意スクリプトが `.claude/bin/claude` として導入先に配置される経路がある | 未対応 |
| P318-H-002 | High | `install.sh` / `generate_activate_script()` | `bin_dir="${REPO_ROOT}/.claude/bin"` を PATH 先頭に注入する activate.sh を生成するが、`REPO_ROOT` が symlink 解決済みかどうかが保証されていない。`vibecorp-sandbox` の WORKTREE/HOME/TMPDIR に適用している 2 段検証（`validate_abs_path` + `canonicalize_dir`）と同等の保護が欠けている | 未対応 |
| P318-M-001 | Medium | `install.sh` / `copy_isolation_templates()` L224, L233 | `[[ -f "$src" ]]` は symlink 先が存在すれば true を返す（P318-001 と同指摘。第1回レビューで Minor と評価されたが、SCRIPT_DIR の symlink 未解決（H-001）と組み合わさると経路が広がるため Medium に格上げ） | 未対応 |
| P318-M-002 | Medium | `tests/test_install_isolation.sh` G テスト L706-717 | G テスト先頭で `create_test_repo` を呼ぶ前に `FAKE_BIN="$R/_fake_bin_no_sandbox"` を設定している。テスト順序変更時に `TMPDIR_ROOT`（=$R）が空で FAKE_BIN のパスが破損する | 未対応 |
| P318-M-003 | Medium | `tests/test_install_isolation.sh` F テスト L676-690 | `bash -c "source ... && echo \"\$PATH\""` で呼び出し元の PATH が継承される。テスト環境の PATH に既に `.claude/bin` 相当のパスがある場合、重複チェック（F2）が誤検知する | 未対応 |
| P318-L-001 | Low | `README.md` L37 | 永続化案内で絶対パス source を推奨しているが、リポジトリ移動・削除後の PATH 残骸リスクへの注意書きがない | 未対応 |
| P318-L-002 | Low | `install.sh` / `generate_activate_script()` L280 | `chmod +x "$activate"` が source 専用スクリプトに実行権限を付与している。直接実行しても効果がなくユーザーを混乱させる | 未対応 |
| P318-L-003 | Low | `tests/test_install_isolation.sh` L565 | `cleanup()` 内の `cd "$SCRIPT_DIR"` に `\|\| true` がない。`.claude/rules/testing.md` の cleanup 規約違反 | 未対応 |

### SECURITY.md 準拠確認

第1回レビューと同様。Phase 1 既知制約は変化なし。SECURITY.md の MUST/MUST NOT 違反は検出されなかった。

### エスカレーション

P318-H-001（SCRIPT_DIR の symlink 未解決による任意ファイル配置経路）、P318-H-002（activate.sh 生成時の REPO_ROOT 検証不足による PATH 注入先の汚染）の 2 件が High 脆弱性として検出された。第1回レビューとの合議結果として以下が確定：

- **全会一致**: P318-001/P318-M-001（templates/ glob の symlink 追跡）— 両レビューで共通指摘
- **第2回のみ**: P318-H-001（SCRIPT_DIR symlink 解決）、P318-H-002（REPO_ROOT 検証）

CISO エスカレーション対象: P318-H-001、P318-H-002

### 判定

**問題あり** — High 脆弱性 2 件を検出。CISO エスカレーション対象。

### 対応状況サマリー

- 未対応: 8件（High: 2, Medium: 3, Low: 3）
- 対応済み: 0件
- 許容済み: 0件

---

## 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）— 第2回独立レビュー（セキュリティ分析員）

### 対象範囲

- `templates/claude/sandbox/claude.sb`（sandbox 境界拡張）
- `install.sh`（`setup_claude_real_symlink()` 追加）
- `tests/test_install_claude_real.sh`（新規）
- `tests/test_isolation_macos.sh`（テスト 9・10 追加）
- `docs/SECURITY.md`（境界・制約表更新）
- `.claude/knowledge/ciso/decisions.md`（CISO 判定エントリ追加）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P320-2-001 | Info | `install.sh` `setup_claude_real_symlink()` L231 | `resolved=$(cd "$p" && readlink claude \|\| echo "$p/claude")` でラッパー除外判定に用いる `resolved` 変数が相対パスになる場合がある（`readlink` は macOS でパスを正規化しない）。`"$resolved" == *"/.claude/bin/claude"` のパターンマッチが機能しない可能性。ただしフォールバックが `echo "$p/claude"` と絶対パスになるため実害は限定的 | 未対応（Info） |
| P320-2-002 | Info | `tests/test_install_claude_real.sh` テスト F | ラッパー symlink 除外の検証ロジックが `readlink` の挙動（相対 vs 絶対）に依存しており、macOS と Linux で異なる結果になる場合がある。ただしテストファイル冒頭で Darwin 以外は skip されるため、実際の CI への影響はない | 未対応（Info） |
| P320-2-003 | Info | `tests/test_isolation_macos.sh` テスト [10] L675 | `expect -c` に渡す文字列内で `$HOME`、`${REAL_BIN}`、`${TMPDIR}` 等を直接展開しているが、これらにシングルクォートや特殊文字が含まれる場合 expect スクリプトの構文が破損する。HOME・TMPDIR は通常の macOS 環境では発生しないが、ユーザー設定によっては問題になりうる | 未対応（Info） |

### SECURITY.md 準拠確認

- `docs/SECURITY.md` の境界表に `~/.claude.json` RW（単一ファイル literal 限定）、`~/.local/share/claude` RO、`/dev` ioctl が正確に記載されている。MUST/MUST NOT 違反は存在しない。
- D-1（`.lock` エントリ除去）、D-2（評価根拠追記）、D-3（symlink 検証なし免責）がすべて SECURITY.md に反映済みであることを確認。

### CR-001 観点の再評価

3 境界拡張（`~/.local/share/claude` RO / `~/.claude.json` `.backup` RW literal / `/dev` file-ioctl）はいずれも `vibecorp-sandbox` スクリプト側の WORKTREE ⊇ HOME 防御ロジックに影響を与えない。CR-001 で封鎖した経路は別レイヤで管理されており、`claude.sb` 境界拡張との干渉なし。

### symlink 経由の任意ファイル配置攻撃経路

`setup_claude_real_symlink()` は PATH 上の `claude` を検出して `ln -sf` する。リンク先バイナリの署名・出所検証は行わない。この制約は SECURITY.md の既知制約表に「`claude-real` symlink 先の検証なし」として明記済み（D-3 対応済み）。Phase 1 スコープ外として文書化されており、追加の脆弱性ではない。

### リスク評価

- 高: なし
- 中: なし
- 低: なし（Info 3件は影響限定的）

### 判定

**問題なし** — セキュリティリスクなし。3 境界拡張はすべて Phase 1 既知制約の範囲内。CISO 承認済みの D-1/D-2/D-3 条件が充足されていることを確認。CR-001 防御ロジックへの影響なし。

### 対応状況サマリー

- 問題なし: 0件（Critical/High/Medium/Low）
- Info（対応不要）: 3件
- 許容済み（CISO 承認）: 3境界拡張すべて

---

## 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）— 第1回独立レビュー（セキュリティ分析員）

### 対象範囲

- `templates/claude/sandbox/claude.sb`（sandbox 境界拡張: ~/.local/share/claude RO / ~/.claude.json RW / /dev ioctl）
- `install.sh`（`setup_claude_real_symlink()` 追加）
- `tests/test_install_claude_real.sh`（新規テスト）
- `tests/test_isolation_macos.sh`（テスト 9・10 追加）
- `docs/SECURITY.md`（境界・制約表更新）
- `.claude/knowledge/ciso/decisions.md`（CISO 判定エントリ追加）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P320-1-001 | Minor | `install.sh` setup_claude_real_symlink L230 | `resolved=$(cd "$p" && readlink claude \|\| echo "$p/claude")` で `readlink` が相対パスを返した場合、`*/.claude/bin/claude` のパターンマッチがすり抜ける。悪意ある経路が通る方向ではなく、正規ラッパーが除外されない方向の失敗だが、SECURITY.md の `.claude/rules/shell.md` の「外部入力を使う場合はサニタイズ」に対する部分的な軽微違反 | 未対応（Minor） |
| P320-1-002 | Info | `install.sh` setup_claude_real_symlink L225 | `local IFS=":"` の同一行代入は bash 3.2 で local の終了コードが 0 に上書きされる既知の挙動。機能には影響しないが shell.md の bash 3.2 互換ルールに照らすと要注意 | 未対応（Info） |
| P320-1-003 | Info | `tests/test_isolation_macos.sh` テスト [10] L675 | expect スクリプト内で `$HOME`・`${REAL_BIN}`・`$SHIM` を直接展開しており、パスに特殊文字が含まれる場合に構文破損の可能性。通常環境では発生しないが、テスト堅牢性として認識しておくべきリスク | 未対応（Info） |

### SECURITY.md 準拠確認

- D-1（`.lock` 除去）、D-2（評価根拠追記）、D-3（symlink 検証なし明記）: すべて反映済み。
- CR-001 再評価: `claude.sb` 境界拡張は `vibecorp-sandbox` スクリプト側の WORKTREE ⊇ HOME 防御ロジックに影響なし。
- A08（Software and Data Integrity Failures）: `setup_claude_real_symlink()` の symlink 先検証なしは SECURITY.md の既知制約として明示済み（D-3）。許容済み。

### リスク評価

- 高: なし
- 中: なし
- 低: P320-1-001（readlink 相対パス返却 — 影響は誤検出方向のみ、攻撃経路なし）

### 判定

**問題なし** — Critical / High / Medium 脆弱性なし。SECURITY.md 準拠。D-1/D-2/D-3 反映確認済み。CR-001 防御ロジックへの影響なし。

### 対応状況サマリー

- 未対応: 1件（Minor: 1）
- 許容済み: 2件（Info）
- 承認済み（CISO）: 3境界拡張すべて

---

## 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）— 第3回独立レビュー（セキュリティ分析員）

### 対象範囲

- `templates/claude/sandbox/claude.sb`（sandbox 境界拡張）
- `install.sh`（`setup_claude_real_symlink()` 追加）
- `tests/test_install_claude_real.sh`（新規）
- `tests/test_isolation_macos.sh`（テスト 9・10 追加）
- `docs/SECURITY.md`（境界・制約表更新）
- `.claude/knowledge/ciso/decisions.md`（CISO 判定エントリ追加）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P320-3-001 | Low | `tests/test_isolation_macos.sh` L673-676 | `expect -c` ヒアストリング内で `$HOME`、`$SHIM`、`$REAL_BIN`、`$TMPDIR` が bash によりインライン展開される。パスにスペースが含まれると引数分割が発生する可能性がある。本番コードへの影響はなく、テストの誤動作リスクに限定される | 未対応（テストコードのみ） |
| P320-3-002 | Low | `install.sh` L230 | `resolved=$(cd "$p" && readlink claude \|\| echo "$p/claude")` で `readlink` 失敗時のフォールバックが `$p/claude` となり、symlink かどうかを検証せずに正当なバイナリとして扱う。SECURITY.md「PATH 汚染はスコープ外」に包含されるため実害は限定的 | 未対応（Phase 1 スコープ外） |

### SECURITY.md 準拠確認

D-1（`.lock` 除去）、D-2（`~/.claude.json` RW 評価根拠追記）、D-3（`claude-real` symlink 検証なし旨の追記）の全条件が SECURITY.md に反映済み。MUST/MUST NOT 違反なし。

### リスク評価

- 高: なし
- 中: なし
- 低: P320-3-001（テストスクリプトの expect 変数展開）、P320-3-002（readlink フォールバックのエッジケース）

### Issue #320 3回合議の一致事項

3回全ての独立レビューで共通した指摘:

1. `expect -c` 内の変数展開（特殊文字・スペース含有パス）— P320-1-003、P320-2-003、P320-3-001（Info/Low 相当）
2. `readlink` フォールバックの検証不足 — P320-1-001、P320-2-001、P320-3-002（Minor/Info/Low 相当）

いずれも Low または Info であり、全会一致ルール（Critical/High/Medium 検出で差し戻し）には該当しない。

### 判定

**問題なし** — セキュリティリスクなし。3 境界拡張はすべて Phase 1 既知制約の範囲内。CISO 承認済み（D-1/D-2/D-3 反映確認済み）。CR-001 防御ロジックへの影響なし。

### 対応状況サマリー

- 問題なし: 0件（Critical/High/Medium）
- Low（対応任意）: 2件（テストコード・Phase 1 スコープ外）
- 許容済み（CISO 承認）: 3境界拡張すべて
