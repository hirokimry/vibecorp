#!/usr/bin/env bash
# release.yml「リリース判定・実行」ステップ用スクリプト
# Conventional Commits を解析し、semver を算出してタグ作成 + GitHub Release を生成する
# 環境変数: GH_TOKEN（gh CLI 用、workflow 側から secrets.GITHUB_TOKEN を渡す）
set -euo pipefail

LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LATEST_TAG" ]; then
  # 初回リリース判定: タグが無いので全コミットを対象にし、起点バージョンを v0.1.0 とする
  COMMITS=$(git log --pretty=format:'%s%x1f%H%x1f%h%x1e' HEAD)
  CURRENT_MAJOR=0
  CURRENT_MINOR=1
  CURRENT_PATCH=0
  FIRST_RELEASE=true
else
  COMMITS=$(git log --pretty=format:'%s%x1f%H%x1f%h%x1e' "${LATEST_TAG}..HEAD")
  VERSION_STR="${LATEST_TAG#v}"
  CURRENT_MAJOR=$(echo "$VERSION_STR" | cut -d. -f1)
  CURRENT_MINOR=$(echo "$VERSION_STR" | cut -d. -f2)
  CURRENT_PATCH=$(echo "$VERSION_STR" | cut -d. -f3)
  FIRST_RELEASE=false
fi

if [ -z "$COMMITS" ]; then
  # 復旧パス: 前回の release create 失敗で GitHub Release のみ欠落しているケースを補完する
  if [ -n "$LATEST_TAG" ] && ! gh release view "${LATEST_TAG}" > /dev/null 2>&1; then
    echo "新しいコミットはありませんが、${LATEST_TAG} の GitHub Release が無いため作成します"
    gh release create "${LATEST_TAG}" \
      --title "${LATEST_TAG}" \
      --generate-notes
    echo "リリース完了: ${LATEST_TAG}"
    exit 0
  fi
  echo "新しいコミットがないためリリースをスキップ"
  exit 0
fi

# BUMP_LEVEL は semver の段階: 0=none, 1=patch, 2=minor, 3=major（数値の大小で「採用すべき bump」を最大化）
BUMP_LEVEL=0

FEAT_COMMITS=""
FIX_COMMITS=""
REFACTOR_COMMITS=""
DOCS_COMMITS=""
BREAKING_COMMITS=""
OTHER_COMMITS=""

while IFS=$'\x1f' read -r -d $'\x1e' subject full_hash short_hash; do
  [ -z "$subject" ] && continue

  BODY=$(git log -1 --pretty=format:"%b" "$full_hash" 2>/dev/null || echo "")
  IS_BREAKING=false
  if echo "$subject" | grep -qE '^[^:]*!:' || echo "$BODY" | grep -q "BREAKING CHANGE:"; then
    IS_BREAKING=true
  fi

  # 絵文字プレフィックスが付いた CC タイトルでも type を抽出できるよう先頭の非英字を除去する
  CLEAN_SUBJECT=$(echo "$subject" | sed 's/^[^a-zA-Z]* *//')

  TYPE=$(echo "$CLEAN_SUBJECT" | sed -n 's/^\([a-zA-Z]*\)\(([^)]*)\)\{0,1\}[!]\{0,1\}:.*/\1/p')

  DESC=$(echo "$subject" | sed 's/^[^:]*: *//')

  if [ "$IS_BREAKING" = true ]; then
    [ "$BUMP_LEVEL" -lt 3 ] && BUMP_LEVEL=3
    BREAKING_COMMITS="${BREAKING_COMMITS}- ${DESC} (${short_hash})\n"
  fi

  case "$TYPE" in
    feat)
      [ "$BUMP_LEVEL" -lt 2 ] && BUMP_LEVEL=2
      FEAT_COMMITS="${FEAT_COMMITS}- ${DESC} (${short_hash})\n"
      ;;
    fix)
      [ "$BUMP_LEVEL" -lt 1 ] && BUMP_LEVEL=1
      FIX_COMMITS="${FIX_COMMITS}- ${DESC} (${short_hash})\n"
      ;;
    refactor)
      [ "$BUMP_LEVEL" -lt 1 ] && BUMP_LEVEL=1
      REFACTOR_COMMITS="${REFACTOR_COMMITS}- ${DESC} (${short_hash})\n"
      ;;
    docs)
      [ "$BUMP_LEVEL" -lt 1 ] && BUMP_LEVEL=1
      DOCS_COMMITS="${DOCS_COMMITS}- ${DESC} (${short_hash})\n"
      ;;
    chore|ci|test)
      # chore / ci / test は BUMP_LEVEL を上げずに OTHER に蓄積（リリースノートの「その他」枠用）
      OTHER_COMMITS="${OTHER_COMMITS}- ${DESC} (${short_hash})\n"
      ;;
    *)
      if [ -n "$TYPE" ]; then
        # 未知の type は patch 扱いに倒す（取りこぼしを避けるための安全側）
        [ "$BUMP_LEVEL" -lt 1 ] && BUMP_LEVEL=1
        OTHER_COMMITS="${OTHER_COMMITS}- ${DESC} (${short_hash})\n"
      else
        # CC 形式でないコミットはバージョン bump 対象に含めない
        OTHER_COMMITS="${OTHER_COMMITS}- ${subject} (${short_hash})\n"
      fi
      ;;
  esac
done < <(printf '%s' "$COMMITS")

if [ "$BUMP_LEVEL" -eq 0 ]; then
  echo "リリース対象のコミットがないためスキップ（chore/ci/test のみ）"
  exit 0
fi

if [ "$FIRST_RELEASE" = true ]; then
  NEW_VERSION="0.1.0"
else
  case "$BUMP_LEVEL" in
    3)
      NEW_MAJOR=$((CURRENT_MAJOR + 1))
      NEW_VERSION="${NEW_MAJOR}.0.0"
      ;;
    2)
      NEW_MINOR=$((CURRENT_MINOR + 1))
      NEW_VERSION="${CURRENT_MAJOR}.${NEW_MINOR}.0"
      ;;
    1)
      NEW_PATCH=$((CURRENT_PATCH + 1))
      NEW_VERSION="${CURRENT_MAJOR}.${CURRENT_MINOR}.${NEW_PATCH}"
      ;;
  esac
fi

NEW_TAG="v${NEW_VERSION}"
echo "リリースバージョン: ${NEW_TAG}"

RELEASE_NOTES=""

if [ -n "$BREAKING_COMMITS" ]; then
  RELEASE_NOTES="${RELEASE_NOTES}## ⚠️ 破壊的変更"$'\n'
  RELEASE_NOTES="${RELEASE_NOTES}$(printf '%b' "$BREAKING_COMMITS")"$'\n'
fi
if [ -n "$FEAT_COMMITS" ]; then
  RELEASE_NOTES="${RELEASE_NOTES}## ✨ 新機能"$'\n'
  RELEASE_NOTES="${RELEASE_NOTES}$(printf '%b' "$FEAT_COMMITS")"$'\n'
fi
if [ -n "$FIX_COMMITS" ]; then
  RELEASE_NOTES="${RELEASE_NOTES}## 🐛 バグ修正"$'\n'
  RELEASE_NOTES="${RELEASE_NOTES}$(printf '%b' "$FIX_COMMITS")"$'\n'
fi
if [ -n "$REFACTOR_COMMITS" ]; then
  RELEASE_NOTES="${RELEASE_NOTES}## 🔄 リファクタリング"$'\n'
  RELEASE_NOTES="${RELEASE_NOTES}$(printf '%b' "$REFACTOR_COMMITS")"$'\n'
fi
if [ -n "$DOCS_COMMITS" ]; then
  RELEASE_NOTES="${RELEASE_NOTES}## 📝 ドキュメント"$'\n'
  RELEASE_NOTES="${RELEASE_NOTES}$(printf '%b' "$DOCS_COMMITS")"$'\n'
fi

# 完全一致判定: -x で行全体マッチを要求し、v1.2.3 が v1.2.30 等に部分一致するのを防ぐ
if git tag -l | grep -qxF "${NEW_TAG}"; then
  echo "タグ ${NEW_TAG} は既に存在します"
  if ! gh release view "${NEW_TAG}" > /dev/null 2>&1; then
    echo "GitHub Release を作成します"
    gh release create "${NEW_TAG}" \
      --title "v${NEW_VERSION}" \
      --notes "$RELEASE_NOTES"
    echo "リリース完了: ${NEW_TAG}"
  else
    echo "GitHub Release も既に存在するためスキップ"
  fi
  exit 0
fi

git tag -a "${NEW_TAG}" -m "リリース v${NEW_VERSION}"
git push origin "${NEW_TAG}"

gh release create "${NEW_TAG}" \
  --title "v${NEW_VERSION}" \
  --notes "$RELEASE_NOTES"

echo "リリース完了: ${NEW_TAG}"
