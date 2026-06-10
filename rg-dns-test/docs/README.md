# rg-dns-test: DNS Private Resolver 閉域網 DNS 検証環境

## 概要

P2S VPN で接続したオンプレミス（Mac）上の DNS サーバーを、Azure の DNS Private Resolver 経由で
Azure リソース（Container Apps）から参照できるか検証するための環境。

---

## アーキテクチャ

```
[Mac (P2S VPN クライアント)]
  IP: 172.16.0.0/24
  └── dnsmasq (Docker)
        admix.go.jp → 203.0.113.1

         ↑ DNS転送 (UDP 53)
         |
[vnet1: VPN Hub]  10.1.0.0/24
  └── VPN Gateway (Basic SKU)
        P2S クライアントプール: 172.16.0.0/24

         ↑ ピアリング (allow_gateway_transit)
         |
[vnet2: Firewall + DNS Resolver]  10.2.0.0/24, 10.2.1.0/24
  ├── Azure Firewall Basic
  │     ネットワークルール:
  │       vnet3 → 172.16.0.0/24 (TCP/UDP): Allow
  │       172.16.0.0/24 → vnet3 (TCP/UDP): Allow
  ├── DNS Private Resolver
  │     受信エンドポイント: 10.2.1.68  ← vnet3 の DNS サーバーとして設定
  │     送信エンドポイント: 10.2.1.80/28
  └── 転送ルールセット
        admix.go.jp → dns_server_ip:53 (Mac の VPN IP)

         ↑ ピアリング
         |
[vnet3: Container Apps]  10.3.0.0/16
  └── Ubuntu Container App (検証用)
        DNS サーバー: 10.2.1.68 (受信エンドポイント)
```

---

## 検証の目的

閉域網（オンプレ）に存在するドメイン（`admix.go.jp` 等）を、Azure 内の Container Apps から
名前解決できるかを確認する。

想定する本番構成では VPN Gateway の代わりに ExpressRoute を使用し、オンプレの DNS サーバーへ
DNS Private Resolver の送信エンドポイントから転送する。

---

## 検証結果と判明した制約

### 動作した部分

- vnet3 Container App → vnet2 受信エンドポイントへの DNS クエリ
- Azure Firewall のネットワークルールによる vnet3 ↔ 172.16.0.0/24 の通信許可（ログ確認済み）

### 動作しなかった部分・根本原因

**送信エンドポイントからオンプレ DNS サーバー (172.16.0.2:53) に到達できなかった。**

原因:
1. P2S VPN クライアントプール (172.16.0.0/24) のルートは、ピアリング先 VNet に **BGP で伝播されない**
   （Basic SKU は BGP 非対応）
2. vnet2 のサブネットに `172.16.0.0/24 → VirtualNetworkGateway` の UDR を設定したが、
   ローカルゲートウェイを持たないスポーク VNet での `VirtualNetworkGateway` next hop は無効（ブラックホール）になった

### 結論

DNS Private Resolver の**送信エンドポイントは、転送先（オンプレ）に直接疎通できる VNet に配置する必要がある**。
受信・送信エンドポイントはリゾルバーと同じ VNet に作成しなければならないため、
**リゾルバー自体を VPN Gateway がある vnet1 に配置するべきだった**。

### 次回への改善点

- リゾルバーを vnet1 に配置（vnet1 のアドレス空間拡張が必要）
- または VPN Gateway を Basic → **VpnGw1 以上**に変更して BGP を有効化することで、
  172.16.0.0/24 のルートが vnet2 にシステムルートとして伝播され、vnet2 のリゾルバーが使えるようになる可能性がある

---

## ファイル構成

```
rg-dns-test/
├── dns-test.tf          # Terraform メイン設定
├── dns-test.tfvars      # 変数定義（秘密情報含む・git 除外）
├── vpn-certs/           # P2S VPN 証明書（git 除外）
└── docs/
    ├── README.md        # このファイル
    ├── cert-setup.md    # P2S VPN 証明書の作成手順
    └── local-dns-setup.md  # Mac 上の dnsmasq 構築手順
```

---

## 主要リソース

| リソース | 名前 | 備考 |
|---------|------|------|
| Resource Group | rg-dns-test | japaneast |
| VNet1 (VPN Hub) | vnet1-dnsrsiv-test-jpe | 10.1.0.0/24 |
| VNet2 (Firewall/DNS) | vnet2-dnsrsiv-test-jpe | 10.2.0.0/24, 10.2.1.0/24 |
| VNet3 (Container Apps) | vnet3-dnsrsiv-test-jpe | 10.3.0.0/16 |
| VPN Gateway | vpgw-vnet1-test-jpe | Basic SKU, P2S IKEv2 |
| Azure Firewall | afw-vnet2-test-jpe | Basic SKU |
| DNS Private Resolver | dnspr-test-jpe | vnet2 に配置 |
| Container App Env | cae-test-jpe | vnet3 に配置 |
