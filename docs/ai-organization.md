# vibecorp AI 組織運用

> このドキュメントは AI エージェントによる組織運用の方針を定義する Source of Truth です。

## 基本思想

AI エージェントチームがプロダクト開発のあらゆる側面を担い、ユーザーは CEO として意思決定に集中する。vibecorp はスクラム開発を前提とする。

- プロダクト開発のあらゆる側面を AI エージェントチームが担う
- 各エージェントは専門領域を持ち、フラットな関係で協働する
- 全ての判断は MVV.md に基づく
- エージェント間に上下関係はなく、提案と調整で連携する
- 管轄外のファイルは role-gate フックにより自動的にブロックされる

## 組織構成

各エージェントは明確な管轄を持ち、管轄外のファイルは編集しない。

| ロール | 役割 | docs/ 編集権限 |
|--------|------|---------------|
| SM（Scrum Master） | プロセス管理・進捗把握・エージェント間調整・並列判定 | なし（プロセス管理のため直接編集しない） |
| CTO | コード品質・アーキテクチャ・技術的負債の番人 | `docs/specification.md` |
| CPO | プロダクト方針・仕様の番人 | `docs/specification.md`, `docs/screen-flow.md`, `docs/ai-prompt-design.md` |
| CFO | コスト分析・予算管理の統括 | なし（経理分析員に委任） |
| CLO | 法務・コンプライアンスの統括 | なし（法務分析員に委任） |
| CISO | セキュリティの統括 | なし（セキュリティ分析員に委任） |

### チーム構成

C-Level エージェントの下に専門分析員を配置し、詳細な分析・調査を委任する。

| チーム | C-Level | 分析員 | 分析員の役割 | docs/ 編集権限 |
|--------|---------|--------|-------------|---------------|
| 法務チーム | CLO | 法務分析員（legal） | ライセンス分析・コンプライアンスチェック | `docs/POLICY.md` |
| 経理チーム | CFO | 経理分析員（accounting） | API コスト計算・予算消化率の算出 | `docs/cost-analysis.md` |
| セキュリティチーム | CISO | セキュリティ分析員（security） | 脆弱性スキャン・セキュリティポリシー検証 | `docs/SECURITY.md` |

分析員は C-Level エージェントから呼び出され、結果を報告する。分析員が各管轄の docs/ ファイルを直接編集する権限を持つ（role-gate フックで制御）。

## ワークフロー × C*O ゲート マトリクス

`/ship` 等の自動化ワークフローでは、**そのフェーズで判断に必要な情報が揃う最初のタイミングで、判断を管轄する C*O（または平社員合議）を入れる**ことを原則とする。C*O は常時起動せず、**管轄領域に触れた差分を検知した時のみ起動**する。

### フェーズ × ゲート対応

| フェーズ | 対象スキル | 対象プリセット | 入れる役職 | 起動条件 |
|---|---|---|---|---|
| 1. Issue 起票 | `/issue` | standard / full | CPO | 常時 |
| 2. autopilot 候補フィルタ | `/diagnose` `/autopilot` | full | CPO + SM + CISO | 常時（3者承認） |
| 3a. 設計レビュー（平社員層） | `/plan-review-loop` | プリセット別デフォルト | plan-architect, plan-security, plan-testing, plan-performance, plan-dx, plan-cost, plan-legal | プリセット別 |
| 3b. 設計レビュー（C*O メタ層） | `/plan-review-loop` | full | CFO / CISO / CLO / SM / CPO / CTO | 条件起動（下記トリガー表） |
| 4. 実装 | `/ship` 内 | — | なし | — |
| 5. 実装レビュー（平社員合議） | `/review-loop` | full | security-analyst×3, accounting-analyst×3, legal-analyst×3 | 差分検知で条件起動 |
| 6. 実装レビュー（C*O メタ層） | `/review-loop` | full | 該当 C*O | 平社員合議で Major 以上 |
| 7. PR レビュー | `/pr-review-loop` | 全プリセット | CodeRabbit のみ | — |
| 8a. マージゲート（standard） | `/sync-check` | standard | CTO / CPO | 管轄領域に触れた時のみ |
| 8b. マージゲート（full） | `/sync-check` | full | CTO / CPO / CFO / CISO / CLO / SM | 管轄領域に触れた時のみ |
| 9. 事後監査 | `/audit-cost` `/audit-security` | full | CFO（週次コスト）/ CISO（月次セキュリティ） | 定期 |

### `plan.review_agents` のプリセット別デフォルト

`install.sh` が `vibecorp.yml` 生成時に以下を出力する（ユーザーは個別に追加・削除可能）。

| プリセット | デフォルト `plan.review_agents` |
|---|---|
| minimal | `[architect]` |
| standard | `[architect, security, testing]` |
| full | `[architect, security, testing, performance, dx, cost, legal]` |

### C*O 起動トリガー表（フェーズ 3b・5・6・8b 共通／full プリセット限定）

| トリガー | 起動 C*O | 平社員合議 |
|---|---|---|
| 実行モード / モデル / API 呼び出し変更、課金影響 | **CFO** | accounting-analyst×3 |
| 認証 / 権限 / 暗号 / secrets / データフロー変更 | **CISO** | security-analyst×3 |
| 依存追加・LICENSE / 規約・第三者リポジトリ参照 | **CLO** | legal-analyst×3 |
| エージェント定義 / hooks / rules / skills 変更 | **SM** | （単独） |
| 仕様 / UX / MVV 影響 | **CPO** | （単独） |
| アーキ / 技術選定 / 依存バージョン | **CTO** | （単独） |

### 設計の要点

- **C*O は常時起動しない**：差分検知に基づく条件起動でオーバーヘッドを抑える
- **平社員 → C*O の2段階**：平社員（×3 合議や `plan-*` 専門家）が一次フィルタ、C*O はメタレビューに専念
- **`plan-cost` と `plan-legal`**：CFO / CLO の代弁者として設計フェーズで起動
- **Issue 起票時は CPO のみ**：この段階で CFO / CISO / CLO を呼んでも判断材料不足
- **autopilot は 3 者承認**（CPO + SM + CISO）：自律実行は「やる価値 × 自動化適性 × 安全性」の 3 軸が必要

## 権限モデル

### 管轄ファイルの更新権限

- 各エージェントは自身の管轄ファイルのみ編集可能
- 管轄外のファイルを編集する場合は、管轄エージェントの承認が必要
- `knowledge/` 配下（`.claude/knowledge/` を含む）は全ロールが編集可能（ナレッジ蓄積のため）

### 承認フロー

管轄外のファイル更新が必要な場合、以下のプロセスで承認を得る。

1. **更新要求**: 変更を必要とするエージェントが、変更内容と理由を明示する
2. **管轄エージェントの確認**: 管轄エージェントが変更内容を確認し、MVV との整合性を検証する
3. **承認または却下**: 管轄エージェントが変更を承認するか、修正を求める
4. **実行**: 承認された場合、管轄エージェントが自身の手で変更を実施する

**注意**: role-gate フックが有効な場合、管轄外のファイル編集は技術的にもブロックされる。承認フローは管轄エージェント自身が変更を代行する形で運用する。

### MVV 編集権限

- MUST: MVV.md の編集はファウンダーのみが行う
- MUST NOT: エージェントが MVV の改変・改変提案を行わないこと

## 段階的導入計画

チームの成熟度に応じて段階的にエージェントを追加する。各フェーズは vibecorp のプリセット（minimal / standard / full）に対応する。

| Phase | 内容 | エージェント構成 | 対応プリセット |
|-------|------|----------------|---------------|
| Phase 0 | 準備 | なし（手動運用） | minimal |
| Phase 1 | レビュー体制 | CTO + CPO | standard |
| Phase 2 | コスト・法務 | + CFO + CLO + 分析員 | full |
| Phase 3 | セキュリティ | + CISO + 分析員 | full |
| Phase 4 | フル組織 | + SM（全エージェント稼働） | full |

### 各フェーズの詳細

#### Phase 0: 準備（minimal プリセット）

- vibecorp をインストールし、基本的なスキルとフックを導入する
- MVV.md を策定する
- エージェントなしで手動運用しながら、開発フローに慣れる
- protect-files フックでファイル保護を開始する
- /review, /commit, /pr 等の基本スキルを活用する

#### Phase 1: レビュー体制（standard プリセット）

- CTO + CPO エージェントを有効化し、コード品質とプロダクト方針のレビューを開始する
- /sync-check, /review-to-rules でドキュメントとコードの整合性を維持する
- sync-gate, review-to-rules-gate フックでゲート制御を導入する

#### Phase 2: コスト・法務（full プリセット）

- CFO + 経理分析員を追加し、API コストの可視化・予算管理を開始する
- CLO + 法務分析員を追加し、ライセンス・コンプライアンスチェックを開始する
- role-gate フックで管轄外編集のブロックを開始する

#### Phase 3: セキュリティ（full プリセット）

- CISO + セキュリティ分析員を追加し、セキュリティ監査体制を確立する
- /diagnose スキルで自律的な問題検出を開始する

#### Phase 4: フル組織（full プリセット）

- SM を追加し、プロセス管理・進捗把握・並列判定を担う
- 全 C-suite + 分析員が稼働し、AI 組織としてフル稼働する
- /ship-parallel で複数 Issue の並列処理が可能になる
