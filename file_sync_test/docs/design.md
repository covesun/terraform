# file_sync_test design

Created-By: unknown (existing asset), refined-by: codex

## 構成概要
- Resource Group: 1
- VNet/Subnet: 1
- NSG: 1 (Azure Bastion サービスタグからの 3389/TCP のみ許可)
- Azure Bastion: 1 (`Developer` SKU)
- Storage Account: 1 (`Standard_LRS`)
- Azure Files Share: 1
- Storage Sync Service: 1
- Sync Group: 1
- Cloud Endpoint: 1
- Windows VM: 2 (Windows Server 2022)
- VM Public IP: なし

各 VM は `CustomScriptExtension` で Azure File Sync Agent 導入とサーバー登録を行う。Server Endpoint は `registered_server_ids` を投入して Terraform 2回目適用で作成する。
VM 管理者パスワードは Terraform でランダム生成し、同一スタックで作成する Key Vault に Secret 保存した値を VM 作成に使用する。

## 設計判断
- 直接 SMB 共有マウント方式は不採用。Azure File Sync を正式採用。
- VM Public IP は廃止し、アクセスは Azure Bastion に統一。
- 初期コスト優先で Storage は Standard/LRS、VM サイズは小さい SKU を採用。
- サーバー登録直後に取得される ID が必要なため、Server Endpoint は 2段階 apply 方式を採用。

## 検証フロー
1. `terraform.tfvars.example` を `terraform.tfvars` にコピー。
2. `subscription_id`, `key_vault_name_prefix`, `afs_agent_download_url` を設定。
3. `terraform init`
4. `terraform apply` (1回目)
5. 登録済みサーバーIDを取得し `registered_server_ids` に設定。
6. `terraform apply` (2回目)
7. Bastion 経由で VM に接続し、ローカル同期フォルダでファイル同期を確認。
8. `terraform destroy`

## セキュリティ留意点
- VM に Public IP は付与しない。
- NSG では `AzureBastion` 以外からの 3389/TCP を許可しない。
- VM Extension の `commandToExecute` は `protected_settings` を使用する。
- シークレット値は Key Vault で管理し、`terraform.tfvars` に平文保持しない。
