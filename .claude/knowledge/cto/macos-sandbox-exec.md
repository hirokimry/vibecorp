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

sandbox-exec 呼び出し時にパラメータとして渡す:

```bash
sandbox-exec -p "$profile" -D DARWIN_TMPDIR="$TMPDIR" -- claude ...
```

### 3. Mach IPC 系の許可

`ipc-posix-shm` や `mach-lookup` など Mach IPC 系を許可しないと、Claude などのモダンなプロセスが起動できない。最低限以下が必要:

```scheme
(allow ipc-posix-shm*)
(allow mach-lookup)
```

## デバッグ方法

Sandbox の拒否ログは `/usr/bin/log` で確認する。zsh では `log` がビルトインに定義されているため、絶対パスを指定する。

```bash
/usr/bin/log show --predicate 'eventMessage CONTAINS "deny"' --last 5m
```

`sandbox` キーワードで絞り込むとノイズが減る:

```bash
/usr/bin/log show --predicate 'eventMessage CONTAINS "deny" AND category == "sandbox"' --last 5m
```

## vibecorp での位置づけ

decisions.md（2026-04-11）の記録通り、vibecorp では Docker（bind mount）方式を推奨としている。
sandbox-exec は「補完的用途のみ」であり、必須要件には含めない。

具体的には:
- Docker が使えない環境でのローカル隔離テスト
- CI 環境での軽量サンドボックス検証

の用途に限定して使用する。
