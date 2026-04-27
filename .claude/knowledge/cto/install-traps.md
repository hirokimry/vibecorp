# install.sh の仕様上の注意点

install.sh を変更する際に踏みやすいトラップを記録する。

## lock ベースの管理ファイル判定

`settings.json` のマージ時に vibecorp 管理フックかどうかを判定する際、以前はフックの `.command` パスに `.claude/hooks/` が含まれるかで判定していた。現在は **lock ファイルのフック名リストで判定** する方式に変更されている。

- lock に記載されたフック名を JSON 配列に変換し、jq の `is_managed_hook` 関数で判定する
- パス文字列に依存しないため、ディレクトリ構造を変更しても判定が壊れない

## プリセットの引き算方式

テンプレートは全プリセット分をフル装備で含む。`install.sh` が `copy_managed_files` でまず全ファイルをコピーした後、`case "$PRESET"` で不要なファイルを `rm` する。

- テンプレートに条件分岐を持たせず、`install.sh` だけが選別ロジックを持つ
- 新しいフック/スキルを追加したら、minimal/standard での削除リストに追記が必要

## --update 時のユーザーファイル保護

- hooks / skills: `--update` 時は上書きする（テンプレートが source of truth）
- agents: 既存ファイルがあればスキップする（`--update` でも上書きしない）
- knowledge: 削除しない（ユーザーが蓄積したデータ）
- docs: 既存ファイルはスキップする（ユーザーがカスタマイズ済みの前提）
- rules: `--update` 時は上書きする

## COPIED_* 変数による lock 精度

lock にファイル名を記録する際、hooks/skills/agents はテンプレートの存在 + 配置先の存在で判定する。一方、rules/docs/knowledge/issue_templates は `COPIED_*` 変数に「実際にコピーしたファイル名」を追記し、lock 生成時にこの変数を参照する。

これにより、既存ファイルのスキップによりコピーが行われなかった場合に lock に誤登録されることを防いでいる。

## vibecorp.yml 設定の読み取り順序

`--update` モードでは:

1. `parse_args` でコマンドライン引数をパース（デフォルト値を設定）
2. `read_vibecorp_yml` で yml から既存設定を読み取る
3. コマンドラインで `--preset` / `--language` が明示指定されていればそちらを優先
4. `update_vibecorp_yml` で yml の preset を更新（`--preset` 指定時のみ）

## coderabbit.enabled の判定

`vibecorp.yml` の `coderabbit:` ブロック内の `enabled:` フィールドは、`awk` でネストを追跡して抽出する。トップレベルに `enabled:` という別のキーがあった場合に誤読しないよう注意が必要。

## プレースホルダー検出の誤検知リスク

テンプレートファイル内の未解決プレースホルダーを検出する際、`grep -q '{{'` のように「`{{` を含むか」で判定すると、正当な Go テンプレート構文（例: `docker inspect --format '{{.State.Status}}'`、Helm チャート、Go html/template）を誤検知する。

vibecorp が管理するプレースホルダーは限定的なので、検出も限定する:

```bash
# 悪い例: 全ての {{ を検出 → Go テンプレート等を誤検知
grep -q '{{' "$f"

# 良い例: vibecorp 管理の 3 つのプレースホルダーのみ対象
grep -q '{{PROJECT_NAME}}\|{{PRESET}}\|{{LANGUAGE}}' "$f"
```

同じ原則を post-substitution 検証にも適用する。新しいプレースホルダーを増やす際は検出パターン側も同時に更新すること。

## .claude/ と templates/claude/ の drift 調査手順

`.claude/`（gitignored、実行環境）と `templates/claude/`（source of truth）が乖離しているか調査する定番手順:

1. `./install.sh --update` で同期する（これだけで解消するケースが多い）
2. `diff -q .claude/hooks/foo.sh templates/claude/hooks/foo.sh` で個別ファイルの差分を確認する
3. `ls -lt .claude/hooks/` で mtime を確認し、最後に `install.sh` を走らせた時刻を把握する

挙動が「テンプレートと違う」と感じたら、まず drift を疑って上記手順を試すこと。drift が実際の原因でなかった場合でも、同期を取った状態で調査を進められる。

## ダウングレード時のユーザーファイル保護パターン

プリセットダウングレード時（例: full → minimal）に vibecorp が配置したテンプレート由来ファイルを削除する際、以下のパターンを使う:

```bash
# 既知のテンプレート由来ファイルだけを個別に削除
rm -f "${REPO_ROOT}/.claude/bin/claude"
rm -f "${REPO_ROOT}/.claude/bin/vibecorp-sandbox"
rm -f "${REPO_ROOT}/.claude/bin/activate.sh"
# ディレクトリは rmdir で削除を試みる（非空なら失敗して残る）
rmdir "${REPO_ROOT}/.claude/bin" 2>/dev/null || true
```

ポイント:

- **`rm -rf` 一括削除は禁止**: ユーザーが独自配置したファイル（例: `.claude/bin/my-custom-tool.sh`）を巻き込む
- **`rmdir` はディレクトリが非空なら失敗する** — この性質を利用してユーザーファイルを自動保護する
- テストで「ユーザー独自配置ファイルが保持される」ことを必ず検証する（`tests/test_install_isolation.sh` の E セクションが参考例）

## テスト容易性のため外部依存は `command -v` で解決する

install.sh が外部コマンド（`sandbox-exec` 等）の存在確認を行う場合、絶対パス（`/usr/bin/sandbox-exec`）ではなく `command -v sandbox-exec` を使う:

```bash
# 推奨: PATH モックでテスト可能
if ! command -v sandbox-exec >/dev/null 2>&1; then
  log_error "sandbox-exec が見つからない"
  exit 1
fi
```

理由: 絶対パスだと PATH を制限する形でテストから非存在状態を作り出せない。`command -v` なら `PATH=<minimal-bin>` で対象コマンドを含めない PATH を構成すれば「不在時の exit 動作」をテストできる（`tests/test_install_isolation.sh` の G セクションが実例）。

## PATH 上の自分自身（ラッパー）を除外して本物バイナリを検索するパターン

`command -v claude` は PATH 先頭のコマンドを返すため、vibecorp の PATH シム（`.claude/bin/claude`）が PATH に追加されている環境では、シム自身を返してしまう。

`setup_claude_real_symlink()` のように「本物バイナリへの symlink を作る」処理では、自身が配置されているディレクトリを PATH から除外して再検索する必要がある。

```bash
setup_claude_real_symlink() {
  local bin_dir="${REPO_ROOT}/.claude/bin"
  local real_claude=""

  # IFS=":" で PATH を分割して自身のディレクトリをスキップ
  local IFS=":"
  local p
  for p in $PATH; do
    [[ -z "$p" || "$p" == "$bin_dir" ]] && continue
    if [[ -x "$p/claude" ]]; then
      # symlink の場合はリンク先が振り返って vibecorp ラッパーを指していないか確認
      local resolved
      resolved=$(cd "$p" && readlink claude || echo "$p/claude")
      [[ "$resolved" == *"/.claude/bin/claude" ]] && continue
      real_claude="$p/claude"
      break
    fi
  done

  [[ -n "$real_claude" ]] && ln -sf "$real_claude" "${bin_dir}/claude-real"
}
```

ポイント:

- `bin_dir` と同じ PATH エントリはスキップ（`[[ "$p" == "$bin_dir" ]]`）
- symlink 解決後のパスが再び vibecorp ラッパーを指していないかチェック（循環参照防止）
- `readlink` が失敗するケース（非 symlink）は `|| echo "$p/claude"` でフォールバック

## スタブ廃止時のクリーンアップ照合: `plugin_skills` vs `skills` セクション

`vibecorp.lock` には `plugin_skills` セクションと `skills` セクションがある。

- `plugin_skills`: Plugin 名前空間に登録されたスキル名のリスト
- `skills`: 旧スタブ生成時に `.claude/skills/` へ配置したファイル名のリスト

Phase 3 でスタブ生成を廃止すると `skills` セクションが空になる。`--update` 時に旧スタブをクリーンアップする際は、`plugin_skills` セクションを参照してスタブパス（`.claude/skills/{skill-name}/SKILL.md`）を算出する。

`skills` セクションを照合基準にしてはならない — スタブ生成廃止後は記録が残っていないため、クリーンアップが機能しなくなる。

## 廃止対象コードの削除粒度

生成コマンドを廃止する際は、以下を一括削除する:

1. **生成ループ本体**（例: `for skill in ...; do cp ...; done`）
2. **前提ディレクトリ作成コマンド**（例: `mkdir -p "$skills_dir"`）

生成先ディレクトリを作成するだけの `mkdir -p` は、ループ削除後も構文エラーにならず dead code として残存しやすい。次の修正者が「このディレクトリは何のために作られているのか」と混乱する原因になる。廃止は生成処理の全体を対象とする。

## アーキテクチャ図の更新漏れパターン

docs のアーキテクチャ変更時、本文の説明文を更新しても図（ASCII アート・構造図）だけ旧状態のまま残るケースが頻発する。

sync-check（`docs/` 内の整合確認）で検出されるが、見落としやすいポイント:

- Markdown ファイル内に埋め込まれた ASCII アートのブロック図
- 同一変更を複数 docs ファイルに反映する際、1〜2 ファイルが更新漏れになるパターン

対処: アーキテクチャ変更を伴う PR では、docs の「図を含むセクション」を必ず目視確認する。`grep -r 'skills/' docs/` のように変更対象のパスが図中に残っていないか検索するのが確実。
