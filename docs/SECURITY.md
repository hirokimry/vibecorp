# 🔒 vibecorp セキュリティポリシー

> [!IMPORTANT]
> **このドキュメントは vibecorp の以下 3 つの Source of Truth である。**
>
> - セキュリティ方針（何を守るか・誰が守るか）
> - 脅威モデル（想定する攻撃と防御の対応関係）
> - 隔離レイヤ境界（sandbox の許可・拒否ルール）
>
> **読者像**: CEO（意思決定者）・利用者（vibecorp 導入開発者）・CISO（監査責任者）

## 📋 セキュリティ方針

vibecorp は AI エージェントを組織化する基盤として、以下を守る。

- **AI エージェントの暴走を防ぐ**: フック群でエージェントの破壊操作を遮断する
- **認証情報を守る**: sandbox で機密ディレクトリへのアクセスを制限する
- **変更を透明にする**: 全コマンドを監査ログに記録する

## 🚨 脆弱性報告

| 項目 | 内容 |
|------|------|
| 報告先 | GitHub Security Advisories（非公開） |
| 対応方針 | 受付後 72 時間以内に初回応答 |

## 🔑 認証・認可

### claude-code-action OAuth 認証経路

AI レビュー（claude-code-action）の OAuth 認証経路は
[`docs/ai-review-auth.md`](ai-review-auth.md) を Source of Truth とする。

以下は同ドキュメントに記載する。

- GitHub App + Claude Max OAuth + secrets 運用
- 漏洩時の revocation 手順
- Forked PR では secrets が渡らない仕様
- `CLAUDE_CODE_OAUTH_TOKEN` 空文字列による silent fail 防止 preflight（Issue #509）

## 🗄️ データ保護

### 機密情報の取り扱い

- シークレット・API キー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する

### 個人情報

個人情報は収集・保存しない。

## 📦 依存関係管理

`/vibecorp:audit-security` による月次監査で新規依存パッケージを検出する。
Critical / Major の既知 CVE は即時対応する。

## 🚑 インシデント対応

セキュリティインシデント発生時は以下の順で対応する。

1. 攻撃経路を特定して遮断する
2. CISO が影響範囲を評価する
3. CEO に 1 時間以内にエスカレーションする
4. 事後監査ログに記録する

## ⚠️ 脅威モデル

vibecorp が想定する 3 段階の脅威と防御を定義する。
隔離レイヤ（後述）は脅威 #2・#3 の二次防御として機能する。

| # | 脅威 | 例 | 一次防御 | 二次防御 |
|---|------|----|---------|---------| 
| 1 | **誤操作** | `rm -rf ~` 等の破壊コマンドを誤実行 | OS 標準のユーザー権限 | `protect-files.sh` / `protect-branch.sh` で設定ファイル・main 直書きを deny |
| 2 | **プロンプトインジェクション経由の破壊** | 外部ドキュメント・Issue・MCP レスポンスに仕込まれた指示で AI が `rm -rf ~` 等を実行 | `protect-files.sh` / `protect-branch.sh` 等の保護系フックで破壊操作を抑制。`block-api-bypass.sh` で `gh api` 直マージ等のワークフロー迂回を遮断 | full プリセットの隔離レイヤ。**macOS (Phase 1)**: `sandbox-exec` で WORKTREE 外書込・`~/.ssh` 等を deny。**Linux (Phase 2)**: `bwrap` で WORKTREE 外書込・HOME 配下サブパスを default deny |
| 3 | **認証情報窃取** | `~/.config/gh/hosts.yml` / `ANTHROPIC_API_KEY` / `~/.ssh/` を読み出して外部送信 | `command-log.sh` で全実行コマンドを監査ログに記録 | full プリセットの隔離レイヤで認証情報配置先を制御。`~/.ssh/` / `~/.aws/` / `~/.gnupg/` は読取・書込ともに deny。`~/.config/gh/` は読取のみ許可・書込 deny |

> [!NOTE]
> 両 OS とも `~/.claude` は全 RW 許可（Phase 1 既知制約）。
> 詳細は「Phase 1 / Phase 2 の位置づけと既知の制約」を参照。

各脅威への対応は以下のセクションで詳述する。

- 脅威 #1・#2 の一次防御: [knowledge ガードレール（多層防御）](#knowledge-ガードレール多層防御)
- 脅威 #2・#3 の二次防御: [エージェント隔離レイヤ（sandbox-exec）](#エージェント隔離レイヤsandbox-exec)

OS サポート方針（macOS / Linux / WSL2 first-class、Windows ネイティブ非対応）の根拠は
[`docs/design-philosophy.md#os-support`](design-philosophy.md#os-support) を参照。

## 🛡️ エージェント隔離レイヤ（sandbox-exec）

### 概要

Claude プロセスを OS の sandbox 機能で隔離する。
macOS 向けを Phase 1 PoC、Linux 向けを Phase 2 として実装済みである。

| ファイル | 役割 |
|---------|------|
| `templates/claude/bin/claude` | PATH シム。`VIBECORP_ISOLATION=1` のとき `vibecorp-sandbox` 経由で起動する |
| `templates/claude/bin/vibecorp-sandbox` | OS ディスパッチャ。Darwin では `sandbox-exec`、Linux では `bwrap` を起動する |
| `templates/claude/sandbox/bwrap-args.sh` | Linux bwrap 引数生成スクリプト。`vibecorp-sandbox` から source される |
| `templates/claude/sandbox/claude.sb` | sandbox-exec プロファイル（TinyScheme） |

### 有効化方法（opt-in）

**full プリセット + macOS / Linux 環境**で `install.sh` を実行すると、
導入先リポジトリに以下が自動配置される。

| ファイル | OS |
|---------|----|
| `.claude/bin/claude` | 両 OS 共通 |
| `.claude/bin/vibecorp-sandbox` | 両 OS 共通 |
| `.claude/bin/activate.sh` | 両 OS 共通 |
| `.claude/sandbox/claude.sb` | macOS のみ |
| `.claude/sandbox/bwrap-args.sh` | Linux のみ |

> [!NOTE]
> Linux 環境では `bwrap`（bubblewrap）の事前インストールが必要。
> `install.sh` の `check_isolation_deps()` が不在を検出して案内する。

導入先のリポジトリルートで以下を実行する。

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

- `VIBECORP_ISOLATION=1` を明示設定したときのみ sandbox 経由で起動する
- 未設定時は通常の claude 実行と同等
- fish 等の他シェルは未対応（bash / zsh のみ）
- Windows ネイティブは非対応（WSL2 を使用）

### 書込・読取境界

| 方向 | 許可範囲 |
|------|---------|
| 書込 | WORKTREE（`$PWD`）・`~/.claude`・`/tmp`・`$TMPDIR`・`~/.cache/vibecorp`（ゲートスタンプ保存先 #326）・`~/.cache/claude`・`~/.local/state/claude`（Claude Code 2.1.112+ XDG サイドカー #331） |
| 書込（単一ファイル） | `~/.claude.json`・`~/.claude.json.backup`・`~/.claude.json.lock`・`~/.claude.json.tmp.<pid>.<epoch_ms>`（regex）— Claude Code の原子的置換パターンに対応（#329） |
| 読取 | `/usr`・`/System`・`/Library`・`/opt/homebrew`・`~/.gitconfig`・`~/.config/gh`・`~/.npm`・`~/.local/share/claude`（claude バイナリ実体） |
| ioctl | `/dev/**`（TTY raw mode 切替に必須。Issue #320 で追加） |
| 拒否（deny default） | `~/.ssh`・`~/.aws`・`~/.gnupg`・`~/Library/Keychains` 等 |

> [!WARNING]
> **Issue #320 で追加された境界は claude バージョンアップで要再検証。**
>
> claude 本体（npm 配布）は以下を要求する。
>
> - `~/.local/share/claude/versions/<version>/` 配下にバイナリ実体を配置する
> - `~/.claude.json` に OAuth トークン・プロジェクト一覧を保存する
> - `/dev/ttys*` への ioctl で TTY raw mode に切り替える
>
> これらが許可されていないと TUI が起動できない。
> claude のバージョンアップで参照パス・要求 ioctl が変わると
> 再びハングする可能性があるため、定期的な再検証を推奨する。

> [!NOTE]
> **Issue #326 で追加された境界（ゲートスタンプの XDG キャッシュ移動）**
>
> ゲートスタンプは `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/{gate名}-ok` に保存される。
> `~/.cache` 全体ではなく `~/.cache/vibecorp` サブパスのみを許可する（攻撃面最小化）。
> 脅威モデル: 同一ユーザーの別プロセスからのスタンプ偽造はスコープ外（信頼境界 = ユーザーアカウント）。
> `chmod 700` で他ユーザーからの偽造のみブロックする。

> [!NOTE]
> **Issue #331 で追加された境界（Claude Code 2.1.112+ XDG サイドカー）**
>
> Claude Code 2.1.112 以降は OAuth state を XDG 3 ディレクトリにまたがって管理する。
>
> - `~/.local/share/claude/versions/<ver>/` — バイナリ実体（RO で既許可、#320）
> - `~/.local/state/claude/locks/<ver>.lock` — バージョン固有ロック（書込必須）
> - `~/.cache/claude/staging/` — staging 領域（書込必須）
>
> `~/.cache/claude` と `~/.local/state/claude` を subpath で RW 許可する。
> lock ファイル名はバージョン依存のため literal 指定は不可。
> `~/.cache` 全体・`~/.local/state` 全体には拡張せず、`claude` 直下サブパスのみに限定する。
> 境界は `test_isolation_macos.sh [17]` で検証する。

### Phase 1 防御レイヤ（実装済み）

Phase 1 で実装済みの境界検証防御を以下に示す。

| 防御 | 実装内容 |
|------|---------|
| WORKTREE 境界の 2 段階検証 | raw バリデーション（空文字列・ルートパス・パストラバーサル）→ `canonicalize_dir()` による symlink 解決 → canonicalize 後の再バリデーション |
| WORKTREE ⊇ HOME 拒否 | symlink 経由で `WORKTREE` が `HOME` を包含する値に解決された場合、`case` 文による包含チェックで起動を拒否する。`~/.ssh`・`~/.aws`・`~/.gnupg` 等への書込経路を遮断する |

> [!NOTE]
> **CR-001 設計背景**
>
> `WORKTREE=/Users` や `$HOME/subdir`、symlink 経由での包含注入は
> 単純な等値比較では検出できない。
> `canonicalize_dir()` で symlink 解決後に包含チェックを行うことで
> この攻撃経路を封鎖する。
> 攻撃チェーンの封鎖は `test_isolation_macos.sh [8]` で検証済み。

> [!NOTE]
> **Issue #320 で拡張した境界に対する CR-001 観点の再評価（2026-04-16）**
>
> - `~/.local/share/claude/**` RO 許可: バイナリ実体への読取のみ。書き換え不可。
>   情報漏洩リスクは既存の `~/.npm` RO 許可と同等かそれ以下。
> - `~/.claude.json` / `.backup` RW 許可: 既存の `~/.claude` 全 RW 許可と同等の信頼境界。
>   OAuth トークンの書き換えは既に可能だったため、攻撃面は実質変わらない。
> - `/dev` 配下 file-ioctl 全許可: `/dev` への read / write-data は既に許可済み。
>   ioctl 追加で新たに開く攻撃面は限定的（`/dev/mem` は現代 macOS で無効化済み）。
>
> CISO メタレビューで「Phase 1 既知制約の範囲内」と判定済み
> （`.claude/knowledge/ciso/decisions/2026-Q2.md` 2026-04-16）。

> [!NOTE]
> **Issue #331 で拡張した境界に対する CR-001 観点の再評価（2026-04-17）**
>
> - `~/.cache/claude/**` RW 許可: claude バージョン固有の staging 領域。
>   書込み対象は `~/.claude.json` / `~/.claude` 全体と同等の信頼境界。
>   `claude-evil` 等の兄弟ディレクトリは subpath 境界により拒否する
>   （`test_isolation_macos.sh [17]` で検証）。
> - `~/.local/state/claude/**` RW 許可: バージョン固有 lock ファイルの書込経路。
>   攻撃面は既存の `~/.claude` 全 RW と同等。

### Phase 1 / Phase 2 の位置づけと既知の制約

> [!WARNING]
> **Phase 1 (macOS) / Phase 2 (Linux) は完全なサンドボックスではない。**
> 以下の既知制約が両 OS に共通して存在する。

| 制約 | 内容 |
|------|------|
| ネットワーク全許可 + `~/.config/gh` RO bind | macOS は `(allow network*)`、Linux は `--unshare-net` 不採用により全通信が許可される。`~/.config/gh` 読取との組み合わせで GitHub PAT 外部送信の経路が存在する。**評価根拠**: gh CLI 連携の利便性を優先し、既知の攻撃面として開示する（CISO メタレビュー 2026-05-16、Issue #310） |
| process-exec 無制限 | macOS は `(allow process-exec)` 無制限、Linux は bwrap 内 process 起動を制限しない。osascript / subprocess 等を経由した sandbox 境界迂回の可能性がある |
| `~/.claude` 全 RW 許可 | hooks 書き換えによる持続的な挙動改変が可能（両 OS 共通） |
| `~/.claude.json` 全 RW 許可 | OAuth トークン・プロジェクト一覧含む全フィールドが RW。macOS は単一ファイル literal、Linux は個別 `--bind-try` で限定。**評価根拠**: 既存の `~/.claude` 全 RW 許可と同等の信頼境界（CISO メタレビュー 2026-04-16） |
| `~/.cache/claude` / `~/.local/state/claude` 全 RW 許可 | Claude Code 2.1.112+ の XDG サイドカーのため subpath で RW 許可（両 OS 共通）。境界は `claude` 直下のみに限定。**評価根拠**: 既存の `~/.claude` 全 RW 許可と同等の信頼境界（CISO メタレビュー 2026-04-17、#331） |
| `--add-dir` 等の WORKTREE 外ディレクトリ読取は未対応 | claude グローバル設定で外部プロジェクトを参照するエイリアスは sandbox に拒否される。opt-in 機構は将来検討する |
| `claude-real` symlink 先の検証なし | `setup_claude_real_symlink()` は PATH 上の `claude` を検出して symlink するのみで、リンク先バイナリの署名・出所検証は行わない。PATH 汚染環境はスコープ外 |
| HOME 改ざん対策未実装 | CI 環境での `HOME` 変数改ざんに対する防御がない |
| TOCTOU 対策未実装 | macOS の PROFILE 読取〜実行間、Linux の `bwrap-args.sh` 起動〜bwrap 実行間の TOCTOU 競合に対する対策がない |

#### macOS (Phase 1) 固有制約

| 制約 | 内容 |
|------|------|
| `/dev` ioctl 全許可 | 個別 ioctl 番号での絞り込みは未実装。TTY 制御以外の ioctl も通過する |
| 過剰読取 | `/Library`・`/private/var/db`・`/private/var/folders` を広く読取許可している |
| IPC/syscall 全許可 | `mach-lookup`・`ipc-posix-shm`・`sysctl-read` を全許可している |

#### Linux (Phase 2) 固有制約

| 制約 | 内容 |
|------|------|
| `.claude.json.tmp.<pid>.<ms>` 動的サイドカー bind 不可 | bwrap は regex 許可をサポートしないため、起動時点で存在しない動的ファイルは bind できない。CISO メタレビュー（2026-04-17 #329 / 2026-05-16 #310 マージ承認）では「rename 失敗時の挙動次第で攻撃面は既存と同等以下」と評価。Phase 2.1（#578）として実機検証手順を後述セクションに明文化済み |
| bind 内 symlink エスケープ | `--bind` 対象ディレクトリ内に攻撃者制御 symlink が存在する場合、コンテナ内から bind 境界外を参照できる可能性がある。Phase 1 の CR-001（WORKTREE ⊇ HOME 拒否）を bwrap 実装でも継承することで HOME 配下を意図せず bind する経路は遮断済み |
| `bwrap-args.sh` の TOCTOU | スクリプトが起動時点の `~/.claude.json*` を `--bind-try` で参照する設計のため、スクリプト実行から bwrap 起動の間にファイル差し替えされる TOCTOU リスクが残る |
| `kernel.unprivileged_userns_clone=0` 環境では起動失敗 | bwrap は user namespace に依存する。一部 distro / 一部の hardened CI ランナーで無効化されている場合、`vibecorp-sandbox` は exit 1 で停止する（fail-closed） |
| **GitHub Actions `ubuntu-latest` (Ubuntu 24.04) では bwrap 起動不可** | AppArmor 4.0 の `unprivileged_userns` 制限により `bwrap` は `Permission denied` で失敗する。CI 上の Linux 隔離テストは自動 skip され、実機検証は CEO ローカル環境または自前ホストランナーで実施する |

#### Linux Phase 2.1 — `.claude.json.tmp.<pid>.<ms>` 動的サイドカー実機検証手順

CISO メタレビュー（2026-05-16）で Phase 2 マージ承認とともに
「rename 失敗時の Claude Code 挙動は実機検証で確定する」と判定された。
未確認領域を埋めるための再現手順を以下に示す。
CEO ローカルまたは自前ホストランナーで Phase 2.1（#578）として順次実施する。

**検証目的**: Claude Code が OAuth トークン更新時に
`~/.claude.json.tmp.<pid>.<ms>` への write → rename を試みた際、
bwrap が tmp サイドカーを bind していないことで rename が失敗した場合の
Claude Code 側の挙動を以下 4 分類で測定する。

| 挙動 | 信頼境界への影響 |
|------|---------|
| (A) クラッシュ | 機能毀損あり。再ログイン不能なら Phase 2 を draft に戻して再設計する |
| (B) ハング | UI 操作不能。最小実害は OAuth セッション 1 回分。CEO は SIGINT → 通常 claude（非 sandbox）で復旧可能 |
| (C) エラー継続 / 再試行 | sandbox 利用は実用上問題なし。エラーメッセージから根本原因が分かれば運用ドキュメントに追記する |
| (D) `~/.claude.json` 直接 write fallback | `~/.claude.json` は `--bind-try` で RW 許可済みのため信頼境界変化なし。最良ケース |

(A) のみがロールバック発火条件。(B)(C)(D) は既知制約として開示継続。

**前提環境**:

- distro: Ubuntu 22.04 LTS 以降 / Fedora 39 以降（user namespace が有効な mainline kernel）
- `kernel.unprivileged_userns_clone=1`（必要なら `sysctl -w` で一時的に有効化）
- bwrap >= 0.6（`bwrap --version` で確認）
- Claude Code が npm/curl で正規インストール済みで対話的 OAuth 認証経路が利用可能

**再現手順**:

```bash
# 1. 隔離レイヤを配置（full プリセット）
./install.sh --update --preset full

# 2. activate.sh で PATH に .claude/bin を通す
source .claude/bin/activate.sh

# 3. 隔離を有効化
export VIBECORP_ISOLATION=1

# 4. 既存セッションを切ってから OAuth 再認証
claude logout
claude login
# → 認証完了で ~/.claude.json が更新される。bwrap の bind 境界で
#   .tmp.<pid>.<ms> への write が成功するか／rename が成功するかを観測する
```

**観測ポイント**:

```bash
# A. strace で rename syscall の結果を採取
strace -f -e trace=openat,rename,renameat,renameat2 \
  -o /tmp/claude-login-trace.log \
  bash -c 'VIBECORP_ISOLATION=1 claude login'
# → trace の rename 行で EROFS / EACCES / 成功 のいずれが出るか確認

# B. ~/.claude.json の inode と更新時刻
stat -c '%i %y %s' ~/.claude.json

# C. bwrap stderr（user namespace / bind エラー）
VIBECORP_ISOLATION=1 claude login 2>&1 | tee /tmp/claude-login-stderr.log

# D. kernel 拒否ログ（AppArmor / SELinux 経由の deny）
dmesg | tail -50
sudo journalctl -k --since "5 minutes ago" | grep -i 'deny\|denied\|apparmor\|selinux'
```

**判定基準**:

| 観測結果 | 分類 | 対応 |
|---------|------|------|
| rename 成功 + `~/.claude.json` 更新 | (D) fallback または bwrap が tmp 経由を透過 | 既存と同等以下と確定。本ドキュメントにステータスを追記する |
| rename EROFS/EACCES + `~/.claude.json` 更新 | (D) Claude Code が tmp 失敗を catch して直接 write fallback | 同上 |
| rename EROFS/EACCES + `~/.claude.json` 未更新 + プロセス継続 | (C) エラー継続 | 既知制約に挙動を追記する。ユーザー向けエラーメッセージ品質を Phase 2.2 で改善検討する |
| rename EROFS/EACCES + プロセスハング | (B) ハング | 本ドキュメントの Linux 診断手段に SIGINT 復旧手順を追記する。実用上は問題なし |
| rename EROFS/EACCES + プロセス終了（再起動不能） | (A) クラッシュ | **ロールバック発火**。Phase 2 を draft に戻して再設計する |

**結果記録先**:

- 検証結果サマリ: 本ドキュメント（`docs/SECURITY.md`）の Linux 固有制約テーブルからリンクして反映する
- CISO 判断履歴: `.claude/knowledge/ciso/decisions/YYYY-QN.md`（実施回ごとの一行記録）
- 監査ログ: `.claude/knowledge/security/audit-log/YYYY-QN.md`（Phase 2.1 検証実施ステータスを追記する）

> [!NOTE]
> **現時点ステータス（2026-05-16）**: 未実施。
> 本セクション追加と `bwrap-args.sh` コメント整理までを #578 PR で完了させる。
> 実機検証は CEO ローカル / 自前ホストランナーで Phase 2.1 後続として順次実施する。
> 検証実施後は本セクション末尾に「検証結果（YYYY-MM-DD）」サブセクションを追記する。

#### Linux 診断手段

`vibecorp-sandbox` の Linux ブランチは bwrap 起動失敗を 4 区分（A/B/C/D）に分けて
日本語メッセージで通知する（Issue #579）。
`vibecorp-sandbox` の stderr に出力された区分判定をまず確認し、
該当する区分の対処手順を参照する。

| 区分 | stderr 抜粋 | 原因 | 対処手順 |
|------|------------|------|---------|
| **A** | `bwrap (bubblewrap) が見つかりません` | バイナリ不在 | `sudo apt-get install bubblewrap` / `sudo dnf install bubblewrap` / `sudo apk add bubblewrap` |
| **B** | `bwrap バイナリは存在しますが --version で起動失敗しました` | バイナリ破損 / 権限不足 | `sudo apt-get install --reinstall bubblewrap` / `sudo dnf reinstall bubblewrap` / `sudo apk add --upgrade bubblewrap`<br>権限確認: `ls -lah "$(command -v bwrap)"` |
| **C** | `user namespace で bwrap が動作しません` | unprivileged user namespace 制限（kernel / AppArmor / SELinux） | 下記「区分 C の切り分け」参照 |
| **D** | `bwrap の preflight は通過しましたが、本番起動で exit code <N> で失敗しました` | preflight 通過後の kernel / distro 固有問題 | 下記「区分 D の切り分け」参照 |

##### 区分 C の切り分け

```bash
# unprivileged user namespace が有効か（0 なら無効）
sysctl kernel.unprivileged_userns_clone

# kernel が bwrap を拒否しているか
dmesg | grep -i bwrap

# AppArmor 制限（GHA ubuntu-latest / Ubuntu 24.04 の既知制約）
aa-status
dmesg | grep -i apparmor

# SELinux モード（Enforcing なら policy で deny されている可能性）
getenforce
```

GHA `ubuntu-latest` (Ubuntu 24.04) / Docker コンテナでは
AppArmor 4.0 の `unprivileged_userns` 制限が既知制約（前述「Linux (Phase 2) 固有制約」表）。
CI 上では既存 SKIP ガード（`test_isolation_linux.sh` / `test_isolation_parity.sh`）で自動 skip される。

##### 区分 D の切り分け

preflight（A/B/C）は通過しているため、bwrap バイナリ自体は動作可能。
本番引数列（`--bind` / `--ro-bind` / `--tmpfs` 等）の組み合わせで失敗している。
kernel / distro 固有の問題切り分けに以下を使う。

```bash
# bwrap の標準エラー出力
vibecorp-sandbox echo test 2>&1 | tail -20

# kernel 拒否ログ（AppArmor / SELinux / kernel ENOSYS 等）
dmesg | tail -50
sudo journalctl -k --since "5 minutes ago" | grep -i 'deny\|denied\|apparmor\|selinux'

# AppArmor 環境のみ
sudo grep "audit" /var/log/audit/audit.log | tail -20
```

これらの制約は Phase 2.1 以降で順次追跡予定。
install.sh 連携は Phase 3a (#318) / Phase 2 (#310) で両 OS 実装済み。

### Phase 1 PoC の動作確認手順

CI（GitHub Actions の macos-latest ランナー）には実機 claude が無いため、
TUI 起動の E2E テスト（`tests/test_isolation_macos.sh [9][10]`）は常に skip される。
ユーザーローカルでは以下の手順で sandbox 経由の TUI 起動を検証できる。

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

## 🧱 knowledge ガードレール（多層防御）

`.claude/knowledge/{role}/decisions/` および `{role}/audit-log/` への
作業ブランチ直書きは、Edit/Write 層と Bash 層の 2 つの PreToolUse hook で
fail-secure deny される。
書込みは buffer worktree 経由（`~/.cache/vibecorp/buffer-worktree/<repo-id>/`）のみ許可される。

### 防御層の構成

| 層 | フック | matcher | 検出対象 |
|---|---|---|---|
| Edit/Write 層 | `protect-knowledge-direct-writes.sh`（Issue #439） | `Edit\|Write\|MultiEdit` | Edit/Write/MultiEdit ツールでの直書き |
| Bash 層 | `protect-knowledge-bash-writes.sh`（Issue #448） | `Bash` | Bash redirect / コマンド経由の直書き |

**配置 preset**: 両 hook は**全 preset（minimal / standard / full）で配置される**。
`install.sh` は `templates/claude/hooks/*.sh` を preset でフィルタせず順次コピーするため、
minimal でも knowledge ガードレールは有効になる。
`vibecorp.yml` の `hooks:` セクションで個別に無効化することは可能（推奨しない）。

### Bash 層の検出対象パターン

| パターン | 例 |
|---|---|
| 出力リダイレクト `>` `>>` | `echo foo >> .claude/knowledge/cfo/decisions/2026-Q2.md` |
| `tee` / `tee -a` | `cat patch.md \| tee .claude/knowledge/security/audit-log/2026-Q2.md` |
| `cp` / `mv` | `cp src.md .claude/knowledge/cto/decisions/2026-Q2.md` |
| GNU sed `-i` / BSD sed `-i ''` | `sed -i 's/old/new/' .claude/knowledge/cfo/decisions/2026-Q2.md` |
| `awk -i inplace` | `awk -i inplace '{print}' .claude/knowledge/cfo/decisions/2026-Q2.md` |

> [!NOTE]
> **heredoc**: `cat <<EOF > path` 形式は heredoc 専用パターンではなく、
> 末尾の `>` redirect で結果的に捕捉される（実装は redirect で検知する）。

コマンド正規化により、以下のラッパー経由でも検出される。

- 環境変数プレフィックス（`KEY=VALUE cat >> ...`）
- `env` / `command` ラッパー（`env cat >> ...`、`command tee ...`）
- `bash -c "..."` / `sh -c "..."` の展開

### 既知ギャップ（多層防御で他層がカバー）

以下は Bash 層で素通りするが、Edit/Write 層 + agent 定義の Edit/Write 強制でカバーされる。

- `bash -c $'...'` 形式（`$''` quote）
- shell function 経由
- `eval "..."` 経由

C\*O / 分析員エージェントは tools 宣言で `Edit, Write, MultiEdit` を持つ。
agent 定義の書込みセクションで「Bash redirect で knowledge 配下に書き込まない」と明文化されている（Issue #448）。

📍 根拠: `docs/ai-organization.md` の「エージェント tools セット」表

### fail-secure 原則

- パス正規化（realpath）に失敗した場合、deny パターンに合致するなら **deny を返す**（fail-closed）
- macOS で BSD `realpath` が無い環境では python3 にフォールバックする
  （共通ヘルパー: `templates/claude/lib/path_normalize.sh`）
- buffer worktree のプレフィックス検証（3 段ガード）に失敗した場合は deny する

> [!NOTE]
> **3 段ガードの内容**:
> `buffer_dir 非空 + abs_buffer_dir 非空 + prefix 一致` の 3 条件を全て満たす場合のみ通過する。

### 例外: harvest-all-active スタンプ

`/vibecorp:harvest-all` のみ作業ブランチへの直接書込みを許可する。
ユーザー承認後に `~/.cache/vibecorp/state/<repo-id>/harvest-all-active` スタンプを発行し、
Edit/Write 層 hook を一時的に通過させる。

> [!WARNING]
> **`decisions/` と `audit-log/` への書込みはスタンプがあっても deny を維持する。**
>
> C\*O 判断記録 / 分析員監査の責務領域は fail-secure で迂回不可。
> これは Issue #439 設計判断 2 で確定された fail-secure ポリシー。

### 救済手順

作業ブランチに残った差分は
[`docs/migration-knowledge-buffer.md`](migration-knowledge-buffer.md)
の手順で buffer 経由に移送する。

### BUFFER_DIR 取得失敗時の判断記録ヘッダー方針

C\*O / 分析員エージェントが `BUFFER_DIR` 取得に失敗した場合、
判断内容は固定ヘッダー名で呼出元に返却される。
この方針は本ドキュメントが SoT として保持する。
移行手順の詳細は [`docs/migration-knowledge-buffer.md`](migration-knowledge-buffer.md) を参照。

| 項目 | 内容 |
|------|------|
| **固定ヘッダー文字列** | `### 判断記録（記録先取得失敗）`（全角カッコ・見出しレベル `###`） |
| **表記ゆれ禁止** | 半角カッコ（`(`）・別語句（`フォールバック判断記録`）・見出しレベル変更（`##`）等は全て検知漏れとなる |
| **アンカー検知必須** | 呼出元スキルは `grep -qxF -- '### 判断記録（記録先取得失敗）'`（行全体一致）または `^...$` で検知し、結果レポートの「⚠️ 手動反映が必要な判断記録」に転記する |

これにより BUFFER_DIR 取得失敗時の判断記録が無言で失われる事象（Issue #439 設計判断 5）を防ぐ。

## ✅ 自律実行承認ゲート（Issue #361）

### 3 者承認ゲートの設計

`/vibecorp:issue` スキル（full/standard プリセット）で Issue 起票時に、
CISO・CPO・SM の 3 者が不可領域フィルタを実施する。

> [!WARNING]
> **全会一致ルール**: 1 者でも「除外」と判定した場合は起票を中止する。

不可領域の 6 分類:

| 分類 | 対象 |
|------|------|
| 認証 | 認証・認可フックの変更、`settings.json` permissions セクション |
| 暗号 | `encrypt`/`decrypt`/`secret`/`credential`/`token` を扱うコード |
| 課金構造 | `claude -p` 等の LLM 起動方式、コスト上限パラメータ |
| ガードレール | `protect-files.sh` / `diagnose-guard.sh` 等の自律制御フック |
| MVV | `MVV.md` 自体の変更 |
| CI エージェント | claude-code-action 等の CI 上 Claude エージェントへの権限変更 |

📍 根拠: `.claude/rules/autonomous-restrictions.md`

### 起票側集約アーキテクチャ

不可領域フィルタは**起票側（`/vibecorp:issue`・`/vibecorp:diagnose`）に集約**する。
`/vibecorp:autopilot` は起票済み Issue を透過パイプとして扱う。

- `/vibecorp:autopilot` は全 open Issue を処理対象とする
- 起票ゲートを通過した Issue のみが存在する前提で動作する
- `/vibecorp:diagnose` も起票時に同等の 3 者承認ゲートを実装済み

> [!WARNING]
> この前提が崩れると「ゲートなしで起票された不可領域 Issue が
> `/vibecorp:autopilot` で自動実装される」攻撃経路が生じる。

> [!NOTE]
> **既知制約**: Issue 本文へのプロンプトインジェクション（「判定: OK」等の埋め込み）
> による判定偽装の可能性がある。
> ただし CEO アカウントの侵害が前提条件となるため、
> 信頼境界（CEO = ユーザー）の設計上スコープ外として扱う。

### プリセット別動作

| プリセット | `/vibecorp:autopilot` | 3 者ゲート | 安全性根拠 |
|-----------|-----------|----------|----------|
| full | 動作する | `/vibecorp:issue`・`/vibecorp:diagnose` で実施済み | 起票側フィルタが前段で機能する |
| standard | 動作しない | `/vibecorp:issue` で実施する | `/vibecorp:autopilot` が存在しないため自動実装経路なし |
| minimal | 動作しない | スキップ（`/vibecorp:issue` のみ動作） | `/vibecorp:autopilot` が存在しないため自動実装経路なし |

minimal プリセットでは `/vibecorp:autopilot` スキル自体が配置されないため、
3 者ゲートが非動作であっても不可領域の自動実装経路は存在しない。

## 📊 事後監査

`/vibecorp:audit-security`（full プリセット限定）で CISO による月次セキュリティ監査を自動化できる。

実行すると以下が行われる。

- 直近 30 日間のコード変更を分析する
- `knowledge/security/audit-log/YYYY-QN.md`（四半期集約）に追記する
- `audit-log/audit-log-index.md` に 1 行サマリを追記する（Issue #442 で確立した 2 段構成）
- Critical / Major 指摘がある場合は `audit` + `security` ラベル付き Issue を自動起票する

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
