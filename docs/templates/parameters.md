# <project> parameters

## 使い方
- `requirements.md` と `design.md` で決めた内容を、実行可能な入力値に落とし込む。
- 値の決定根拠を備考に残す。

## Terraform Parameters

| Name | Type | Required | Default | Example | Description | Source |
|---|---|---|---|---|---|---|
| `prefix` | `string` | Yes | - | `filesync` | リソース命名の接頭辞 | requirements |
| `location` | `string` | Yes | - | `japaneast` | デプロイ先リージョン | requirements |

## CLI/API Parameters

| Name | Required | Example | Description | Source |
|---|---|---|---|---|
| `subscription` | Yes | `<SUBSCRIPTION_ID>` | コマンド実行先サブスクリプション | requirements |

## 環境差分

| Environment | Difference | Reason |
|---|---|---|
| `dev` | 小さい SKU を使用 | コスト最適化 |
| `prod` | 可用性優先設定を使用 | 信頼性要件 |

## 変更履歴
- YYYY-MM-DD: 変更内容 / 理由

