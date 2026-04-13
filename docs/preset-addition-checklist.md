# プリセット引き算方式 — 新規フック/スキル追加時チェックリスト

> 新しいフックやスキルを追加した際に、プリセット別の引き算ロジックを更新し忘れないためのチェックリストです。

## 前提知識

vibecorp はプリセット（minimal / standard / full）で機能を段階的に提供しています。
テンプレートには **全機能（full 相当）** を収録し、低プリセットでは不要なファイルを **削除（引き算）** する方式です。

```text
full = テンプレート全体（何も削除しない）
standard = full − (full 専用のフック/スキル)
minimal = standard − (standard 専用のフック/スキル)
```

## チェックリスト

新しいフックまたはスキルを追加するとき、以下の **全ステップ** を確認してください。

### 1. install.sh — プリセット別削除（case 文）

**ファイル**: `install.sh` L633–656 付近

```bash
# プリセット別削除（引き算方式）
case "$PRESET" in
  minimal)
    rm -f "${hooks_dir}/新しいフック.sh"      # ← minimal で不要なら追加
    rm -rf "${skills_dir}/新しいスキル"        # ← minimal で不要なら追加
    ;;
  standard)
    rm -f "${hooks_dir}/新しいフック.sh"      # ← standard で不要なら追加
    rm -rf "${skills_dir}/新しいスキル"        # ← standard で不要なら追加
    ;;
esac
```

**判断基準**:
- minimal 専用で削除するもの → `minimal)` ブロックに追加
- standard でも削除するもの → `minimal)` と `standard)` の両方に追加
- full 専用で削除するものは通常ないが、もし必要なら `full)` ブロックを新設

**注意**: `minimal)` ブロックには standard で削除するものも含める（minimal は standard のサブセット）

### 2. install.sh — settings.json フィルタ（jq）

**ファイル**: `install.sh` L1007–1026 付近

```bash
case "$PRESET" in
  minimal)
    # 既存の除外条件に and で新しいフックを追加する
    new_settings=$(echo "$new_settings" | jq '
      .hooks.PreToolUse |= [
        .[]
        | .hooks |= [.[] | select(
            (.command | contains("既存フック1") | not)
            and (.command | contains("既存フック2") | not)
            and (.command | contains("新しいフック") | not)
          )]
        | select((.hooks | length) > 0)
      ]
    ')
    ;;
  standard)
    # standard で不要なら同様に and で追加
    ;;
esac
```

**判断基準**: ステップ1と同じプリセット区分に合わせる。settings.json.tpl にフックを登録した場合は必須。

### 3. install.sh — knowledge コピー制御

**ファイル**: `install.sh` L1239–1242 付近

新しいエージェントロールに紐づく knowledge ディレクトリがある場合:
- `templates/claude/knowledge/` 配下にディレクトリを作成
- minimal では自動的にスキップされる（既存ロジック）
- standard / full 固有の knowledge がある場合は個別制御を追加

### 4. settings.json.tpl — フックエントリ追加

**ファイル**: `templates/settings.json.tpl`

新しいフックを追加する場合:

1. 適切な `matcher`（`Edit|Write`, `Bash` 等）のブロックに hook エントリを追加
2. `command` パスは `"$CLAUDE_PROJECT_DIR"/.claude/hooks/新しいフック.sh` の形式
3. 必要に応じて `timeout` を設定

```json
{
  "type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/新しいフック.sh"
}
```

### 5. README.md — プリセットテーブル更新

**ファイル**: `README.md` L66–68 付近

3つのテーブルを更新する:

1. **プリセット概要テーブル** — スキル一覧・フック一覧・エージェント一覧の列を更新
2. **スキル詳細セクション** — 該当するプリセット見出し配下にスキルの説明を追加
3. **フック詳細テーブル** — フック名、対象プリセット、matcher、説明を追加

### 6. テスト追加

**ファイル**: `tests/test_新しいフック.sh`（新規作成）

- フックの場合: `tests/` 配下に `test_新しいフック.sh` を作成
- 既存テストのパターン（`tests/test_*.sh`）に従う
- 正常系・異常系・バイパス耐性をテストする
- 既存テストが壊れていないことを確認する

### 7. templates/ — テンプレートファイル配置

新しいフック/スキルのテンプレートファイルを適切な場所に配置する:

| 種別 | 配置先 |
|------|--------|
| フック | `templates/claude/hooks/新しいフック.sh` |
| スキル | `templates/claude/skills/新しいスキル/SKILL.md` |
| エージェント | `templates/claude/agents/新しいエージェント.md` |
| knowledge | `templates/claude/knowledge/新しいロール/` |

## まとめ: 更新箇所の早見表

| # | ファイル | 更新内容 | 必須条件 |
|---|---------|---------|---------|
| 1 | `install.sh`（case 文） | rm 行を追加 | フック/スキルが全プリセット対象でない場合 |
| 2 | `install.sh`（jq フィルタ） | select 条件を追加 | フックを settings.json.tpl に登録した場合 |
| 3 | `install.sh`（knowledge） | コピー制御を追加 | 新エージェントに knowledge がある場合 |
| 4 | `settings.json.tpl` | フックエントリを追加 | フックの場合 |
| 5 | `README.md` | テーブル・セクションを更新 | 常に必須 |
| 6 | `tests/test_*.sh` | テストケースを追加 | 常に必須 |
| 7 | `templates/` | テンプレートファイルを配置 | 常に必須 |

## full プリセット限定: Docker 依存機能を追加する場合

full プリセット専用の機能が Docker CLI・デーモン・イメージに依存する場合、以下の追加チェックが必要です。

### 8. install.sh — check_docker() の呼び出し確認

**対象**: Docker CLI またはデーモンを実行時に必要とする機能

`install.sh` の `check_docker()` は full プリセット時に自動で呼ばれる。新機能が Docker に依存するなら、この関数が以下を満たしているか確認する:

- Docker CLI (`docker` コマンド) の存在確認
- Docker デーモンの起動確認 (`docker info`)
- 未導入・未起動の場合は案内メッセージを出力して `exit 1` する

新機能向けに追加の CLI ツールや権限が必要な場合は `check_docker()` 内に確認ロジックを追加する。

### 9. install.sh — prepare_docker_image() の対象確認

**対象**: インストール時にビルドが必要な Docker イメージを使う機能

`install.sh` の `prepare_docker_image()` は full プリセット時に `docker/claude-sandbox/` からイメージをビルドする。新機能が別のイメージを必要とする場合:

- `docker/` 配下に対応するイメージ定義ディレクトリを追加する
- `prepare_docker_image()` に追加のビルド処理を追記する
- ビルドはインストール時（`install.sh` 実行時）に行う。スキル実行時の遅延ビルドは採用しない

```bash
# prepare_docker_image() 内への追記パターン
docker build -t "vibecorp/新しいイメージ:dev" \
  "${SCRIPT_DIR}/docker/新しいイメージ" \
  || { echo "エラー: Docker イメージのビルドに失敗しました" >&2; exit 1; }
```

### 10. install.sh — generate_vibecorp_yml() の container セクション確認

**対象**: `vibecorp.yml` に `container:` セクションが必要な機能

full プリセット時、`generate_vibecorp_yml()` は `container:` セクションを生成する。新機能がコンテナ設定を参照する場合:

- `container:` セクションに必要なキーが含まれているか確認する
- スキル側でコンテナ名・イメージ名を参照する場合は `vibecorp.yml` の対応するキーを追加する
- minimal / standard プリセットでは `container:` セクションが存在しないことを前提にスキルを設計する

## まとめ: Docker 依存機能の追加チェックリスト（full プリセット）

| # | 確認事項 | 必須条件 |
|---|---------|---------|
| 8 | `check_docker()` の確認ロジックが新機能の依存を網羅しているか | Docker CLI / デーモンを使う場合 |
| 9 | `prepare_docker_image()` にビルド処理が追加されているか | 新規 Docker イメージを使う場合 |
| 10 | `generate_vibecorp_yml()` の `container:` セクションに必要なキーがあるか | スキルが `vibecorp.yml` のコンテナ設定を参照する場合 |
