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
- **根拠**: spike-loop は内部で `/ship-parallel` を呼び出し、ship-parallel は COO エージェントが担うチームオーケストレーションに依存する。COO エージェントは full プリセットにのみ含まれるため、プリセット自己完結の原則に従うと spike-loop も full 専用となる
- **代替案**: preset 条件分岐型（`/issue` の CPO ゲートと同パターン）で standard では COO なしで動作させる案も検討したが、spike-loop の本質的な価値（ship-parallel の自動 E2E 検証）は COO なしでは成立しないため条件分岐による回避は意味をなさない

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

### 2026-04-11: docker/claude-sandbox/ のリポジトリトップレベル配置判断（Issue #266）

- **判断**: コンテナ隔離環境のイメージ定義（`Dockerfile` / `entrypoint.sh` / `seccomp.json` / `README.md` / `.dockerignore`）を `docker/claude-sandbox/` としてリポジトリトップレベルに配置する。`.claude/` 配下には置かない
- **根拠**:
  - `docker/` は Docker エコシステムの業界標準配置パターンであり、他リポジトリや外部利用者から発見しやすい
  - `.claude/` は Claude Code 規約パスのための予約空間であり、Docker 関連ファイルを混入させると規約の意味が希薄になる
  - `docs/file-placement.md` が禁じているのは `.claude/vibecorp/` のような Claude Code 規約外の独自 namespace の作成であり、リポジトリトップへの新規ディレクトリ追加は別論点
  - `templates/` は `install.sh` で配布先にコピーされる source of truth であり、コンテナ定義は配布先でも vibecorp ソースと同じ構造を保ちたい（`templates/` 配下ではない）
- **代替案**:
  - `.claude/docker/` 配置案 → 却下。Claude Code 規約空間の汚染になり、規約と独自要素の境界が曖昧になる
  - `templates/docker/` 配置案 → 却下。`templates/` は配布先コピー用であり、vibecorp 本体の開発時点でイメージを使うユースケース（CI でのビルドテスト等）に対応しづらい

### 2026-04-11: seccomp プロファイルを ALLOW デフォルト + 特定 syscall denial 構成で実装（Issue #266）

- **判断**: `docker/claude-sandbox/seccomp.json` を `defaultAction: SCMP_ACT_ALLOW` + `ptrace` / `mount` / `pivot_root` / `bpf` / `unshare` / `setns` / `reboot` / `kexec_load` / `swapon` / `swapoff` / `init_module` / `perf_event_open` の明示的な `SCMP_ACT_ERRNO` 拒否で構成する。Docker default seccomp profile（800 行超の allowlist）は同梱しない
- **根拠**:
  - Docker default profile を同梱すると常に Docker 最新版との乖離リスクを抱えることになり、メンテナンスコストが高い
  - 本イメージは `--cap-drop ALL` + `--cap-add NET_ADMIN` + `setpriv` による bounding set drop + `--read-only` + `no-new-privileges` + `--pids-limit` 等の多層防御を前提としており、seccomp は追加防御層として位置付けられる
  - 攻撃面として最も危険な syscall 群（コンテナエスケープ経路、debugger 介入、カーネル操作）を明示的に拒否することで、ALLOW デフォルトでも実質的な isolation を維持できる
- **代替案**: Docker default profile をベースにして同梱する案 → 却下（保守性の問題）。Phase 2 以降で厳格化の必要性が出た場合は再評価する

### 2026-04-12: spike-loop container integration — PID 管理からコンテナ ID 管理への移行（Issue #267 / Phase 1-2）

- **判断**: spike-loop のヘッドレス Claude 起動を `run_in_background` PID ベースから `docker run -d` container ベースに完全移行する。PID 管理パターン・`command-log` ベース stuck 検出・ホスト直接実行フォールバックは SKILL.md から完全削除する
- **根拠**:
  - CISO 最低条件の read-only rootfs / egress allowlist / non-root 実行を spike-loop にも適用する必要がある
  - PID ベースでは `kill <PID>` + `pgrep` でプロセス終了を管理するが、コンテナでは `docker stop` で一括管理でき簡潔になる
  - Phase 2-3 (#270) で install.sh が `full` プリセット時に Docker 必須化する方針と整合する
- **代替案**: Docker 未導入環境向けにホスト直接実行フォールバックを残す案 → 却下。2 モード混在はメンテナンスコストが高く、受け入れ基準「コンテナライフサイクルで動作」と矛盾する

### 2026-04-12: docker logs --since 無音カウンタ方式の採用（Issue #267 / Phase 1-2）

- **判断**: stuck 検出を `command-log` 最終タイムスタンプ比較から `docker logs --since=30s | wc -l` の無音カウンタ方式に変更する。30 秒間隔でポーリングし、0 行が 10 分（600 秒）続いたら stuck と判定する
- **根拠**:
  - Phase 1-1 のコンテナイメージは vibecorp の command-log hook を持たないため、command-log は container 内に存在しない
  - `docker logs --since=30s` はタイムスタンプ parse 不要で、BSD/GNU `date` の互換性問題を回避できる
  - 起動直後のログ空状態も自然に処理できる（最初の 600 秒は待機扱い）
- **代替案**: `docker logs --timestamps` のタイムスタンプを parse して経過時間を計算する案 → 却下（BSD/GNU `date -d` 互換問題が発生する）

### 2026-04-12: SESSION_ID ファイル永続化による孤立コンテナ検出設計（Issue #267 / Phase 1-2）

- **判断**: spike-loop セッション開始時に `.current-session` ファイルに `$(date +%s)` を保存し、全 run_N の container 名を `vibecorp-spike-loop-${SESSION_ID}-${RUN_N}` で一意化する
- **根拠**:
  - Bash ツールは呼び出しごとに shell を再生成するため `$$`（PID）が呼び出しごとに変わり、container 名の prefix として使えない
  - ファイル経由で SESSION_ID を共有することで、shell 再生成の影響を受けずに全 run_N を同一セッションに束ねられる
  - 孤立コンテナクリーンアップ時に `--filter "name=vibecorp-spike-loop-${SESSION_ID}"` で自セッションの container のみ対象にでき、並列 spike-loop 実行時も安全
- **代替案**: `uuidgen` による UUID 方式 → 却下（追加依存。epoch で十分一意化できる）

### 2026-04-12: worktree ↔ コンテナの 2 マウント + GIT_DIR 環境変数方式（Issue #268 / Phase 2-1）

- **判断**: worktree 作業ディレクトリを `/workspace`（RW）、リポジトリの `.git/` を `/repo-git`（RO）にマウントし、`GIT_DIR` / `GIT_WORK_TREE` 環境変数で git メタデータの場所を指定する
- **根拠**:
  - worktree 内の `.git` は `gitdir: <絶対パス>` のポインタファイルであり、コンテナ内でホスト側の絶対パスが解決できない
  - 環境変数方式はホスト側ファイルの書き換えが不要で、並列実行時の競合が発生しない
  - コンテナ終了後のクリーンアップも不要
- **代替案**:
  - `.git` ポインタファイル書き換え → 却下（ホスト側変更が必要、並列競合リスク）
  - `git clone --shared` → 却下（余分な I/O、ブランチ同期の複雑さ）

### 2026-04-12: git push に gh CLI HTTPS token 方式を採用、deploy key 不要（Issue #268 / Phase 2-1）

- **判断**: `git push` は gh CLI の credential helper 経由で HTTPS + fine-grained PAT で認証する。deploy key は不要
- **根拠**:
  - gh CLI は `git credential helper` として登録されており、`git push` 時に自動で `GH_TOKEN` を使って HTTPS 認証する
  - SSH プロトコルを使わないため `.ssh` マウント禁止（CISO #4）と矛盾しない
  - deploy key は生成→登録→削除の運用が複雑で、GitHub API rate limit リスクもある
- **代替案**:
  - 使い捨て deploy key → 却下（運用複雑、rate limit リスク）
  - 永続 deploy key → 却下（SSH agent or `GIT_SSH_COMMAND` が必要、CISO #4 との整合が微妙）

### 2026-04-12: ship-parallel のコンテナ化 — TeamCreate + Agent から docker run への移行（Issue #269 / Phase 2-2）

- **判断**: ship-parallel の並列実行アーキテクチャを TeamCreate + Agent + SendMessage から docker run + docker logs に完全移行する。各 worktree を個別コンテナにマウントして `/ship --worktree` を実行する
- **根拠**:
  - TeamCreate + Agent はコンテナ境界を越えてホスト側のツール API にアクセスでき、隔離が不完全
  - docker run 方式では各 `/ship` が物理的にコンテナ内に閉じ込められ、CISO 最低条件（read-only rootfs, non-root, seccomp）を自動的に満たす
  - spike-loop（Phase 1-2）で確立した docker logs --since 無音カウンタ方式を流用でき、監視ロジックが統一される
- **代替案**: TeamCreate + Agent をコンテナ内から呼び出す案 → 却下（Agent ツールはホスト側の Claude Code プロセスと通信するため、コンテナ内からの利用は設計上不整合）

### 2026-04-12: ship 単体実行のコンテナ化 — VIBECORP_IN_CONTAINER によるネスト防止（Issue #269 / Phase 2-2）

- **判断**: `/ship` を直接呼んだ場合もコンテナ内で実行する。ship-parallel 経由で既にコンテナ内にいる場合は `VIBECORP_IN_CONTAINER=1` 環境変数で検出してコンテナ起動をスキップする
- **根拠**:
  - 単体 `/ship` もヘッドレス実行の経路であり、コンテナ隔離の対象
  - ネスト防止がないと docker-in-docker が発生し、セキュリティモデルが複雑化する
  - 環境変数による判定はシンプルで、worktree モード（`--worktree`）との組み合わせも自然に処理できる
- **代替案**: docker socket をコンテナ内にマウントして docker-in-docker を許可する案 → 却下（docker socket マウントはコンテナエスケープの代表的ベクター）

### 2026-04-12: autopilot のコンテナ化 — メインループ自体をコンテナ内で実行（Issue #269 / Phase 2-2）

- **判断**: autopilot の diagnose → ship-parallel サイクル全体をコンテナ内で実行する。`VIBECORP_IN_CONTAINER=1` が設定されている場合はコンテナ起動をスキップ
- **根拠**:
  - autopilot は `--auto` モードで完全自律実行が可能であり、ホスト環境への影響を最小化すべき
  - コンテナ内の autopilot が ship-parallel を呼ぶと、ship-parallel はさらにコンテナを起動する（docker-in-docker にはならない、ship-parallel のコンテナ起動は worktree マウントのためホスト側から実行）
- **代替案**: autopilot はホスト側で実行し、ship-parallel のみコンテナ化する案 → 却下（autopilot 自体もヘッドレス実行であり、一貫した隔離ポリシーが必要）

### 2026-04-12: Team 機能経由のサブエージェントはコンテナ化により自動的に境界内に閉じ込められる設計判断（Issue #269 / Phase 2-2）

- **判断**: ship-parallel が docker run で各 `/ship` をコンテナとして起動する設計に移行したことで、Team 機能（TeamCreate + Agent + SendMessage）はコンテナ内から利用されなくなる。各コンテナ内の Claude プロセスは物理的にコンテナ境界を越えられない
- **根拠**:
  - TeamCreate/SendMessage は Claude Code のプロセス間通信機能であり、コンテナ内のプロセスがホスト側のプロセスと通信するには明示的なネットワーク設定が必要
  - コンテナは `--cap-drop ALL` + `no-new-privileges` で起動されるため、権限昇格によるコンテナエスケープも防止される
  - 追加の SKILL.md 変更や hooks は不要であり、コンテナ化の副産物として自然に実現される
- **代替案**: 明示的に TeamCreate/SendMessage を禁止する hooks を追加する案 → 不要（コンテナ境界が物理的に防止するため、ソフトウェア的なブロックは冗長）

### 2026-04-12: gh CLI 認証は GH_TOKEN 環境変数のみ、.config/gh マウント不要（Issue #268 / Phase 2-1）

- **判断**: `$HOME/.config/gh` のマウントを省略し、`/run/secrets/github_token` からの `GH_TOKEN` 展開のみで gh CLI を運用する
- **根拠**:
  - gh CLI は `GH_TOKEN` 環境変数を `hosts.yml` より優先するため、設定ファイルのマウントが不要
  - read-only マウントの場合、OAuth token refresh 時に書き込みエラーが発生するリスクがある
  - fine-grained PAT は refresh 不要のため、`GH_TOKEN` のみで安定動作する
- **代替案**: `.config/gh` を read-only マウント → 不要と判断（`GH_TOKEN` が優先されるため冗長）
