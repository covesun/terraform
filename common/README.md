# AMA + Blob ストレージ プライベート エンドポイント検証構成（Terraform）
## 概要
このリポジトリは、以下の2つの検証を行うためのモジュール化されたTerraform構成です：
- Azure Monitor Agent (AMA) によるファイアウォール越し（透過プロキシ経由）のログ送信
- Blob ストレージへのプライベートエンドポイント + DNS 経由のセキュアアクセス
## ディレクトリ構成
```
  terraform-ama-blob/
   ├── common/ 共通リソース（VNet、Subnet、NSG、確認用VMなど） 
   ├── ama_test/ AMA + VM + Log Analytics Workspace + 拡張＋診断設定 
   ├── blob_test/ Storage Account + Private Endpoint + DNS構成 
   └── backend-config/ backend.tf など必要に応じて使用（現在は未使用）
```
## はじめに
1. このリポジトリをクローンまたはZIPでダウンロード
2. 各ディレクトリの `terraform.tfvars.example` を参考に `.tfvars` を作成
3. SSH鍵パスや prefix、リージョンを環境に合わせて設定
4. 各モジュールディレクトリで以下を実行：
```
cd common/
terraform init
terraform apply
```
他のディレクトリ（例：ama_test/, blob_test/）でも同様に実行してください。
## AMA構成メモ
- common/ にあるVMは Blob アクセス確認用の共通リソースです
- ama_test/ のVMには Azure Monitor Agent（AMA）が拡張としてインストールされます
- ログは Log Analytics Workspace へ送信され、ファイアウォール越しでも透過プロキシで通信されます
- ファイアウォールでは以下のFQDNを許可してください：
  - .ods.opinsights.azure.com
  - *.oms.opinsights.azure.com
  - *.blob.core.windows.net
## Blob Storage Private Endpoint構成メモ
- ストレージアカウントは blob_test/ にて作成
- Private Endpoint を介して Subnet に接続
- privatelink.blob.core.windows.net に対応する Private DNS Zone も定義
- DNS Zone は common/ の VNet にリンクされ、VMから名前解決可能
## 変数ファイルの例：terraform.tfvars.example
各ディレクトリに terraform.tfvars.example が配置されています。これを .tfvars にコピーして使用します。
```
location         = "japaneast"
resource_prefix  = "example"
vm_admin_ssh_key = "~/.ssh/id_rsa.pub"
```
## 出力例：outputs.tf
各モジュールの outputs.tf により、重要な値（リソース名、IPアドレスなど）を出力できます。
```
output "resource_group_name" {
  value = azurerm_resource_group.example.name
}

output "vnet_name" {
  value = azurerm_virtual_network.example_vnet.name
}

output "client_vm_private_ip" {
  value = azurerm_network_interface.client_nic.private_ip_address
}

output "test_vm_private_ip" {
  value = azurerm_network_interface.example_nic.private_ip_address
}
```
## セキュリティに関する注意
認証情報はハードコードされていません
- .tfvars など機密値が含まれるファイルはコミットしないでください
- .gitignore にて以下が除外されています：
```
# Terraform
*.tfstate
*.tfstate.backup
.terraform/
*.log

# 機密ファイル
*.env
*.pem
*.key
terraform.tfvars
```

