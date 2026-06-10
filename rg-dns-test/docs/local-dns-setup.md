# ローカルDNSサーバー構築手順（Mac + Docker）

## 目的

VPN接続したMac上でDNSサーバーを立て、AzureのDNS Private Resolver（Outbound Endpoint）から
`admix.go.jp` の問い合わせを受け取って任意のIPを返す。

```
[Container App (VNet3)]
  | dig admix.go.jp
  ↓
[DNS Private Resolver - Outbound Endpoint]
  | Forwarding Rule: admix.go.jp → dns_server_ip:53
  ↓
[このMac の VPN IP:53]  ← Dockerで立てるDNSサーバー
  | A record: admix.go.jp → 203.0.113.1（テスト用IP）
  ↓
Container に返る
```

---

## 前提

- Docker Desktop for Mac がインストール済み
- P2S VPN に接続済み（→ MacのVPN IPが確定する）

---

## 1. VPN接続後のMacのIPを確認

P2S VPN接続後、割り当てられたIPを確認する。

```bash
# utun系インターフェースのIPを探す
ifconfig | grep -A 1 utun | grep "inet 172"
```

出力例: `inet 172.16.0.3` → このIPが `dns_server_ip` として使われる。

**Terraformの `dns_server_ip` と異なる場合は tfvars を更新して再 apply する。**

```hcl
# dns-test.tfvars
dns_server_ip = "172.16.0.3"  # ← 実際のVPN IPに合わせる
```

---

## 2. dnsmasq コンテナを起動

```bash
docker run -d \
  --name local-dns \
  --restart unless-stopped \
  -p 53:53/udp \
  -p 53:53/tcp \
  4km3/dnsmasq \
  --no-daemon \
  --address=/admix.go.jp/203.0.113.1 \
  --log-queries
```

> `203.0.113.1` はテスト用の架空IP（RFC 5737 ドキュメント用アドレス）。
> 実際の閉域網IPが分かっている場合はそちらに変更する。

---

## 3. 動作確認（Mac側）

```bash
# Mac から直接クエリ
dig @127.0.0.1 admix.go.jp

# 期待する応答
# ;; ANSWER SECTION:
# admix.go.jp.    0    IN    A    203.0.113.1
```

---

## 4. Azure Container App から動作確認

Azure ポータルまたは az CLI でコンテナに exec する。

```bash
# az CLI でコンテナに入る
az containerapp exec \
  --name ubuntu-test \
  --resource-group rg-dns-test \
  --command /bin/bash
```

コンテナ内で実行：

```bash
# DNS解決テスト（VNet3のDNS → Resolver → Mac上のdnsmasq）
dig admix.go.jp

# 期待する応答: 203.0.113.1

# 疎通テスト（DNSが解決できた後）
curl -v --connect-timeout 5 http://admix.go.jp/ || true
```

---

## 5. dnsmasq ログ確認

Azure側から問い合わせが届いているかをMac側で確認する。

```bash
docker logs -f local-dns
```

出力例：
```
dnsmasq: query[A] admix.go.jp from 10.3.0.xx
dnsmasq: config admix.go.jp is 203.0.113.1
```

---

## 6. 後片付け

```bash
# コンテナを停止・削除
docker stop local-dns && docker rm local-dns
```

---

## トラブルシューティング

### Mac の 53番ポートが使用中の場合

```bash
# 使用プロセスを確認
sudo lsof -i :53

# macOS の mDNSResponder が使っている場合はポートを変更して起動
docker run -d --name local-dns \
  -p 5353:53/udp -p 5353:53/tcp \
  4km3/dnsmasq \
  --no-daemon \
  --address=/admix.go.jp/203.0.113.1

# Terraform の dns_server_ip を IP:5353 形式で指定（ただし Terraform側は port=53 固定のため要確認）
```

> ポート競合が起きる場合、Azure Firewall 側のネットワークルールで UDP/TCP 5353 を許可するか、
> mDNSResponder を一時停止する（`sudo launchctl stop com.apple.mDNSResponder`）。

### Azure側から届かない場合のチェックリスト

- [ ] VPN接続中であること
- [ ] `dns_server_ip` が実際のVPN IPと一致していること
- [ ] Azure Firewall のネットワークルールで UDP/TCP 53 が許可されていること
- [ ] Mac の ファイアウォールで Docker（port 53）が許可されていること
- [ ] VNet3 の DNS設定がInbound Endpointを向いていること（`azurerm_virtual_network_dns_servers`）
