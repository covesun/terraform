# file_sync_test requirements

Created-By: unknown (existing asset), refined-by: codex

## 目的
Azure File Sync を用いて、2 台の Azure VM (Windows Server 2022) と Azure Files を同期し、VM1 側で作成したファイルが VM2 側にも同期されることを検証する。

## 要件
- Terraform で検証環境を一括作成できること。
- Azure File Sync 構成 (Storage Sync Service, Sync Group, Cloud Endpoint, Server Endpoint) を採用すること。
- VM は 2 台で、各 VM に Azure File Sync Agent を導入すること。
- VM 管理者パスワードは Terraform でランダム生成し、Key Vault に保存すること。
- 各 VM を Storage Sync Service に登録できること。
- VM1 で作成したファイルを VM2 で確認できること。
- 破棄 (`terraform destroy`) で一括削除できること。

## 前提
- Azure サブスクリプションが利用可能。
- `az login` 済み、または適切な認証方式が利用可能。
- Azure Portal から Bastion 接続を実施できる権限があること。
- Azure File Sync Agent をダウンロード可能なネットワーク到達性があること。

## 非機能要件
- 可能な限り低コスト:
  - VM: Windows Server 2022 を小さいサイズ 2 台
  - Storage: `Standard_LRS` の Azure Files
  - 接続方式: Azure Bastion Developer SKU
- 可能な限り手作業を排除し、再実行可能な手順であること。

## 受け入れ条件
- `terraform apply` (1回目) が成功し、Storage Sync Service/Group/Cloud Endpoint と VM2台が作成される。
- VM Extension により Agent 導入とサーバー登録が完了する。
- `registered_server_ids` を設定した `terraform apply` (2回目) が成功し、Server Endpoint が作成される。
- VM1 で作成したファイルが VM2 で読める。
- `terraform destroy` が成功する。
