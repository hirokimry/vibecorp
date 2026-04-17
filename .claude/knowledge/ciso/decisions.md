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

## 2026-04-16 — Issue #318 Phase 3a: install.sh macOS 隔離レイヤ配置ロジック統合

### 判定

条件付き承認（Minor 2 点を Phase 3a スコープ内で修正、Low 以下はトラッキング済みとして却下）

### 対象

- `install.sh`（`copy_isolation_templates` / `generate_activate_script` / `check_isolation_deps` 追加）
- `tests/test_install_isolation.sh`（新規テスト）
- `tests/test_install.sh`（T テスト追加）
- `README.md` / `docs/SECURITY.md` / `docs/specification.md`（ドキュメント更新）

### 合議状況

- Analyst 1: Minor 1 件（symlink 追跡）、残りは Info
- Analyst 2: High 2 件（SCRIPT_DIR/REPO_ROOT symlink）、Medium 3 件（同上 + テスト 2 件）、Low 3 件
- Analyst 3: Minor 2 件（symlink 追跡 + cleanup cd `|| true` 欠落）

3 名中 1 名（Analyst 2）が High 判定 → 全会一致ルール発動。精査の上、High 判定の妥当性を検証した。

### High 判定の妥当性検証（P318-H-001 / P318-H-002）

**P318-H-001（SCRIPT_DIR の symlink 非解決）**

`SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` は物理パスを解決しない（`pwd -P` 相当ではない）。

しかし攻撃前提が「git 管理下の `templates/` 配下ファイルが symlink にすり替えられる」ことであり、これはリポジトリそのものへの書込権限（または supply chain 侵害）を前提とする。vibecorp は git リポジトリを Source of Trust とする設計であり、リポジトリ改ざんは install.sh のスコープ外の前提侵害である。

また `copy_isolation_templates` は `[[ -f "$src" ]]` によりシンボリックリンクを素通しするため（P318-001）、symlink すり替えが成立しているとファイルがコピーされる。ただし SCRIPT_DIR が正しく解決されても symlink すり替えが発生すれば同じ問題であり、SCRIPT_DIR の `pwd -P` 化は「SCRIPT_DIR 自体が symlink」なケースへの対策にとどまる。Phase 1/2 で実装済みの `validate_abs_path` + `canonicalize_dir` は sandbox 実行経路（vibecorp-sandbox スクリプト内）に実装されており、install.sh の配置経路への多層防御は Phase 3a のスコープ外である。

**判定: High → Minor に格下げ**。`pwd -P` を使うことは望ましいが、攻撃の成立にはリポジトリ改ざんが前提であり、install.sh 単体でこの前提をくつがえすことは設計上困難。SECURITY.md の既知制約セクションへの追記と並行して、symlink 追跡（P318-001）の修正で対応が妥当。

**P318-H-002（generate_activate_script の REPO_ROOT symlink 非解決）**

activate.sh 内の `bin_abs="$(cd "$(dirname "$script_path")" && pwd)"` は source 実行時に物理パスを解決する。ここはインストール後のユーザー実行フェーズであり、install.sh の配置フェーズとは別問題。REPO_ROOT の symlink 解決は `detect_repo_root` 関数で行うべきだが、これは既存設計の課題でありPhase 3a 新規変更の直接的な脆弱性ではない。

**判定: High → Low（Phase 2 以降トラッキング）**。activate.sh の PATH 注入は `pwd` 経由で物理パスを取得しており、symlink 解決は呼び出し元シェルの PATH 展開の問題。設計変更が必要なレベルであり Phase 3a のスコープを超える。

### 採用する指摘

**Minor — Phase 3a で修正すべき**

| ID | 検出者 | 内容 | 採用根拠 |
|----|--------|------|----------|
| P318-001 | 全員一致（3/3） | `copy_isolation_templates` の `[[ -f "$src" ]]` がシンボリックリンクを通過する | 3名全員一致。`[[ ! -L "$src" ]]` の追加で排除可能 |
| P318-003 | Analyst 3 単独 | `cleanup()` の `cd "$SCRIPT_DIR"` に `\|\| true` なし。`.claude/rules/testing.md` 規約違反 | 規約明記の Trivial。単独指摘だが testing.md に明記された MUST 事項のため採用 |

### 却下する指摘

| ID | 検出者 | 却下理由 |
|----|--------|----------|
| P318-H-001 | Analyst 2 単独 | リポジトリ改ざんを前提とする攻撃経路。install.sh スコープ外の前提侵害。Minor に格下げして P318-001 修正で包含 |
| P318-H-002 | Analyst 2 単独 | activate.sh の PATH 解決はインストール後フェーズの設計課題。Phase 3a 新規変更の直接的脆弱性ではない。Phase 2 以降でトラッキング |
| P318-M-002 | Analyst 2 単独 | G テストの `$R` 設定順序。`create_test_repo` がグローバル変数 `TMPDIR_ROOT` を設定し、その後 `R="$TMPDIR_ROOT"` とすれば動作する。diff L702 確認: G テストで `create_test_repo` を先に呼び `R="$TMPDIR_ROOT"` は呼んでいない（`R` 未設定のままパスを構築）。これは Info 相当のテスト信頼性問題だが、G テストは `PATH="$FAKE_BIN" bash ...` 形式で参照しておらず実害なし。Trivial に格下げして Phase 2 以降でトラッキング |
| P318-M-003 | Analyst 2 単独 | F テストの `bash -c` が呼び出し元 PATH を継承。これはテストの意図通り（activate.sh を source した後の PATH 変化を検証するため既存 PATH を引き継ぐことが前提）。却下 |
| Info 各種 | 各アナリスト | README.md 永続化警告不足、generate_activate_script デッドコード、$R シングルクォート混入、command -v sandbox-exec PATH 依存、chmod +x 不要、cleanup cd の順序 → 情報提供のみ / 軽微スタイル |

### Phase 3a で修正すべき項目

1. **`install.sh` の `copy_isolation_templates`（L225 / L233 付近）**
   - `[[ -f "$src" ]]` を `[[ -f "$src" ]] && [[ ! -L "$src" ]]` に変更
   - シンボリックリンクのファイルを配置対象から除外する
2. **`tests/test_install_isolation.sh` の `cleanup()` 内（L565）**
   - `cd "$SCRIPT_DIR"` を `cd "$SCRIPT_DIR" || true` に変更
   - `.claude/rules/testing.md` 規約: cleanup 内のリソース解放コマンドは `|| true` で失敗を無害化

### Phase 2（#310）以降でトラッキングする項目

| 項目 | 理由 |
|------|------|
| SCRIPT_DIR の `pwd -P` 化（P318-H-001 格下げ版） | リポジトリ改ざん前提の経路。Phase 2 で多層防御追加時に見直し |
| REPO_ROOT の symlink 解決強化（P318-H-002） | `detect_repo_root` の設計変更が必要。Phase 2 以降のスコープ |
| G テストの `$R` 設定タイミング（P318-M-002） | テスト信頼性の改善。次回テストリファクタリング時に対処 |

### 攻撃チェーン分析

`install.sh` の `copy_isolation_templates` が symlink を通過するケース（P318-001）が最大リスクだが、攻撃の前提は「`templates/claude/bin/` 配下にシンボリックリンクが混入していること」であり、これはリポジトリへの書込権限を前提とする。sandbox 実行経路（vibecorp-sandbox）は Phase 1/2 で `canonicalize_dir` + 包含チェックの 2 段階検証が実装済みであるため、install.sh の配置フェーズを通過しても sandbox 境界崩壊には至らない。

深刻度: **低**（Phase 1/2 の防御レイヤが配置後の実行時を保護）

### 過去判断との一貫性

- #309 判断「Phase 3（install.sh 配布）以降で全ユーザーに波及するため、Phase 1 で入口部分（サニタイズ・バイパス構造）を修正しておくことが重要」に合致。Phase 3a として最低限の symlink 排除（P318-001）を適用する。
- CR-001（WORKTREE ⊇ HOME 攻撃経路）の 2 段階検証は install.sh 配置後の sandbox 実行時に有効化されるため、Phase 3a の修正と干渉しない。

## 2026-04-16 — Issue #320 Phase 1 sandbox 境界拡張（TUI ハング修正）

### 判定

条件付き承認（Phase D 実装時に 2 点の修正を反映後、Phase E-1 最終確認で承認）

### 対象

- `templates/claude/sandbox/claude.sb`（sandbox 境界拡張）
- `install.sh`（`setup_claude_real_symlink` 追加）
- `docs/SECURITY.md`（境界・制約表の更新）

### 合議状況

計画段階の事前 CISO レビュー。平社員層レビュー（単一モード・5件指摘）の妥当性評価を兼ねる。

### 各境界拡張の評価

**A: `~/.local/share/claude/**` RO 許可 — 条件付 OK**

- バイナリ実体への RO のみ。書き換え不可。
- 情報漏洩リスクは既存の `~/.npm` RO 許可と同等かそれ以下。
- SECURITY.md 更新案の `.claude.json.lock` 残存（D-1 指摘）のみ要修正。

**B: `~/.claude.json` / `.backup` RW 許可 — 条件付 OK**

- `~/.claude` 全 RW 許可と同等の信頼境界。攻撃面は実質変わらない。
- `(literal ...)` による単一ファイル限定は最小権限の観点で妥当。
- SECURITY.md の既知制約表にこの評価根拠を一文追記することが条件（D-2 指摘）。

**C: `/dev/**` file-ioctl 全許可 — 条件付 OK**

- `/dev` への read/write-data は既に許可済み。ioctl 追加で新たな攻撃面は限定的。
- `/dev/mem` は現代 macOS で無効化済み。IOKit との組み合わせは Phase 1 既知制約の範囲内。
- 個別 ioctl 番号絞り込みは Phase 2 以降トラッキング。Phase 1 PoC として全許可は妥当。
- SECURITY.md 既知制約表への追記が必要。

### 平社員指摘の評価（全5件採用）

1. `.claude.json.lock` 境界削除 — 採用。ただし SECURITY.md 更新案から `.lock` が除去されていない（D-1 指摘として別途修正が必要）。
2. `-x` 単独検出条件 — 採用。セキュリティ観点で問題なし。
3. minimal/standard 削除ブロック 2 箇所明記 — 採用。不完全な symlink 残存を防ぐために必須。
4. `tests/test_install_claude_real.sh` 新規追加 — 採用。testing.md 規約必須。
5. Phase B-3 検証を Phase B-4 テストでカバー — 採用。フェーズ対応の明確化として妥当。

### 新規懸念

- **D-1（SECURITY.md `.lock` 矛盾）:** 計画書の SECURITY.md 更新案（p.215 表）に `.claude.json.lock` が残存。Phase D-1 実装時に削除すること。
- **D-2（B の評価根拠追記）:** `~/.claude.json` RW の既知制約説明に「`~/.claude` 全 RW と同等の信頼境界であり攻撃面は変わらない」旨を追記すること。
- **D-3（`claude-real` symlink サプライチェーン）:** PATH 汚染環境での悪意バイナリ誤 symlink は Phase 1 許容範囲内。SECURITY.md の既知制約に「`claude-real` symlink 先の検証なし（PATH 汚染環境は対象外）」を追記推奨。

### 攻撃チェーン分析

今回の 3 境界拡張はいずれも Phase 1 既知制約（ネットワーク全許可・`~/.claude` 全 RW・process-exec 無制限）の範囲内にとどまる。CR-001 で封鎖した WORKTREE 境界・HOME 包含拒否の防御ロジックは `vibecorp-sandbox` スクリプト側に実装されており、`claude.sb` 境界拡張に影響されない。深刻度: 低。

### 過去判断との一貫性

- #309 および CR-001 判断と矛盾なし。Phase 1 スコープ内の境界拡張として整合している。
- #318 の「Phase 3a 以降で全ユーザーに波及する」前提のもと、SECURITY.md へのドキュメント整合（D-1/D-2）が重要。

### 最終評価（実装後）— 2026-04-16 Phase E-1

#### 判定

承認: セキュリティリスクなし

#### D-1/D-2/D-3 反映確認

- **D-1（`.lock` 除去）:** `claude.sb` に `.claude.json.lock` のエントリなし。SECURITY.md の書込境界表にも記載なし。反映済み。
- **D-2（評価根拠追記）:** SECURITY.md の既知制約表の `~/.claude.json` 全 RW 許可行に「評価根拠: 既存の `~/.claude` 全 RW 許可と同等の信頼境界であり、攻撃面は実質変わらない（CISO メタレビュー 2026-04-16）」が明記されている。反映済み。
- **D-3（symlink 検証なし）:** SECURITY.md の既知制約表に「`claude-real` symlink 先の検証なし」行として PATH 汚染環境はスコープ外である旨が追記されている。反映済み。

#### 境界実装の整合性

`claude.sb` を直接検証した。3 境界拡張（`~/.local/share/claude` RO / `~/.claude.json` `.backup` RW literal / `/dev` file-ioctl）はすべて計画通りに実装されており、計画段階で承認した範囲を超える権限追加は存在しない。

#### テスト [9][10] の評価

- テスト [9]: 実 HOME を使って sandbox 経由で `claude --version` を実行。`~/.local/share/claude` RO 許可と `~/.claude.json` RW 許可が破綻した場合に検出できる構造。
- テスト [10]: `expect` で TUI を起動し ANSI エスケープ（raw mode 証跡）を検出。`/dev` file-ioctl 許可が破綻した場合に検出できる構造。
- 両テストとも CI では実機 claude 不在により skip される設計で、SECURITY.md に明記済み。CI 偽陽性を生まない。

#### CR-001 観点の再評価メモの一貫性

SECURITY.md の再評価メモは攻撃チェーン分析と整合している。特に「CR-001 で封鎖した WORKTREE 境界・HOME 包含拒否の防御ロジックは `vibecorp-sandbox` スクリプト側に実装されており、`claude.sb` 境界拡張に影響されない」という記述は、境界拡張が防御ロジックを迂回しないことを明示しており妥当。

#### 攻撃チェーン分析

今回の実装によって新たな攻撃経路が生まれていないことを確認した。3 境界拡張はいずれも Phase 1 既知制約（ネットワーク全許可・`~/.claude` 全 RW・process-exec 無制限）の範囲内にとどまる。深刻度: 低。

#### 過去判断との一貫性

計画段階（条件付き承認）の条件がすべて充足された。矛盾なし。PR 作成に進んでよい。

## 2026-04-16 — Issue #320 合議制最終チェック（security-analyst ×3 メタレビュー）

### 判定

承認: セキュリティリスクなし

### 対象

コミット 8bef923（隔離レイヤ Phase 1 — claude TUI ハング修正）の差分全体。

### 合議状況

security-analyst 3名全員一致で「問題なし」。全会一致ルール適用なし（Major 以上の検出ゼロ）。

### 共通指摘の最終評価

**P320-readlink（install.sh L230 付近）**

`readlink claude` が相対パスを返した場合にラッパー除外パターン不一致が生じる。ただし最悪ケースは exec ループ（DoS 相当）に限定され、sandbox 境界崩壊・権限昇格・情報漏洩には至らない。SECURITY.md 既知制約「`claude-real` symlink 先の検証なし（PATH 汚染環境は対象外）」および decisions.md D-3 判断でスコープ外と位置付け済み。Minor 評価を支持。

**P320-expect-vars（tests/test_isolation_macos.sh L673-676）**

`expect -c` のインライン変数展開でスペース含むパスが引数分割される可能性。テストコードのみに影響し、プロダクションの sandbox 境界・シム・vibecorp-sandbox スクリプトには影響しない。Minor 評価を支持。

### 攻撃チェーン分析

2 指摘を連鎖させた攻撃経路を検討したが、sandbox 境界崩壊・権限昇格に至らないことを確認した。WORKTREE 境界・HOME 包含拒否の防御ロジック（vibecorp-sandbox 側）は今回の変更ファイルで改変されていない。深刻度: 低。

### 過去判断との一貫性

Phase E-1「承認: セキュリティリスクなし。PR 作成に進んでよい」および D-3「PATH 汚染環境はスコープ外」と矛盾なし。

## 2026-04-17 — Issue #326 ゲートスタンプの XDG キャッシュ移動（docs/SECURITY.md 不整合修正）

### 判定

承認: セキュリティリスクなし（ドキュメント不整合の修正のみ）

### 対象

- `docs/SECURITY.md`（書込・読取境界表の更新 + #326 説明ノート追記）

### 合議状況

ドキュメント不整合修正のため security-analyst 合議なし。CISO 単独レビュー。

### メタレビュー内容

Issue #326 / PR #327 にてゲートスタンプの保存先が `.claude/state/` から `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/` に移動済み。sandbox プロファイル（`claude.sb`）に `~/.cache/vibecorp` の subpath 許可も追加済み。しかし `docs/SECURITY.md` の書込・読取境界表にこの変更が未反映だった（sync-check 検出）。

### 変更内容

1. **書込境界表の「書込」行に追記**: `~/.cache/vibecorp`（ゲートスタンプ保存先 #326）
2. **Issue #326 説明ノート追加（#320 パターンに倣う）**: 保存パスの形式・サブパス限定許可の根拠・脅威モデルを記載

### 攻撃チェーン分析

- `~/.cache/vibecorp` は `~/.cache` 全体ではなくサブパスのみを許可（攻撃面最小化。既に実装済み）
- 脅威モデル: 同一ユーザーの別プロセスからのスタンプ偽造はスコープ外（信頼境界 = ユーザーアカウント）
- 他ユーザーからの偽造は chmod 700 でブロック
- 新たな攻撃経路は生じない。深刻度: 低（既実装の境界をドキュメントに反映したのみ）

### 過去判断との一貫性

#320 の「`~/.cache` 全体ではなくサブパス限定」という攻撃面最小化の設計思想と一致。矛盾なし。

## 2026-04-17 — Issue #329 VIBECORP_ISOLATION=1 下の /login 失敗修正（サイドカー書込許可追加）

### 判定

条件付き承認（以下 4 点の対応後に承認）

### 対象

- `.claude/sandbox/claude.sb`（`~/.claude.json.lock` literal 許可 + `~/.claude.json.tmp.<pid>.<epoch_ms>` regex 許可追加）
- `templates/claude/sandbox/claude.sb`（同上、同期）
- `tests/test_isolation_macos.sh`（テスト [11][12] 追加）
- `docs/SECURITY.md`（書込境界表更新）

### 合議状況

計画段階レビュー（plan-security が Critical 1 件・Major 1 件を検出）。CISO メタレビューにより Critical/Major の再評価を実施。

### 各指摘の判定

| 指摘元 | 内容 | 判定 | 理由 |
|--------|------|------|------|
| plan-security Critical | CEO 承認トレーサビリティ欠落 | 却下（Info） | セキュリティ脆弱性ではなく監査ガバナンスの好みの問題。計画書に「CEO 承認済み」の記載あり |
| plan-security Major | HOME `.` がSBPL regex でメタ文字誤マッチ | 却下（Info） | 計画書 C1 節で既評価済み。`.` が誤マッチしても許可範囲は `.claude.json.lock/.tmp.*` のみ。`validate_abs_path` が危険メタ文字を事前排除済み |
| plan-security Minor | テスト [12] 境界値パターン不足 | 部分採用 | `.tmp.1.2.extra` / `.tmp.abc.1` の 2 パターン追加を推奨（実装ブロックなし） |
| plan-architect | `date +%s` 秒精度と epoch_ms 不一致 | 採用（コメント修正のみ） | regex は桁数不問のため動作は正しい。`.claude/rules/comments.md` 準拠でコメント修正 |
| plan-architect | `diff` 同期チェック未組込み懸念 | 却下（Info） | 計画書 Phase 1 に既記載 |
| plan-architect | `/login` 成功が CI 外 | 却下（Info） | Phase 1 からの既知設計。SECURITY.md に明記済み |
| plan-testing | テスト [12] パターン不足（重複） | 部分採用（上記と同一） | 同上 |
| plan-testing | `.claude/sandbox` 側テスト欠落 | 却下（Info） | `diff 0` 検証で同一性担保済み |
| plan-testing | `.lock` 既存状態ケース不在 | 採用（Minor） | 次回改善候補。実装ブロックなし |
| plan-dx 全件 | UX/CI 手順の懸念 | 却下（Info） | セキュリティリスクに非該当 |

### 新規懸念

**N-001（過去判断との一貫性違反 — 必須対応）**

#320 CISO 判断「D-1: `claude.sb` に `.claude.json.lock` のエントリなし。反映済み」を今回の変更が上書きする。kernel ログにより `.lock` deny が確認されたため再追加する必要性は正当だが、decisions.md・SECURITY.md に「#329 で再追加した背景（#320 D-1 の方針変更）」を明記すること。

**N-002（sandbox param 未設定時の regex 動作確認 — Minor）**

`(regex (string-append (param "HOME") "..."))` は sandbox-exec 起動時に評価される。テスト [11] フェイク環境で `-D HOME=...` が確実に渡されることを確認すること。

### #320 D-1 判断の上書き記録

**旧判断（2026-04-16）**: `claude.sb` に `.claude.json.lock` のエントリなし。D-1 により除去・反映済み。

**新判断（2026-04-17）**: kernel ログ `deny(1) file-write-create /Users/hiroki/.claude.json.lock` により、`/login` 実行時に `.lock` の書込が必須であることが実機確認された。`.lock` 除去判断を撤回し、literal 許可として再追加する。攻撃面への影響: `~/.claude.json` 全 RW 許可（#320 承認済み）と同等の信頼境界のため、実質的な攻撃面変化なし。

### 攻撃チェーン分析

- 追加される regex: `^<HOME>/\.claude\.json\.tmp\.[0-9]+\.[0-9]+$`（`^`/`$` 固定）
- `vibecorp-sandbox` の `validate_abs_path` により HOME の危険文字を事前排除済み
- regex インジェクションで追加の書込権限を得る経路なし
- `.lock` literal 許可: 単一ファイルのみ
- 深刻度: 低（Phase 1 既知制約の範囲内）

### 過去判断との一貫性

#320 D-1 を明示的に上書き（理由: kernel log による必要性の確認）。それ以外の #309/CR-001/#318/#320/#326 の判断とは矛盾なし。
