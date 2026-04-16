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
