# VNet内コンテナからインターネット・閉域網へのTCP443アクセス設計

## 概要

VNet内コンテナから以下2種類の宛先にTCP443でアクセスする構成の設計と設定手順。

- `example1.com` → インターネット
- `example2.com` → 閉域網（DNSは閉域網DNSで解決、実IPは210.x系）

---

## アーキテクチャ

```
[コンテナ (Spoke VNet)]
  |
  | UDR: 0.0.0.0/0 → Firewall
  v
[Azure Firewall (Hub VNet)]
  |                        |
  | example1.com           | example2.com
  v                        v
インターネット          VPN Gateway
                           |
                      オンプレネットワーク
                           |
                        閉域網DNS / 閉域網サービス (210.x)
```

---

## DNS（名前解決）

### 課題

`example2.com` は閉域網DNSでしか解決できない。
デフォルトではコンテナのDNS問い合わせが閉域網DNSに届かないため名前解決が失敗する。

### 解決策：DNS Private Resolver Outbound Endpoint + Forwarding Ruleset

#### 構成

```
[コンテナ (Spoke VNet)]
  | DNS query: example2.com
  v
[DNS Private Resolver - Outbound Endpoint (Hub VNet)]
  | Forwarding Rule: example2.com → 閉域網DNSのIP (100.x)
  v
[閉域網DNS]
  | → 210.x.x.x を返す
  v
コンテナが 210.x.x.x を取得
```

#### やること

| # | 作業 | 詳細 |
|---|---|---|
| 1 | Hub VNetに専用サブネット追加 | `subnet-dns-outbound` (/28以上、NSG不可) |
| 2 | DNS Private ResolverにOutbound Endpoint追加 | 既存Resolverに追加 |
| 3 | Forwarding Ruleset作成 | `example2.com` → 閉域網DNSのIP (100.x) |
| 4 | Forwarding RulesetをSpoke VNetにリンク | コンテナのVNetに紐づける |
| 5 | Firewallルール追加 | UDP/TCP 53 → 閉域網DNSのIP 許可 |

#### DNS Private Resolverのエンドポイント整理

| エンドポイント | 方向 | 用途 | 状況 |
|---|---|---|---|
| Inbound | オンプレ → Azure | VPN経由でAzure Private DNS Zoneを解決 | 既存・稼働中 |
| Outbound | Azure → オンプレ/閉域網 | 閉域網DNSへクエリを転送 | **今回追加** |

---

## ルーティング

### 課題

`example2.com` が解決されて得られる `210.x.x.x` は見た目がパブリックIPのため、
ルートが適切に設定されていないとインターネットに出てしまう。

### 解決策

`210.x.x.x` 宛のトラフィックをVPN Gateway経由で閉域網に流す。

#### やること

| # | 作業 | 詳細 |
|---|---|---|
| 1 | BGP伝播の確認 | VPN GatewayのBGP学習ルートに210.xが含まれるか確認 |
| 2 | (BGP未伝播の場合のみ) AzureFirewallSubnetのUDR追加 | `210.x.x.x/xx → VPN Gateway` |
| 3 | Firewallルール追加（Application Rule） | `example2.com` HTTPS(443) 許可 |

#### BGP確認コマンド

```bash
az network vnet-gateway list-learned-routes \
  --resource-group <rg> \
  --name <vpn-gateway-name> \
  --output table
```

210.xのルートが出力されれば、AzureFirewallSubnetへの自動伝播により追加UDR不要。

#### ルーティングの仕組み

```
コンテナ (Spoke Subnet)
  | UDR: 0.0.0.0/0 → Firewall  ← 全トラフィックをFirewallへ
  v
Azure Firewall
  | Application Rule: example2.com HTTPS(443) 許可
  | (FirewallはDNS Proxyでexample2.comを解決し210.xを動的に管理)
  v
AzureFirewallSubnetのルートテーブル
  | 210.x.x.x/xx → VPN Gateway  ← BGP伝播 or 手動UDR
  v
VPN Gateway → 閉域網
```

---

## Firewallルール追加まとめ

| ルール種別 | プロトコル/ポート | 宛先 | 用途 |
|---|---|---|---|
| Network Rule | UDP/TCP 53 | 閉域網DNSのIP (100.x) | DNS問い合わせ転送 |
| Application Rule | HTTPS (443) | example2.com | 閉域網サービスへのアクセス |

> **Note:** Application RuleでFQDNを指定することでIPを事前に知らなくてもよい。
> FirewallのDNS Proxyが動的にFQDNを解決してIPを管理する。

---

## 作業前確認事項

- [ ] 閉域網DNSのIPアドレス（100.x系）
- [ ] 閉域網のCIDR（210.x系、BGP伝播確認のため）
- [ ] VPN GatewayのBGP学習ルートに210.xが含まれるか
- [ ] Hub VNetに /28 以上の空きサブネット帯域があるか
- [ ] FirewallのDNS ProxyのDNS設定先

---

## 関連サービス整理

| サービス | 役割 |
|---|---|
| Azure DNS Private Resolver (Inbound) | オンプレ→AzureのPrivate DNS Zone解決（既存） |
| Azure DNS Private Resolver (Outbound) | Azure→閉域網DNSへのクエリ転送（今回追加） |
| Azure Firewall | 通信の許可/拒否、DNS Proxy |
| VPN Gateway | オンプレ/閉域網との接続、BGPルート学習 |
| UDR (Spoke Subnet) | コンテナの全通信をFirewallへ向ける |
| UDR (AzureFirewallSubnet) | BGP未伝播の場合のみ210.x→VPN Gatewayを手動追加 |
