シェルスクリプトで以下のパターンを守ること。

## YAML パース

- `grep -A N` で固定行数を取るとセクション境界を越えて別キーの値を巻き込む
- `awk` でブロック単位（次のトップレベルキーで停止）に抽出する

## コマンド判定（フック内）

- ユーザー入力のコマンド文字列を判定する際は以下を正規化する:
  - 環境変数プレフィックス (`KEY=VALUE ...`) の除去
  - ラッパーコマンド (`env`, `command`) の除去
  - 絶対パス/相対パスを `basename` で正規化
- 正規化せずに文字列比較すると簡単にバイパスされる

## `sed -i` を使わない（BSD/GNU 互換）

- `sed -i` は macOS (BSD) と Linux (GNU) で引数の形式が異なり、移植性がない
  - GNU: `sed -i 's/old/new/' file`
  - BSD: `sed -i '' 's/old/new/' file`
- クロスプラットフォームで動作させるには、対象ファイルと同一ディレクトリで一時ファイルを作るパターンを使う:

```bash
# 推奨パターン: 対象ファイルと同一ディレクトリに一時ファイルを作成してから置換
# （同一ファイルシステムなので mv が原子的に動作する）
tmp="$(mktemp "$(dirname "$file")/.${file##*/}.XXXXXX")"
sed 's/old/new/' "$file" > "$tmp" && mv "$tmp" "$file"
```

- `sed -i` はスクリプト内で使用禁止とする

## jq フィルタでのフック名マッチング

- `settings.json` のフックエントリから hook 名を抽出する際は、`.command` フィールドのパス末尾（basename）を使う
- パス文字列の前方一致で判定するとディレクトリ構造の変更に弱い
- `split("/") | last` で basename を取り出し、`.sh` 拡張子を除去してから比較する

## ファイル名に外部入力を使う場合

- ユーザー入力値をファイルパスに組み込む前にサニタイズする
- 許可文字以外を置換する（例: `tr -cs 'A-Za-z0-9._-' '_'`）
- 未設定時のフォールバック値を必ず用意する

## `gh api` のページネーション

- リスト系エンドポイント（comments, reviews 等）は `--paginate` を付ける
- 未指定だと最初の30件のみ返り、以降が欠落する

## コマンドのセグメント分割（quote-aware）

- `&&` や `;` でコマンドを分割する際は、quote 内の区切り文字を無視しなければならない
- `sed 's/&&/\n/g; s/;/\n/g'` は quote（`'...'`・`"..."`）の内外を区別しないため禁止
  - 例: `awk '/^key:/ { sub(/^key:/, ""); print; exit }' file` を分割すると `;` の位置で誤切断される
- awk で `in_single` / `in_double` フラグを管理して quote 内をスキップするか、対象外コマンドを early-exit で弾く方式を使う

```bash
# 推奨パターン: awk による quote-aware セグメント分割
echo "$cmd" | awk '
BEGIN { in_s=0; in_d=0; seg="" }
{
  n = split($0, chars, "")
  for (i = 1; i <= n; i++) {
    c = chars[i]
    if (c == "'"'"'" && !in_d) { in_s = !in_s }
    else if (c == "\"" && !in_s) { in_d = !in_d }
    else if (!in_s && !in_d) {
      if (c == ";" || (c == "&" && chars[i+1] == "&")) {
        print seg; seg = ""
        if (c == "&") i++
        continue
      }
    }
    seg = seg c
  }
  if (seg != "") print seg
}'
```
