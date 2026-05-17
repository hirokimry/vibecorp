#!/usr/bin/env bash
# release.yml「git ユーザー設定」ステップ用スクリプト
# semantic release のタグ作成・push を github-actions[bot] 名義で実行できるよう設定する
set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
