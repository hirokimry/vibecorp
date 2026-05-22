---
description: vibecorp の品質基準。参照元プロジェクトの実装を全網羅し、それを超えることを前提とする
paths: ["**/*"]
---

# 🎯 品質基準: 参照元を超える

> [!IMPORTANT]
> 参照元プロジェクトのパスは環境変数 `VIBECORP_REFERENCE_DIR` で指定する。**本ルールは `VIBECORP_REFERENCE_DIR` が設定されている場合にのみ MUST として作用する。未設定時はルール全体をスキップする**。
> 設定時は: vibecorp が生成するテンプレート（hooks / skills / agents / rules 等）は、参照元プロジェクト（`T-00分析: .claude/plans/T-00_analysis.md`）の実装を **全て網羅した上で、品質・汎用性・堅牢性で上回る**。
> 「たぶんこうだろう」で実装しない。設定時は実装前に必ず参照元の対応ファイルを読む。

本ルールは `VIBECORP_REFERENCE_DIR` が設定されている場合に、参照元プロジェクトの実装に劣るアウトプットを禁じる。網羅 → 改善 → 汎用化 → テスト の 4 段で常に品質を底上げする。`VIBECORP_REFERENCE_DIR` 未設定時は本ルール全体がスキップされる。

## 🎯 対象範囲

| 対象 | 適用 |
|------|------|
| `hooks/` 配下の新規 / 改修 | ✅ 適用する |
| `skills/` 配下の新規 / 改修 | ✅ 適用する |
| `.claude/agents/` の新規 / 改修 | ✅ 適用する |
| `.claude/rules/` の新規 / 改修 | ✅ 適用する |
| `.claude/knowledge/` の新規 / 改修 | ✅ 適用する |
| `.claude/settings.json` の改修 | ✅ 適用する |

## ✅ 指針（MUST、`VIBECORP_REFERENCE_DIR` 設定時）

`VIBECORP_REFERENCE_DIR` が設定されている場合、実装時のチェックリスト 4 段を必ず通す（未設定時は本セクション全体をスキップする）。

| # | 項目 | 内容 |
|---|------|------|
| 1 | **網羅確認** | 実装対象のファイルについて、参照元の該当ファイルを必ず読み、機能を漏れなくカバーしているか確認する |
| 2 | **品質向上** | 参照元にあったエッジケース未対応 / エラーハンドリング不足 / ハードコード等を改善する |
| 3 | **汎用化** | 参照元でプロジェクト固有だった部分を適切にパラメータ化する |
| 4 | **テスト** | 参照元にテストがあればそれ以上のカバレッジ、なければ新規にテストを書く |

## ❌ 禁止パターン

- ❌ 参照元を読まずに「たぶんこうだろう」で実装する
- ❌ 参照元の機能を取りこぼす（網羅不足のまま PR を出す）
- ❌ 参照元のエッジケース未対応・ハードコードをそのまま引き継ぐ
- ❌ 参照元にテストがあるのに、新規実装でテストを書かない

## 📁 参照元の確認方法（`VIBECORP_REFERENCE_DIR` 設定時）

参照元プロジェクトのパスは環境変数 `VIBECORP_REFERENCE_DIR` で指定する。設定されている場合のみ以下を適用する（未設定時は本セクション全体をスキップする）。

| 種別 | 参照パス |
|------|---------|
| hooks | `${VIBECORP_REFERENCE_DIR}/.claude/hooks/` |
| skills | `${VIBECORP_REFERENCE_DIR}/skills/`（Plugin ルート） |
| agents | `${VIBECORP_REFERENCE_DIR}/.claude/agents/` |
| rules | `${VIBECORP_REFERENCE_DIR}/.claude/rules/` |
| knowledge | `${VIBECORP_REFERENCE_DIR}/.claude/knowledge/` |
| settings | `${VIBECORP_REFERENCE_DIR}/.claude/settings.json` |

`VIBECORP_REFERENCE_DIR` が設定されている場合は、実装前に必ず参照元の対応ファイルを読む（未設定時はスキップ）。

## 🔗 関連ルール

- プリセット自己完結: `self-contained.md`
- スキル使用義務: `use-skills.md`
- テスト追加義務: `testing.md`
