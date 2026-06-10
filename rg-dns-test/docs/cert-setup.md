# P2S VPN 証明書生成手順

## 概要

P2S VPN の証明書認証に必要な以下2種類の証明書を生成する。

- **ルート証明書（CA）**: Terraform で Azure に登録する公開鍵
- **クライアント証明書**: 接続するMacにインストールする証明書

---

## 1. ルート証明書（自己署名CA）の生成

```bash
# 作業ディレクトリを作成
mkdir -p ~/vpn-certs && cd ~/vpn-certs

# ルートCA の秘密鍵と自己署名証明書を生成（有効期間10年）
openssl req -x509 -newkey rsa:2048 \
  -keyout root-ca.key \
  -out root-ca.crt \
  -days 3650 \
  -nodes \
  -subj "/CN=dns-test-P2S-RootCA"
```

---

## 2. クライアント証明書の生成

```bash
# クライアント証明書の秘密鍵と CSR を生成
openssl req -newkey rsa:2048 \
  -keyout client.key \
  -out client.csr \
  -nodes \
  -subj "/CN=dns-test-client"

# ルートCAで署名（有効期間1年）
openssl x509 -req \
  -in client.csr \
  -CA root-ca.crt \
  -CAkey root-ca.key \
  -CAcreateserial \
  -out client.crt \
  -days 365
```

---

## 3. Terraform 用の公開鍵データを取得

```bash
# BEGIN/END 行を除いた Base64 を出力
openssl x509 -in root-ca.crt -outform der | base64 | tr -d '\n'
```

出力された文字列を `dns-test.tfvars` に設定する。

```hcl
vpn_root_cert_data = "MIIDxxxxxxxxxxxxxx...（出力された文字列）"
```

---

## 4. クライアント証明書を Mac にインストール

```bash
# クライアント証明書を PKCS#12 形式に変換
openssl pkcs12 -export \
  -in client.crt \
  -inkey client.key \
  -certfile root-ca.crt \
  -out client.p12 \
  -passout pass:""
```

Finder で `client.p12` をダブルクリック → キーチェーンアクセスに追加。

---

## 5. ルート証明書を System Keychain に信頼済みで追加

macOS の IKEv2 VPN はログインキーチェーンの証明書を参照しない。System Keychain に登録が必要。

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /Users/shuheimaki/Documents/terraform/rg-dns-test/vpn-certs/root-ca.crt
```

---

## 6. macOS ネイティブ VPN 設定

システム設定 → VPN → VPN 接続を追加 → IKEv2

| 項目 | 値 |
|---|---|
| サーバアドレス | VPN GatewayのパブリックIP |
| リモートID | VPN GatewayのパブリックIP（サーバアドレスと同じ） |
| ローカルID | `dns-test-client` |
| 認証方法 | 証明書 |
| 証明書 | `dns-test-client`（キーチェーンから選択） |

> Azure VPN Client はEntra ID (AAD) 認証専用のため、証明書認証では使用不可。

---

## ファイル一覧

| ファイル | 用途 | 保管 |
|---|---|---|
| `root-ca.key` | ルートCA秘密鍵 | 厳重保管、Azureには不要 |
| `root-ca.crt` | ルートCA証明書 | Terraform で公開鍵を登録 |
| `client.key` | クライアント秘密鍵 | Mac のみ |
| `client.crt` | クライアント証明書 | Mac のみ |
| `client.p12` | キーチェーン用パッケージ | Mac にインストール後不要 |

> `~/vpn-certs/` は Git 管理外に置くこと。絶対にリポジトリにコミットしない。
