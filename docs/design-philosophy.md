# vibecorp 設計思想

> このドキュメントは vibecorp の **設計思想・判断根拠の Source of Truth** です。「なぜそう設計したか」を規定します。
>
> プリセットの機能スコープ・auto 体験射程・SKIP 性マトリクス・非機能要件は [`docs/specification.md`](specification.md) を Source of Truth とし、本ファイルとは役割分担しています。

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

- **C-suite + SM**: CTO, CPO, CFO, CLO, CISO, SM -- MVVに基づいて判断する専門家
- **チーム分析員**: accounting, legal, security -- 3回独立実行し、C-suiteがレビュー

特徴:
- 持続的なアイデンティティがある（「私はCTOです」）
- 自律的に判断し、knowledge に**役割別の構造**で蓄積する（後述「knowledge 三領域構造」参照）
- 他エージェントと権限境界がある（管轄ファイルが異なる）

### knowledge 三領域構造（Issue #442）

`.claude/knowledge/` は責務に応じて 3 つの領域に分離する:

| 領域 | ロール | 構造 | 目的 |
|---|---|---|---|
| C-suite + SM | cto / cpo / cfo / ciso / clo / sm | `{role}/decisions-index.md` + `{role}/decisions/YYYY-QN.md` | 判断記録（四半期集約） |
| 分析員 | accounting / security / legal | `{role}/audit-log/audit-log-index.md` + `{role}/audit-log/YYYY-QN.md` | 監査記録（四半期集約） |
| 揮発データ | `/cycle-metrics` 等 | `~/.cache/vibecorp/state/<repo-id>/cycle-metrics/YYYY-MM-DD.md` | 同日中に消費する一過性データ。git 管理外 |

設計方針:
- **永続データ（判断・監査）は `.claude/knowledge/` 配下** に置き、index + 四半期アーカイブの 2 段構成で肥大化を防ぐ
- **揮発データは XDG_CACHE_HOME 配下** に置き、git 履歴に永続化しない（Issue #335 で CISO の `decisions.md` が肥大化した教訓）
- `.claude/knowledge/{role}/decisions/` および `{role}/audit-log/` への作業ブランチ直書きは **2 層のフック**で deny される（buffer worktree 経由のみ許可、fail-secure）

### fail-secure 多層防御（Issue #448 で確立）

`.claude/knowledge/` の保護は **Edit/Write 層** と **Bash 層** の 2 層で実装する。

| 層 | フック | matcher | 担当 |
|---|---|---|---|
| Edit/Write 層 | `protect-knowledge-direct-writes.sh` | `Edit\|Write\|MultiEdit` | Edit/Write/MultiEdit ツール経由の書込みを deny |
| Bash 層 | `protect-knowledge-bash-writes.sh` | `Bash` | `>`, `>>`, `tee`, `cp`, `mv`, `sed -i`, `awk -i inplace` 等の Bash 経由書込みを deny |

両層で `audit-log/` `decisions/` への直書きを deny し、buffer worktree 経由でのみ許可する。

**設計原則**:
- C*O 6 エージェント（cfo/cto/cpo/ciso/clo/sm）には `Edit, Write, MultiEdit` を tools として宣言し、Edit/Write 経由の書込みを誘導する
- agent 定義の書込みセクションで「Bash redirect 禁止」を明文化する
- それでも Bash redirect を試みた場合は Bash 層で fail-secure deny される
- 共通のパス正規化ヘルパー `lib/path_normalize.sh` を両フックから source して DRY を維持する

**なぜ 2 層必要か**: 当初は Edit/Write 層のみで設計したが、エージェントが Bash redirect を選んだ場合に hook を素通りする経路が判明（Issue #448）。多層防御により agent の tool 選択に依存せず保護を維持する。

### skills 内のステップにするもの

アイデンティティや持続的な知識蓄積が不要なタスク実行:

- **CLI実行型**: CodeRabbit CLI、カスタムレビューコマンド等
- **タスク実行型**: 計画に基づくコード修正
- **判断するがアイデンティティ不要**: レビュー妥当性判定、修正計画策定（共通基準は `.claude/rules/severity/coderabbit.md` / `severity/claude-action.md` / `review-handling.md` / `review-observations.md` に定義）

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

## プラグイン配布方式: Claude Code 公式 Plugin 規約に準拠

vibecorp は Claude Code 公式 Plugin 形式（`.claude-plugin/plugin.json`）でスキルを配布し、`/vibecorp:xxx` 名前空間を持つ。これは [Claude Code 公式 Plugin 仕様](https://docs.claude.com/en/docs/claude-code/plugins) が定める規約パスであり、独自拡張ではない。ビルトインコマンドとの衝突回避、他 Plugin とのスキル分離、バージョン管理の観点で公式が推奨する方式である。

```text
導入先リポジトリ:
├── .claude-plugin/
│   └── plugin.json      ← Plugin メタデータ（スキルはプラグインキャッシュから配信）
├── .claude/
│   ├── hooks/           ← フック（ファイル保護等）
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

- **Claude Code 公式 Plugin 規約に準拠する**
  Phase 1 実機検証（Issue #352）で `/vibecorp:review` 形式の名前空間付きスキルが動作することを確認し、Phase 2（Issue #358）で全 26 スキルを移行した。ビルトインコマンド（`/vibecorp:review`, `/vibecorp:plan`, `/vibecorp:commit` 等）との衝突を解消し、スキルの出自が明確になった

- **互換レイヤの廃止（Phase 3 完了）**
  `.claude/skills/` の互換スタブは Phase 3（#359）で廃止された。`install.sh --update` で既存プロジェクトのスタブが自動クリーンアップされる

- **`$CLAUDE_PROJECT_DIR` の維持（install.sh 配布モデル）**
  install.sh ファイルコピー方式では `$CLAUDE_PROJECT_DIR/.claude/lib/` が正しく解決する。スキルはプラグインキャッシュから配信されるが、lib/ や hooks/ は引き続き install.sh がコピーするため `$CLAUDE_PROJECT_DIR` を維持している

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

## リポジトリ単位配置を選んだ理由

vibecorp は **リポジトリ単位**（`.claude/`）にインストールする。ユーザー設定（`~/.claude/`）への配置はサポートしない。

「ユーザー設定（`~/.claude/`）に導入できないか」という検討を行った結果、本方針を確定した（CPO・CTO の論議による）。将来「user 層に移してはどうか」という問いが再度上がった際に判断根拠を再構成できるよう、ここに記録として残す。

### MVV との対応

| MVV 要素 | リポジトリ単位である理由 |
|---|---|
| Mission「あらゆる**リポジトリ**で再現性のある」 | 再現性の単位 = リポジトリ。user 層だと「このリポを clone した別の人」に再現されない |
| Vision「AIエージェントが**チームメンバー**として機能」 | メンバーの居場所 = チームの作業場 = リポジトリ。user 層だと「個人の AI 助手」に退化する |
| Value 3「**透明性**」 | 判断根拠を PR でチームメイトがレビューできる位置 = リポジトリ。user 層は他人から見えない |
| Value 4「**段階的成長**」 | 成熟の主語はチーム/プロダクト。user 層だと fintech と個人ツールが同じ preset を強制される |

### 代替案（user 設定導入）の却下理由

- **hooks のサイレント失敗**: `protect-files.sh` 等は `vibecorp.yml` 不在で no-op 化し、保護してるつもりで無防備になる
- **knowledge/ の横断混在**: `knowledge/cto/decisions.md` はプロダクト固有の判例集。リポジトリ A の CTO 判断が B に漏れる
- **CI・Branch Protection と切り離される**: `.coderabbit.yaml` / `.github/workflows/` はリポジトリにないと機能しない
- **public-ready 違反**: `.claude/rules/public-ready.md` が「`~/.claude/` 等のユーザーグローバル設定に依存しない」を明文で禁止している
- **Claude Code の規約逸脱**: 公式 Plugin のリポジトリ単位運用方針と衝突する。user 層の独自グローバル配置に依存する設計は採らない

### 「散らかる」違和感への応答

リポジトリに `.claude/` が生成されることへの違和感は正当な UX フィードバックだが、対処は **user 層への移動ではなく、リポジトリ内配置のまま選択肢を提示する** こと:

- `.claude/` を `.gitignore` するかは導入先プロジェクトの判断（前述「`.gitignore` の判断はユーザーに委ねる」参照）
- 複数小規模リポで skills を共有したいニーズは、Claude Code 公式の plugin API 成熟待ち
- 自前で `~/.claude/vibecorp/` を作るのは、user 層の独自グローバル配置に依存しない原則に反する

### 将来の見直し条件

以下のいずれかが成立した場合、本方針を再検討する:

- Claude Code が公式の user-level plugin API を提供し、リポジトリ単位設定とのマージ仕様を定義した
- MVV が「個人ユーザー向け AI 助手」方向に書き換えられた（ファウンダー判断）

## 3つの組織規模プリセット（設計思想観点）

vibecorp は組織規模に応じた 3 段階プリセット（minimal / standard / full）を提供する。本セクションは設計思想観点の要約に絞り、配置されるスキル / フック / エージェントの具体一覧と auto 体験射程・SKIP 性は [`docs/specification.md`](specification.md) を Source of Truth とする（`README.md` には概要テーブルとリンクのみ）。

設計原則:

- **加算モデル**: 上位プリセットは下位プリセットの機能を全て含む（minimal ⊂ standard ⊂ full）。プリセット切り替え時の挙動が予測可能になる
- **課金境界**: minimal / standard は Claude Max 定額内で完結する設計。full のみが ANTHROPIC_API_KEY 従量課金に到達しうる（並列スキル `/vibecorp:ship-parallel` / `/vibecorp:autopilot` を含むため）。詳細は [`docs/cost-analysis.md`](cost-analysis.md)
- **SKIP 不可 hook の存在**: 保護系 / ゲート系 / API バイパス防止系 / ログ系は `vibecorp.yml` の `hooks:` トグルで無効化できない。ユーザーの設定ミスでガードレールが空洞化する経路を塞ぐ。マトリクスは [`docs/specification.md#skip-性マトリクス`](specification.md#skip-性マトリクス) を参照

## 承認フローへの非介入

vibecorp は Claude Code の **承認フロー（permission flow）を書き換えない**。承認に関わる hook（PreToolUse で `permissionDecision: "allow"` を返して承認ダイアログを bypass する hook）は提供しない。

### 方針

- vibecorp は「素の Claude Code の挙動」を Source of Truth とする組織化レイヤ
- 承認フローはセキュリティの最後の砦であり、これを書き換える hook は本体のガードレールを崩す
- 承認負荷の低減は skill/hook レイヤではなく、Claude Code 本体の sandbox + `--dangerously-skip-permissions` 機能で実現する
- minimal / standard プリセットは素の Claude Code の承認体験に従う（都度承認）
- 並列実行は full + sandbox opt-in の組み合わせを推奨する

### 歴史的経緯

過去には `team-auto-approve.sh` という PreToolUse hook を配布していた（Agent Teams が `settings.local.json` の allow リストを継承しないバグ #26479 への回避策）。CEO 合議（2026-04-18）で上記方針が確定したため、本 hook は #336 で完全削除した。既存プロジェクトでは `install.sh --update` 実行で `.claude/hooks/team-auto-approve.sh` と対応する `.claude/settings.json` エントリが自動除去される（orphan hook 削除ロジック）。

### プラン毎の auto 体験射程（設計思想観点）

プラン別の「公式サポート / ユーザー裁量」の表本体は [`docs/specification.md`](specification.md#プリセット) に集約した。設計思想観点として残す要点:

- **責任境界**: 公式サポートは vibecorp が提供するスキル単発実行のみ。`/loop` による定期実行はユーザー裁量領域とし、vibecorp は cron 化を強制しない
- **full + sandbox OFF の自己責任**: full プリセットで sandbox を有効化せず並列実行した場合、「承認ダイアログ多発」または「ユーザーが `.claude/settings.local.json` の allow リストを自己調整」のいずれかとなる。これは下記「承認フローへの非介入」方針との帰結であり、vibecorp は承認体験を書き換えない
- **承認フロー非介入との整合**: auto 体験射程の拡張は「承認 hook を増やすこと」ではなく「sandbox + `--dangerously-skip-permissions` を Claude Code 本体に委ねること」で達成する

### 関連ドキュメント

- `templates/docs/team-permissions.md.tpl` — チームモードでの承認負荷を下げる実用ガイド
- [anthropics/claude-code#26479](https://github.com/anthropics/claude-code/issues/26479) — Agent Teams の allow リスト未継承バグ

## フック設計パターン

### ファイル保護型

- **protect-files.sh**: 保護ファイルの編集をブロック（`protected_files` で設定可能）
- **protect-branch.sh**: メインブランチ（`base_branch`）での Edit/Write/git commit をブロック
- **role-gate.sh**: エージェントの役割に応じたファイル編集権限制御（full のみ）

### ワークフローゲート型

- **review-to-rules-gate.sh**: `gh pr merge` 前に `/vibecorp:review-to-rules` 完了を強制
- **sync-gate.sh**: `git push` 前に `/vibecorp:sync-check` 完了を強制（standard 以上）
- **session-harvest-gate.sh**: `gh pr merge` 前に `/vibecorp:session-harvest` 完了を強制（standard 以上）
- **review-gate.sh**: `gh pr create` 前に `/vibecorp:review` または `/vibecorp:review-loop` 完了を強制（standard 以上）

いずれも `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/{gate名}-ok` 形式のステートファイルで状態管理する（後述「ゲートスタンプの保存先」セクション参照）。ステートは確認後に自動削除される（ワンタイム）。`<repo-id>` は worktree の絶対パスから生成されるため、ブランチ単位で自然に分離される。

### API バイパス防止型

- **block-api-bypass.sh**: `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック。auto-merge 環境ではこれらがレビュープロセスの迂回手段になるため、エージェントの利用を禁止する

### コマンドログ型

- **command-log.sh**: 全 Bash コマンドをログファイル（`~/.cache/vibecorp/state/<repo-id>/command-log`）に記録する。判定は返さない（ログ記録のみ）。`/vibecorp:approve-audit` スキルと組み合わせて `settings.local.json` の allow リスト最適化に使用する。`.claude/` 配下ではなく XDG cache に書き込むのは、Claude Code の書込確認プロンプトを回避するため（#334）

## スキル設計原則

### プリセット自己完結の原則

各プリセットに含まれるスキルは、そのプリセット内で完結しなければならない。
スキルが参照するコマンド・スキルは、同じプリセットに必ず存在すること。

- NG: minimal の `/vibecorp:pr-fix-loop` が standard にしかない `/vibecorp:review-to-rules` を呼ぶ
- OK: minimal の `/vibecorp:pr-fix-loop` が minimal の `/vibecorp:pr-fix` を呼ぶ

### preset 条件分岐型エージェントゲート

プリセット自己完結の原則の例外として、**スキル内で preset を確認し、上位プリセットでのみエージェントを呼び出すパターン**を許容する。

- `/vibecorp:issue` は minimal プリセットに含まれるが、内部で `vibecorp.yml` の preset を確認する
- `standard` または `full` の場合のみ **CISO + CPO + SM の3者承認ゲート**を呼び出す（不可領域フィルタ + プロダクト整合チェック + 自律実行可否判定。`.claude/rules/autonomous-restrictions.md` 参照）
- `minimal`、vibecorp.yml が存在しない、または preset キーが未定義の場合はゲートをスキップして動作する

この設計により、スキル自体は minimal に配置しつつ、上位プリセットでは追加のガードレールが有効になる。
デフォルト（minimal）でも完全に動作するため、プリセット自己完結の原則には反しない。

**責務分離の根拠（Issue #361）**: `/vibecorp:autopilot` / `/vibecorp:ship-parallel` が全 open Issue を自律実行対象とするため、不可領域の門番を起票側（`/vibecorp:issue` と `/vibecorp:diagnose`）に集約する。ship 側は起票済み Issue を信頼して実行する（透過パイプ設計）。minimal では3者フィルタが動作しないが、`/vibecorp:autopilot` が full 専用のため不可領域 Issue が自動実装される経路は存在しない。

**ship の責務範囲（Issue #561）**: `/vibecorp:ship` は「ブランチ作成 → 計画 → レビュー → 実装 → PR → auto-merge → **マージ後の網羅検証**」までを責務範囲とする。マージ後検証は `/vibecorp:pr-fix-loop` が MERGED で正常終了した直後に既存 Claude Code セッション内の LLM 呼び出しのみで完結する（新規ヘッドレス LLM 呼び出しは追加しない、`autonomous-restrictions.md` §3 抵触回避）。詳細は `docs/specification.md` の「ship のマージ後検証」セクションを参照。

### 拡張ポイントの設計

ユーザー設定（vibecorp.yml）による拡張は許容するが、**デフォルトで動作する**ことが前提。
拡張ポイントはデフォルト空で、ユーザーが意図的に追加した場合にのみ動作する。

- `review.custom_commands`: デフォルト空。ユーザーが追加すれば `/vibecorp:review` 内で並列実行される
- スキルは `custom_commands` が空でも CodeRabbit CLI のみで正常に動作する

外部 CI 統合系（`coderabbit` / `claude_action`）は別カテゴリで、デフォルト `enabled: true` を採る。これは拡張ポイント（opt-in）ではなく標準機能（opt-out）として位置づける。`enabled: false` を明示した場合のみ無効化される。`install.sh` の `ensure_claude_action_section` は既存 `vibecorp.yml` に対して未定義キーだけ追加し、利用者がカスタマイズした値を絶対に上書きしない設計（旧バージョンからの安全な移行を担保）。

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

<a id="coderabbit-settings"></a>
### CodeRabbit 設定（`.coderabbit.yaml`）

- `/vibecorp:pr-fix-loop` が前提とする CodeRabbit の挙動を設定する
- `request_changes_workflow: true` — 指摘0件なら approve、指摘ありなら request changes、全コメント resolve 後に approve に切り替え。Branch Protection の「Require approvals」と連動して auto-merge を実現する。`request_changes_workflow` の派生として、CodeRabbit が修正済みと判定したレビューコメントを push 時に自動 resolve するため、`/vibecorp:pr-fix-loop` の「修正した指摘は返信不要」方針も同時に成立する（`auto_resolve` 等の独立キーは公式スキーマに存在しない）
- `language: ja-JP` — レビューコメントを日本語で出力（`vibecorp.yml` の `language` と連動）
- 各設定値が `/vibecorp:pr-fix-loop` のどのステップに対応しているかの詳細は `docs/ai-review-dependency.md` の「CodeRabbit 設定値の根拠（参考）」セクションを参照

### claude-code-action 設定（`vibecorp.yml` の `claude_action`）

- CodeRabbit と並走する AI レビュー経路として claude-code-action を有効化する設定
- `claude_action.enabled` — `true` で有効化。`install.sh` 実行時に `verify_claude_action_secrets` が GitHub secrets の `CLAUDE_CODE_OAUTH_TOKEN` 登録を確認し、未登録なら警告を出す
- `claude_action.skip_paths` — AI レビュー対象から除外するパス。デフォルトで業界標準（`*.lock`、`.git/**`、`node_modules/**`、`dist/**`、`build/**`、`.cache/**`、`vendor/**`）をセット
- 全プリセット（minimal / standard / full）でデフォルト `enabled: true`。CodeRabbit と同様に AI レビューを全プリセットで利用できる思想と整合
- 認証経路・運用ガイドラインの Source of Truth は `docs/ai-review-auth.md`

#### skip_paths は単一入力源、2 出力先に自動反映

`claude_action.skip_paths` は単一の入力源として、生成される 2 つのファイルに `install.sh` が自動反映する:

| 出力先 | 反映方式 |
|---|---|
| `REVIEW.md`（claude-code-action のプロンプト） | `templates/REVIEW.md.tpl` の `{{SKIP_PATHS_BLOCK}}` を `- "<path>"` 形式で置換 |
| `.coderabbit.yaml`（CodeRabbit 設定） | `templates/coderabbit.yaml.tpl` の `{{PATH_FILTERS_BLOCK}}` を `- "!<path>"` 形式（除外指定）で置換 |

これにより利用者は `vibecorp.yml` の `skip_paths` を編集するだけで両方の AI レビュー経路の除外設定が同期し、CodeRabbit と claude-code-action の skip 設定が乖離しない。`REVIEW.md` 自体は claude-code-action のプロンプト用で、判定基準・観点の実体は `.claude/rules/severity/claude-action.md`（severity 5 段階）/ `review-handling.md`（捌き基準）/ `review-observations.md`（観点定義）を Source of Truth として参照させる（`REVIEW.md` は実体ルールを持たない）。

#### REVIEW.md / ai-review.yml の生成方式

- `templates/REVIEW.md.tpl` を方式 2（プレースホルダー置換）で `REVIEW.md` として生成
- `templates/.github/workflows/ai-review.yml` を `generate_ai_review_workflow` で配布
- `templates/.github/workflows/ai-review-golden-test.yml` を `generate_ai_review_golden_test_workflow` で配布（claude-code-action の動作確認用 golden test ワークフロー。`claude_action.enabled` と連動して有効/無効が切り替わる）
- ai-review.yml の `Run Claude Code Action` step が `REVIEW.md` をプロンプトとして読み込み、claude-code-action の `prompt:` に渡す
- 既存ファイルは `merge_or_overwrite` の 3-way マージで利用者カスタマイズを保持、`enabled: false` 時は管理下ファイル（`ai-review.yml`・`ai-review-golden-test.yml`・`REVIEW.md`）と base snapshot を削除して AI レビューを実質無効化
- **0.33.6 互換**: 旧版（〜0.33.6）で `copy_workflows()` 経由で配置された `ai-review.yml` / `ai-review-golden-test.yml` は `vibecorp.lock` に `base_hash` が未登録のため通常の `was_managed` 判定では「管理外残置」となるが、Issue #532 からはテンプレートと SHA256 完全一致なら vibecorp 管理下とみなす遡及ロジックが入っている。ユーザー編集済み（ハッシュ不一致）のファイルは引き続き残置されるため誤削除リスクなし（`generate_ai_review_workflow` / `generate_ai_review_golden_test_workflow` 両関数に実装）

### Branch Protection（GitHub 設定）

GitHub API でしか設定できないため、`install.sh` から `gh api` で自動適用する（権限不足時はフォールバックとして推奨設定を表示）:

- **Require a pull request before merging** — 直接 push を防止
- **Require approvals** (1以上) — CodeRabbit の approve を必須化
- **Dismiss stale pull request approvals when new commits are pushed** — push 後に approve をリセットし、再レビューを強制する。auto-merge との組み合わせで、未レビューのコードがマージされることを防止
- **Required status checks**: `test` — CI 集約ジョブの通過を必須化

### マージ戦略（GitHub 設定）

- **Allow squash merging のみ有効化** — ブランチ単位で1コミットにまとまり、履歴がクリーンに保たれる
- **Allow auto-merge 有効化** — required checks パス + approve 後に自動マージ。`/vibecorp:pr` が `gh pr merge --auto --squash` で設定し、条件達成時に GitHub が自動マージする。`/vibecorp:pr-fix-loop` はレビュー修正に特化し、マージは auto-merge に委ねる

### 設計判断

- **セットで提供する理由**: CI・CodeRabbit・Branch Protection は相互依存している。CI の集約ジョブ名が Branch Protection の required check と一致しなければ永遠に pending になり、CodeRabbit の `request_changes_workflow` が無効なら approve が出ずマージできない。個別に手動設定させると不整合が起きるため、vibecorp がセットで提供する
- **テンプレートとして配布**: `.github/workflows/test.yml` と `.coderabbit.yaml` は `install.sh` でテンプレートから配置する。ユーザーがカスタマイズ可能（skills/hooks と同じ原則）。`.coderabbit.yaml` の配置は `vibecorp.yml` の `coderabbit.enabled`（デフォルト: `true`）で制御され、`false` 時は生成されない
- **GitHub API 設定はベストエフォート**: Branch Protection とマージ戦略は `gh api` で設定するが、権限不足の場合は推奨設定を表示してユーザーに手動設定を促す

## 統合問題は配布先のデフォルト CI で担保する

### 原則

複数 PR の組み合わせで発生する統合問題は、配布先プロジェクトの **デフォルト CI**（型チェック・ビルド・テスト・lint）で機械的に検出する。vibecorp は統合問題対策としての追加 CI / レビュー設定を配布しない。

### vibecorp が統合問題対策の CI / レビュー設定を配布しない理由

1. **配布先依存**: 言語・フレームワーク・ディレクトリ構造はプロジェクトごと。汎用設定は成立しない
2. **責任分担**: vibecorp 配布物の品質は vibecorp 本体 CI で担保。配布先 CI に押し付けない
3. **ユーザーの CI を尊重**: プロジェクト固有の CI 設計に vibecorp 専用ワークフローを混ぜない

### 配布しないもの（統合問題対策として）

- `.coderabbit.yaml` の統合観点拡張 — 配布先のディレクトリ構造依存
- `.semgrep/rules/` — シェルスクリプト中心のプロダクトとミスマッチ、言語依存
- shellcheck CI — `.claude/hooks/*.sh` のみ対象、vibecorp 本体 CI の責任範囲

> 通常の PR レビューを支える `.coderabbit.yaml` は引き続き配布する（[CodeRabbit 設定（`.coderabbit.yaml`）](#coderabbit-settings) を参照）。本セクションが対象とするのは「統合問題を AI レビューで拾う目的の追加配布」であり、それは行わない。

### 配布する例外

- `close-on-feature-merge.yml`: GitHub の default branch 自動 close 仕様の制約を回避するため、vibecorp のエピック運用固有の GHA として配布

例外として配布する基準:

1. GitHub / 外部サービスの仕様的制約を回避する目的に限定される
2. vibecorp のブランチ運用（`feature/epic-*` 等）固有で、配布先のディレクトリ構造に依存しない
3. LLM 非介在（決定論的）

### AI レビューで統合問題を拾わない

1. CodeRabbit は 1 PR 独立評価 — cross-PR 衝突を検出する設計になっていない
2. AI 自己ループは Rubber stamp 問題（AI の指摘を AI が修正する周回は品質検証にならない）
3. AI API 呼び出しは従量課金で vibecorp の Claude Max 定額前提と矛盾
4. 人間（CEO）にレビューを依頼するのは「AI 駆動開発を CEO の意図から自動運転」ミッションに反する

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

## スキル実行時のエラーハンドリング方針

### コマンドリダイレクト・フォールバックの禁止

スキル（SKILL.md）内で Bash コマンドを実行する際、以下のパターンを禁止する:

- `2>/dev/null` — 標準エラー出力のリダイレクト
- `|| echo ""` — エラー時のフォールバック出力
- `; echo ""` — 無条件の後続出力
- `|| true` — 終了コードの握りつぶし

### 根拠

Claude Code のスキル実行アーキテクチャでは、コマンドの**終了コード**と**標準エラー出力**がエラー検知の唯一の手段である。リダイレクトやフォールバックを付加すると以下の問題が発生する:

1. **エラーの隠蔽**: `2>/dev/null` はコマンドが失敗した理由を消し去る。Claude Code はエラー出力を読んで次のアクションを判断するため、エラー情報の欠落は誤った判断に直結する
2. **終了コードの偽装**: `|| echo ""` や `|| true` はコマンド失敗を成功に見せかける。スキルのフロー制御がエラーを検知できなくなり、後続ステップが不正な前提で実行される
3. **デバッグの困難化**: エラーが抑制されると、スキルが期待通りに動かない場合に原因特定が著しく困難になる。エラーメッセージが残っていれば即座に特定できる問題が、沈黙した出力からは判断できない
4. **フック・ゲートの無力化**: `sync-gate.sh` 等のワークフローゲートはコマンドの終了コードで通過/拒否を判断する。終了コードを握りつぶすとゲートが素通りになり、ワークフローの強制が機能しなくなる

### 正しい対処

コマンドがエラーを返した場合、リダイレクトで隠すのではなく:

- エラー出力をそのまま Claude Code に返し、スキルのフロー内で適切に処理する
- 想定されるエラー（ファイルが存在しない等）は事前チェックで回避する
- 回復不能なエラーはスキルを中断してユーザーに報告する

<a id="os-support"></a>

## OS サポート

vibecorp は **macOS / Linux / WSL2 を first-class** としてサポートし、**Windows ネイティブは非対応** とする。`install.sh` 実行時に `uname -s` で OS を判定し、非対応 OS では exit 2 で中断する。

### サポート対象

| OS | サポート状況 | 備考 |
|---|---|---|
| **macOS** (12 Monterey 以降) | ✅ first-class | `sandbox-exec` による隔離レイヤを full プリセットで提供 |
| **Linux** (Ubuntu 22.04+, Fedora 38+, Alpine 3.18+ 等) | ✅ first-class | `bwrap` (bubblewrap) を full プリセットで検出。実隔離は Phase 2 (#310) で対応 |
| **WSL2** (Ubuntu 22.04+ on Windows) | ✅ first-class | Linux 同等の扱い |
| **Windows ネイティブ** | ❌ 非対応 | `install.sh` が `uname -s` で `MINGW*` / `MSYS*` / `CYGWIN*` を検出して exit 2。WSL2 への誘導メッセージを表示 |
| その他 (FreeBSD, OpenBSD 等) | ❌ 非対応 | `install.sh` が exit 2 |

### Windows ネイティブ非対応の根拠

vibecorp は以下の Unix 系ツール・規約に強く依存する設計のため、Windows ネイティブ環境では動作保証できない:

- **POSIX shell スクリプト**: hooks / `install.sh` / templates 配下のスクリプトは `bash` 3.2+ を前提（macOS のデフォルト bash バージョン）。Windows の cmd / PowerShell では動作しない。利用者が対話シェルから `source` する想定のあるライブラリ（`templates/claude/lib/knowledge_buffer.sh` など）は zsh からも `source` できるよう `BASH_VERSION` / `ZSH_VERSION` 判定でパス解決をフォールバックする
- **Unix 標準コマンド**: `uname` / `awk` / `sed` / `grep` / `mktemp` / `find` / `sandbox-exec` / `bwrap` / `git` / `jq` 等を前提
- **隔離レイヤの実装基盤**: macOS `sandbox-exec` は macOS 専用 syscall、Linux `bwrap` は Linux user namespace に依存。Windows ネイティブには同等の軽量サンドボックスが存在しない（Hyper-V / Windows Sandbox は重量級で `install.sh` のフロー外）
- **ファイルシステムのケース感度・パス区切り**: vibecorp の hooks / settings.json は Unix 系の case-sensitive ファイルシステム・`/` 区切りを前提

WSL2 (Ubuntu 22.04+) を使用すれば Windows 上でも完全な Linux 環境で vibecorp を動作させられる。これが Windows ユーザーへの公式な推奨経路である。

### サポート対象 OS の判定ロジック

`install.sh` の `detect_os()` / `check_unsupported_os()` が以下の判定を行う:

1. `uname -s` の出力を `Darwin` / `Linux` / `MINGW*|MSYS*|CYGWIN*` / その他 に分類
2. Windows ネイティブ・その他 OS で exit 2 + WSL2 誘導メッセージ
3. macOS / Linux で `check_isolation_deps()` が full プリセット時に `sandbox-exec` / `bwrap` 存在を検証

将来的に他 OS をサポート対象に追加する場合は、`detect_os()` に分岐を追加し、対応する隔離レイヤ実装（または非対応の明示）を `check_isolation_deps()` に追加する。

## プロセス隔離（Phase 1 PoC）

### PATH シム方式

vibecorp は Claude Code 本体を書き換えず、ユーザーの PATH 先頭に薄いラッパー（`templates/claude/bin/claude`）を配置することでサンドボックスを挟み込む。本体ファイルの侵食がなく、UX や他のコマンドライフサイクルへの影響を最小限に留める。

### opt-in 設計

デフォルトは passthrough。`VIBECORP_ISOLATION=1` を明示した場合のみ sandbox 経由で起動する。Phase 1 PoC 段階のため、意図しない環境で隔離が有効になることを防ぐ。

### 二重サンドボックス防止

`VIBECORP_SANDBOXED=1` 環境変数と PPID チェーン検証の AND 条件で passthrough を判断する。環境変数単独では外部注入によるバイパスが可能なため、祖先プロセスに `sandbox-exec` が存在することをあわせて確認する。

### OS ディスパッチャの抽象化

OS 判定を `vibecorp-sandbox` に閉じ込める。実 sandbox 起動の段階分け:

- **Phase 1（実装済み）**: Darwin で `sandbox-exec` による実隔離が稼働する
- **Phase 1（実装済み）**: Linux で `install.sh` の `check_isolation_deps()` が `bwrap` の存在を検出する。不在時は distro 別インストール手順を表示して exit 1 する（利用者誘導のみ、実隔離は未起動）
- **Phase 2 (#310)**: Linux で `vibecorp-sandbox` が `bwrap` を起動して実隔離を実現する

Phase 1 で「Linux は完全未対応」から「bwrap 存在検出 + 利用者誘導」まで進めた理由は、Phase 2 での実隔離投入時に `bwrap` 不在の Linux ユーザーが install 段階で躓かないようにするため。実際の `bwrap` 経由のサンドボックス起動は Phase 2 以降の拡張余地として確保する。

### 境界パラメータの symlink 解決と 2 段階検証

`WORKTREE` / `HOME` 等の境界パラメータは raw バリデート（絶対パス確認）の後、`(cd "$p" && pwd -P)` で symlink を解決してから再度バリデートする 2 段階検証を行う。macOS の `$TMPDIR` は `/var/folders/...` で `/private/var/...` の symlink であるため、解決前後の混在比較を行うと包含判定が崩れる。

### WORKTREE が HOME を包含する設定の拒否

`WORKTREE=/Users` のような設定は sandbox-exec の `(subpath (param "WORKTREE"))` 経由で `~/.ssh` / `~/.aws` を書込み対象に含めてしまう。canonicalize 後に `case "${HOME_VALUE}/" in "${WORKTREE_VALUE}/"*)` で WORKTREE が HOME を包含するケースを入口で拒否する。

### 境界定義の正典

macOS sandbox-exec プロファイルの許可・拒否境界（書込許可パス・読取許可パス・ioctl 許可デバイス、`literal` / `subpath` の使い分け、network/process 制約等）の詳細は `.claude/sandbox/claude.sb` の全体（ヘッダコメント + SBPL ルール本文）を正として参照すること。本セクションは設計思想の記述であり、個々のパス・ルールを逐次列挙するスコープではない。

## ゲートスタンプ・一時ファイルの保存先

### `.claude/` 外への切り出し

ゲートスタンプおよび実装計画ファイルは XDG Base Directory 仕様に準拠し `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/` 配下に配置する。`.claude/` 配下への書込みは Claude Code の `--dangerously-skip-permissions` でも確認プロンプトが発生するため、スタンプ発行が連続するスキルワークフロー（PR 作成からマージまで最大 4 回）の UX を阻害する。

#### state — ゲートスタンプ

`/vibecorp:sync-check`、`/vibecorp:session-harvest`、`/vibecorp:review-to-rules`、`/vibecorp:review-loop` が発行するゲートスタンプは `~/.cache/vibecorp/state/<repo-id>/` 配下に配置する。

#### plans — 実装計画ファイル

Issue 対応時の実装計画ファイルは `~/.cache/vibecorp/plans/<repo-id>/` 配下に配置する（`{ブランチ名}.md` 形式）。旧来は `.claude/plans/` に配置していたが、同じく `.claude/` 書込確認プロンプトの問題と worktree 分離（worktree ごとに異なる `<repo-id>` を持つ）の両理由から XDG パスへ移行した。

### `<repo-id>` 構成

`<sanitized-basename>-<sha8>` 形式。basename は `git rev-parse --show-toplevel` の basename を `tr -cs 'A-Za-z0-9._-' '_'` でサニタイズ、sha8 は同 toplevel パスの SHA-256 先頭 8 文字。multi-repo 共存時の衝突を回避する。

### sandbox-exec 内動作（VIBECORP_ISOLATION=1）

`~/.cache/vibecorp/` は claude.sb の writable subpath に追加されており、隔離レイヤ内でも gate hook がスタンプを書き込める。親ディレクトリ `~/.cache/` の作成は sandbox 内で拒否されるため、install.sh が起動時に `~/.cache/vibecorp/state/` を pre-create する（`chmod 700` 適用）。

### 脅威モデル

スタンプは存在チェックのみで内容検証を行わない。同一ユーザー内の任意プロセスからの偽造は本設計のスコープ外（信頼境界 = ユーザーアカウント）。ディレクトリは `chmod 700` で他ユーザーからの偽造のみブロックする。HMAC や PID 埋め込みは v1 では採用しない。

### デバッグ手順

スタンプの実体パスを確認するには:

```bash
source .claude/lib/common.sh
vibecorp_stamp_dir
# → /Users/me/.cache/vibecorp/state/vibecorp-a1b2c3d4
```

gate hook 失敗時はこのディレクトリ内の `<name>-ok` ファイル有無で原因を切り分けられる。

## 配布物の Source of Truth 原則

install.sh が配布先 (`REPO_ROOT/.claude/` 等) に書き出すファイルは、以下のいずれかの方式で管理する。新規に配布ファイルを追加するときは下の方式 1 → 2 → 3 の順で検討し、静的内容なら方式 1 を優先する。

### 方式 1: テンプレート配布（推奨 / 静的内容）

静的な内容（ユーザー環境に依存しない）は `templates/` 配下に単一ファイルとして配置し、`merge_or_overwrite` フローで配布する。配置先でカスタマイズされた場合は `vibecorp.lock` の `base_hashes` と `vibecorp-base/` スナップショットを使った 3-way マージで安全に更新する。

- `templates/claude/rules/`, `templates/claude/hooks/`, `templates/claude/agents/`
- `templates/claude/.gitignore.tpl`
- `templates/claude/bin/activate.sh`

**利点**: 差分レビューが可能、上流でのルール変更・削除が consumer へ伝播する、カスタマイズ保持が 3-way merge で自動化される。

### 方式 2: プレースホルダー置換配布（静的テンプレート + 少数の変数置換）

`{{PROJECT_NAME}}` 等のプレースホルダーを持つテンプレートを `sed` で置換して配布する。

- `templates/CLAUDE.md.tpl`, `templates/MVV.md.tpl`, `templates/docs/*.tpl`

**利点**: 方式 1 の拡張。変数注入点が明示的でレビューしやすい。

### 方式 3: heredoc 生成（動的内容限定）

以下のいずれかに該当する場合のみ `install.sh` 内の heredoc による直接生成を許容する。

- **自動生成マーカーを持つファイル**: `vibecorp.lock`（ハッシュ・commit SHA・タイムスタンプを含み、内容がインストール毎に変わる）
- **プリセット別に構造が分岐する設定ファイル**: `vibecorp.yml`（`generate_plan_yaml_section` 等の内部関数呼び出しを含み、プリセットにより出力行数・キーが変わる）

これら以外の静的または準静的な内容は、方式 1 または 2 で配布する。heredoc に静的内容を埋め込むと:

- `templates/` に source ファイルがないため差分レビューが shell 関数の diff になる
- 上流で不要になったエントリを削除しても consumer に残り続ける
- `merge_or_overwrite` / `save_base_snapshot` の 3-way merge フローから外れ、カスタマイズ保持が壊れる

という構造的欠陥を抱える（#366 参照）。

### 新規追加時の判断フロー

1. 配布対象がユーザー環境に依存しない静的内容か → **方式 1**
2. 数個の変数置換のみで完結するか → **方式 2**
3. 自動生成マーカーまたはプリセット別分岐を持つ動的内容か → **方式 3**
4. 判断に迷う場合は **方式 1** を優先する（最も退行検出しやすいため）

## ガードレール

- **Public Ready**: セキュリティ情報・特定プロダクト名・ローカルパス依存の混入禁止
- **品質基準**: 参照元の実装を全網羅し、品質・汎用性・堅牢性で上回る
- **テスト必須**: hooks / install.sh は自動テスト付き。テストなしで push しない
- **Source of Truth**: 配布物は静的内容なら `templates/` 配下のファイルを唯一のソースとする。heredoc による直接生成は動的内容限定（上記「配布物の Source of Truth 原則」参照）
