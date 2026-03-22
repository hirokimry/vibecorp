# 実装計画: #53 CodeRabbit 未使用環境でのスキル動作対応

## 概要

vibecorp のスキル群が CodeRabbit 未導入環境でも正常に動作するよう、`vibecorp.yml` に `coderabbit.enabled` 設定を追加し、各スキル・install.sh・hooks を分岐対応する。

## 影響範囲

### 設定ファイル
- `.claude/vibecorp.yml` — `coderabbit` セクション追加
- `install.sh` — 設定に基づく `.coderabbit.yaml` 生成制御

### スキル（テンプレート含む）
- `.claude/skills/pr-review-loop/SKILL.md` — CodeRabbit OFF 時のフロー分岐
- `.claude/skills/review/SKILL.md` — CodeRabbit OFF 時のスキップ明示
- `.claude/skills/ship/SKILL.md` — ステップ9 の説明文修正
- `.claude/skills/review-to-rules/SKILL.md` — 変更不要（既に人間レビュアーのみで動作可能）
- `templates/claude/skills/` 配下の対応テンプレート

### Hooks
- `.claude/hooks/block-api-bypass.sh` — CodeRabbit OFF 時は `@coderabbitai approve` ブロック不要（ただし残しても無害なので変更不要）

### テスト
- `tests/test_install.sh` — CodeRabbit OFF 時のテスト追加
- `tests/test_hooks.sh` — 変更不要

### ドキュメント
- `docs/coderabbit-dependency.md` — 設定方法の追記

## Phase 分け

### Phase 1: vibecorp.yml への設定キー追加と読み取りユーティリティ

**タスク:**
1. `vibecorp.yml` のデフォルトテンプレート（`install.sh` の `generate_vibecorp_yml()`）に `coderabbit.enabled` を追加（デフォルト: `true`）
2. スキルが `vibecorp.yml` から `coderabbit.enabled` を読み取る共通パターンを定義

**判定ロジック（スキル内で使用）:**

```bash
# vibecorp.yml から coderabbit.enabled を読み取る
awk '/^coderabbit:/{found=1; next} found && /^[^ ]/{exit} found && /enabled:/{print $2}' \
  "$CLAUDE_PROJECT_DIR"/.claude/vibecorp.yml
```

スキルはシェルスクリプトではなく SKILL.md（マークダウン）なので、スキル内に「vibecorp.yml の `coderabbit.enabled` を確認せよ」という指示を記述する形になる。

**テスト:**
- `vibecorp.yml` に `coderabbit` セクションがある場合の値読み取り確認
- `coderabbit` セクションがない場合のデフォルト値（`true`）確認

### Phase 2: install.sh の分岐対応

**タスク:**
1. `generate_coderabbit_yaml()` を `coderabbit.enabled` の値で分岐
   - `true`（デフォルト）: 従来通り `.coderabbit.yaml` を生成
   - `false`: `.coderabbit.yaml` を生成しない + ログ出力
2. `resolve_github_checks()` は既に `.coderabbit.yaml` ファイル存在で分岐しているため変更不要
3. `generate_vibecorp_yml()` でデフォルトテンプレートに `coderabbit` セクションを含めるかの判断
   - standard プリセットでは含めない（デフォルト `true` なのでキー省略＝有効）
   - ユーザーが明示的に `false` にしたい場合に手動追加する運用

**テスト（`tests/test_install.sh` に追加）:**
- `test_coderabbit_disabled_skips_yaml`: `vibecorp.yml` に `coderabbit:\n  enabled: false` を事前配置 → install.sh 実行 → `.coderabbit.yaml` が生成されないこと
- `test_coderabbit_default_generates_yaml`: `coderabbit` キーなし → 従来通り `.coderabbit.yaml` が生成されること
- `test_coderabbit_disabled_no_required_check`: `coderabbit.enabled: false` → Branch Protection の required checks に `CodeRabbit` が含まれないこと

### Phase 3: スキルの CodeRabbit OFF 対応

**タスク:**

#### 3-1. `/pr-review-loop` SKILL.md

現在のフローは CodeRabbit コメントを5分ポーリングし、0件なら「未導入」と判断してスキップする。
これを `vibecorp.yml` の設定で **即時判定** に変更:

- ステップ 2.1 の冒頭に判定を追加:
  - `coderabbit.enabled: false` → ポーリングをスキップし、ステップ3（auto-merge確認）へ直接進む
  - `coderabbit.enabled: true`（デフォルト）→ 従来通りポーリング

これにより、CodeRabbit OFF 環境で無駄な5分待ちが解消される。

- ステップ 2.3 の GraphQL クエリも CodeRabbit OFF 時はスキップ

#### 3-2. `/review` SKILL.md

- セクション「CodeRabbit CLI（常に実行）」を条件付きに変更:
  - `coderabbit.enabled: false` → CodeRabbit CLI セクション全体をスキップ
  - `coderabbit.enabled: true` → 従来通り（`cr` コマンド不可時のスキップも維持）

#### 3-3. `/ship` SKILL.md

- ステップ9 の説明を修正:
  - `coderabbit.enabled: false` の場合、`/pr-review-loop` が CodeRabbit レビューをスキップする旨を記載

#### 3-4. テンプレート同期

- `templates/claude/skills/pr-review-loop/SKILL.md` を同期
- `templates/claude/skills/review/SKILL.md` を同期
- `templates/claude/skills/ship/SKILL.md` を同期

**テスト:**
- スキルはマークダウンのため自動テストの対象外。手動確認項目として記載

### Phase 4: ドキュメント更新

**タスク:**
1. `docs/coderabbit-dependency.md` に設定方法セクションを追加
   - `vibecorp.yml` での `coderabbit.enabled: false` の設定方法
   - 各スキルの OFF 時挙動（既存テーブルの更新）
2. `install.sh` の挙動セクションを更新

**テスト:**
- ドキュメントの整合性確認（コードと矛盾がないか）

## 懸念事項

1. **CodeRabbit CLI のみ使用するケース**: Issue で検討事項に挙がっている「SaaS 未課金だが CLI は無料」のケースは、`coderabbit.enabled` の1フラグでは区別できない。ただし、現時点では CLI のみのユーザーは `enabled: true` のまま `cr` コマンドをインストールすれば動作するため、1フラグで十分と判断する。
2. **既存インストール済み環境への影響**: `coderabbit` キーが `vibecorp.yml` にない場合はデフォルト `true` として扱うため、後方互換性は維持される。
3. **`@coderabbitai approve` ブロック hook**: CodeRabbit OFF でもこの hook は無害（マッチするコメントを投稿すること自体がない）なので、分岐不要。
