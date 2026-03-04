# file_sync_test tasks

Created-By: codex

## 実行ルール
- 1回目 apply でインフラと AFS 基盤を作成する。
- サーバー登録IDを取得後、2回目 apply で Server Endpoint を作成する。
- VM管理者パスワードは Terraform がランダム生成し、Key Vault に保存する。
- 実行結果は `Execution Log` に残す。

## Phase 0: 準備
1. Azure 認証を確認。
```bash
az login
az account show
```
2. 変数ファイル作成。
```bash
cp terraform.tfvars.example terraform.tfvars
```
3. `terraform.tfvars` を設定。
- `subscription_id`
- `key_vault_name_prefix`
- `afs_agent_download_url`
4. Terraform 実行ラッパーに実行権限を付与 (初回のみ)。
```bash
chmod +x scripts/tf-secure.sh
chmod +x scripts/get-vm-admin-password.sh
```

## Phase 1: 初回構築 (Infra + AFS基盤)
1. 初期化。
```bash
./scripts/tf-secure.sh init
```
2. 実行計画確認。
```bash
./scripts/tf-secure.sh plan
```
3. 初回 apply。
```bash
./scripts/tf-secure.sh apply
```
4. 期待結果:
- Storage Sync Service / Sync Group / Cloud Endpoint 作成済み
- VM2台作成済み
- VM Extension で Agent 導入とサーバー登録が完了

## Phase 2: 登録サーバーID取得
1. 登録サーバー一覧を取得。
```bash
az storagesync registered-server list \
  --resource-group <RESOURCE_GROUP_NAME> \
  --storage-sync-service <STORAGE_SYNC_SERVICE_NAME> \
  --query "[].{id:id,name:name}" -o table
```
2. `terraform.tfvars` に `registered_server_ids` を設定。
```hcl
registered_server_ids = {
  vm1 = "/subscriptions/.../registeredServers/..."
  vm2 = "/subscriptions/.../registeredServers/..."
}
```
3. パスワードローテーションが必要な場合は `password_rotation_token` を任意の新しい文字列へ更新する (例: `2026-03-05-rotate1`)。

## Phase 3: Server Endpoint 作成 (2回目apply)
1. 実行計画確認。
```bash
./scripts/tf-secure.sh plan
```
2. 2回目 apply。
```bash
./scripts/tf-secure.sh apply
```
3. 期待結果: `azurerm_storage_sync_server_endpoint` が 2 つ作成される。

## Phase 4: 同期検証
1. Bastion 経由で VM1/VM2 に接続。
2. VM ログイン用パスワードを Key Vault から取得。
```bash
./scripts/get-vm-admin-password.sh
```
3. `F:\AFSData` (または `server_endpoint_local_path`) にテストファイルを作成。
4. 必要に応じて VM 側で変更検出を実行 (管理者 PowerShell)。
```powershell
Import-Module "C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll"
Invoke-StorageSyncServerChangeDetection -ServerEndpointPath "F:\AFSData"
# 必要なら DeepScan
# Invoke-StorageSyncServerChangeDetection -ServerEndpointPath "F:\AFSData" -DeepScan
```
5. 必要に応じて Cloud Endpoint 側で変更検出を実行 (管理端末の PowerShell)。
```powershell
Invoke-AzStorageSyncChangeDetection `
  -ResourceGroupName "rg-filesync" `
  -StorageSyncServiceName "filesync-svc" `
  -SyncGroupName "filesync-group" `
  -CloudEndpointName "filesync-cloud-endpoint"
```
6. もう一方の VM で同ファイルを確認。
7. 期待結果: ファイルが同期される。

## Phase 5: 破棄
```bash
./scripts/tf-secure.sh destroy
```

## Phase 6: 振り返り
1. `docs/retrospective.md` を更新。
2. 少なくとも以下を記録。
- 何を試したか (時系列)
- 何が失敗したか / なぜ失敗したか
- 最終的に採用した方式と理由
- 次回のチェック項目

## Execution Log

| Date | Operator | Phase | Command/Action | Result | Notes |
|---|---|---|---|---|---|
| 2026-03-05 | codex | Refactor | Azure Files直接共有からAzure File Sync構成へ再設計 | success | main/variables/outputs/docs 更新 |
| 2026-03-05 | codex | Validation | `terraform validate` | fail | `registry.terraform.io` へ名前解決不可の環境制約 |
