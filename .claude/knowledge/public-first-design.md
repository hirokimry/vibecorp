# Public First 設計 — OSSを前提としたリポジトリ運用

## 背景

「最終的に出来が良かったら世に出したい」というケースで、
最初から Public 前提で設計すべきか、Private で育てて後から Public にすべきかを検討した。

## 結論: 最初から Public 前提で設計する

### 理由
- Private で開発して後から Public にすると「やばいものが混入してた」リスクがある
- git history は後から消すのが困難（rebase しても GitHub のキャッシュに残りうる）
- 最初から Public 前提なら、全コミットで自然とガードレールが効く

### ただし公開タイミングは分ける
- 開発中は Private のまま（未完成品を公開しない）
- 中身が整ったタイミングで Public に切り替え

## git history の安全性

### develop ブランチ問題
- develop ブランチで開発メモ（特定プロダクト名等）を含むコミットをしてしまうと、
  Public 化時に squash merge で main は綺麗にできても、develop の履歴はリモートに残る
- ブランチ削除しても GitHub は dangling commit を一定期間保持する
- GC タイミングは非公開で制御できない

### 対策
- 機密性のあるファイル（plans/ 等）は .gitignore 対象にする
- または Public 化時に新リポジトリを作り、main の最新だけを push する

### 今回の設計
- .claude/ 全体を .gitignore にした
- plans/, rules/, knowledge/ はローカル専用。Claude Code はファイルシステムから読むので問題なし
- git に載るのは templates/, docs/, install.sh, tests/ のみ（全て Public 可能な内容）

## 守るべきルール

1. シークレット、トークン、APIキー、パスワードを絶対にコミットしない
2. 特定の別リポジトリやプロダクト名を直接記載しない
3. ローカル環境・ユーザー設定への依存を作らない
4. コミットメッセージは公開されても恥ずかしくない内容にする
5. WIP、仮置き、デバッグ用コードをコミットしない
