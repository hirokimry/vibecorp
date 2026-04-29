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
| 書込 | WORKTREE（`$PWD`）、`~/.claude`、`/tmp`、`$TMPDIR`、`~/.cache/vibecorp`（ゲートスタンプ保存先 #326）、`~/.cache/claude`、`~/.local/state/claude`（Claude Code 2.1.112+ XDG サイドカー #331）|
| 書込（単一ファイル） | `~/.claude.json`、`~/.claude.json.backup`、`~/.claude.json.lock`、`~/.claude.json.tmp.<pid>.<epoch_ms>`（regex）— Claude Code の原子的置換パターンに対応（#329） |
| 読取 | `/usr`、`/System`、`/Library`、`/opt/homebrew`、`~/.gitconfig`、`~/.config/gh`、`~/.npm`、`~/.local/share/claude`（claude バイナリ実体） |
| ioctl | `/dev/**`（TTY raw mode 切替に必須。Issue #320 で追加） |
| 拒否（deny default） | `~/.ssh`、`~/.aws`、`~/.gnupg`、`~/Library/Keychains` 等 |

**Issue #320 で追加された境界（claude バージョンアップで要再検証）:**

claude 本体（npm 配布）は `~/.local/share/claude/versions/<version>/` 配下にバイナリ実体を配置し、`~/.claude.json` に OAuth トークン・プロジェクト一覧を保存し、`/dev/ttys*` への ioctl で TTY raw mode に切り替える。これらが許可されていないと TUI が起動できない。claude のバージョンアップで参照パス・要求 ioctl が変わると再びハングする可能性があるため、定期的な再検証を推奨する。

**Issue #326 で追加された境界（ゲートスタンプの XDG キャッシュ移動）:**

ゲートスタンプは `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/{gate名}-ok` に保存される。`~/.cache` 全体ではなく `~/.cache/vibecorp` サブパスのみを許可（攻撃面最小化）。脅威モデル: 同一ユーザーの別プロセスからのスタンプ偽造はスコープ外（信頼境界 = ユーザーアカウント）。chmod 700 で他ユーザーからの偽造のみブロック。

**Issue #331 で追加された境界（Claude Code 2.1.112+ XDG サイドカー）:**

Claude Code 2.1.112 以降は OAuth state を XDG 3 ディレクトリにまたがって管理する:

- `~/.local/share/claude/versions/<ver>/` — バイナリ実体（RO で既許可、#320）
- `~/.local/state/claude/locks/<ver>.lock` — バージョン固有ロック（書込必須）
- `~/.cache/claude/staging/` — staging 領域（書込必須）

`~/.cache/claude` と `~/.local/state/claude` を subpath で RW 許可する。lock ファイル名はバージョン依存（`2.1.112.lock` 等）のため literal 指定は不可。`~/.cache` 全体・`~/.local/state` 全体には拡張せず、`claude` 直下サブパスのみに限定（他アプリのサイドカーを巻き込まない）。境界は `test_isolation_macos.sh [17]` で検証。

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

CISO エージェントによるメタレビューで「Phase 1 既知制約の範囲内」と判定済み（`.claude/knowledge/ciso/decisions/2026-Q2.md` 2026-04-16）。CR-001 で封鎖した WORKTREE 境界・HOME 包含拒否の防御ロジックは `vibecorp-sandbox` スクリプト側に実装されており、`claude.sb` 境界拡張に影響されない。

**Issue #331 で拡張した境界に対する CR-001 観点の再評価（2026-04-17）**:

- `~/.cache/claude/**` RW 許可: claude バージョン固有の staging 領域。書込み対象は `~/.claude.json` / `~/.claude` 全体と同等の信頼境界。`claude-evil` 等の兄弟ディレクトリは subpath 境界により拒否（`test_isolation_macos.sh [17]` で検証）。
- `~/.local/state/claude/**` RW 許可: バージョン固有 lock ファイルの書込経路。攻撃面は既存の `~/.claude` 全 RW と同等。

### Phase 1 の位置づけと既知の制約

**Phase 1 は PoC であり、完全なサンドボックスではない。** Phase 2 で追跡予定の既知制約を以下に列挙する。

| 制約 | 内容 |
|------|------|
| ネットワーク全許可 | `(allow network*)` により全通信が許可。`~/.config/gh` 読取との組み合わせで GitHub PAT 外部送信の経路が存在する |
| process-exec 無制限 | `(allow process-exec)` が無制限のため、osascript 等を経由した sandbox 境界迂回の可能性がある |
| `~/.claude` 全 RW 許可 | hooks 書き換えによる持続的な挙動改変が可能 |
| `~/.claude.json` 全 RW 許可 | OAuth トークン・プロジェクト一覧含む全フィールドが RW。境界は単一ファイル literal に限定。**評価根拠**: 既存の `~/.claude` 全 RW 許可と同等の信頼境界であり、攻撃面は実質変わらない（CISO メタレビュー 2026-04-16） |
| `~/.cache/claude` / `~/.local/state/claude` 全 RW 許可 | Claude Code 2.1.112+ の XDG サイドカー（staging / version lock）のため subpath で RW 許可。境界は `claude` 直下のみに限定し、`~/.cache` 全体・`~/.local/state` 全体には拡張しない。**評価根拠**: 既存の `~/.claude` 全 RW 許可と同等の信頼境界（CISO メタレビュー 2026-04-17、#331） |
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

## knowledge ガードレール（多層防御）

`.claude/knowledge/{role}/decisions/` および `{role}/audit-log/` への作業ブランチ直書きは、Edit/Write 層と Bash 層の 2 つの PreToolUse hook で fail-secure deny される。書込みは buffer worktree 経由（`~/.cache/vibecorp/buffer-worktree/<repo-id>/`）のみ許可される。

### 防御層の構成

| 層 | フック | matcher | 検出対象 |
|---|---|---|---|
| Edit/Write 層 | `protect-knowledge-direct-writes.sh`（Issue #439） | `Edit\|Write\|MultiEdit` | Edit/Write/MultiEdit ツールでの直書き |
| Bash 層 | `protect-knowledge-bash-writes.sh`（Issue #448） | `Bash` | Bash redirect / コマンド経由の直書き |

**配置 preset**: 両 hook は **全 preset（minimal / standard / full）で配置される**。`install.sh` は `templates/claude/hooks/*.sh` を preset でフィルタせず順次コピーするため、minimal でも knowledge ガードレールは有効になる。`vibecorp.yml` の `hooks:` セクションで個別に無効化することは可能（推奨しない）。

### Bash 層の検出対象パターン

| パターン | 例 |
|---|---|
| 出力リダイレクト `>` `>>` | `echo foo >> .claude/knowledge/cfo/decisions/2026-Q2.md` |
| `tee` / `tee -a` | `cat patch.md \| tee .claude/knowledge/security/audit-log/2026-Q2.md` |
| `cp` / `mv` | `cp src.md .claude/knowledge/cto/decisions/2026-Q2.md` |
| GNU sed `-i` / BSD sed `-i ''` | `sed -i 's/old/new/' .claude/knowledge/cfo/decisions/2026-Q2.md` |
| `awk -i inplace` | `awk -i inplace '{print}' .claude/knowledge/cfo/decisions/2026-Q2.md` |

> **heredoc**: `cat <<EOF > path` 形式は heredoc 専用パターンではなく、末尾の `>` redirect で結果的に捕捉される（実装は redirect で検知）。

コマンド正規化により、以下のラッパー経由でも検出される:

- 環境変数プレフィックス（`KEY=VALUE cat >> ...`）
- `env` / `command` ラッパー（`env cat >> ...`、`command tee ...`）
- `bash -c "..."` / `sh -c "..."` の展開

### 既知ギャップ（多層防御で他層がカバー）

以下は Bash 層で素通りするが、Edit/Write 層 + agent 定義の Edit/Write 強制でカバーされる:

- `bash -c $'...'` 形式（`$''` quote）
- shell function 経由
- `eval "..."` 経由

C\*O / 分析員エージェントは tools 宣言で `Edit, Write, MultiEdit` を持ち（C\*O 6 体は全員、分析員は accounting / security のみ Write を持つ。詳細は `docs/ai-organization.md` の「エージェント tools セット」表）、agent 定義の書込みセクションで「Bash redirect で knowledge 配下に書き込まない」と明文化されている（Issue #448）。

### fail-secure 原則

- パス正規化（realpath）に失敗した場合、deny パターンに合致するなら **deny を返す**（fail-closed）
- macOS で BSD `realpath` が無い環境では python3 にフォールバック（共通ヘルパー: `templates/claude/lib/path_normalize.sh`）
- buffer worktree のプレフィックス検証（3 段ガード: `buffer_dir 非空 + abs_buffer_dir 非空 + prefix 一致`）に失敗した場合は deny

### 例外: harvest-all-active スタンプ

`/vibecorp:harvest-all` のみ作業ブランチへの直接書込みを許可するため、ユーザー承認後に `~/.cache/vibecorp/state/<repo-id>/harvest-all-active` スタンプを発行し、Edit/Write 層 hook を一時的に通過させる。**ただし `decisions/` と `audit-log/` への書込みはスタンプがあっても deny を維持する**（C\*O 判断記録 / 分析員監査の責務領域は fail-secure で迂回不可）。これは Issue #439 設計判断 2 で確定された fail-secure ポリシー。

### 救済手順

作業ブランチに残った差分は [`docs/migration-knowledge-buffer.md`](migration-knowledge-buffer.md) の手順で buffer 経由に移送する。

## 自律実行承認ゲート（Issue #361）

### 3者承認ゲートの設計

/vibecorp:issue スキル（full/standard プリセット）でのIssue起票時に、CISO・CPO・SMの3者が不可領域フィルタを実施する。**全会一致ルール**: 1者でも「除外」と判定した場合は起票を中止する。

不可領域の5分類:

| 分類 | 対象 |
|------|------|
| 認証 | 認証・認可フックの変更、settings.json permissions セクション |
| 暗号 | encrypt/decrypt/secret/credential/token を扱うコード |
| 課金構造 | claude -p 等の LLM 起動方式、コスト上限パラメータ |
| ガードレール | protect-files.sh / diagnose-guard.sh 等の自律制御フック |
| MVV | MVV.md 自体の変更 |

詳細定義: `.claude/rules/autonomous-restrictions.md`

### 起票側集約アーキテクチャ

不可領域フィルタは**起票側（/vibecorp:issue・/vibecorp:diagnose）に集約**し、/vibecorp:autopilot は起票済み Issue を透過パイプとして扱う。

- /vibecorp:autopilot は全 open Issue を処理対象とするが、起票ゲートを通過した Issue のみが存在する前提で動作する
- /vibecorp:diagnose も起票時に同等の3者承認ゲートを実装済みであり、この前提を担保する
- この前提が崩れると「ゲートなしで起票された不可領域 Issue が /vibecorp:autopilot で自動実装される」攻撃経路が生じる

**既知制約**: Issue 本文へのプロンプトインジェクション（「判定: OK」等の埋め込み）による判定偽装の可能性がある。ただし CEO アカウントの侵害が前提条件となるため、信頼境界（CEO = ユーザー）の設計上スコープ外として扱う。

### プリセット別動作

| プリセット | /vibecorp:autopilot | 3者ゲート | 安全性根拠 |
|-----------|-----------|----------|----------|
| full | 動作する | /vibecorp:issue・/vibecorp:diagnose で実施済み | 起票側フィルタが前段で機能 |
| standard | 動作しない | /vibecorp:issue で実施 | /vibecorp:autopilot が存在しないため自動実装経路なし |
| minimal | 動作しない | スキップ（/vibecorp:issue のみ動作） | /vibecorp:autopilot が存在しないため自動実装経路なし |

minimal プリセットでは /vibecorp:autopilot スキル自体が配置されないため、3者ゲートが非動作であっても不可領域の自動実装経路は存在しない。

## 事後監査

`/vibecorp:audit-security`（full プリセット限定）で CISO による月次セキュリティ監査を自動化できる。直近 30 日間のコード変更を分析し、`knowledge/security/audit-log/YYYY-QN.md`（四半期集約）に追記し、`audit-log/audit-log-index.md` に 1 行サマリを追記する（Issue #442 で確立した分析員監査ログの 2 段構成）。Critical / Major 指摘がある場合は自動で `audit` + `security` ラベル付き Issue を起票する。

### 定期実行例

```bash
# 毎月1日 09:00 JST に実行
/schedule monthly "0 0 1 * *" /vibecorp:audit-security
```

または cron で:

```bash
# crontab -e
0 0 1 * * cd /path/to/repo && claude -p "/vibecorp:audit-security"
```

### 監査観点

- 認証・認可ロジックの変更
- 新規依存パッケージの追加
- hooks のガードレール変更
- secrets / credentials 扱い箇所の変更
- OWASP Top 10 該当変更の有無
