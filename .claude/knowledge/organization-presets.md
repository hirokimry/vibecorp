# AIエージェント組織の規模プリセット設計

## 背景

1つのプラグインで「個人開発」から「AI企業」まで対応するため、
組織規模をプリセットとして段階的に提供する設計を行った。

## 3つのプリセット

### minimal（個人〜小規模）

最小構成。エージェント定義なしでスキルだけで回る。

- agents: なし（スキル内で直接実行）
- skills: /review, /review-loop, /pr-merge-loop, /pr-review-fix, /pr, /commit
- hooks: protect-files
- docs/: なし
- knowledge/: なし（運用中に蓄積）

ポイント:
- CodeRabbit CLI 実行はスキル内のステップとして行う（agent不要）
- 「とりあえず入れてみる」のハードルを最小化
- MVV保護だけは最初から有効（品質の床を作る）

### standard（チーム開発）

CTO と CPO が判断する体制。レビュー修正ループが自動化される。

- agents: CTO, CPO（Role Agents）
- skills: minimal + /review-to-rules, /sync-check
- hooks: minimal + review-to-rules-gate, sync-gate
- docs/: specification.md
- knowledge/: cto/, cpo/（principles + decisions）

ポイント:
- review-to-rules-gate で merge 前に /review-to-rules を強制
- docs/ が Source of Truth として登場
- sync-gate で push 前に docs/knowledge の整合性チェックを強制

### full（AI企業）

C-suite 全員 + チーム分析員による組織運営。

- agents: C-suite全員（CTO, CPO, COO, CFO, CLO, CISO）+ 分析員（accounting, legal, security）
- skills: standard + /sync-edit
- hooks: standard + role-gate
- docs/: specification, POLICY, SECURITY, cost-analysis, ai-organization
- knowledge/: 全ロール（principles + decisions）

ポイント:
- チーム分析員は「同一プロンプトで3回独立実行 → C-suiteがメタレビュー」パターン
- role-gate でエージェントごとに編集可能ファイルを制限
- コンプライアンス（法務・セキュリティ・財務）を AI が自律的にチェック

## テンプレートの引き算方式

テンプレートは全プリセット分をフル装備で含む。install.sh がプリセットに応じて不要分を削除する。

- settings.json.tpl: 全フック入り → minimal では review-to-rules-gate を jq del
- hooks/skills: 全テンプレート同梱 → minimal では review-to-rules 関連を削除
- pr-merge-loop/SKILL.md: vibecorp.yml の gates.review_to_rules を参照して分岐

テンプレートは1つ、環境が振る舞いを決める。

## 設計のポイント

- プリセットはデフォルト値の束。個別フィールドで上書き可能
- 例: minimal だけど review_to_rules だけ有効にしたい → `gates.review_to_rules: true` を追記
- 必須項目は `name` のみ。他は全てデフォルトで動く
