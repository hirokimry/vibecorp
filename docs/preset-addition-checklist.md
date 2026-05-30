# ✅ プリセット引き算方式 — 新規フック / スキル追加時チェックリスト

> [!IMPORTANT]
> 読者像はフック・スキルを追加する開発者（コントリビューター）。
> プリセット別の引き算ロジックを更新し忘れないためのチェックリスト。
> **全 7 ステップを確認するまで PR を出さない**。

## 🎯 前提知識

vibecorp はプリセット（minimal / standard / full）で機能を段階的に提供する。

引き算方式の構造を以下に整理する。

- 🧱 テンプレートには **全機能（full 相当）** を収録する。
- ✂️ 低プリセットでは不要なファイルを **削除（引き算）** する。

```text
full = テンプレート全体（何も削除しない）
standard = full − (full 専用のフック / スキル)
minimal = standard − (standard 専用のフック / スキル)
```

## 🪜 チェックリスト

新しいフックまたはスキルを追加するとき、以下の **全ステップ** を確認する。

### 1️⃣ install.sh — プリセット別削除（case 文）

📍 ファイル: `install.sh` L633–656 付近。

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

#### 🎯 判断基準

- ➡️ minimal 専用で削除するもの → `minimal)` ブロックに追加。
- ➡️ standard でも削除するもの → `minimal)` と `standard)` の両方に追加。
- ➡️ full 専用で削除するものは通常ない。
  - もし必要なら `full)` ブロックを新設する。

> [!NOTE]
> `minimal)` ブロックには standard で削除するものも含める。
> minimal は standard のサブセットだから。

#### 🚨 full プリセット専用スキル / フック追加時の必須対応

`/vibecorp:autopilot`、`/vibecorp:ship-parallel` のように full 限定のスキルを追加した場合の対応。

- ✅ MUST: `minimal)` と `standard)` の両方に `rm -rf "${skills_dir}/<スキル名>"` を追加する。
- 🛡️ SKILL.md 内のソフトガード（preset 判定ロジック）だけに頼らない。
  - install.sh で物理削除することがハード制限の本筋。
  - 隔離レイヤが full でしか効かないため。
  - minimal / standard で誤爆させないため。

### 2️⃣ install.sh — settings.json フィルタ（jq）

📍 ファイル: `install.sh` L1007–1026 付近。

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

#### 🎯 判断基準

- ➡️ ステップ 1 と同じプリセット区分に合わせる。
- ➡️ hooks/hooks.json にフックを登録した場合は必須。

### 3️⃣ install.sh — knowledge コピー制御

📍 ファイル: `install.sh` L1239–1242 付近。

新しいエージェントロールに紐づく knowledge ディレクトリがある場合の対応。

- ✅ `templates/claude/knowledge/` 配下にディレクトリを作成する。
- ✅ minimal では自動的にスキップされる（既存ロジック）。
- ⚙️ standard / full 固有の knowledge がある場合は個別制御を追加する。

### 4️⃣ hooks/hooks.json — フックエントリ追加

📍 ファイル: `hooks/hooks.json`（plugin native 配布の唯一の登録元、#716/#720/#759）。

> [!NOTE]
> フックは settings.json には登録しない（#759 で settings.json は単一 SSOT 化され hooks ブロックを持たない）。登録は plugin マニフェスト経由の `hooks/hooks.json` に一元化されている。

新しいフックを追加する場合の手順を以下に整理する。

1. 適切な `matcher`（`Edit|Write|MultiEdit`、`Bash` 等）のブロックに hook エントリを追加する。
2. `command` パスを plugin native 形式で記述する。
   - 形式: `${CLAUDE_PLUGIN_ROOT}/hooks/新しいフック.sh`。
3. 必要に応じて `timeout` を設定する。

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/新しいフック.sh"
}
```

### 5️⃣ ドキュメント更新（README.md と docs/specification.md）

#### 5-1️⃣ `docs/specification.md` — Source of Truth の更新

📍 位置: `## 機能仕様` セクション内の以下サブセクション。

| 何を更新するか | 場所（セクション見出しベース） |
|---|---|
| スキル詳細テーブル | `### スキル一覧（Source of Truth）` 配下のプリセット別サブセクション |
| フック詳細テーブル | `### フック一覧（Source of Truth）` 配下の系統別サブセクション |
| ゲートフック対応表 | `### ゲートフックとスタンプ` |
| `settings.json` フックエントリ | `### フック登録構造（settings.json）` のコードブロック |

> [!NOTE]
> 行番号ではなく **セクション見出し** で参照する。
> `docs/specification.md` の構成変更により行番号は容易に腐敗する。

#### 5-2️⃣ `README.md` — 概要テーブルとリンクの更新

📍 位置: `## 🎁 プリセット` セクション内の以下テーブル。

| 何を更新するか | 場所（セクション見出しベース） |
|---|---|
| プリセット概要テーブル | `## 🎁 プリセット` 直下の比較テーブル |
| auto 体験射程テーブル | `### auto 体験射程` 配下のテーブル |
| スキル概要 | `## 🛠️ スキル一覧（概要）` 配下のプリセット別サブセクション |
| フック概要 | `## 🪝 フック概要` 配下の系統別テーブル |

> [!IMPORTANT]
> `README.md` には**詳細を載せない**。
> 新規スキル / フックの詳細仕様は必ず `docs/specification.md` を更新する。
> README には簡略版を記載し、SoT 重複を作らない。

### 6️⃣ テスト追加

📍 ファイル: `tests/test_新しいフック.sh`（新規作成）。

テスト要件を以下に整理する。

- ✅ フックの場合は `tests/` 配下に `test_新しいフック.sh` を作成する。
- ✅ 既存テストのパターン（`tests/test_*.sh`）に従う。
- ✅ 正常系・異常系・バイパス耐性をテストする。
- ✅ 既存テストが壊れていないことを確認する。

### 7️⃣ templates/ — テンプレートファイル配置

新しいフック / スキルのテンプレートファイルを所定の場所に配置する。

| 種別 | 配置先 |
|---|---|
| フック | `templates/claude/hooks/新しいフック.sh` |
| スキル | `skills/新しいスキル/SKILL.md` |
| エージェント | `agents/新しいエージェント.md` |
| knowledge | `templates/claude/knowledge/新しいロール/` |

## 📋 まとめ: 更新箇所の早見表

| # | ファイル | 更新内容 | 必須条件 |
|---|---|---|---|
| 1 | `install.sh`（case 文） | rm 行を追加 | フック / スキルが全プリセット対象でない場合 |
| 2 | `install.sh`（case 文の preset 別 rm） | rm 行を追加 | フックが全プリセット対象でない場合 |
| 3 | `install.sh`（knowledge） | コピー制御を追加 | 新エージェントに knowledge がある場合 |
| 4 | `hooks/hooks.json` | フックエントリを追加 | フックの場合 |
| 5a | `docs/specification.md` | スキル / フック詳細テーブル（SoT）を更新 | 常に必須 |
| 5b | `README.md` | プリセット概要テーブル + 概要セクションを更新 | 常に必須 |
| 6 | `tests/test_*.sh` | テストケースを追加 | 常に必須 |
| 7 | `templates/` | テンプレートファイルを配置 | 常に必須 |
