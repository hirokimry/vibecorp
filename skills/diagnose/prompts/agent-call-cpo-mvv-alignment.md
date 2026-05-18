以下の観点でコードベースを分析し、MVV・プロダクト方針に沿っていない箇所をリストアップしてください:
- MVV.md のバリューに属さない機能の検出（例: 規律の自動化に寄与しないフック）
- docs/specification.md / docs/design-philosophy.md と矛盾する実装
- 追加されたが使われていない機能（dead feature）
- プリセット間でのスコープ漏れ（full 専用機能が standard に露出している等）
