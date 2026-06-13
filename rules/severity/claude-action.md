# 🤝 claude-code-action severity 実体版

> [!IMPORTANT]
> 本ファイルは `.claude/rules/severity/coderabbit.md`（CodeRabbit 公式仕様）の **定義を実体としてコピーした** vibecorp 保有版。
> 外部依存を最小化し、vibecorp 単独でも判定基準が完結するように保持する。
> 定義は CodeRabbit と **完全に一致** させ、公式変更時は同時追従する。
> ⚠️ ファイル名は `claude-action.md` のままだが、レビューは Issue #531 で vibehawk へ移譲済み（ファイル名リネームは別 Issue）。

CodeRabbit と vibehawk の判定軸を **完全に揃える** ためのファイル。

## 🎯 役割

本ファイルは vibecorp の severity 定義の Source of Truth。

- 性質: CodeRabbit 公式定義からのコピー実体。
- 同期対象: `.claude/rules/severity/coderabbit.md`（CodeRabbit 公式仕様の記録）と定義を完全一致させる。
- 注入先（Issue #531）: `vibehawk.enabled: true` 運用時、severity を含む vibecorp 独自の判断軸は `.vibehawk.yaml` の `reviews.path_instructions` に注入される。
  - 旧構成では `REVIEW.md`（claude-code-action のプロンプト）から参照されていたが、レビュー移譲により注入先が変わった。
  - severity 定義の内容・CodeRabbit との完全一致は不変。

## 📊 severity 5 段階（vibecorp 実体版）

| Marker | severity | 定義（重大度の意味） |
|--------|---------|------|
| 🔴 | Critical | システム障害、セキュリティ侵害、データ損失を引き起こす重大な問題 |
| 🟠 | Major | 機能・パフォーマンスに大きく影響する重要な問題 |
| 🟡 | Minor | 対応すべきだがシステムに致命的な影響はない問題 |
| 🔵 | Trivial | コード品質を高めるための軽微な提案 |
| ⚪ | Info | 情報提供のみ、対応不要 |

> [!NOTE]
> 本テーブルは severity の **定義**（重大度の意味）を CodeRabbit と完全一致させて記録する。
> **修正対象とするかどうかの判定** は `.claude/rules/review-handling.md` が別途行う（vibecorp 独自運用ルール）。
> 特に Info は CodeRabbit デフォルトでは「対応不要」だが、vibecorp は **判定の側で**「重視軸該当なら対応」に拡張する（severity 定義そのものは変えない）。

## 🔄 CodeRabbit 定義との同期

`.claude/rules/severity/coderabbit.md`（CodeRabbit 公式仕様の記録）と本ファイルの定義は **完全に一致** させる。

- 同期条件: CodeRabbit 公式が定義を変更した場合、両方を同時に追従する。

## 🛠️ vibehawk での使用

`vibecorp.yml` の `vibehawk.enabled: true` で vibehawk を運用する場合、本ファイルの severity 定義を含む判断軸は `.vibehawk.yaml` の `reviews.path_instructions` に注入される。

- 流れ: vibehawk がレビュー指摘を出し、`.claude/rules/review-handling.md` の捌き基準（intent × severity）に従って review-fix（`pr-fix` / `review-loop`）が修正対象を判定する。
- vibehawk の severity 5 段階はツール側に内蔵されており、本ファイルは CodeRabbit / vibehawk との severity 定義の同期記録として保持される（`.claude/rules/severity/coderabbit.md` と同じ役割）。
- `vibehawk.enabled: false`（例: CodeRabbit 単独運用）でも、本ファイルの severity 定義は CodeRabbit 側との同期記録として保持される。

## 🔗 関連ルール

- 公式定義の記録: `.claude/rules/severity/coderabbit.md`
- 捌き基準（intent × severity）: `.claude/rules/review-handling.md`
- レビュー観点: `.claude/rules/review-observations.md`
- プロンプト作成基準: `.claude/rules/prompt-writing.md`
- マークダウン規約: `.claude/rules/markdown.md`
