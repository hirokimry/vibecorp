# vibecorp 設計思想

## vibecorp とは

vibecorp は「AIエージェントを組織化してプロダクト開発を回す」仕組みをプラグインとして提供する。
バイブコーディング時代の AI企業キット。どのリポジトリにも導入できる。

## 3層アーキテクチャ

```text
MVV.md（最上位方針・ファウンダーのみ編集）
  ↓ 全エージェント・スキルの判断基準
docs/（Source of Truth・仕様書群）
  ↓ エージェントが参照・更新する設計情報
.claude/（実行層）
  ├── agents/    ← Role Agents のみ（判断 + knowledge蓄積する者）
  ├── skills/    ← ワークフロー定義（内部でAgent起動しモデル/ツール制御）
  ├── hooks/     ← ゲート制御（ファイル保護 + ワークフロー強制）
  ├── knowledge/ ← 役割別の判断基準・判断記録（運用中に蓄積）
  ├── rules/     ← 全エージェント共通のコーディング規約
  └── settings.json ← フック設定
```

## agents vs skills の設計原則

### agents に定義するもの（Role Agents）

持続的アイデンティティ + 自律判断 + knowledge蓄積を持つエンティティ:

- **C-suite**: CTO, CPO, COO, CFO, CLO, CISO -- MVVに基づいて判断する専門家
- **チーム分析員**: accounting, legal, security -- 3回独立実行し、C-suiteがレビュー

特徴:
- 持続的なアイデンティティがある（「私はCTOです」）
- 自律的に判断し、`knowledge/{role}/decisions.md` に蓄積する
- 他エージェントと権限境界がある（管轄ファイルが異なる）

### skills 内のステップにするもの

アイデンティティや持続的な知識蓄積が不要なタスク実行:

- **CLI実行型**: CodeRabbit CLI、カスタムレビューコマンド等
- **タスク実行型**: 計画に基づくコード修正
- **判断するがアイデンティティ不要**: レビュー妥当性判定、修正計画策定（共通基準は `.claude/rules/review-criteria.md` に定義）

いずれもスキル内のステップとして直接実行する。

### 判断フローチャート

```text
そのエンティティは...

1. 持続的なアイデンティティがある？（「私はCTOです」）
   → No → スキル内のステップ
   → Yes ↓

2. 自律的に判断し、knowledge に蓄積する？
   → No → スキル内のステップ（Agent起動時に model/tools を指定）
   → Yes ↓

3. 他エージェントと権限境界がある？
   → Yes → agents/ に定義する
```

## プラグイン配布方式: Claude Code 規約パスへの直接配置

```text
導入先リポジトリ:
├── .claude/
│   ├── hooks/           ← フック（ファイル保護等）
│   ├── skills/          ← スキル（Claude Code の /コマンド）
│   ├── rules/           ← コーディング規約
│   ├── vibecorp.yml     ← プロジェクト設定
│   ├── vibecorp.lock    ← バージョン固定 + マニフェスト
│   ├── settings.json    ← フック設定（マージ管理）
│   └── CLAUDE.md        ← プロジェクト指示
├── .github/
│   └── workflows/
│       └── test.yml     ← CI ワークフロー
├── .coderabbit.yaml     ← CodeRabbit 設定
└── MVV.md               ← 最上位方針
```

設計上の重要な判断:

- **独自名前空間を持たない**
  `.claude/vibecorp/` のような独自ディレクトリは作らない。全ファイルを Claude Code の規約パス（`.claude/hooks/`, `.claude/skills/`, `.claude/rules/`）に直接配置する。Claude Code が認識しないパスにファイルを置くことは、プラグインとして意味がない

- **lock をマニフェストとして使う**
  `vibecorp.lock` に vibecorp が管理するファイルの一覧を記録する。lock に載っている = vibecorp 管理、載っていない = ユーザー作成。更新時は lock を参照して vibecorp 管理ファイルのみ差し替える

- **.gitignore の判断はユーザーに委ねる**
  vibecorp は `.gitignore` を操作しない。`.claude` を gitignore するか git 管理するかは導入先プロジェクトの判断。生成物を一括 gitignore する案（node_modules パターン）は却下した。vibecorp の生成物は rules, skills, CLAUDE.md 等のチームがレビュー・カスタマイズする人間可読な設定であり、node_modules のような第三者コードとは性質が異なる。PR でのレビューを可能にするため、git 管理を推奨する

- **settings.json はマージ管理**
  vibecorp 由来フック（パスに `.claude/hooks/` を含む）のみ操作し、ユーザー独自フックは保持

- **Public 前提**
  vibecorp リポジトリ自体はテンプレートのみで実データを含まない公開前提の設計

### 生成物をフックで保護しない理由

vibecorp が生成した skills, rules, hooks を protect-files フックで保護する案は却下した。

- **生成物はユーザーのもの**
  プラグインが生成したファイルであっても、ユーザーが自由に編集できるべき。npm が `node_modules/` を保護しないのと同じ原則
- **復元は再実行で可能**
  ユーザーが誤って壊しても `install.sh` を再実行すれば元に戻る
- **保護はビジネスルールに限定**
  protect-files が守るのは MVV.md のような「ファウンダーの方針」であり、「vibecorp が生成したから」という理由でファイルを保護するのはプラグインの越権行為

## 3つの組織規模プリセット

| プリセット | agents | hooks | ユースケース |
|---|---|---|---|
| **minimal** | なし | protect-files | 個人〜小規模 |
| **standard** | CTO, CPO | + review-to-rules-gate, sync-gate, review-gate | チーム開発 |
| **full** | C-suite全員 + 分析員 | + role-gate | AI企業・コンプライアンス重視 |

各プリセットに含まれるスキル:

- **minimal**: /review, /review-loop, /pr-review-loop, /pr, /commit, /issue, /ship, /plan, /branch, /plan-review-loop
- **standard**: 上記 + /review-to-rules, /sync-check, /sync-edit, /session-harvest, /harvest-all
- **full**: 上記（スキル追加なし）

## フック設計パターン

### ファイル保護型

- **protect-files.sh**: 保護ファイルの編集をブロック（`protected_files` で設定可能）
- **role-gate.sh**: エージェントの役割に応じたファイル編集権限制御（full のみ）

### ワークフローゲート型

- **review-to-rules-gate.sh**: `gh pr merge` 前に `/review-to-rules` 完了を強制
- **sync-gate.sh**: `git push` 前に `/sync-check` 完了を強制（standard 以上）
- **session-harvest-gate.sh**: `gh pr merge` 前に `/session-harvest` 完了を強制（standard 以上）
- **review-gate.sh**: `gh pr create` 前に `/review` または `/review-loop` 完了を強制（standard 以上）

いずれもスタンプファイル（`/tmp/.{project}-*`）で状態管理。スタンプは確認後に自動削除される（ワンタイム）。

### API バイパス防止型

- **block-api-bypass.sh**: `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック。auto-merge 環境ではこれらがレビュープロセスの迂回手段になるため、エージェントの利用を禁止する

## スキル設計原則

### プリセット自己完結の原則

各プリセットに含まれるスキルは、そのプリセット内で完結しなければならない。
スキルが参照するコマンド・スキルは、同じプリセットに必ず存在すること。

- NG: minimal の `/pr-review-loop` が standard にしかない `/review-to-rules` を呼ぶ
- OK: minimal の `/pr-review-loop` が minimal の `/review` を呼ぶ

### 拡張ポイントの設計

ユーザー設定（vibecorp.yml）による拡張は許容するが、**デフォルトで動作する**ことが前提。
拡張ポイントはデフォルト空で、ユーザーが意図的に追加した場合にのみ動作する。

- `review.custom_commands`: デフォルト空。ユーザーが追加すれば `/review` 内で並列実行される
- スキルは `custom_commands` が空でも CodeRabbit CLI のみで正常に動作する

### スキル・フックのトグル設定

プリセットで配置された skills / hooks は、`vibecorp.yml` の `skills:` / `hooks:` セクションで個別に有効/無効を切り替えられる。

```yaml
skills:
  commit: true
  review-to-rules: false
hooks:
  protect-files: true
  sync-gate: false
```

設計原則:

- **opt-out 方式**: キーを省略した場合は有効扱い。明示的に `false` を指定した場合のみ無効化される
- **プリセット削除が先**: プリセットによるファイル選択が先に適用され、その後トグルでさらに絞る
- **インストール時に反映**: `install.sh` 実行時（初回・`--update` 両方）にトグル設定を評価し、無効化されたファイルはコピー対象から除外・削除される
- **settings.json にも反映**: 無効化された hooks は `settings.json` の hooks エントリからも除外される

## リポジトリインフラ設定

vibecorp は Claude Code の実行層だけでなく、開発ワークフロー全体を支えるリポジトリインフラ設定もテンプレートとして提供する。
スキルやフックが正しく機能するには、CI・レビュー・ブランチ保護が連動している必要があるため、これらをセットで提供する。

### CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を自動実行する CI ワークフローを提供する
- matrix ジョブ（macOS / Ubuntu）の結果を `test` ジョブに集約し、Branch Protection の required check として機能させる
- `push` + `pull_request` の両方でトリガーし、`concurrency` グループで同一ブランチの重複実行を防止する

### CodeRabbit 設定（`.coderabbit.yaml`）

- `/pr-review-loop` が前提とする CodeRabbit の挙動を設定する
- `request_changes_workflow: true` — 指摘0件なら approve、指摘ありなら request changes、全コメント resolve 後に approve に切り替え。Branch Protection の「Require approvals」と連動して auto-merge を実現する
- `auto_resolve: true` — push 時に修正済みのレビューコメントを自動 resolve する。`/pr-review-loop` の「修正した指摘は返信不要」方針の前提
- `language: ja-JP` — レビューコメントを日本語で出力（`vibecorp.yml` の `language` と連動）

### Branch Protection（GitHub 設定）

GitHub API でしか設定できないため、`install.sh` から `gh api` で自動適用する（権限不足時はフォールバックとして推奨設定を表示）:

- **Require a pull request before merging** — 直接 push を防止
- **Require approvals** (1以上) — CodeRabbit の approve を必須化
- **Dismiss stale pull request approvals when new commits are pushed** — push 後に approve をリセットし、再レビューを強制する。auto-merge との組み合わせで、未レビューのコードがマージされることを防止
- **Required status checks**: `test` — CI 集約ジョブの通過を必須化

### マージ戦略（GitHub 設定）

- **Allow squash merging のみ有効化** — ブランチ単位で1コミットにまとまり、履歴がクリーンに保たれる
- **Allow auto-merge 有効化** — required checks パス + approve 後に自動マージ。`/pr` が `gh pr merge --auto --squash` で設定し、条件達成時に GitHub が自動マージする。`/pr-review-loop` はレビュー修正に特化し、マージは auto-merge に委ねる

### 設計判断

- **セットで提供する理由**: CI・CodeRabbit・Branch Protection は相互依存している。CI の集約ジョブ名が Branch Protection の required check と一致しなければ永遠に pending になり、CodeRabbit の `request_changes_workflow` が無効なら approve が出ずマージできない。個別に手動設定させると不整合が起きるため、vibecorp がセットで提供する
- **テンプレートとして配布**: `.github/workflows/test.yml` と `.coderabbit.yaml` は `install.sh` でテンプレートから配置する。ユーザーがカスタマイズ可能（skills/hooks と同じ原則）。`.coderabbit.yaml` の配置は `vibecorp.yml` の `coderabbit.enabled`（デフォルト: `true`）で制御され、`false` 時は生成されない
- **GitHub API 設定はベストエフォート**: Branch Protection とマージ戦略は `gh api` で設定するが、権限不足の場合は推奨設定を表示してユーザーに手動設定を促す

## --update モードの設計判断

`install.sh --update` は「vibecorp 管理ファイルの差し替え」と「ユーザー作成ファイルの保護」を両立する。

### ファイル削除の非対称性

- **hooks / skills / agents**: lock 記載の管理ファイルを削除し、テンプレートから再配置する
- **knowledge**: 運用中にユーザー（エージェント）が蓄積したデータのため、`--update` でも削除しない
- **rules**: `--update` 時はテンプレート由来の rules を上書きする。ユーザーが独自に追加した rules（テンプレートに存在しないファイル名）は影響しない
- **docs**: ユーザーが内容をカスタマイズ済みの前提で、既存ファイルはスキップする

### Branch Protection の既存設定との共存

`install.sh` は Branch Protection の required status checks を設定する際、既存の checks を破壊しない:

1. 既存の required status checks を GitHub API で取得する
2. vibecorp が必要とする checks（`test`, 任意で `CodeRabbit`）と UNION をとる
3. 重複を排除してソートした結果を PUT する
4. 既存の checks 取得に失敗した場合（権限不足等）は上書きリスクを避けるため自動設定をスキップし、手動設定のガイダンスを表示する

### vibecorp.lock のセクション構造

lock はインストール時に配置されたファイルの完全なマニフェストを記録する:

```yaml
files:
  hooks:       # テンプレート由来かつ配置先に存在するもの
  skills:      # 同上
  agents:      # 同上
  rules:       # コピー時に実際にコピーされたもの（既存スキップ分は含まない）
  issue_templates:  # 同上
  docs:        # 同上
  knowledge:   # 同上
```

「テンプレートに存在し、かつプリセット削除後も配置先に残っているもの」のみ記録される。これにより `--update` 時に vibecorp 管理ファイルだけを正確に差し替えできる。

## ガードレール

- **Public Ready**: セキュリティ情報・特定プロダクト名・ローカルパス依存の混入禁止
- **品質基準**: 参照元の実装を全網羅し、品質・汎用性・堅牢性で上回る
- **テスト必須**: hooks / install.sh は自動テスト付き。テストなしで push しない
