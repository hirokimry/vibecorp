---
description: vibecorp の品質基準。参照元プロジェクトの実装を全網羅し、それを超えることを前提とする。
paths: ["**/*"]
---

# 品質基準: 参照元を超える

## 原則

vibecorp が生成するテンプレート（hooks, skills, agents, rules 等）は、
参照元プロジェクト（T-00分析: .claude/plans/T-00_analysis.md）の実装を
**全て網羅した上で、品質・汎用性・堅牢性で上回る**こと。

## 実装時のチェックリスト

1. **網羅確認**: 実装対象のファイルについて、参照元の該当ファイルを必ず読み、機能を漏れなくカバーしているか確認する
2. **品質向上**: 参照元にあったエッジケース未対応、エラーハンドリング不足、ハードコードなどを改善する
3. **汎用化**: 参照元でプロジェクト固有だった部分を適切にパラメータ化する
4. **テスト**: 参照元にテストがあればそれ以上のカバレッジ、なければ新規にテストを書く

## 参照元の実装を確認する方法

参照元プロジェクトのパスは環境変数 `VIBECORP_REFERENCE_DIR` で指定する。未設定時はスキップ可。

- hooks: `${VIBECORP_REFERENCE_DIR}/.claude/hooks/`
- skills: `${VIBECORP_REFERENCE_DIR}/.claude/skills/`
- agents: `${VIBECORP_REFERENCE_DIR}/.claude/agents/`
- rules: `${VIBECORP_REFERENCE_DIR}/.claude/rules/`
- knowledge: `${VIBECORP_REFERENCE_DIR}/.claude/knowledge/`
- settings: `${VIBECORP_REFERENCE_DIR}/.claude/settings.json`

実装前に必ず参照元の対応ファイルを読むこと。「たぶんこうだろう」で実装しない。
