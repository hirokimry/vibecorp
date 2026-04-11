# COO 判断記録

## 2026-04-11: コンテナ化構想の運用評価

### 背景

オーナーから「`claude --dangerously-skip-permissions` を安全に使うためにコンテナ化隔離」の構想について運用評価の依頼。

### 判断

段階導入推奨。具体的には「spike-loop 等の自動実行のみコンテナ化 → 安定したら拡大」の順序が現実的。

### 根拠

1. **現行アーキテクチャとコンテナの摩擦が大きい**
   - ship-parallel: `git worktree add` でリポジトリ外（`../project.worktrees/`）にパスを展開する。コンテナ内では相対パスが消えるためボリュームマウント設計の再考が必要
   - spike-loop: ホスト側の `claude` CLI プロセスを子プロセスとして PID 管理する。コンテナ境界を越えた PID 管理は別の問題を生む
   - hooks: command-log.sh, protect-branch.sh 等がホストの git/gh に依存。ゲストから gh 認証を引き継ぐための設定が必要
   - state/: `.claude/state/` をコンテナ内に閉じると親セッションからの可視性が失われる

2. **一人運用のメンテコストが高い**
   - Dockerfile/compose のメンテ、gh auth の引き継ぎ、IDE 連携（ファイル補完、デバッガ）の再設定
   - `--dangerously-skip-permissions` を使う局面は既に spike-loop に `--permission-mode dontAsk` で代替されている

3. **MVV「導入の手軽さ」との緊張**
   - vibecorp はテンプレートとして配布するプロダクト。コンテナ必須化はセットアップ摩擦を増やす

### エスカレーション不要

判断は明確（段階導入推奨）。MVV解釈の迷いなし。

