# チームモードのパーミッション

## 基本原則

チームメイトはリーダーのパーミッション設定を自動継承する。

> Teammates start with the lead's permission settings.
> You can't set per-teammate modes at spawn time.

## Agent の mode パラメータ

Agent ツールの `mode` パラメータ（`"auto"`, `"bypassPermissions"` 等）は、
**チームモードではパーミッション制御に使えない**。

チームメイトの `--permission-mode` はリーダーの設定で決まる。

## team lead approval

チームモードでは Write/Edit 操作が「Waiting for team lead approval」として
リーダーセッションに転送される場合がある。
これはリーダーのパーミッション設定が `acceptEdits` の場合に発生する。

## パーミッション確認を減らすには

| 方法 | 効果 | リスク |
|------|------|--------|
| リーダーの allow リストを充実させる | 許可済み操作は確認なし | 許可範囲が広がる |
| `--dangerously-skip-permissions` でリーダーを起動 | 全チームメイトも全スキップ | セキュリティリスク |
| 起動後に個別チームメイトの設定を変更 | 個別制御可能 | 手動操作が必要 |

## 検証結果（2026-03-23）

| テスト | mode 指定 | 実際の --permission-mode | team lead 承認 |
|--------|----------|------------------------|----------------|
| 単独 Agent | `"auto"` | （確認なし） | N/A |
| チーム Agent | `"auto"` | `acceptEdits` | 発生 |
| チーム Agent | `"bypassPermissions"` | `acceptEdits` | 発生 |

## 未解明

- `settings.local.json` の allow リストに `Write`, `Edit` があるにも関わらず team lead approval が発生する理由
- allow リストと team lead approval の優先関係
