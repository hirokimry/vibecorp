# C*O decisions.md → decisions-index.md + 四半期アーカイブ 移行ガイド

## 背景

C*O エージェント（CISO/CTO/CPO/CFO/CLO/SM）は workflow step 1「情報収集」で毎回 `.claude/knowledge/{role}/decisions.md` を Read する。append-only で肥大化する構造のため、CISO では 631 行 / 約 40KB に達し、サブエージェント起動のたびに全量がトークンコストに乗る問題が発生した（Issue #335）。

## 新構造

```text
.claude/knowledge/{role}/
├── decisions-index.md           # 目次（毎起動 Read、小さく保つ）
└── decisions/
    ├── 2026-Q1.md               # 四半期アーカイブ（関連時のみ Read）
    ├── 2026-Q2.md
    └── ...
```

- **decisions-index.md**: 1 エントリ 1 行のサマリを新しい順で並べる目次
- **decisions/YYYY-QN.md**: 判断の詳細本文を四半期単位で保持するアーカイブ

## 書式仕様

### インデックスエントリ

1 エントリ = 1 行:

```text
- YYYY-MM-DD — Issue #NNN または CR-NNN または トピック名 — 結論の一行要約
```

例:

```text
- 2026-04-16 — Issue #309 sandbox-exec PoC Phase 1 — REQUEST_CHANGES（必須修正3点）
- 2026-04-18 — プリセット別安全性評価 — full = sandbox + skip-permissions 前提
```

### アーカイブの見出し形式

各エントリは H2 見出しで記述する:

```markdown
## YYYY-MM-DD — タイトル

本文（判断、根拠、代替案 等）
```

H1 はファイル先頭に 1 つだけ:

```markdown
# {ROLE} 判断記録 YYYY-QN
```

### 四半期計算式（共通仕様）

日付 `YYYY-MM-DD` から:

| 月（MM） | 四半期 |
|---------|--------|
| 01-03 | YYYY-Q1 |
| 04-06 | YYYY-Q2 |
| 07-09 | YYYY-Q3 |
| 10-12 | YYYY-Q4 |

## 既存環境の移行手順

既に `.claude/knowledge/{role}/decisions.md`（旧形式）を持つ vibecorp 導入リポジトリの管理者向け。

### 対象読者

- 運用中に agents が `decisions.md` に追記した履歴を持つリポジトリ
- `install.sh --update` 実行済みで agents は新版に差し替え済みだが knowledge 配下の `decisions.md` は残存している状態（install.sh は knowledge 配下を削除しない）

### 手順

```bash
# Step 1: バックアップ
cp .claude/knowledge/{role}/decisions.md .claude/knowledge/{role}/decisions.md.bak

# Step 2: 四半期ごとにエントリを分割
# H2（例: `## 2026-04-16 — ...`）または H3（`### 2026-04-16: ...`）の日付から四半期を判定
mkdir -p .claude/knowledge/{role}/decisions
# 各エントリブロックを適切な YYYY-QN.md に振り分ける（手動または分割スクリプト）

# Step 3: decisions-index.md を作成
# 各エントリの日付・タイトル・結論を 1 行サマリに整理し、新しい順に列挙

# Step 4: 確認
# 移行前後のエントリ数が一致することを確認
grep -c "^## \|^### 20" .claude/knowledge/{role}/decisions.md.bak
grep -c "^## 20" .claude/knowledge/{role}/decisions/*.md
grep -c "^- 20" .claude/knowledge/{role}/decisions-index.md

# Step 5: 動作確認後にバックアップ削除
rm .claude/knowledge/{role}/decisions.md.bak
rm .claude/knowledge/{role}/decisions.md
```

### 確認コマンド

移行の正確性は以下で検証する:

```bash
# 旧ファイルの H2 + H3 日付見出し数
grep -cE "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}|^### 20[0-9]{2}-[0-9]{2}-[0-9]{2}" decisions.md.bak

# 新アーカイブの H2 数の合計（全四半期ファイル）
grep -cE "^## 20" decisions/*.md | awk -F: '{sum += $2} END { print sum }'

# 新インデックスのエントリ行数
grep -cE "^- 20" decisions-index.md
```

3 つの値が一致すれば分割は完全。

## 互換性

### エージェント側の fallback

C*O エージェント step 1 は以下の優先度で Read する:

1. `decisions-index.md` が存在 → index を読み、関連アーカイブを追加 Read
2. `decisions-index.md` 不在 & `decisions.md` 存在 → legacy モードで `decisions.md` を Read
3. どちらも不在 → 空として扱う

step 4（記録）も同様に fallback する。両方存在する場合は新形式（decisions-index.md）を優先。

### 移行タイミング

肥大化していない legacy 環境（例: CFO / SM で数エントリのみ）は無理に移行しなくてよい。現状の `decisions.md` を使い続けられる。

肥大化が顕在化（数百行・数十 KB 級）した時点で本手順に従って分割する。

## 肥大化時の 2 次分割方針（将来）

単一四半期アーカイブが 1,000 行を超えた場合の月次分割（`decisions/2026-Q2-05.md` 等）の判断基準は本 Issue では未定義（YAGNI）。

現状どの role も単一 Q で 1,000 行未満。肥大化が顕在化した段階で別 Issue で定義する。

## 関連 Issue

- Issue #335: C*O decisions.md をインデックス + アーカイブ 2 段構成に分割
