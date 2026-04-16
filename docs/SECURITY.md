# vibecorp セキュリティポリシー

> このドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth です。

## セキュリティ方針

（セキュリティに関する基本方針を記載）

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

（認証方式・認可モデルの概要を記載）

## データ保護

### 機密情報の取り扱い

- シークレット・APIキー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する

### 個人情報

（個人情報の取り扱い方針を記載）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）

## エージェント隔離レイヤ（sandbox-exec）

### 概要

macOS 向けの Claude プロセス隔離レイヤ（Phase 1 PoC）を `templates/claude/` に配置している。

| ファイル | 役割 |
|---------|------|
| `templates/claude/bin/claude` | PATH シム。`VIBECORP_ISOLATION=1` のとき `vibecorp-sandbox` 経由で起動する |
| `templates/claude/bin/vibecorp-sandbox` | OS ディスパッチャ。Darwin では sandbox-exec、Linux は Phase 2 で実装予定 |
| `templates/claude/sandbox/claude.sb` | sandbox-exec プロファイル（TinyScheme）|

### 有効化方法（opt-in）

**full プリセット + macOS 環境**で `install.sh` を実行すると、導入先リポジトリに以下が自動配置される:

- `.claude/bin/claude` — PATH シム
- `.claude/bin/vibecorp-sandbox` — OS ディスパッチャ
- `.claude/bin/activate.sh` — PATH 設定スクリプト
- `.claude/sandbox/claude.sb` — sandbox-exec プロファイル

導入先のリポジトリルートで bash / zsh セッションに以下を実行する:

```bash
# PATH 先頭に .claude/bin を追加
source .claude/bin/activate.sh

# 隔離を有効化
export VIBECORP_ISOLATION=1
```

**動作確認:**

```bash
which claude
# => /path/to/project/.claude/bin/claude
```

`VIBECORP_ISOLATION=1` を明示設定したときのみ sandbox 経由で起動する。未設定時は通常の claude 実行と同等。fish 等の他シェルは未対応（bash / zsh のみ）。Windows ネイティブは非対応（WSL2 を使用）。

### 書込・読取境界

| 方向 | 許可範囲 |
|------|---------|
| 書込 | WORKTREE（`$PWD`）、`~/.claude`、`/tmp`、`$TMPDIR` |
| 書込（単一ファイル） | `~/.claude.json`、`~/.claude.json.backup`（claude グローバル設定） |
| 読取 | `/usr`、`/System`、`/Library`、`/opt/homebrew`、`~/.gitconfig`、`~/.config/gh`、`~/.npm`、`~/.local/share/claude`（claude バイナリ実体） |
| ioctl | `/dev/**`（TTY raw mode 切替に必須。Issue #320 で追加） |
| 拒否（deny default） | `~/.ssh`、`~/.aws`、`~/.gnupg`、`~/Library/Keychains` 等 |

**Issue #320 で追加された境界（claude バージョンアップで要再検証）:**

claude 本体（npm 配布）は `~/.local/share/claude/versions/<version>/` 配下にバイナリ実体を配置し、`~/.claude.json` に OAuth トークン・プロジェクト一覧を保存し、`/dev/ttys*` への ioctl で TTY raw mode に切り替える。これらが許可されていないと TUI が起動できない。claude のバージョンアップで参照パス・要求 ioctl が変わると再びハングする可能性があるため、定期的な再検証を推奨する。

### Phase 1 防御レイヤ（実装済み）

以下は Phase 2 制約とは別に、Phase 1 で実装済みの境界検証防御である。

| 防御 | 実装内容 |
|------|---------|
| WORKTREE 境界の 2 段階検証 | raw バリデーション（空文字列・ルートパス・パストラバーサル）→ `canonicalize_dir()` による symlink 解決 → canonicalize 後の再バリデーション |
| WORKTREE ⊇ HOME 拒否 | symlink 経由で `WORKTREE` が `HOME` を包含する値に解決された場合、`case` 文による包含チェックで起動を拒否する。`~/.ssh`、`~/.aws`、`~/.gnupg` 等への書込経路を遮断 |

**背景（CR-001）**: `WORKTREE=/Users` や `$HOME/subdir`、symlink 経由での包含注入は、単純な等値比較では検出できない。`canonicalize_dir()` で symlink 解決後に包含チェックを行うことで、この攻撃経路を封鎖している。攻撃チェーンの封鎖は `test_isolation_macos.sh [8]`（WORKTREE ⊇ HOME 拒否テスト）で検証済み。

**Issue #320 で拡張した境界に対する CR-001 観点の再評価（2026-04-16）**:

- `~/.local/share/claude/**` RO 許可: バイナリ実体への読取のみ。書き換え不可。情報漏洩リスクは既存の `~/.npm` RO 許可と同等かそれ以下。
- `~/.claude.json` / `.backup` RW 許可: 既存の `~/.claude` 全 RW 許可と同等の信頼境界。OAuth トークンの書き換えは既に可能だったため、攻撃面は実質変わらない（`(literal ...)` で単一ファイルに限定）。
- `/dev` 配下 file-ioctl 全許可: `/dev` への read / write-data は既に許可済み。ioctl 追加で新たに開く攻撃面は限定的（`/dev/mem` は現代 macOS で無効化済み）。

CISO エージェントによるメタレビューで「Phase 1 既知制約の範囲内」と判定済み（`.claude/knowledge/ciso/decisions.md` 2026-04-16）。CR-001 で封鎖した WORKTREE 境界・HOME 包含拒否の防御ロジックは `vibecorp-sandbox` スクリプト側に実装されており、`claude.sb` 境界拡張に影響されない。

### Phase 1 の位置づけと既知の制約

**Phase 1 は PoC であり、完全なサンドボックスではない。** Phase 2 で追跡予定の既知制約を以下に列挙する。

| 制約 | 内容 |
|------|------|
| ネットワーク全許可 | `(allow network*)` により全通信が許可。`~/.config/gh` 読取との組み合わせで GitHub PAT 外部送信の経路が存在する |
| process-exec 無制限 | `(allow process-exec)` が無制限のため、osascript 等を経由した sandbox 境界迂回の可能性がある |
| `~/.claude` 全 RW 許可 | hooks 書き換えによる持続的な挙動改変が可能 |
| `~/.claude.json` 全 RW 許可 | OAuth トークン・プロジェクト一覧含む全フィールドが RW。境界は単一ファイル literal に限定。**評価根拠**: 既存の `~/.claude` 全 RW 許可と同等の信頼境界であり、攻撃面は実質変わらない（CISO メタレビュー 2026-04-16） |
| `/dev` ioctl 全許可 | 個別 ioctl 番号での絞り込みは未実装。TTY 制御以外の ioctl も通過する |
| `--add-dir` 等の WORKTREE 外ディレクトリ読取は未対応 | claude グローバル設定で外部プロジェクトを参照するエイリアスは sandbox に拒否される。Phase 2 で opt-in 機構を検討 |
| `claude-real` symlink 先の検証なし | `setup_claude_real_symlink()` は PATH 上の `claude` を検出して symlink するのみで、リンク先バイナリの署名・出所検証は行わない。PATH 汚染環境（攻撃者制御の `~/.local/bin/claude` 等）は Phase 1 のスコープ外。ユーザー側で正規の Anthropic 配布物が PATH 上にあることを担保する必要がある |
| 過剰読取 | `/Library`、`/private/var/db`、`/private/var/folders` を広く読取許可している |
| IPC/syscall 全許可 | `mach-lookup`、`ipc-posix-shm`、`sysctl-read` を全許可している |
| HOME 改ざん対策未実装 | CI 環境での `HOME` 変数改ざんに対する防御がない |
| PROFILE の TOCTOU 対策未実装 | プロファイルファイルの読取から実行までの TOCTOU 競合に対する対策がない |

これらは Phase 2（Linux bwrap 統合、#310）以降で追跡予定。install.sh 連携は Phase 3a（#318）で実装済み。

### Phase 1 PoC の動作確認手順

CI（GitHub Actions の macos-latest ランナー）には実機 claude が無いため、TUI 起動の E2E テスト（`tests/test_isolation_macos.sh [9][10]`）は常に skip される。ユーザーローカルでは以下の手順で sandbox 経由の TUI 起動を検証できる:

```bash
# 1. install.sh で隔離レイヤを配置
./install.sh --update --preset full

# 2. claude-real symlink が作られたことを確認
ls -la .claude/bin/claude-real
# => claude-real -> ~/.local/bin/claude（または PATH 上の本物 claude）

# 3. 隔離有効化
source .claude/bin/activate.sh
export VIBECORP_ISOLATION=1

# 4. TUI 起動
claude
# => プロンプトが表示されれば OK。ハングする場合は claude のバージョン依存の
#    新規境界要求が発生している可能性があるため、以下で deny ログを確認:
#    log show --predicate 'process == "kernel" AND eventMessage CONTAINS "deny"' --last 2m
```

claude のメジャーバージョンアップ後は再検証を推奨する。

## 事後監査

`/audit-security`（full プリセット限定）で CISO による月次セキュリティ監査を自動化できる。直近30日間のコード変更を分析し、`knowledge/security/audit-YYYY-MM-DD.md` にレポートを保存する。Critical / Major 指摘がある場合は自動で `audit` + `security` ラベル付き Issue を起票する。

### 定期実行例

```bash
# 毎月1日 09:00 JST に実行
/schedule monthly "0 0 1 * *" /audit-security
```

または cron で:

```bash
# crontab -e
0 0 1 * * cd /path/to/repo && claude -p "/audit-security"
```

### 監査観点

- 認証・認可ロジックの変更
- 新規依存パッケージの追加
- hooks のガードレール変更
- secrets / credentials 扱い箇所の変更
- OWASP Top 10 該当変更の有無
