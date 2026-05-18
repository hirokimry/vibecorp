# 🏢 vibecorp AI 組織運用

> [!IMPORTANT]
> 読者像は vibecorp 導入者（利用者）と開発者（コントリビューター）。
> 本ドキュメントは AI エージェントによる組織運用の **Source of Truth**。
> 役職の管轄・権限・段階的導入の判断はここを参照する。

## 🎯 基本思想

AI エージェントチームがプロダクト開発を担い、ユーザーは CEO として意思決定に集中する。

vibecorp はスクラム開発を前提とする。

- 👔 **CEO は代表取締役社長＝経営者である**。
  - ソフトウェアの「ふるまい」で判断する。
  - 判断基準: 何をできるようになったか／壊れたか／変わるか。
  - 関数名・ファイルパス・diff のような実装詳細では判断しない。
  - したがって CEO への報告は全て **動作主語** で行う。
  - 規約: `.claude/rules/communication.md`
- 🤖 プロダクト開発のあらゆる側面を AI エージェントチームが担う。
- 🧭 各エージェントは専門領域を持つ。
- 🤝 エージェント同士はフラットな関係で協働する。
- 🌟 全ての判断は `MVV.md` に基づく。
- 🛡️ 管轄外のファイル編集は role-gate フックで自動ブロックされる。

## 🧱 組織構成

各エージェントは管轄を持ち、管轄外は編集しない。

| ロール | 役割 | docs/ 編集権限 |
|---|---|---|
| SM | プロセス管理・進捗・並列判定 | `docs/ai-organization.md` |
| CTO | コード品質・アーキテクチャ・技術的負債 | `docs/specification.md`（技術スタック部分）・`docs/design-philosophy.md` |
| CPO | プロダクト方針・仕様の一貫性 | `docs/specification.md`・`docs/screen-flow.md` |
| CFO | コスト分析・予算管理 | なし（経理分析員に委任） |
| CLO | 法務・コンプライアンス | なし（法務分析員に委任） |
| CISO | セキュリティ | なし（セキュリティ分析員に委任） |

### 🎯 原則: 仕様は CPO、設計は CTO

仕様と設計を別の C\*O が管轄する。

- 📋 プロダクト仕様（ユーザー視点・機能・プリセット）は CPO。
  - 配置: `docs/specification.md`
- 🏗️ 技術設計（アーキテクチャ・フック・スキル・sandbox 等）は CTO。
  - 配置: `docs/design-philosophy.md`

### 🛠️ エージェント tools セット

各エージェントは Claude Code の subagent として独立する。

tools 宣言は frontmatter で固定する。

| エージェント種別 | tools |
|---|---|
| C\*O 6 体（cfo / cto / cpo / ciso / clo / sm） | `Read, Edit, Write, MultiEdit, Bash, Grep, Glob` |
| accounting-analyst | `Read, Write, Bash, Grep, Glob` |
| security-analyst | `Read, Write, Bash, Grep, Glob` |
| legal-analyst | `Read, Bash, Grep, Glob`（書込み権限なし） |
| 計画レビュー専門家（plan-architect / plan-security 等） | `Read, Glob, Grep`（読取専用） |

C\*O は Edit / Write / MultiEdit を持つ。

これにより knowledge への書込みは Edit/Write 層 hook が確実に検知できる。

- 検知 hook（Edit/Write 経路）: `protect-knowledge-direct-writes.sh`
- 検知 hook（Bash redirect 経路）: `protect-knowledge-bash-writes.sh`
- Bash redirect で書こうとしても hook が deny する。
- tools 選択の誤りで素通りする経路はない（Issue #448 多層防御）。

詳細は [`docs/SECURITY.md` の「knowledge ガードレール（多層防御）」](SECURITY.md#knowledge-ガードレール多層防御) を参照。

### 👥 チーム構成

C-Level の下に専門分析員を配置する。

詳細分析・調査を分析員に委任する。

| チーム | C-Level | 分析員 | 分析員の役割 | docs/ 編集権限 |
|---|---|---|---|---|
| 法務チーム | CLO | legal-analyst | ライセンス分析・コンプライアンス | なし（`docs/POLICY.md` は CLO 経由） |
| 経理チーム | CFO | accounting-analyst | API コスト計算・予算消化率 | `docs/cost-analysis.md` |
| セキュリティチーム | CISO | security-analyst | 脆弱性スキャン・ポリシー検証 | `docs/SECURITY.md` |

分析員は C-Level から呼ばれ、結果を報告する。

- ✅ `accounting-analyst` / `security-analyst` は管轄の docs/ を直接編集できる。
  - 制御: role-gate フック。
- ❌ `legal-analyst` は Write 権限を持たない。
  - `docs/POLICY.md` の編集は CLO に委任する。

### 📋 エージェント一覧（full プリセット）

`README.md` から本ドキュメントに移譲した詳細一覧。

standard プリセットでは CTO と CPO のみが配置される。

#### C-suite（単独判断）

| エージェント | ロール | 管轄 |
|---|---|---|
| `cto.md` | CTO（技術責任者） | コード品質・アーキテクチャ・技術的負債 |
| `cpo.md` | CPO（プロダクト責任者） | プロダクト方針・仕様の一貫性 |
| `sm.md` | SM（Scrum Master） | プロセス管理・進捗・並列実行判定 |
| `cfo.md` | CFO（最高財務責任者） | コスト分析・API 利用量管理 |
| `clo.md` | CLO（最高法務責任者） | ライセンス・規約・コンプライアンス |
| `ciso.md` | CISO（最高情報セキュリティ責任者） | セキュリティ |

各 C-suite は `knowledge/<役職>/` を管理する。

#### 分析員（合議制: 3 回独立実行 → C-suite がメタレビュー）

| エージェント | ロール | レビュー先 |
|---|---|---|
| `accounting-analyst.md` | 経理分析員 | コスト管理ポリシー・課金ロジック → CFO |
| `legal-analyst.md` | 法務分析員 | ライセンス・規約・著作権 → CLO |
| `security-analyst.md` | セキュリティ分析員 | 脆弱性・依存パッケージ・OWASP Top 10 → CISO |

#### 計画レビュー専門家（plan-review-loop から起動）

| エージェント | ロール |
|---|---|
| `plan-architect.md` | 構造設計・責務分離・拡張性 |
| `plan-security.md` | 脆弱性・認証・認可・入力検証 |
| `plan-testing.md` | テストカバレッジ・境界値・E2E 設計 |
| `plan-performance.md` | ボトルネック・スケーラビリティ |
| `plan-dx.md` | DX・エラーハンドリング・可観測性 |
| `plan-cost.md` | API 頻度・モデル選択・トークン消費（full 限定） |
| `plan-legal.md` | LICENSE 適合・第三者リポ参照・規約影響（full 限定） |

## ⚖️ ワークフロー × C\*O ゲート マトリクス

`/vibecorp:ship` などの自動化ワークフローで、判断に必要な情報が揃う最初のタイミングで C\*O ゲートを入れる。

C\*O は常時起動しない。

管轄領域に触れた差分を検知した時のみ起動する。

### 🪜 フェーズ × ゲート対応

| フェーズ | 対象スキル | 対象プリセット | 入れる役職 | 起動条件 |
|---|---|---|---|---|
| 1. Issue 起票 | `/vibecorp:issue` | standard / full | CISO + CPO + SM | 常時（3 者承認） |
| 2. autopilot 候補フィルタ | `/vibecorp:diagnose` `/vibecorp:autopilot` | full | CPO + SM + CISO | 常時（3 者承認） |
| 3a. 設計レビュー（平社員層） | `/vibecorp:plan-review-loop` | プリセット別 | plan-architect / plan-security / plan-testing / plan-performance / plan-dx / plan-cost / plan-legal | プリセット別 |
| 3b. 設計レビュー（C\*O メタ層） | `/vibecorp:plan-review-loop` | full | CFO / CISO / CLO / SM / CPO / CTO | 条件起動（下記トリガー表） |
| 4. 実装 | `/vibecorp:ship` 内 | — | なし | — |
| 5. 実装レビュー（平社員合議） | `/vibecorp:review-loop` | full | security / accounting / legal-analyst ×3 | 差分検知で条件起動 |
| 6. 実装レビュー（C\*O メタ層） | `/vibecorp:review-loop` | full | 該当 C\*O | 平社員合議で Major 以上 |
| 7. PR レビュー | `/vibecorp:pr-fix-loop` | 全プリセット | CodeRabbit のみ | — |
| 8a. マージゲート（standard） | `/vibecorp:sync-check` | standard | CTO / CPO | 管轄領域に触れた時のみ |
| 8b. マージゲート（full） | `/vibecorp:sync-check` | full | CTO / CPO / CFO / CISO / CLO / SM | 管轄領域に触れた時のみ |
| 9. 事後監査 | `/vibecorp:audit-cost` `/vibecorp:audit-security` | full | CFO（週次）/ CISO（月次） | 定期 |

### 🛠️ `plan.review_agents` のプリセット別デフォルト

`install.sh` が `vibecorp.yml` 生成時に出力する。

利用者は個別に追加・削除できる。

| プリセット | デフォルト `plan.review_agents` |
|---|---|
| minimal | `[architect]` |
| standard | `[architect, security, testing]` |
| full | `[architect, security, testing, performance, dx, cost, legal]` |

### 🚦 C\*O 起動トリガー表（フェーズ 3b・5・6・8b 共通／full 限定）

| トリガー | 起動 C\*O | 平社員合議 |
|---|---|---|
| 実行モード・モデル・API 呼び出し変更・課金影響 | **CFO** | accounting-analyst ×3 |
| 認証・権限・暗号・secrets・データフロー変更 | **CISO** | security-analyst ×3 |
| 依存追加・LICENSE・規約・第三者リポ参照 | **CLO** | legal-analyst ×3 |
| エージェント定義・hooks・rules・skills 変更 | **SM** | （単独） |
| 仕様・UX・MVV 影響 | **CPO** | （単独） |
| アーキ・技術選定・依存バージョン | **CTO** | （単独） |

### 🧭 設計の要点

ゲート設計の判断基準を以下に整理する。

- 🔁 **C\*O は常時起動しない**。
  - 差分検知に基づく条件起動でオーバーヘッドを抑える。
- 🪜 **平社員 → C\*O の 2 段階**。
  - 平社員（×3 合議や `plan-*` 専門家）が一次フィルタ。
  - C\*O はメタレビューに専念する。
- 🎯 **`plan-cost` と `plan-legal` は CFO / CLO の代弁者**。
  - 設計フェーズで起動する。
- 🛡️ **Issue 起票時は CISO + CPO + SM の 3 者承認**。
  - CPO は「やる価値」を判定する。
  - CISO は「不可領域 5 分類の安全性」を判定する。
  - SM は「自動化適性・プロセス整合」を判定する。
  - CFO / CLO はこの段階では判断材料不足のため対象外。
- 🚪 **起票側と ship 側の責務分離**。
  - `/vibecorp:issue` 起票時に不可領域フィルタを完結させる。
  - `/vibecorp:ship`（`/vibecorp:autopilot`）は起票済み Issue を信頼する透過パイプ。
- 🤖 **autopilot は 3 者承認**（CPO + SM + CISO）。
  - 自律実行は「やる価値 × 自動化適性 × 安全性」の 3 軸が必要。

## 🛡️ 権限モデル

### 📁 管轄ファイルの更新権限

各エージェントは管轄ファイルのみ編集できる。

- ✅ 管轄ファイルは自身のロールで編集する。
- ⚠️ 管轄外を編集する場合は、管轄エージェントの承認が必要。
- 📚 `knowledge/` 配下（`.claude/knowledge/` を含む）は、Write 権限を持つロールのみ編集可能。
  - 理由: ナレッジ蓄積と権限モデルの整合を両立するため。
  - 補足: `legal-analyst` は Write 権限を持たないため対象外。

### 🤝 承認フロー

管轄外のファイル更新が必要な場合、以下の順で承認を得る。

1. 📝 **更新要求**: 変更を必要とするエージェントが、内容と理由を提示する。
2. 👀 **管轄エージェントの確認**: 管轄エージェントが MVV との整合性を検証する。
3. ✅ **承認または却下**: 管轄エージェントが承認または修正要求する。
4. 🔨 **実行**: 承認された場合、管轄エージェントが代行で変更する。

> [!NOTE]
> role-gate フックが有効な場合、管轄外編集は技術的にブロックされる。
> 承認フローは管轄エージェントが代行する形で運用する。

### 🌟 MVV 編集権限

- ✅ MUST: `MVV.md` の編集はファウンダーのみが行う。
- ❌ MUST NOT: エージェントが MVV の改変・改変提案を行わない。

## 🪜 段階的導入計画

チームの成熟度に応じて段階的にエージェントを追加する。

各フェーズは vibecorp のプリセット（minimal / standard / full）に対応する。

| Phase | 内容 | エージェント構成 | 対応プリセット |
|---|---|---|---|
| Phase 0 | 準備 | なし（手動運用） | minimal |
| Phase 1 | レビュー体制 | CTO + CPO | standard |
| Phase 2 | コスト・法務 | + CFO + CLO + 分析員 | full |
| Phase 3 | セキュリティ | + CISO + 分析員 | full |
| Phase 4 | フル組織 | + SM（全エージェント稼働） | full |

### Phase 0: 準備（minimal プリセット）

導入直後の手動運用フェーズ。

- vibecorp をインストールし、基本のスキルとフックを導入する。
- `MVV.md` を策定する。
- エージェントなしで開発フローに慣れる。
- protect-files フックでファイル保護を開始する。
- `/vibecorp:review`、`/vibecorp:commit`、`/vibecorp:pr` 等の基本スキルを活用する。

### Phase 1: レビュー体制（standard プリセット）

レビュー自動化を始める。

- CTO + CPO エージェントを有効化する。
- コード品質とプロダクト方針のレビューを開始する。
- `/vibecorp:sync-check`、`/vibecorp:review-to-rules` で整合性を維持する。
- sync-gate、review-to-rules-gate フックでゲート制御を導入する。

### Phase 2: コスト・法務（full プリセット）

C-Level 体制を強化する。

- CFO + 経理分析員を追加する。
  - API コストの可視化・予算管理を開始する。
- CLO + 法務分析員を追加する。
  - ライセンス・コンプライアンスチェックを開始する。
- role-gate フックで管轄外編集のブロックを開始する。

### Phase 3: セキュリティ（full プリセット）

セキュリティ統制を整える。

- CISO + セキュリティ分析員を追加する。
  - セキュリティ監査体制を確立する。
- `/vibecorp:diagnose` スキルで自律的な問題検出を開始する。

### Phase 4: フル組織（full プリセット）

スクラム運用が完成する。

- SM を追加する。
  - プロセス管理・進捗把握・並列判定を担う。
- 全 C-suite + 分析員が稼働する。
- `/vibecorp:ship-parallel` で複数 Issue の並列処理が可能になる。

### 🔌 Plugin 名前空間移行（完了）

Claude Code 公式 Plugin 機能を利用した `/vibecorp:xxx` 形式の名前空間に移行済み。

- 🚀 Phase 1（実機検証）: Issue #352。
- 🚀 Phase 2（全スキル plugin 化 + 互換レイヤ）: Issue #358。
- 🚀 Phase 3（互換レイヤ廃止）: Issue #359。
- ✅ 全 26 スキルが `skills/`（plugin ルート）に配置されている。
- ✅ Plugin 名前空間（`/vibecorp:xxx`）のみで呼び出し可能。
- ❌ `.claude/skills/` の互換スタブは廃止済み。
