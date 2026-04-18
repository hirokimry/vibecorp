# CTO 判断記録

技術的な判断とその根拠を記録する。CTO エージェントがレビュー時に追記する。

## 記録フォーマット

```markdown
### YYYY-MM-DD: 判断タイトル

- **判断**: 何をどう判断したか
- **根拠**: なぜそう判断したか（MVV・原則のどれに基づくか）
- **代替案**: 検討した他の選択肢（あれば）
```

## 判断ログ

<!-- CTO エージェントが以下に追記していく -->

### 2026-03-22: settings.json マージ時に unique_by(.command) でフック重複を排除

- **判断**: install.sh の settings.json マージ処理において、`unique_by(.command)` を用いてフックエントリの重複を排除する
- **根拠**: lock 未登録フックとテンプレートの衝突により、同一コマンドのエントリが重複して生成されるケースがあった。冪等性を確保し、繰り返し実行しても同じ結果になるよう設計する必要があった
- **代替案**: マージ前に既存エントリを削除してから追加する方式も検討したが、既存設定を破壊するリスクがあるため採用しなかった

### 2026-03-22: templates/settings.json.tpl からレガシーパス .claude/vibecorp/hooks/sync-gate.sh を削除

- **判断**: `templates/settings.json.tpl` に残存していた旧パス `.claude/vibecorp/hooks/sync-gate.sh` のエントリを削除する
- **根拠**: 旧名前空間 `.claude/vibecorp/` は廃止済みであり、実際にはパスが存在しない状態だった。存在しないパスをテンプレートに残すことは誤解を招くため、廃止完了に合わせてテンプレートからも除去した
- **代替案**: コメントアウトして残す案もあったが、廃止済みのエントリを残すことで混乱を招くため完全削除を選択した
### 2026-03-29: skills / hooks のトグル設定を opt-out 方式で実装（Issue #61）

- **判断**: `vibecorp.yml` の `skills:` / `hooks:` セクションで個別の有効/無効を切り替えられるようにする。省略時は有効、明示的に `false` のみ無効化（opt-out 方式）
- **根拠**: プリセットはチームの成熟度に合わせた一括設定だが、特定の hooks/skills だけ不要というケースが生じる。フルカスタマイズよりも「デフォルト有効、必要なものを外す」方が MVV の「導入の手軽さ」に合致する。opt-in 方式（省略時は無効）だと既存ユーザーへの破壊的変更になるため採用しなかった
- **代替案**: プリセットを細かく増やして対応する案も検討したが、プリセット数が増えると選択の迷いが生まれ「設定の迷いをなくす」というバリューに反するため却下した

### 2026-04-02: protect-branch.sh — メインブランチ保護フックの追加

- **判断**: 全プリセット（minimal/standard/full）に `protect-branch.sh` を追加し、`base_branch` 上での Edit/Write/git commit を PreToolUse でブロックする
- **根拠**: AIエージェントはブランチ分岐を確認せずメインブランチに直接コミットする誤操作を起こしやすい。「規律の自動化 — レビュー・保護・ルールをフックとスキルで強制する。人の意志力に頼らない」というバリューに基づき、フックで強制する
- **代替案**: settings.json のグローバル設定として Branch Protection で防ぐ案もあるが、それは GitHub 側の設定であり、ローカル作業中の誤 commit をリアルタイムに止められない。フックによる早期検出が適切

### 2026-04-02: command-log.sh — コマンドログ型フックを新分類として追加（Issue #216）

- **判断**: `command-log.sh` を「判定を返さない純粋なオブザーバブルフック」として新分類し、minimal 以上の全プリセットに含める
- **根拠**: ゲート系フックは permit/deny の判定を返すが、ログ記録はそれと直交する関心事であり、別分類として扱うことで設計の明確さを保てる。minimal 以上に含める根拠は、コマンド履歴の可視化が MVV「透明性 — 全ての判断根拠をルール・設定ファイルとして可視化する」に直接対応するため、プリセット段階を問わず必要な機能と判断した
- **代替案**: ゲート系フックに副作用としてログ処理を組み込む案も検討したが、責務が混在し保守性が下がるため却下した

### 2026-04-03: pr-review-loop の終了条件見直し提案の評価

- **判断**: ユーザー提案（`/loop` コマンド + マージ完了終了条件）は採用しない。代わりに「push からの経過時間ゲート」を 2.1 節に追加する案を推奨する
- **根拠**: `/loop` は外部非同期プロセス待機には不適切（意味論が合わない）。「マージ完了まで待つ」はターン長時間占有・required reviewers によるブロック・デバッグ困難性のデメリットが大きい。問題の本質は「CodeRabbit がレビュー開始前に0件安定と判定してしまう」点であり、push からN分未満は安定判定しないゲートで解決できる。最小変更・最大効果の原則に合致する
- **代替案**: CodeRabbit の reviews API を使ってレビュー submitted_at を確認する方法（案B）も有効。案Aとの組み合わせも検討余地あり

### 2026-04-03（再評価）: pr-review-loop の /loop 分割方式の評価

ユーザーの提案を正確に再把握した上での評価。

提案内容:
- `/loop` コマンド（新規スキル）で pr-review-loop を定期起動する
- 各回の pr-review-loop の処理範囲を「コメントがあれば修正→push して終了」に限定する
- マージ完了を `/loop` の終了条件にする

- **判断**: 採用しない。

- **根拠**:

  1. `/loop` は Claude Code CLI の公式コマンドとして存在しない（`claude --help` で確認）。新規スキルとして実装するなら追加コストがかかり、「導入の手軽さ」に反する

  2. 「CodeRabbit がまだレビュー前なのに抜ける」問題は解消されない。インターバルが短ければ同じ誤判定が起きる。インターバルを長くすればレイテンシが増す。問題の根本（push から CodeRabbit レビュー完了までの時間差）が解決されていない

  3. CodeRabbit はストリーミング的にコメントを投稿する。「コメントがあれば修正してその回は終了」のロジックは、まだコメントが増え続けている途中で修正を開始して push するケースを誘発する

  4. ループ状態（「何周目か」「前回の push タイムスタンプ」）が /loop 呼び出し間で共有されない。状態を持てないため、「push から N 分未満は安定判定しない」のような経過時間ゲートが実装できない

  5. マージ完了監視を /loop に持たせると「汎用ループ管理」ではなく「PR マージ監視ループ」になり、再利用性が下がる

- **代替案**:

  - **案A（推奨）**: pr-review-loop の 2.1 節冒頭に「最後の push から N 分未満は CodeRabbit 安定判定をスキップし、N 分待ってから安定判定を開始する」ゲートを追加。変更量は数行。問題の根本解決。
  - **案B**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews` で CodeRabbit の `submitted_at` を取得し、最後の push より後のレビューが存在するまでポーリング継続する。「push に対するレビューが完了したか」をより正確に判定できる。案Aと組み合わせ可能

### 2026-04-03（ゼロベース再評価）: /loop 公式コマンド前提での pr-review-loop 設計評価

前回の再評価で「`/loop` は存在しない」を根拠1に置いたが、これは誤りだった。`/loop` は Claude Code のインタラクティブセッション内スラッシュコマンドであり、`claude --help` には出てこない別名前空間に属する。CLI サブコマンドと混同した。前回評価を撤回し、`/loop` が公式機能であることを前提にゼロベースで再評価する。

提案内容（確認済み）:
- `/loop 5m /pr-review-loop` で定期実行
- 各回: PR 状態を新規取得 → 未解決コメントがあれば修正 → push → 終了
- マージ済みを検出したら「マージ完了」と出力して終了
- 状態共有なし（毎回 PR の現在状態を取得）

- **判断**: `/loop` 活用は採用する価値あり。ただし pr-review-loop の「1パス終了」への変更は採用しない。2.1 節の安定判定修正を先行させることを強く推奨する。

- **根拠**:

  1. `/loop` が公式機能であることが確認されたため、「新規スキルの実装コストがかかる」という前回根拠1は無効。既存機能の組み合わせで実現できる

  2. 「ユーザーが毎回指示する必要がある」問題は解消される。セッションが生きている間の放置（席を外す程度）には十分実用的

  3. **【撤回】** 当初「1パス終了を採用しない」と判断したが、ユーザーの指摘を受けて撤回。スキルを `/pr-review-fix`（1回実行）と `/pr-review-loop`（`/loop 5m /pr-review-fix` を呼ぶラッパー）に分離する設計を採用した。名前と動作が一致し、責務が明確になる

  4. ポーリング待ちの問題は `/loop` による定期実行で根本解決する。各回は PR の現在の状態を新規取得するため、状態共有不要

### 2026-04-05: team-auto-approve.sh — Bash コマンドの多段検証とセグメント分割（Issue #233 対応）

- **判断**: Bash コマンド判定ロジックを `is_safe_segment()` 関数に抽出し、`&&`/`;` 連結コマンドをセグメント分割して全セグメントを個別検証する。サブシェル（`$()`/バッククォート）とパイプ（`|`/`||`）は事前ブロックする。危険フラグリストに `--rsh` を追加する
- **根拠**: 従来の実装はコマンド全体を1つの文字列として判定していたため、`safe_cmd && dangerous_cmd` のような連結コマンドで safe_cmd 部分のみ判定されていた。セグメント分割により全コマンドを検証できる。サブシェル・パイプは安全リストのコマンドを迂回する攻撃ベクターになるため事前遮断が必要。`--rsh` は rsync による任意コマンド実行（`rsync --rsh=malicious_cmd`）を防ぐために追加した
- **代替案**: 全 Bash コマンドを deny する案はチームメイトの操作性を大きく損なうため却下。サブシェル・パイプを許可しつつ内部コマンドも解析する案は複雑性が高くバイパスリスクが残るため採用しなかった

### 2026-04-05: /issue スキルへの preset 条件分岐型 CPO ゲートの採用

- **判断**: `/issue`（minimal プリセットに含まれるスキル）の内部で `vibecorp.yml` の preset を確認し、`standard` または `full` の場合のみ CPO エージェントをゲートとして呼び出す設計を採用する
- **根拠**: プリセット自己完結の原則（「スキルが参照するコマンド・スキルは同じプリセットに必ず存在すること」）との整合を保ちつつ、上位プリセットで追加のガードレールを有効にする唯一の手段が条件分岐による runtime 判定だった。`minimal` ではゲートをスキップするためプリセット自己完結の原則には反しない。CPO エージェント自体は standard 以上にのみ存在するが、スキルはその存在を前提にせず preset 確認の結果として呼び出す構造にした
- **代替案**: `/issue` を preset ごとに別スキルとして用意する案（`/issue-minimal`, `/issue-standard`）も検討したが、スキル名の一貫性が失われ「導入の手軽さ」に反するため却下した。また、CPO ゲートを standard 専用スキルとして外出しする案は、ユーザーが明示的に呼び出す必要があり規律の自動化に反するため採用しなかった

### 2026-04-08: team-auto-approve.sh — quote-aware セグメント分割への置き換え（Issue #252）

- **判断**: `sed 's/&&/\n/g; s/;/\n/g'` による単純分割を廃止し、awk で `in_single`/`in_double` フラグを管理する quote-aware 分割に置き換える
- **根拠**: `awk '/^key:/ { sub(...); print; exit }' file` のような正当なコマンドが `;` の位置で誤分割され、safe list 判定に漏れて permission ダイアログが毎回表示される問題が発生した。quote 内の区切り文字を無視しない実装はバグと同等であり、フックの信頼性を損なう
- **代替案**: 対象外コマンドを early-exit で弾く方式も有効（分割コスト不要）だが、汎用性が低く新しいコマンドパターンへの対応漏れが起きやすい。awk による state-tracking の方が根本解決として採用した

### 2026-04-08: compound command の分割を SKILL.md で制約（Issue #258）

- **判断**: Claude Code built-in security check（`cd` + パイプ + リダイレクトの複合コマンドをブロックする）は hook で override 不可。対策として ship / ship-parallel の SKILL.md に「`cd` + パイプ + リダイレクトを含む compound command は避け、個別の Bash 呼び出しに分割する」旨の制約を追加する。単純な `cd && git ...` のような harmless な命令チェーンは対象外
- **根拠**: hook の後段で動く built-in check は `permissionDecision: "allow"` を無視する。hook 側での解決は不可能であり、コマンドを生成するエージェント（teammate）への指示で上流から防ぐのが唯一の実用策
- **代替案**: built-in check を無効化する設定を探したが、そのような設定は存在しない（2026年4月時点）

### 2026-04-10: ship-parallel の Agent 起動に mode: "dontAsk" を指定（Issue #260）

- **判断**: ship-parallel で Agent (teammate) を起動する際に `mode: "dontAsk"` を指定する
- **根拠**: Agent の mode が未指定（`default`）の場合、teammate のツール呼び出しが親セッション（チームリーダー）に承認要求を上げる。この場合、worktree に `team-auto-approve.sh` が存在し settings.json のマッチャーも正しくコピーされていても、hook の `permissionDecision: "allow"` が Agent の permission レイヤーに上書きされて効かない。`dontAsk` を指定することで hook が permission を完全に制御できるようになる
- **代替案**: `bypassPermissions` はファウンダー方針（Issue #252）で使用禁止。`dontAsk` はこの方針に矛盾せず、hook が引き続き動作するため安全性を維持できる

### 2026-04-11: ヘッドレス Claude を子プロセスとして起動し PID 管理するアーキテクチャパターンの採用（spike-loop）

- **判断**: spike-loop では `claude -p --permission-mode dontAsk --verbose` を Bash の `run_in_background: true` で起動し、返却された PID を記録して kill・監視に使用する
- **根拠**: #260 で採用した `dontAsk` モードの応用として、ヘッドレス Claude を外部プロセスとして管理することで、スキルから ship-parallel の E2E 実行を完全に自律制御できる。PID を記録することで stuck 時の強制終了とクリーンアップが確実に行える
- **代替案**: Agent ツールで子エージェントとして起動する案も検討したが、長時間実行の監視・強制終了・再起動がツール API では制御できないため採用しなかった

### 2026-04-11: command-log ベースの stuck 検出（10分閾値）と 30 秒間隔ポーリングの採用（spike-loop）

- **判断**: command-log の最終タイムスタンプを `tail -1` で取得し 30 秒間隔でポーリングする。最終タイムスタンプから 10 分以上更新がなければ stuck と判定する
- **根拠**: Monitor ツールはプロセスの stdout イベントを通知するが、長時間監視では通知が多量発生してコンテキストを圧迫する。30 秒間隔の明示的なポーリングであればコンテキスト消費が予測可能で、stuck 検出の精度（10分）も ship-parallel の平均的なステップ所要時間に対して妥当な閾値である
- **代替案**: Monitor ツールによるイベント駆動監視は通知過多でコンテキスト圧迫のリスクがあり採用しなかった。command-log のポーリングは既存の hook インフラ（command-log.sh）を再利用でき追加インフラ不要の点でも優れる

### 2026-04-11: spike-loop を full プリセット専用とした判断（Issue #263 前提）

- **判断**: spike-loop は full プリセット専用とし、standard 以下のプリセットへの配布は行わない
- **根拠**: spike-loop は内部で `/ship-parallel` を呼び出し、ship-parallel は SM エージェントが担うチームオーケストレーションに依存する。SM エージェントは full プリセットにのみ含まれるため、プリセット自己完結の原則に従うと spike-loop も full 専用となる
- **代替案**: preset 条件分岐型（`/issue` の CPO ゲートと同パターン）で standard では SM なしで動作させる案も検討したが、spike-loop の本質的な価値（ship-parallel の自動 E2E 検証）は SM なしでは成立しないため条件分岐による回避は意味をなさない

### 2026-04-11: --dangerously-skip-permissions のコンテナ化隔離方式の評価

- **判断**: Docker（bind mount）方式を推奨。gVisor/Firecracker は現時点では過剰。vibecorp 本体の必須要件にはせず、オプション機能として位置づける
- **根拠**:
  - コンテナ化が守るのは「ホスト環境への波及防止」であり「コンテナ内操作の安全化」ではない。この区別が重要
  - Docker bind mount は ship-parallel の手動 worktree・spike-loop の PID 管理・Team 機能の Agent 間通信すべてと整合する
  - gVisor は syscall 互換レイヤーで Claude Code CLI / spike-loop の `kill $pid` に影響が出る可能性があり、E2E 検証コストが高い
  - Firecracker はVMオーバーヘッドが大きく、インタラクティブワークフローのホストには不適
  - コンテナ化を必須にすると MVV「導入の手軽さ」と衝突する
- **実装要件**: `--init`（tini）フラグ必須（spike-loop の子プロセス zombie 対策）、`~/.gitconfig` と `~/.config/gh/` は ro マウント、`~/.claude/` はコンテナ専用ディレクトリで分離、`CLAUDE_PROJECT_DIR` を明示設定
- **代替案**: gVisor（隔離強度は高いが互換性未検証）、macOS sandbox-exec（補完的用途のみ）

### 2026-04-11: spike-loop SKILL.md の kill+cleanup セクションを自己矛盾のない手順に書き換え（PR #264）

- **判断**: spike-loop SKILL.md が宣言している制約（`--force`/`-D` 禁止、Bash 1 コマンド 1 呼び出し、`2>/dev/null`・`|| echo` 等のフォールバック禁止）を、自身の例示コードで違反していた。プロセス kill・worktree 削除・ブランチ削除のコマンドを `pgrep` / `git worktree remove <path>`（force なし）/ `git branch -d <branch>`（小文字）に修正。uncommitted 変更や未マージブランチは安全に削除できないため手動対応とする設計を採用した。合わせて `headless-claude.md` のサンプルコードも同制約に合わせて修正（`kill "$pid" 2>/dev/null || true` → `kill "$pid"`、パイプを使った `last_ts` 取得 → `awk 'END { print $1 }' "$COMMAND_LOG"` に置き換え）
- **根拠**: ドキュメント内の制約とサンプルコードが矛盾しているとエージェントが誤ったパターンを学習する。ルールとサンプルの整合性はドキュメントの信頼性の基本
- **代替案**: フォールバックを許容して制約を緩める案も検討したが、spike-loop の制約は Claude Code built-in security check への対策として設計されたものであり（Issue #258）、緩めることは安全性の低下につながるため採用しなかった

### 2026-04-16: ship-parallel / autopilot を full プリセット専用に格下げ（Issue #308）

- **判断**: `/ship-parallel` と `/autopilot` を minimal/standard プリセットから物理的に除外し、full プリセット専用とする。install.sh の minimal/standard ブロックに `rm -rf` を追加するハード制限方式を採用。SKILL.md 内のソフトガード（preset 判定ロジック）は defense-in-depth として残す
- **根拠**: #293 隔離レイヤ計画で「隔離は full プリセットのみ」が確定した。隔離が効かない minimal/standard でヘッドレス並列スキルを開放すると、誤爆リスク（意図しないファイル変更・ブランチ汚染）が防止できない。ソフトガードのみに依存するとスキルファイルの手動配置やテンプレート直接コピーでバイパスされるため、install.sh での物理削除がハード制限の本筋
- **代替案**: SKILL.md のソフトガードのみで制御する案（物理削除なし）も検討したが、install.sh で配置してしまう以上、ソフトガードのバイパスリスクが残る。物理削除 + ソフトガード併存の defense-in-depth が最も堅牢

### 2026-04-16: 環境変数を認証・セキュリティ境界として使う場合の設計方針

- **判断**: 環境変数（例: `VIBECORP_SANDBOXED=1`）を単独でプロセスの信頼判定に使うことを禁止する。必ずプロセス系譜（PPID chain）や FD 経由トークンなど、親プロセスの制御下にある情報と AND 条件で組み合わせる
- **根拠**: 環境変数は `env VIBECORP_SANDBOXED=1 claude ...` のように外部から任意に設定できる。単独で信頼判定に使うと完全バイパスされる。Issue #309 の sandbox-exec PoC で `VIBECORP_SANDBOXED=1` をパスthrough判定の唯一の根拠にしようとした際に検出した
- **代替案**: プロセス起動時に FD（ファイルディスクリプタ）経由でトークンを渡し、子プロセス内で FD が存在するかを確認する方法がより堅牢。ただし実装コストが上がるため、sandbox-exec PoC Phase 1 では「PPID chain で vibecorp 親プロセスを確認する」方式を暫定採用とした

### 2026-04-16: docs/design-philosophy.md にプロセス隔離（Phase 1 PoC）セクションを追加

- **判断**: PATH シム方式・opt-in 設計・二重サンドボックス防止・OS ディスパッチャ抽象化の 4 点を `docs/design-philosophy.md` の「プロセス隔離（Phase 1 PoC）」セクションとして追記した
- **根拠**: PR #317 / Issue #309 で `templates/claude/bin/` 配下の隔離レイヤが追加されたが、設計思想ドキュメントに未反映だった。sync-check で検出された不整合を解消する。Phase 1 PoC の段階に見合った概略レベルの記述にとどめ、過剰な加筆を避けた
- **代替案**: 既存のフック設計パターンセクションに混在させる案も検討したが、隔離はフックとは独立した関心事であり独立セクションとして分離した

### 2026-04-16: vibecorp-sandbox に symlink 解決 + 2 段階検証と WORKTREE ⊇ HOME 拒否を追加（PR #317 第 2 回レビュー対応）

- **判断**: `canonicalize_dir()` ヘルパ（`(cd "$p" && pwd -P)`）を追加し、raw バリデート → canonicalize → canonicalize 後に再度 `validate_abs_path` を実行する 2 段階検証を採用。加えて、canonicalize 後に `case "${HOME_VALUE}/" in "${WORKTREE_VALUE}/"*)` で WORKTREE が HOME を包含するケースを入口で拒否する
- **根拠**:
  - macOS の `$TMPDIR` は `/var/folders/...` で `/private/var/...` の symlink であり、解決前後の文字列を混在比較すると包含判定が崩れる。canonicalize 後に比較することで symlink の違いによる誤判定を防ぐ
  - `WORKTREE=/Users` のような設定は sandbox-exec の `(subpath (param "WORKTREE"))` を通じて `~/.ssh` / `~/.aws` を RW 境界に含めてしまう。書込み境界が HOME 全体に広がるのを防ぐため、入口で拒否する
  - WORKTREE ⊇ HOME 包含判定に bash の `case` 文を使った理由: macOS のデフォルト bash は 3.2 であり `[[ =~ ]]` の正規表現は使えないが、`case` の glob パターンは bash 3.2 でも安定して動作する。`case "${HOME}/" in "${WORKTREE}/"*)` でサフィックス `/` を付けることで完全パスセグメント単位の一致判定ができ、誤マッチを防げる
- **代替案**: `[[ "$HOME_VALUE" == "$WORKTREE_VALUE"/* ]]` のような bash 4+ の二重ブラケット glob 展開も機能するが、macOS 3.2 互換性を確保するため `case` 文を採用した

### 2026-04-16: install.sh に macOS 隔離レイヤ配置ロジックを統合（Phase 3a / Issue #318）

- **判断**: install.sh に `detect_os()` / `check_unsupported_os()` / `check_isolation_deps()` / `copy_isolation_templates()` / `generate_activate_script()` の 5 関数を追加し、`preset=full && OS=darwin` のときのみ `.claude/bin/{claude, vibecorp-sandbox, activate.sh}` と `.claude/sandbox/claude.sb` を自動配置する。minimal / standard へのダウングレード時は `rm -f` + `rmdir` でディレクトリを残したままユーザー独自配置ファイルを保護しつつ vibecorp 配置分のみ削除する
- **根拠**:
  - Phase 1（#309/#317）でテンプレートは templates/claude/ に存在するが install.sh からのコピー未実装だった。Phase 3 を一括で macOS + Linux にするのは #310（Linux bwrap）が未完了のためブロックされており、先に macOS だけ切り出す Phase 3a（#318）とすることで full プリセット + macOS ユーザーに最速で価値を届ける（「段階的成長」「導入の手軽さ」バリュー）
  - `generate_activate_script` は templates としてファイル配布せず heredoc 生成する方式を採用。理由: activate.sh は `REPO_ROOT`（導入先ごとに異なる絶対パス）をスクリプト本文に埋め込む必要があり、静的テンプレートでは表現できないため
  - ダウングレード時のクリーンアップは `rm -f` 既知ファイル + `rmdir` のみとする。`rm -rf` は「templates 由来ではないユーザー独自配置ファイル（例: `.claude/bin/my-custom-tool.sh`）」を巻き込む可能性があり、非空 `rmdir` が失敗することで非 vibecorp ファイルを自動的に保護できる設計とした
  - symlink 検証（`[[ -f "$src" && ! -L "$src" ]]`）は security-analyst 3 名全員一致 Minor 指摘に基づく多層防御。Phase 1 sandbox 実行時の `canonicalize_dir()` + 包含チェックが本命の防御レイヤだが、入口（コピー時）で symlink を弾くことでサプライチェーン侵害時の配置経路を減らす
- **代替案**:
  - Phase 3 一括（macOS + Linux 同時対応）: #310 Linux bwrap 設計が未完のため待つ必要がある。CEO 承認のもと #318 で分割
  - `rm -rf` 一括削除: ユーザー独自ファイル保護ができないため却下
  - activate.sh を templates として配布: REPO_ROOT の動的埋め込みができないため却下
  - `SCRIPT_DIR` / `REPO_ROOT` の `pwd -P` 化（Analyst 2 が High 指摘）: リポジトリ改ざん前提の攻撃経路であり、Phase 1/2 sandbox 実行時防御が 2 段検証で保護するため Phase 2 追跡に格下げ（CISO メタレビュー判断）

### 2026-04-16: claude TUI ハング修正 — sandbox-exec プロファイルへの `file-ioctl` 追加（Issue #320）

- **判断**: `templates/claude/sandbox/claude.sb` に `(allow file-ioctl (subpath "/dev"))` を追加し、`~/.local/share/claude` RO 許可と `~/.claude.json` RW 許可（literal 限定）も追加する
- **根拠**:
  - `file-ioctl` は `file-read*` / `file-write*` とは独立した権限カテゴリ。`/dev` への read/write を許可しても ioctl は通過しない。claude（npm 配布）は TUI 起動時に `/dev/ttys*` への ioctl（TTY raw mode 切替）を実行するため、欠落するとプロセスは生きているが入力を受け付けない状態（TUI ハング）になる
  - `~/.local/share/claude/versions/<version>/` は claude バイナリ実体の格納場所。RO 許可がなければ claude 自体が起動できない
  - `~/.claude.json` は OAuth トークン・プロジェクト一覧を保存。RW 許可がなければ認証フローが機能しない
  - 境界拡張の CR-001 観点での再評価（CISO メタレビュー 2026-04-16）: `/dev` ioctl 追加は既存の `file-read*/file-write-data` 許可の延長であり新たな攻撃面は限定的。`~/.local/share/claude` RO は `~/.npm` RO 許可と同等。`~/.claude.json` RW は既存の `~/.claude` 全 RW と同等の信頼境界
- **代替案**: `file-ioctl` を特定の ioctl 番号に絞る方法も検討したが、ioctl 番号を SBPL で列挙する機能が存在しないため、`subpath "/dev"` への全 `file-ioctl` 許可が現実的な唯一の選択肢だった

### 2026-04-16: ドキュメントの「正典委譲」パターン — パス列挙は実装ファイルに委譲

- **判断**: 境界・制約の詳細は実装ファイル（例: `.claude/sandbox/claude.sb`）の **全体（ヘッダコメント + SBPL ルール本文）** を正典とし、設計ドキュメント（`docs/design-philosophy.md`）では思想のみを記述してパス列挙・ルール詳細の重複を避ける
- **根拠**: 同じパス一覧やルール詳細を 2 箇所に書くと、実装を更新したときにドキュメント側の更新が漏れて乖離が発生する。「正典は 1 箇所」の原則（Single Source of Truth）を維持しつつ、設計ドキュメントには「詳細は当該ファイルを参照」と参照先を明記することで両方の役割を成立させる。`literal` / `subpath` の使い分け、`file-ioctl` の独立性、network/process 制約等の本文側ルールも正典範囲に含める
- **適用範囲**: sandbox プロファイルの許可/拒否パス一覧・SBPL ルールに限らず、設定ファイル・テンプレートのキー一覧など「実装が正」になる詳細全般に適用できる汎用パターン

### 2026-04-17: ゲートスタンプの保存先を `.claude/` 外に切り出し（Issue #326）

- **判断**: `/sync-check`、`/session-harvest`、`/review-to-rules`、`/review-loop` が発行するスタンプを `.claude/state/<name>-ok` から `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/<name>-ok` に移動。`<repo-id>` は basename（サニタイズ済み）+ 同パスの sha256 先頭 8 文字
- **根拠**: Claude Code は `--dangerously-skip-permissions` 起動時でも `.claude/` 配下への書込みで確認プロンプトを発生させる仕様があり、ゲートスタンプ発行が連続するスキルワークフローの UX を阻害していた。XDG 仕様準拠の場所に切り出すことで本体側の保護対象から外れる
- **重要設計**: gate hook の `STAMP_FILE` 評価は早期 exit **後** に移動。PreToolUse は全ツール呼び出しで発火するため、無関係コマンドで `git rev-parse` + `shasum` を走らせない
- **脅威モデル**: 同一ユーザー内の任意プロセスからのスタンプ偽造はスコープ外（信頼境界 = ユーザーアカウント）。`chmod 700` で他ユーザー保護のみ実施。HMAC/PID 埋め込みは v1 では採用しない
- **代替案**: (a) `.claude/` 内のままで bypass 例外を厳密化 → 本体側仕様に依存し根本解決にならず却下、(b) PID/HMAC 埋め込みでスタンプ内容検証 → 信頼境界の越境ではなくコスト見合いせず却下

### 2026-04-16: ゲートスタンプ XDG 移行に伴う実装上の技術判断（PR #327）

- **判断**: (a) `basename | tr` パターンには `printf '%s'` で trailing newline を除去する。(b) PreToolUse フックのスタンプパス計算は early exit の後に置く。(c) 共通ヘルパーの重複呼び出しは `STAMP_DIR` 変数で1回取得・再利用に統一。(d) sandbox subpath 外の親ディレクトリは sandbox-exec より前（install.sh / pre-launch）に事前作成する
- **根拠**:
  - `basename "$root" | tr -cs ...` は basename の trailing `\n` も `_` に変換して末尾に付く。PR #327 でリポジトリ ID 生成が `<name>_` になる不具合として発現
  - PreToolUse は Read/Write/Bash 全呼び出しで発火するため、early exit より前に `git rev-parse + shasum` を置くと無関係なツール呼び出しで毎回外部プロセスが 2 つ走る
  - `vibecorp_stamp_path` が内部で `vibecorp_stamp_dir` を呼ぶ設計の場合、複数回呼ぶと同回数 `git rev-parse + shasum` が実行される。STAMP_DIR を一度取得して再利用することで O(N) → O(1) になる
  - `(allow file-write* (subpath "~/.cache/vibecorp"))` は存在しない中間ディレクトリの作成権限を含まない。macOS sandbox-exec の `subpath` は対象パスが存在するディレクトリの配下のみをカバーする
- **代替案**: `basename` の newline 除去に `tr -d '\n'` を `basename` と `tr -cs` の間に挟む方法も機能するが、`printf '%s'` の方がコマンド置換の標準的な newline 除去慣用句として可読性が高い

### 2026-04-16: `git pull` による意図しない merge commit 混入の扱い

- **判断**: workflow.md への追記は COO 管轄（rules/ の追記は管轄内だが今回は見送り）。`git pull --ff-only` または `git pull --rebase` を CI / install.sh で呼ぶ箇所に限定的に強制する。開発者向けのグローバル設定（`pull.ff = only`）の推奨は README に記載を推奨する（CPO・COO 判断に委ねる）
- **根拠**: local main が divergent 状態（origin にない commit を持つ等）のとき `git pull origin main` を素直に実行すると merge commit が生まれ、PR のコミット履歴が汚染される。vibecorp の install.sh は `git pull origin main` を実行するパスがあるため影響を受ける。ただし `pull.ff = only` を rules/ に書くと全開発者の git グローバル設定に干渉する恐れがあり、スコープを install.sh / CI 内コマンドに限定する
- **代替案**: `pull.rebase = true` の git config 推奨を rules/ に追記する案も検討したが、既存の git ワークフローへの干渉リスクがあり今回は見送り

### 2026-04-17: 原子的置換パターンの実挙動確認とSBPL設計（Issue #329）

- **判断**: (a) `.lock`（固定名）と `.tmp.<pid>.<epoch_ms>`（動的名）は SBPL の同一ブロックに混在させず、`literal` 許可と `regex` 許可を分離したブロックに記述する。(b) epoch_ms の桁数は不問とし `[0-9]+\.[0-9]+` で統一する
- **根拠**:
  - kernel deny ログ `deny(1) file-write-create /Users/hiroki/.claude.json.lock` および `deny(1) file-write-create /Users/hiroki/.claude.json.tmp.98846.1776431009101` により、Claude Code の OAuth state 書込が `.lock`（固定名）→ `.tmp.<pid>.<epoch_ms>`（動的名）→ rename という原子的置換パターンを採用していることを実挙動で確認した
  - `literal` と `regex` は SBPL 内で意味論が異なる（前者は完全一致・後者はパターン照合）。同一 `(allow ...)` ブロックに混在させると可読性が低下し境界責務が曖昧になるため、ブロックを分離する
  - `$(date +%s)` は 10 桁（秒）、`epoch_ms` は 13 桁だが `[0-9]+\.[0-9]+` は桁数不問でどちらにもマッチする。Claude Code 側が precision を秒→ミリ秒等に変更しても regex を修正する必要がなく、将来変更への耐性が高い
- **代替案**: `.lock` も regex で `\.lock$` として統一する案も検討したが、固定サフィックスを literal で書けるのに regex を使うのは過剰であり、`literal` の方が意図が明確なため採用しなかった

### 2026-04-18: Hook と sandbox 隔離の役割分担評価（full = sandbox + skip-permissions 前提）

- **判断**:
  - sandbox（SBPL）と Hook は制御層が異なる。sandbox は OS リソース境界（ファイルシステム・ネットワーク）を物理封じ込めし、Hook は Claude Code のツール意味論（どのパス・どのコマンド）を制御する。両者は直交する二層防御であり「sandbox があれば Hook を削減できる」は原則として成立しない
  - 唯一の削減候補は `team-auto-approve.sh`。この Hook の目的は「承認プロンプトを消す」ことであり、`--dangerously-skip-permissions` が前提なら存在意義がなくなる。full + macOS sandbox + VIBECORP_ISOLATION=1 有効時のみ、install.sh の配置条件から除外することを推奨する
  - ワークフローゲート 2 本（sync-gate / review-gate）はプロセス強制であってセキュリティではなく、sandbox・skip-permissions と直交する。standard 以上で維持必須（review-to-rules-gate / session-harvest-gate は #328 知見閉ループ再設計でスキル任意実行化に伴い廃止）
  - セキュリティ系 Hook（protect-files / protect-branch / role-gate / block-api-bypass / diagnose-guard）はツール意味論レベルの制御を担い、sandbox では代替不可能。全プラン維持必須
- **根拠**: sandbox の subpath 制御は WORKTREE 境界を設定するが、WORKTREE 内の特定ファイルの除外・現在ブランチの文脈判断・エージェントのロール状態・コマンドの意味論制御は SBPL に記述できない。Hook が担保している制御を sandbox に移植する手段がそもそも存在しない
- **代替案**: team-auto-approve を全プランで削除し、全ユーザーに skip-permissions を要求する案も検討したが、MVV「導入の手軽さ」「段階的成長」に反するため却下。full 専用の条件分岐が最小変更・最大効果の判断

### 2026-04-18: CodeRabbit による cross-PR 統合問題検出の技術評価

- **判断**: CodeRabbit は「子A + 子B の組み合わせで発生する API 衝突・命名不整合」をアーキテクチャ上検出できない。feature→main PR を OFF にするコスト削減は合理的だが、統合問題の防止目的には別レイヤー（Semgrep + CI）での補完が必要
- **根拠**:
  - CodeRabbit は PR ごとに独立した LLM セッションで動作し、他 PR の diff を参照する cross-PR analysis 機能を持たない（2026年4月時点）
  - `knowledge_base` / `learnings` は過去レビューの蓄積であり、リアルタイムの cross-PR API surface 比較にはならない
  - `path_instructions` でルールを書いても「2 つの PR が独立してルールに従っている場合の衝突」は instruction では防げない
  - `path_filters` で既レビュー済みファイルを除外すると LLM コストは削減できるが、統合問題の検出能力は上がらない
- **推奨構成**:
  - 子PR（dev/xxx → feature/epic-xxx）: CodeRabbit フル有効
  - feature→main PR: CodeRabbit の `path_filters` で重複除外 + Semgrep によるルール違反チェックを CI に追加
  - Semgrep ルールファイル（`.semgrep/rules/`）はテンプレートとして配布可能（ユーザー環境依存なし）
- **代替案**: `danger.js` は cross-PR の差分比較スクリプトを書ける点で最も直接的だが Node.js 実行環境依存が増えるため採用優先度は低い。Semgrep OSS 版（YAML 定義・CI インライン実行）が vibecorp テンプレート配布との相性が最もよい

### 2026-04-18（再評価）: Semgrep 採用見直し — YAGNI 原則により不採用

前回（同日）の推奨を撤回する。

- **判断**: Semgrep は不採用。CodeRabbit `path_instructions` + `shellcheck` で代替する
- **根拠**:
  1. vibecorp の本体はシェルスクリプト群であり、Semgrep が本領を発揮する TypeScript/Python/Go の型・API surface 解析の恩恵がほとんどない。`shellcheck` / `bash -n` が検出できない問題を Semgrep DSL で追加検出できるケースが見当たらない
  2. 命名規約・構造制約は CodeRabbit の `path_instructions` に自然言語で記述することで LLM ベースのレビューとして機能する。「`path_instructions` では検出できないが Semgrep なら検出できる」ケースが vibecorp では特定できなかった
  3. cross-PR 統合問題の補完手段として前回 Semgrep を挙げたが、Semgrep も単一 PR を静的解析するツールであり cross-PR 衝突は検出できない。前回の根拠は誤りだった
  4. 導入コスト（テンプレート配布・install.sh 拡張・CI workflow 追加・利用者の DSL 学習）が MVV「導入の手軽さ」と衝突する
- **推奨構成**:
  - 子PR: CodeRabbit フル有効
  - feature→main PR: CodeRabbit フル有効（コスト削減で `path_filters` 除外も可だが、統合問題検出には絞り込まない方が望ましい）
  - シェルスクリプト品質: `shellcheck` を CI に追加
- **代替案**: 将来的に TypeScript/Go など型のある言語を vibecorp に採用した場合、その時点で Semgrep の導入を再評価する（YAGNI の後追い）

### 2026-04-18: `.coderabbit.yaml` テンプレート配布の取り下げ（Issue #348 再評価）

- **判断**: Issue #348 を現在の設計のまま取り下げる。`shellcheck` CI のみ別 Issue で再設計する。`.coderabbit.yaml` テンプレートの配布は不採用。
- **根拠**:
  1. `path_filters` で `templates/` `docs/` を除外する設計は vibecorp 自身のディレクトリ構造を前提にしている。インストール先リポジトリに `templates/` が存在する保証はなく、TypeScript / Go / Rust 等どのようなプロジェクトにも適用できる汎用設定にはなりえない
  2. `path_instructions` も配布先の命名規約・構造制約を事前定義できないため、内容が空か無意味になる
  3. feature→main PR の `path_filters` 絞り込みは、別の子 PR が同じファイルを変更する統合問題を見落とす。フル有効の方が安全であり、CodeRabbit のコスト削減は現時点で優先課題ではない
  4. CodeRabbit 設定は配布先プロジェクトのオーナーが自分で書くべき領域であり、vibecorp がスコープを持つ理由がない
- **`shellcheck` CI について**: 配布する場合の対象は `.claude/hooks/*.sh`（vibecorp がインストールするファイル）のみ。`install.sh` / `tests/*.sh` は vibecorp 本体の CI で実行するものであり配布 CI の対象ではない。プリセット制限も不要（hooks は minimal 以上に存在するため全プリセットに配布可）。別 Issue で再設計する
- **代替案**: vibecorp が `.coderabbit.yaml` の雛形コメント（`# 各プロジェクト固有のパスを設定してください`）を配布する案も検討したが、メンテ不能なゴミになるリスクがあり却下
