# macOS sandbox-exec プロファイル設計ノウハウ

Issue #309（macOS sandbox-exec PoC Phase 1）の実装セッションで得た知見。

## 前提

`sandbox-exec` は macOS の SBPL（Sandbox Profile Language）ベースのプロセス隔離機構。
現代の macOS では非推奨扱いだが、ローカル環境での軽量隔離には依然有効。
Docker を使わずホストOS上で隔離したいケース（vibecorp の隔離レイヤ、full プリセット専用）で補完的に使用する。

## プロファイル設計の落とし穴

### 1. ルートディレクトリ `(literal "/")` の読取許可が必須

サブパス（`/usr`, `/private/tmp` 等）を全て allow していても、`(literal "/")` への読取許可がないとプロセスが起動時に SIGABRT（Abort trap: 6）で即死する。

```scheme
(allow file-read-data (literal "/"))
```

これはパス解決のためにルートディレクトリを stat する macOS の内部動作によるもの。

### 2. `$TMPDIR` は `/tmp` ではない

macOS の `$TMPDIR` は `/var/folders/xx/.../T/` 形式で、`/tmp` や `/private/tmp` とは異なる。sandbox profile で `(param "DARWIN_TMPDIR")` として受け取り、明示的に許可する。

```scheme
(allow file-read* file-write* (subpath (param "DARWIN_TMPDIR")))
```

sandbox-exec 呼び出し時にパラメータとして渡す（`-f` はプロファイルファイルを指定するオプション。vibecorp の実装では `-f` のみを使用する）:

```bash
sandbox-exec -f "$profile" -D DARWIN_TMPDIR="$TMPDIR" -- claude ...
```

### 3. Mach IPC 系の許可

`ipc-posix-shm` や `mach-lookup` など Mach IPC 系を許可しないと、Claude などのモダンなプロセスが起動できない。最低限以下が必要:

```scheme
(allow ipc-posix-shm)
(allow mach-lookup)
```

### 4. `file-ioctl` は `file-read*` / `file-write*` と別の権限カテゴリ（Issue #320 で判明）

`/dev` 配下に `file-read*` / `file-write-data` を許可しても、TTY raw mode の切替（`_IO('t', 20)` 等の ioctl）は通過しない。`file-ioctl` は独立した権限カテゴリとして明示的に許可が必要。

claude（npm 配布）は TUI 起動時に `/dev/ttys*` への ioctl を実行するため、これが欠けると TUI がハングする（プロセス自体は生きているが入力を受け付けない状態）。

```scheme
;; file-read*/file-write* は ioctl をカバーしない
(allow file-read* file-write-data
  (subpath "/dev"))
;; TTY raw mode 切替に必須
(allow file-ioctl
  (subpath "/dev"))
```

### 5. `literal` と `subpath` の使い分け

- `(literal ...)` — 単一ファイルのみに適用。ディレクトリ配下には及ばない
- `(subpath ...)` — ディレクトリ配下の全ファイル・ディレクトリに再帰的に適用

単一ファイルへの限定許可（例: `~/.claude.json`）には `literal` を使い、意図せず広い範囲に権限を与えないようにする。

```scheme
;; ~/.claude.json 1ファイルのみ RW（~/.claude/ 全体には及ばない）
(allow file-read* file-write*
  (literal (string-append (param "HOME") "/.claude.json")))
```

HOME 相対パスは `(string-append (param "HOME") "/...")` で組み立てる。`~` 展開は SBPL では行われないため、`(literal "~/.claude.json")` は機能しない。

### 6. `literal` と `regex` の分離ブロック原則（Issue #329 で確立）

SBPL では `(literal ...)` と `(regex ...)` を同一の `(allow ...)` ブロックに混在させず、責務に応じてブロックを分離する。

- **`(literal ...)`**: 固定名ファイルの完全一致許可。意図が明確で誤許可が起きにくい
- **`(regex ...)`**: 動的名ファイルのパターン照合許可。pid/epoch 等の動的サフィックスに使用

```scheme
;; 固定名ロックファイル（literal で完全一致）
(allow file-read* file-write* file-write-create
  (literal (string-append (param "HOME") "/.claude.json.lock")))

;; 動的名一時ファイル（regex でパターン照合）
(allow file-read* file-write* file-write-create file-write-unlink
  (regex (string-append "^" (param "HOME") "/\.claude\.json\.tmp\.[0-9]+\.[0-9]+")))
```

**`regex` のメタ文字挙動**: `[0-9]+\.[0-9]+` は桁数不問でマッチするため、epoch_s（10桁）・epoch_ms（13桁）・epoch_ns（19桁）いずれにも対応できる。ライブラリ側が time precision を変更しても regex を修正する必要がなく、将来変更への耐性が高い。

**混在させない理由**: 同一ブロックに混在すると「このエントリが固定名なのかパターンなのか」が一見して判別できず、レビュー・更新時に境界責務が曖昧になる。

## デバッグ方法

### `log show` vs `log stream`

Sandbox の拒否ログは `/usr/bin/log` で確認する。zsh では `log` がビルトインに定義されているため、絶対パスを指定する。

**`log stream` は使わない。** `log stream` はリアルタイムストリーミングだが、ログが大量に流れると処理が詰まって端末がフリーズすることがある。`log show --last` の方が安定して動作する。

```bash
# 推奨: 直近 2 分の deny ログを一括取得（短時間指定でノイズを抑える）
/usr/bin/log show --predicate 'process == "kernel" AND eventMessage CONTAINS "deny"' --last 2m
```

`--last` の時間指定は短めにする（`2m`〜`5m` 程度）。長時間にするとシステム全体の deny ログが大量に混入してノイズになる。

`sandbox` カテゴリで絞り込むとさらにノイズが減る:

```bash
/usr/bin/log show --predicate 'eventMessage CONTAINS "deny" AND category == "sandbox"' --last 2m
```

deny ログの典型的な形式:

```text
kernel: (Sandbox) deny(1) file-ioctl /dev/ttys003
kernel: (Sandbox) deny(1) file-read-data /Users/xxx/.local/share/claude/versions/1.2.3/node_modules/...
```

### sandbox 適用確認の複数プローブ検証（Issue #322 セッションで確立）

`VIBECORP_ISOLATION=1` 配下で sandbox-exec が本当に適用されているかを確認する際、単一プローブでは OS デフォルトの挙動と区別しづらい。複数の許可・拒否プローブを組み合わせて全体像を把握する手法が有効。

**拒否境界の確認（sandbox 適用の強い証拠）**:

```bash
# ps 実行 → "Operation not permitted" になれば sandbox 適用の強い証拠
ps aux 2>&1 | head -3

# $HOME 直下への書込み → "Operation not permitted"（書込拒否境界の検証）
touch "$HOME/sandbox_test_probe" 2>&1
```

**許可境界の確認（誤ってブロックしていないか）**:

```bash
# /tmp 書込み → 成功するはず
touch /tmp/sandbox_test_ok 2>&1

# /etc/hosts 読取り → 成功するはず（/private/etc は RO 許可）
head -1 /etc/hosts 2>&1

# ネットワーク疎通 → 成功するはず（network* 全許可）
curl -s --max-time 2 https://example.com > /dev/null 2>&1 && echo "ok"
```

**判定ロジック**: 拒否すべきもの（$HOME 直書き）が拒否され、許可すべきもの（/tmp 書き込み・ネット）が通る場合に sandbox が正しく機能していると判断できる。

## sandbox 経由でのバイナリテスト戦略

### FAKE_HOME vs 実 HOME の役割分担（Issue #320 で確立）

テスト用の一時 HOME（FAKE_HOME）を使うと、real binary が `~/.local/share/...` を参照するパスが存在しないため、実際の TUI 起動検証ができない。

テストは目的によって HOME 戦略を分ける:

| テスト種別 | HOME 戦略 | 目的 |
|-----------|-----------|------|
| sandbox 境界テスト（fake claude-real） | FAKE_HOME（テスト用一時ディレクトリ） | sandbox プロファイルの境界定義が正しいか。本物バイナリ不要 |
| real binary E2E テスト | 実 HOME | 本物の claude が sandbox 経由で TUI 起動できるか |

振り分けの実装例（`tests/test_isolation_macos.sh` の構造）:

- テスト [1]〜[8]: FAKE_HOME で sandbox 境界・ラッパー動作を検証
- テスト [9][10]: 実 HOME で実 claude バイナリの TUI 起動を検証（CI では skip）

実 HOME を使うテストは CI（GitHub Actions）では `claude` 実機がないため skip が適切。ローカルでのみ実行する設計にする。

## vibecorp での位置づけ

Phase 1 PoC（#309/#317）で `templates/claude/` 配下にテンプレートを配置し、Phase 3a（#318）で install.sh が `preset=full && OS=darwin` 時に自動配置するよう連携した。

Issue #320 で TUI ハング問題（`file-ioctl` 欠落）を修正し、実用レベルに達した。

現状の用途:

- full プリセット + macOS 環境で install.sh を実行すると `.claude/bin/` / `.claude/sandbox/` が自動配置される
- ユーザーが導入先リポジトリで `source .claude/bin/activate.sh && export VIBECORP_ISOLATION=1` を実行したときのみ sandbox 経由で claude が起動する（opt-in）
- `VIBECORP_ISOLATION` 未設定時は通常の claude 実行と同等

Phase 2（#310）で Linux bwrap を統合予定。Windows ネイティブは非対応（WSL2 を使用）。

Docker（bind mount）方式との関係は decisions.md（2026-04-11）の記録通り「補完的用途」の位置づけを維持する。Docker が使えない macOS ホスト上で Phase 3a 連携により軽量な隔離が提供される形となる。

### 6. `subpath` 許可だけでは親ディレクトリを作れない（PR #327 で確認）

`(allow file-write* (subpath "/Users/me/.cache/vibecorp"))` を許可しても、親ディレクトリ `/Users/me/.cache/` が存在しない場合に `mkdir -p ~/.cache/vibecorp` は失敗する。

**原因**: `mkdir -p` は中間ディレクトリ（`~/.cache/`）を作成するため `~/` への write が必要だが、sandbox プロファイルでは許可していない。`subpath` の許可はその配下に限定されており、存在しない中間パスの作成には親への write 権限が別途必要になる。

**解決策**: sandbox 外（install.sh や activate.sh 等、sandbox-exec より前に実行される処理）でディレクトリを事前作成する:

```bash
# install.sh / pre-launch スクリプト内（sandbox 外）
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state"

# その後 sandbox-exec を起動
sandbox-exec -f "$profile" -- claude ...
```

プリセット install 時や初回起動スクリプト（`activate.sh` 等）でのディレクトリ事前作成をルールとして設ける。


## Claude Code の既知実装パターン（sandbox 設計時の前提知識）

### OAuth state の原子的置換パターン（Issue #329 で実挙動確認）

Claude Code は OAuth state（`~/.claude.json`）を以下の原子的置換パターンで書き込む:

1. `.lock`（固定名）— 書込中ロック
2. `.tmp.<pid>.<epoch_ms>`（動的名）— 書込先一時ファイル
3. rename — 一時ファイルを本名に移動（原子的）

kernel deny ログで確認した実挙動:

```text
deny(1) file-write-create /Users/xxx/.claude.json.lock
deny(1) file-write-create /Users/xxx/.claude.json.tmp.98846.1776431009101
```

sandbox プロファイルでは、固定名（`.lock`）と動的名（`.tmp.<pid>.<epoch_ms>`）それぞれに対して適切な許可を与える必要がある（セクション6の literal/regex 分離原則を適用）。
