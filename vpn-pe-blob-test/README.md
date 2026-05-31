# VPN → Private Endpoint 経由 Blob アクセス検証

## 概要

ストレージエクスプローラー / Azure ポータルから、P2S VPN → VNet ピアリング → Private Endpoint 経由で Blob ストレージにアクセスできることを検証するためのTerraformテンプレート。

## 構成

```
[クライアント]
    │ P2S VPN (OpenVPN + Entra ID)
    ▼
[VNet-VPN: 10.1.0.0/16]
  └─ GatewaySubnet ── VPN Gateway (VpnGw1AZ)
    │ VNet Peering
    ▼
[VNet-PE: 10.2.0.0/16]
  └─ snet-pe ── Private Endpoint (Blob)
                    │
                    ▼
           [Storage Account]
           パブリックアクセス無効
           信頼済みサービスバイパス無効
```

## デプロイ手順

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars に値を設定

terraform init
terraform apply
```

### terraform.tfvars に必要な値

| 変数 | 取得コマンド |
|---|---|
| subscription_id | `az account show --query id -o tsv` |
| tenant_id | `az account show --query tenantId -o tsv` |
| blob_reader_object_id | `az ad signed-in-user show --query id -o tsv` |

## VPN クライアント設定

```bash
az network vnet-gateway vpn-client generate \
  --resource-group rg-vpnpe-test \
  --name vpn-gw \
  --output json
```

出力URLからzipをダウンロード → `AzureVPN/azurevpnconfig.xml` を Azure VPN Client にインポート → Entra ID でサインイン。

---

## 検証結果

### 結論

**VPN接続 + DNS解決ができれば、AzureポータルのストレージブラウザーからもStorage ExplorerからもBlobアクセス可能。**  
認証（Entra ID + RBAC）も問題なく通る。

---

## 各リソースの必要設定

### VPN Gateway

| 設定 | 値 | 備考 |
|---|---|---|
| SKU | `VpnGw1AZ` 以上 | 非AZ SKU（VpnGw1等）は2025年以降廃止済み・作成不可 |
| vpn_client_protocols | `OpenVPN` | Entra ID 認証に必須 |
| aad_audience | `41b23e61-6c1e-4545-b367-cd054e0ed4b4` | Azure VPN Client アプリの固定値 |

### Public IP（VPN GW 用）

| 設定 | 値 | 備考 |
|---|---|---|
| sku | `Standard` | |
| zones | `["1", "2", "3"]` | AZ SKU の GW には必須。未指定だとデプロイエラー |

### VNet ピアリング（双方向）

| 設定 | VNet-VPN 側 | VNet-PE 側 |
|---|---|---|
| allow_gateway_transit | `true` | `false` |
| use_remote_gateways | `false` | `true` |

> `use_remote_gateways = true` は VPN GW 完成後でないと設定できないため `depends_on = [azurerm_virtual_network_gateway.vpn_gw]` が必要。

### Storage Account

| 設定 | 値 | 備考 |
|---|---|---|
| public_network_access_enabled | `false` | |
| network_rules.default_action | `Deny` | |
| network_rules.bypass | `[]` | 空にしないと信頼済み Azure サービス（ポータル等）がネットワーク制限をバイパスする |

### Private DNS Zone

- `privatelink.blob.core.windows.net` を **両方の VNet**（VNet-VPN・VNet-PE）にリンク必須
- PE 側のみのリンクでは VPN クライアントの DNS 解決に不十分（後述）

### RBAC

- アクセスするユーザーに `Storage Blob Data Contributor` 以上を付与

---

## ハマりポイント

### DNS 解決が VPN クライアントに届かない

P2S VPN クライアントは Azure 内部 DNS（`168.63.129.16`）に到達できないため、Private DNS Zone をリンクしていても自動的には解決されない。

**根本原因：** `168.63.129.16` は Azure VNet 内からしかアクセスできない特殊 IP。VPN クライアントはVNet の外にいるため届かない。

| 対策 | 難易度 | 用途 |
|---|---|---|
| `/etc/hosts` に直書き | 低 | 検証・一時対応 |
| Azure DNS Private Resolver を VNet-VPN 内に配置 | 高 | 本番構成 |

```bash
# 一時対応（検証用）
sudo sh -c 'echo "10.2.1.4 vpnpeblobtest.blob.core.windows.net" >> /etc/hosts'

# 検証後に削除
sudo sed -i '' '/vpnpeblobtest/d' /etc/hosts
```

### ポータルアクセスがバイパスを使う場合がある

`network_rules.bypass` に `AzureServices` が含まれていると、VPN 未接続・Private Endpoint 未経由でもポータルからデータ操作が可能になる。検証の正確性を担保するには `bypass = []` で明示的に無効化すること。

### SKU と認証方式の関係

| SKU | Entra ID 認証 | OpenVPN | 備考 |
|---|---|---|---|
| Basic | ✗ | ✗ | 証明書 + SSTP/IKEv2 のみ |
| VpnGw1（非 AZ） | ✓ | ✓ | 廃止済み・新規作成不可 |
| VpnGw1AZ | ✓ | ✓ | 現在選択可能な最小構成 |

**Entra ID 認証を使う場合は VpnGw1AZ 以上が必須。**

---

## コスト概算（Japan East）

| リソース | 時間単価 |
|---|---|
| VPN Gateway VpnGw1AZ | ~$0.43/h |
| Public IP (Standard) | ~$0.006/h |
| Private Endpoint | ~$0.01/h |
| Storage Account (Standard LRS) | ほぼ $0（容量・操作次第） |
| **合計** | **~$0.45/h（≒ ¥68/h）** |

検証完了後は `terraform destroy` で即削除推奨。
