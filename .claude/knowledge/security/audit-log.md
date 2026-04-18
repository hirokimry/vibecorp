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

---

## 2026-04-18 — Issue #328 知見閉ループ再設計（セキュリティ分析員レビュー）

### 対象範囲

- `templates/claude/lib/knowledge_buffer.sh`（新規 +232行）
- `templates/claude/skills/review-harvest/SKILL.md`（新規 +248行）
- `templates/claude/skills/knowledge-pr/SKILL.md`（新規 +196行）
- `templates/claude/skills/session-harvest/SKILL.md`（変更）
- `templates/claude/skills/autopilot/SKILL.md`（変更）
- `templates/claude/skills/pr/SKILL.md`（変更）
- `templates/claude/lib/common.sh`（変更: `vibecorp_repo_id` / `vibecorp_cache_root` リファクタリング）
- `templates/claude/hooks/review-to-rules-gate.sh`（削除）
- `templates/claude/hooks/session-harvest-gate.sh`（削除）
- `templates/settings.json.tpl`、`.claude/settings.json`（フック削除対応）
- `install.sh`（minimal プリセット除外リスト更新）
- テスト群（新規: `test_knowledge_buffer.sh`、`test_knowledge_pr.sh`、`test_review_harvest.sh`、削除: `test_review_to_rules_gate.sh`、`test_session_harvest_gate.sh`）
- 各種 decisions.md（CFO/CISO/CPO/CTO: ナレッジ追記）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P328-001 | Minor | `knowledge_buffer.sh` L626 | `git -C "$dir" commit --author "${bot_name} <${bot_email}>" -m "$message"` で `bot_name` / `bot_email` が `git config` から取得した外部入力。`git config` は信頼されたユーザーローカル設定だが、`bot_name` に `"` や `<>` が含まれると `--author` 引数の解析が崩れる可能性がある。通常は発生しないが、サニタイズ未実施は規約（shell.md 外部入力ルール）に対する軽微な違反 | 未対応 |
| P328-002 | Minor | `review-harvest/SKILL.md` ステップ5 L1078-1080 | `jq '[.[] \| select(.in_reply_to_id != null) \| .user.login = (if (.user.login \| test("coderabbit"; "i")) then "CodeRabbit" else "<reviewer>" end) \| {pr: '"$pr_num"', ...}]'` で `$pr_num` が jq フィルタ内に埋め込まれる。`$pr_num` は `gh pr list` の JSON から `jq -r '.[].number'` で取得した整数のため、実際にはインジェクション経路は存在しない。ただし数値以外が混入した場合 jq が構文エラーを起こす（攻撃にはならないが堅牢性の問題）。`knowledge_buffer_write_last_pr` の整数バリデーションと同等のガードが jq フィルタ生成にも適用されていない | 未対応 |
| P328-003 | Minor | `knowledge-pr/SKILL.md` ステップ3 L776-785 | `gh issue list --search "📖 docs: 知見バッファの反映 in:title is:open"` で絵文字（📖）を含む文字列を `--search` クエリに使用している。shell での絵文字処理は bash 3.2 のマルチバイト非対応（shell.md 記載）により、macOS のデフォルト bash では変数展開時に問題が生じる可能性がある。実際には文字列リテラルを直接渡しているので safe だが、将来的に変数経由で渡した場合のリスクが潜在する | 未対応（Info） |
| P328-004 | Low | `knowledge_buffer.sh` L527-539 | `knowledge_buffer_ensure` 内の `git -C "$repo_root" fetch origin main` / `git -C "$repo_root" worktree add -B knowledge/buffer "$dir" origin/main` で `$dir` が `knowledge_buffer_worktree_dir()` から取得したパス。`knowledge_buffer_worktree_dir()` はシンボリックリンクチェックを実施するが、`$dir` の親ディレクトリが外部から操作可能な場合に TOCTOU が残る。通常のユーザーローカル cache 環境では攻撃面は極めて小さい | 未対応 |
| P328-005 | Low | `knowledge_buffer.sh` L477-496 | `mkdir-based lock` の stale lock 検出は PID ファイルの記録のみで、実際に PID の生存確認（`kill -0 $pid`）は実装されていない。SKILL.md の説明でも「PID をロック内に記録し、プロセス終了検出時のスタールロックを呼出元で確認可能にする」と記載されているが、呼出元スキルに PID チェックロジックが存在しない。結果として、クラッシュ時に stale lock が残り `VIBECORP_LOCK_TIMEOUT` 秒（デフォルト60秒）のウェイトが発生する。セキュリティリスクではなく DoS 的な degradation | 未対応 |
| P328-006 | Low | `review-harvest/SKILL.md` ステップ7 L1119-1149 | PR レビューコメント（`COMMENTS_ALL`）を 5 つの C*O エージェントに並列渡しする際、コメント本文に `${BUFFER_WORKTREE}` 等のシェル変数風文字列が含まれていた場合、LLM プロンプトに埋め込まれる。プロンプトインジェクションとして機能するリスクがある。`user.login` の匿名化は実施されているが、コメント本文（`body` フィールド）のサニタイズは未実施 | 対応済み（PR #344・コミット f7ee7f2 で委任プロンプトに「セキュリティ前提」防御指示を追加。メタ命令無視・スコープ限定・PII フィルタ・コード実行禁止・本文の生引用禁止を明記） |
| P328-007 | Info | `docs/SECURITY.md` | sandbox の書込境界表（Issue #326 追記部分）は `~/.cache/vibecorp` サブパスのみ許可と記載しているが、本変更で追加される `~/.cache/vibecorp/buffer-worktree/<repo-id>/` はその配下のため記述上は問題ない。ただし buffer worktree に `git push` するため SSH 鍵・GH トークン読取が必要となるが、sandbox の `~/.config/gh` RO 許可と既存の Phase 1 既知制約（ネットワーク全許可）の範囲内であり、新たな境界拡張は発生しない | 確認不要 |

### SECURITY.md 準拠確認

- SECURITY.md の機密情報保護（シークレット・APIキーをリポジトリにコミットしない）: 差分内にハードコードされた認証情報なし。準拠。
- sandbox 書込境界: `~/.cache/vibecorp/buffer-worktree/` は `~/.cache/vibecorp` サブパスとして既許可範囲内。追加の境界変更なし。SECURITY.md 更新も不要（既記述範囲内）。
- OWASP A03 インジェクション: P328-002（jq フィルタへの数値埋め込み）は整数値のため実際の注入リスクは低い。P328-006（プロンプトインジェクション）は LLM レイヤの問題であり、従来型インジェクションとは異なる。
- 認証・認可: gh CLI トークンは `~/.config/gh` 経由（sandbox RO 許可範囲内）。新たな認証情報の保存・漏洩経路なし。
- ゲートフック削除: `review-to-rules-gate.sh` / `session-harvest-gate.sh` の廃止は、これらが `autonomous-restrictions.md` で「代替不可」に分類されていないことを確認した（`.claude/knowledge/ciso/decisions.md` 2026-04-18 エントリでは「ワークフローゲート」として「セキュリティではなくプロセス強制」と明記）。セキュリティ機能の欠落ではなくワークフロー変更として許容。
- `diagnose-guard.sh` / `role-gate.sh` が `.claude/settings.json` から削除されている点: 本差分の `diff --git a/.claude/settings.json` に含まれる。これらは SECURITY.md の「代替不可」ガードフックに該当するが、`templates/settings.json.tpl` での削除は確認されず、`.claude/settings.json` のみの変更であれば vibecorp のテンプレート側に影響はない。ただし意図的な変更かどうかは不明のため要注意。

### リスク評価

- 高: なし
- 中: P328-006（プロンプトインジェクション — LLM への信頼できないコンテンツ埋め込み）
- 低: P328-001（git author 外部入力サニタイズ不足）、P328-002（jq フィルタ数値埋め込み）、P328-004（TOCTOU — 攻撃面は限定的）、P328-005（stale lock による degradation）
- Info: P328-003（bash 3.2 絵文字 — リテラルのため現状 safe）、P328-007（sandbox 境界範囲内）

### 判定

- 対応済み: P328-006（PR #344・コミット f7ee7f2 で防御指示を実装。委任プロンプトに「セキュリティ前提」セクションを追加し、メタ命令無視・スコープ限定・PII フィルタ・コード実行禁止・本文の生引用禁止を明記）。
- 対応済み: `.claude/settings.json` からの `diagnose-guard.sh` / `role-gate.sh` 削除: PR #344・コミット f7ee7f2 で復元（CISO H-1 指摘対応）。autonomous-restrictions.md 対象のガードレールが復活。
- 問題なし（Minor/Low/Info）: P328-001〜P328-005、P328-007 は現実の攻撃経路として成立するリスクが低く、Critical/High 脆弱性は検出されない。

### 対応状況サマリー

- 未対応: 6件（Minor: 2, Low: 2, Info: 2）
- 対応済み: 1件（P328-006: Low）
- 許容済み: 0件

---

## 2026-04-18 — Issue #296 protect-branch.sh worktree 誤検知修正（セキュリティ分析員レビュー）

### 対象範囲

- `.claude/hooks/protect-branch.sh`（新規 146行: file_path ベース worktree 判定・realpath サニタイズ・deny メッセージ拡張）
- `templates/claude/hooks/protect-branch.sh`（同期）
- `tests/test_protect_branch.sh`（worktree テスト WT-1〜WT-11 + DIFF-1 追加、run_hook ヘルパー変更）
- `docs/known-limitations.md`（新規）
- `.claude/plans/dev/296_fix_worktree_cwd_protect_branch.md`（実装計画）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P296-001 | Minor | `protect-branch.sh` L145 | Bash コマンド分割の `sed 's/&&/\n/g; s/\|\|\n/g; s/;/\n/g'` が quote-aware でない。`shell.md` に「`sed` によるコマンド分割は quote 内の区切り文字を無視するため禁止」と明記されているルール違反。実装計画（懸念事項6）でも「既存の Bash sed 分割バイパス — 既存問題であり本 Issue 範囲外」と認識・記録済み。この問題により `git commit -m "message; with semicolon"` や `git commit -m "message && more"` が quote 内区切りで誤分割され、コミットをすり抜けられる可能性がある | 未対応（既知・別 Issue 後続化予定） |
| P296-002 | Minor | `protect-branch.sh` L22-30 | `CLAUDE_PROJECT_DIR` 経由の `VIBECORP_YML` パスが外部入力。`awk` で `base_branch` を取得しているが、YAML の値に改行・制御文字・シェルメタキャラクタが含まれた場合に `BASE_BRANCH` が汚染される。`protect-branch.sh` は `BASE_BRANCH` を `jq --arg branch "$BASE_BRANCH"` に渡しているため JSON インジェクションには至らないが、deny 条件の文字列比較（`"$CURRENT_BRANCH" != "$BASE_BRANCH"`）でバイパス可能になりうる。例: `base_branch: main\nfoo` のような YAML を書くと `BASE_BRANCH` が `main` のみでなく制御文字付き文字列になる可能性。通常 vibecorp.yml はリポジトリ管理者が書くファイルのため実際の攻撃面は限定的 | 未対応（リスク低） |
| P296-003 | Info | `protect-branch.sh` L83-98 | deny メッセージに `check_dir` のパスが含まれる。内部ディレクトリ構造（worktree のフルパス等）がエラーメッセージに露出する。OWASP A09（セキュリティロギング・監視の失敗）の情報漏洩に相当するが、deny を受けるのは Claude Code エージェント自身であり外部公開されないため、実際のリスクは Info レベル | 未対応（Info） |
| P296-004 | Info | `protect-branch.sh` L40-66 | `ALLOWED_ROOT` の判定が「`CLAUDE_PROJECT_DIR` の親ディレクトリ配下」という広い許容範囲。worktree が兄弟ディレクトリに配置されるという前提は運用規約依存であり、兄弟ディレクトリに別の git repo があると file_path がそのリポジトリのパスでも `ALLOWED_ROOT` 配下として通過する。結果として `git -C` がその別 repo のブランチを読む（deny/allow が別 repo の状態に依存）。構造的制限として許容範囲 | 未対応（Info・設計上の既知トレードオフ） |

### autonomous-restrictions.md 準拠確認

- `protect-branch.sh` は `autonomous-restrictions.md` セクション4「ガードレール」に該当する自律実行不可領域。
- 実装計画に「CEO（ユーザー）からの明示的な指示で `/ship` 経由で人間主導実装」と明記されており、同ファイル末尾「人間承認ルート」に該当。自律実行禁止の制約には抵触しない。

### ガードレールバイパス評価

新ロジック追加後のバイパス経路を攻撃者視点で評価する:

1. **Edit/Write での file_path 偽装**: `ALLOWED_ROOT` 配下に収まらないパスは `CHECK_DIR="."` フォールバックで安全側 deny。テスト WT-4〜WT-8 で検証済み。バイパス困難。
2. **Bash での git commit バイパス（既知）**: P296-001 の quote-aware 問題により `git commit -m "cmd && echo ok"` 等でセグメント分割が誤動作しうる。設計上の既知制限として実装計画に明記済み。
3. **シンボリックリンク経由のパス偽装**: `realpath` が symlink を解決するため、`ALLOWED_ROOT` チェックは実体パスで行われる。macOS の `/private/tmp` ↔ `/tmp` も `realpath` で吸収。バイパス困難。
4. **CLAUDE_PROJECT_DIR 改ざん**: フックは Claude Code が環境変数を渡す前提で動作。環境変数自体を改ざんできる場合はガードレール全体が無効になるが、これはガードレール全般に共通の前提条件であり本変更固有の問題ではない。
5. **ALLOWED_ROOT の過広設定**（P296-004）: Info レベル。deny/allow が隣接 repo の状態に依存するが、deny されるべき main への書き込みが allow になる経路としては機能しない（隣接 repo が main でなければ allow、main ならば deny）。

### SECURITY.md 準拠確認

- 機密情報のハードコード: なし。
- シェルスクリプト固有リスク: P296-001（sed quote-aware 問題）が `shell.md` の明示的な禁止事項違反。ただし実装計画で「既存問題・本 Issue 範囲外」として認識・記録済み。

### リスク評価

- 高: なし
- 中: なし
- 低: P296-001（Bash コマンド分割 sed バイパス — 既存問題・別 Issue 後続化予定）、P296-002（vibecorp.yml の base_branch 値サニタイズ不足 — 攻撃面限定的）
- Info: P296-003（deny メッセージのパス露出）、P296-004（ALLOWED_ROOT の設計トレードオフ）

### 判定

- 問題なし: Critical / High / Medium 脆弱性なし。
- 要注意: P296-001（Minor）— sed による quote-aware でないコマンド分割。`shell.md` の明示ルール違反。実装計画で認識・後続 Issue として記録済み。

### 対応状況サマリー

- 未対応: 2件（Minor: 2）
- Info（対応不要）: 2件（P296-003、P296-004）
- 許容済み: 0件

---

## 2026-04-19 — Issue #366 配布物の Source of Truth テンプレート化（セキュリティ分析員レビュー #1）

### 対象範囲

- `templates/claude/.gitignore.tpl`（新規）
- `templates/claude/bin/activate.sh`（新規）
- `install.sh`（`copy_claude_gitignore()` 追加、`generate_claude_gitignore()` 置換、`migrate_tracked_artifacts()` 追加、`--no-migrate` オプション追加、`copy_isolation_templates()` に `save_base_snapshot` 追加）
- `tests/test_install.sh`（AJ/AK セクション追加）
- `docs/design-philosophy.md`、`README.md`、`.claude/knowledge/*`（ドキュメント更新）

### 検出事項

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| P366-001 | Minor | `install.sh` migrate_tracked_artifacts() awk抽出 | awk の `in_section` フラグにセクション終端判定がなく、将来 `.gitignore.tpl` に複数マーカーセクションが追加された場合、意図しないパスが untrack 対象に混入する可能性がある。現在のファイル構造では実害なし | 未対応（将来拡張時リスク） |
| P366-002 | Minor | `install.sh` copy_isolation_templates() | P318-001 指摘（`[[ -f "$src" ]]` が symlink 通過）が未対応のまま継続。今回追加された `save_base_snapshot` 呼び出しも symlink チェックなしで実行される | 未対応（既存未対応指摘の継続） |
| P366-003 | Trivial | `install.sh` migrate_tracked_artifacts() | `artifacts+=(".claude/${line}")` で awk 出力行の trailing スペース等に対するサニタイズが未実施。通常 `.gitignore` エントリで発生しないが堅牢性上の軽微な問題 | 未対応 |
| P366-004 | Trivial | `templates/claude/bin/activate.sh` L7 | `bin_abs="$(cd "$(dirname "$script_path")" && pwd)"` で `pwd -P` を使用しておらず symlink が解決されない。旧 `generate_activate_script()` からの引継ぎで動作仕様に変更なし | 未対応（旧実装からの引継ぎ） |

### SECURITY.md 準拠確認

- 機密情報保護: 差分にハードコード認証情報・マシン固有パスなし。準拠。
- sandbox 書込境界: 変更なし。
- OWASP A01（パストラバーサル）: `.claude/` プレフィックス + `..` 拒否の 2 重チェックあり。`git rm --cached` への引数は検証済みパスのみ。
- vibecorp.yml 経由の悪意あるパス注入: 入力源が SCRIPT_DIR 配下の templates 固定のため経路なし。

### リスク評価

- 高: なし
- 中: なし
- 低: P366-001（Minor）、P366-002（Minor・既存継続）、P366-003/P366-004（Trivial）

### 判定

**問題なし** — Critical / High / Medium 脆弱性は検出されなかった。Minor 2件はいずれも現状で実害なし（将来拡張時リスク・既存未対応継続）。

### 対応状況サマリー

- 未対応: 4件（Minor: 2, Trivial: 2）
- 対応済み: 0件
- 許容済み: 0件

---

## 2026-04-19 — Issue #366 配布物の Source of Truth テンプレート化（セキュリティ分析員レビュー #2）

### 対象範囲

- `templates/claude/.gitignore.tpl`（新規）
- `templates/claude/bin/activate.sh`（新規）
- `install.sh`（`copy_claude_gitignore()` 追加・`generate_claude_gitignore()` 削除・`migrate_tracked_artifacts()` 追加・`--no-migrate` オプション追加・`copy_isolation_templates()` に `save_base_snapshot` 追加）
- `tests/test_install.sh`（AJ/AK セクション追加）
- `docs/design-philosophy.md`、`README.md`、`.claude/knowledge/*`（ドキュメント更新）

### 検出事項

| ID | 重要度 | 対象ファイル:行 | 内容 | 対応状況 |
|----|--------|--------------|------|---------|
| P366-2-001 | Minor | `install.sh` `migrate_tracked_artifacts()` パス検証ロジック | `[[ "$artifact" == *..* ]]` の glob マッチはサブストリング一致であり、`valid-..name/` のような正当なパスも誤拒否する可能性がある。一方でパス正規化なしの `..` チェックだけでは `bin/%2e%2e/passwd` 等の URL エンコードはすり抜ける。ただし入力元が vibecorp リポジトリ管理下の `.gitignore.tpl` であり実際の外部入力ではないため、`.claude/` プレフィックス強制のみで十分な防御が成立しており、`..` チェックは冗長かつ誤検知リスクを伴う | 未対応（Minor・現状実害なし） |
| P366-2-002 | Minor | `install.sh` `copy_claude_gitignore()` UPDATE_MODE 分岐 | `grep -vxF -f "$src" "$dest"` でテンプレートに含まれないコメント行（`# ----` マーカー行等）も `existing_custom_lines` として抽出される。merge 後に重複追記が起こりうるが、gitignore の動作には影響しない | 未対応（Minor・動作への影響なし） |
| P366-2-003 | Low | `templates/claude/bin/activate.sh` | symlink 経由で source された場合、`cd "$(dirname "$script_path")" && pwd` がリンク先の実体ディレクトリを返す可能性がある。SECURITY.md Phase 1 既知制約「claude-real symlink 先の検証なし」と同一信頼境界内であり設計上の既知トレードオフ | 未対応（既存制約の範囲内） |
| P366-2-004 | Low | `install.sh` `copy_isolation_templates()` | P318-001 / P318-M-001 指摘の `[[ -f "$src" ]]` が symlink 通過問題が未対応のまま継続しており、今回追加された `save_base_snapshot` 呼び出しも同問題を引き継ぐ | 未対応（既存未対応の継続） |
| P366-2-005 | Info | `install.sh` `migrate_tracked_artifacts()` L316 エラーメッセージ | ユーザー向けエラーメッセージに `$artifact`（`.claude/bin/claude-real` 等）のパスが展開される。外部公開されないインストールログ内の情報であり Info レベル | 未対応（Info） |

### .gitignore.tpl → git rm --cached 攻撃経路の評価

`migrate_tracked_artifacts()` が `git rm --cached` 引数を `.gitignore.tpl` から動的抽出する経路を攻撃者視点で評価した。

1. **vibecorp.yml 経由**: `migrate_tracked_artifacts()` は `vibecorp.yml` を参照しない。ユーザー制御入力の到達経路なし。
2. **通常配布（vibecorp リポジトリ）**: `.gitignore.tpl` は vibecorp 管理ファイルであり、改ざんには vibecorp リポジトリへの書き込み権限が必要。そのレベルの侵害では `install.sh` 本体も改ざん可能であり、本経路を追加的な攻撃面と見なす必要はない。
3. **SCRIPT_DIR symlink 置換（P318-H-001）**: 既存 High 脆弱性。この経路が成立すると `.gitignore.tpl` も改ざん済みになりうるが、既存問題の範囲内。

### SECURITY.md / public-ready.md 準拠確認

- ハードコードされた機密情報・マシン固有パス: なし。本変更の主目的（`generate_activate_script()` heredoc 削除）が `public-ready.md` の「特定マシンパスのハードコード禁止」違反の構造的解消であり、方針に合致。
- `migrate_tracked_artifacts()` で `.env` 等秘密ファイルが誤 untrack される経路: untrack 対象は `.gitignore.tpl` の machine-specific セクション明示リスト（現状 `bin/claude-real` 1 エントリ）のみ。経路なし。
- `autonomous-restrictions.md` 5 不可領域: 認証・暗号・課金・ガードレール・MVV いずれにも抵触しない（SM 判定と一致）。
- 権限: `chmod +x` 対象は `bin/` 配下テンプレートに限定されており妥当。`activate.sh` の `chmod +x` は P318-L-002 指摘（source 専用スクリプトへの不要な実行権限）を継続するが、セキュリティリスクには至らない。

### リスク評価

- 高: なし
- 中: なし
- 低: P366-2-001（`..` 拒否 glob の誤検知リスク）、P366-2-003（activate.sh symlink 解決）、P366-2-004（既存 symlink 通過問題の継続）
- Info: P366-2-002（コメント行重複追記）、P366-2-005（エラーメッセージのパス露出）

### 判定

**問題なし** — Critical / High / Medium 脆弱性は検出されなかった。全会一致ルール（High 以上で差し戻し）は発動しない。SECURITY.md および public-ready.md 準拠。

### 対応状況サマリー

- 未対応: 5件（Minor: 2, Low: 2, Info: 1）
- Critical/High/Medium: 0件
- 許容済み: 0件

---

## 2026-04-19 — Issue #366 配布物の Source of Truth テンプレート化（第3回独立レビュー）

### 対象範囲

- `templates/claude/.gitignore.tpl`（新規: .claude/.gitignore の Source of Truth）
- `templates/claude/bin/activate.sh`（新規: 旧 generate_activate_script heredoc を静的配布に置換）
- `install.sh`（`copy_claude_gitignore()` 導入、`generate_activate_script()` 削除、`migrate_tracked_artifacts()` 追加、`--no-migrate` オプション追加、`save_base_snapshot` 呼び出し追加）
- `tests/test_install.sh`（AJ/AK セクション追加）
- `docs/design-philosophy.md`、`README.md`、`.claude/knowledge/**`（ドキュメント更新）

### 検出事項

| ID | 重要度 | 対象ファイル | 内容 | 対応状況 |
|----|--------|------------|------|---------|
| P366-3-001 | Minor | `install.sh` migrate_tracked_artifacts() awk 抽出 | `in_section` フラグにセクション終端条件がなく EOF まで true のまま。将来 `.gitignore.tpl` に `# ---- machine-specific artifacts ----` より後に別セクションを追加した場合、後続セクションのエントリまで untrack 対象に混入する。現在の単一セクション構造では実害なし | 未対応（将来拡張時リスク） |
| P366-3-002 | Minor | `install.sh` copy_isolation_templates() | `[[ -f "$src" ]]` チェックが symlink を通過させる（P318-001 / P318-M-001 未対応継続）。今回追加された `save_base_snapshot` 呼び出しも symlink チェックなしで実行される | 未対応（既存未対応指摘の継続） |
| P366-3-003 | Low | `install.sh` copy_claude_gitignore() | `merge_or_overwrite` 失敗時に `log_skip` して処理継続するが、コンフリクトマーカーが混入した `.gitignore` が実ファイルとして残る可能性がある。git 的実害は限定的だが、コンフリクトマーカー行がパターンとして誤適用される可能性 | 未対応 |
| P366-3-004 | Low | `templates/claude/bin/activate.sh` L7 | `bin_abs="$(cd "$(dirname "$script_path")" && pwd)"` が `pwd -P` を使わず symlink 解決しない。P318-H-002 の継続課題 | 未対応（既知） |

### 各観点の評価サマリー

- **Path Traversal / Injection**: `.claude/*` プレフィックス必須 + `..` 拒否の 2 段検証あり。`git rm --cached` への引数は検証済みパスのみ到達。`vibecorp.yml` 経由の注入経路なし（入力源は静的テンプレート）。問題なし。
- **Supply Chain / Symlink**: `[[ -f "$src" ]]` の symlink 通過は P318-001 / P318-H-001 として既知・未対応。今回の変更が新たに悪化させた点はなく、同じ経路・同じリスクレベルが継続する。
- **認証情報漏洩**: untrack 対象は `.gitignore.tpl` 記載の `bin/claude-real` のみ。`.env` 等は対象外。merge ロジックも既存カスタムエントリを保持する設計。問題なし。
- **権限**: `chmod +x` は既存の `copy_isolation_templates()` と同様。`activate.sh` への実行権限は意味的に冗長だが脆弱性ではない（P318-L-002 既知）。
- **SECURITY.md 準拠**: ハードコード認証情報・マシン固有パスなし。`public-ready.md` に従い heredoc からの固定パス埋め込みを除去する変更であり、適合方向への変更。MUST/MUST NOT 違反なし。

### リスク評価

- 高: なし
- 中: なし
- 低: P366-3-001（awk セクション終端未定義）、P366-3-002（symlink 通過 — 既存継続）、P366-3-003（merge 失敗時コンフリクトマーカー残留）、P366-3-004（pwd -P 未使用 — 既知）

### 判定

**問題なし** — Critical / High / Medium 脆弱性は検出されなかった。検出した Minor / Low はいずれも現実の攻撃経路として成立しにくく、既存の未対応課題（P318-H-001 / P318-H-002）との組み合わせでも攻撃面の実質的な拡大はない。

### 対応状況サマリー

- 未対応: 4件（Minor: 2, Low: 2）
- 対応済み: 0件
- 許容済み: 0件
