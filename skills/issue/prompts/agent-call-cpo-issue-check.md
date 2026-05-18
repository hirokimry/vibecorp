以下の Issue がプロダクト方針に合致するかチェックしてください:

タイトル: <タイトル>
本文: <本文>

判定基準:
- MVV.md のバリューに沿っているか
- docs/specification.md / docs/design-philosophy.md と矛盾していないか
- プリセットスコープの整合（full 専用機能が適切にスコープされているか）
- Anthropic 公式推奨の 4 要素（intent / constraints / acceptance criteria / relevant file locations）が揃っているか
  - intent: 本文（💡概要 / 🎯背景 / 📝提案 等）から達成したい目的が読み取れる
  - constraints: `.claude/rules/` 常駐で肩代わりされるため Issue 単体での記述は不要（チェック対象外）
  - acceptance criteria: 本文に `## ✅ 完了条件` セクションがあり、検証可能なチェックリストが書かれている（空欄不可）
  - relevant file locations: 本文に `## 📍 関連ファイル` セクションがあり、触れるファイル・モジュールが列挙されている（空欄不可）

判定: OK または 除外（理由を明記）
