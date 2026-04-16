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

```bash
export VIBECORP_ISOLATION=1
```

`VIBECORP_ISOLATION=1` を明示設定したときのみ sandbox 経由で起動する。未設定時は通常の claude 実行と同等。

### 書込・読取境界

| 方向 | 許可範囲 |
|------|---------|
| 書込 | WORKTREE（`$PWD`）、`~/.claude`、`/tmp`、`$TMPDIR` |
| 読取 | `/usr`、`/System`、`/Library`、`/opt/homebrew`、`~/.gitconfig`、`~/.config/gh`、`~/.npm` |
| 拒否（deny default） | `~/.ssh`、`~/.aws`、`~/.gnupg`、`~/Library/Keychains` 等 |

### Phase 1 防御レイヤ（実装済み）

以下は Phase 2 制約とは別に、Phase 1 で実装済みの境界検証防御である。

| 防御 | 実装内容 |
|------|---------|
| WORKTREE 境界の 2 段階検証 | raw バリデーション（空文字列・ルートパス・パストラバーサル）→ `canonicalize_dir()` による symlink 解決 → canonicalize 後の再バリデーション |
| WORKTREE ⊇ HOME 拒否 | symlink 経由で `WORKTREE` が `HOME` を包含する値に解決された場合、`case` 文による包含チェックで起動を拒否する。`~/.ssh`、`~/.aws`、`~/.gnupg` 等への書込経路を遮断 |

**背景（CR-001）**: `WORKTREE=/Users` や `$HOME/subdir`、symlink 経由での包含注入は、単純な等値比較では検出できない。`canonicalize_dir()` で symlink 解決後に包含チェックを行うことで、この攻撃経路を封鎖している。攻撃チェーンの封鎖は `test_isolation_macos.sh [8]`（WORKTREE ⊇ HOME 拒否テスト）で検証済み。

### Phase 1 の位置づけと既知の制約

**Phase 1 は PoC であり、完全なサンドボックスではない。** Phase 2 で追跡予定の既知制約を以下に列挙する。

| 制約 | 内容 |
|------|------|
| ネットワーク全許可 | `(allow network*)` により全通信が許可。`~/.config/gh` 読取との組み合わせで GitHub PAT 外部送信の経路が存在する |
| process-exec 無制限 | `(allow process-exec)` が無制限のため、osascript 等を経由した sandbox 境界迂回の可能性がある |
| `~/.claude` 全 RW 許可 | hooks 書き換えによる持続的な挙動改変が可能 |
| 過剰読取 | `/Library`、`/private/var/db`、`/private/var/folders` を広く読取許可している |
| IPC/syscall 全許可 | `mach-lookup`、`ipc-posix-shm`、`sysctl-read` を全許可している |
| HOME 改ざん対策未実装 | CI 環境での `HOME` 変数改ざんに対する防御がない |
| PROFILE の TOCTOU 対策未実装 | プロファイルファイルの読取から実行までの TOCTOU 競合に対する対策がない |

これらは install.sh 連携（Phase 3）の前に Phase 2 で追跡予定。

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
