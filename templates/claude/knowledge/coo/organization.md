# 組織運用ナレッジ

docs/ai-organization.md の組織構成と MVV.md から導出される、COO の判断基準。
AI組織構成は `docs/ai-organization.md` を参照すること。

## 組織構成

<!-- プロジェクトに合わせてエージェント構成を記述する -->

| ロール | 判断方式 | 管轄ドキュメント |
|--------|---------|----------------|
| COO（番頭） | 単独判断 | docs/ai-organization.md |
| CTO | 単独判断 | docs/specification.md |
| CPO | 単独判断 | docs/specification.md |
| CFO + 経理チーム | 合議制（多数決） | docs/cost-analysis.md |
| CLO + 法務チーム | 合議制（全会一致） | docs/POLICY.md |
| CISO + セキュリティチーム | 合議制（全会一致） | docs/SECURITY.md |

## 管轄ファイルマッピング

<!-- 各エージェントが編集権限を持つファイルを記述する -->
<!-- role-gate.sh による書き込み制御と一致させること -->

| エージェント | 管轄パス |
|-------------|---------|
| CTO | .claude/knowledge/cto/, .claude/rules/ |
| CPO | .claude/knowledge/cpo/, docs/specification.md |
| COO | .claude/knowledge/coo/, docs/ai-organization.md |
| CFO | .claude/knowledge/cfo/, docs/cost-analysis.md |
| CLO | .claude/knowledge/clo/, docs/POLICY.md |
| CISO | .claude/knowledge/ciso/, docs/SECURITY.md |

## ナレッジ配置場所

| ディレクトリ | 用途 |
|-------------|------|
| .claude/knowledge/cto/ | 技術判断原則・判断記録 |
| .claude/knowledge/cpo/ | プロダクト原則・判断記録 |
| .claude/knowledge/coo/ | 組織運用ナレッジ・判断記録 |
| .claude/knowledge/cfo/ | コスト判断記録 |
| .claude/knowledge/clo/ | 法務判断記録 |
| .claude/knowledge/ciso/ | セキュリティ判断記録 |
| .claude/knowledge/accounting/ | 経理分析員の判断基準 |
| .claude/knowledge/legal/ | 法務分析員の判断基準 |
| .claude/knowledge/security/ | セキュリティ分析員の判断基準 |

## 段階的導入計画

<!-- プロジェクトの導入フェーズに合わせて記述する -->

| フェーズ | 内容 | エージェント |
|---------|------|------------|
| minimal | 基本開発フロー | なし（hooks + rules のみ） |
| standard | CTO + CPO レビュー | CTO, CPO |
| full | 全エージェント + 合議制チーム | COO, CTO, CPO, CFO, CLO, CISO + 分析員 |
